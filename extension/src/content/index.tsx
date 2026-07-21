// =============================================================================
// content/index.tsx — 콘텐츠 스크립트 오케스트레이터 (Stream A 소유, T=3)
//
// 소유권(§T3.1): 이 파일은 content 파이프라인(extract→anchor→observe)이 척추이고
//   B(mount/queue)·C(message)는 그 위 호출자이므로 Stream A가 소유. B·C 공개 API와
//   ChromeMessage 계약에 "의존만" 하고 그쪽 내부는 건드리지 않는다.
//
// end-to-end 체인(§T3.0):
//   1. extractArticle()            [A] 본문·문단
//   2. REQUEST_QUIZ                [A→C] background가 서버 /quiz 호출 → Quiz[]
//   3. anchorQuizzes()             [A] 퀴즈 ↔ 문단 매칭
//   4. mountPanel({ onEnd })       [B] Shadow DOM 패널
//   5. createSessionQueue()        [B] 제출 큐
//   6. observer.observe()          [A] 앵커 문단 ∪ {마지막 문단}
//   7. onParagraphEnter            [A] enqueue + unanchored flush (단일 콜백, 컨트롤러 소유)
//   8. 큐 → startQuestion → 채점    [B]
//   9. onEnd → flush → SEND_SCRAP  [A→C] + 세션 정지
// =============================================================================

import { extractArticle, type ExtractResult } from './extractor'
import { isNonArticleUrl } from './page-gate'
import { anchorQuizzes } from './anchor'
import { createParagraphObserver } from './observer'
import { createSessionQueue } from './session-bind'
import { mountPanel, mountStartPrompt, unmountStartPrompt } from './ui/mount'
import { useSession } from './session'
import { DETECT_RETRY_DELAYS_MS } from '../shared/constants'
import { relationsOf } from '../shared/relations'
import type { ChromeMessage, Quiz } from '../shared/types'

/** 이보다 문단이 적으면 기사로 보지 않고 중단(비기사 페이지에서 /quiz 남발 방지, §T3.2). */
const MIN_ARTICLE_PARAGRAPHS = 3

/** background에 퀴즈 트리를 요청한다(§T3.3). 실패·비정상 응답 시 throw. */
async function requestQuiz(title: string, body: string): Promise<Quiz[]> {
  const resp = (await chrome.runtime.sendMessage(
    { type: 'REQUEST_QUIZ', title, body } satisfies ChromeMessage,
  )) as ChromeMessage
  if (resp.type === 'QUIZ_ERROR') throw new Error(resp.error)
  if (resp.type === 'QUIZ_RESPONSE') return resp.quiz
  throw new Error('unexpected quiz response')
}

/** boot 결과. 실패 사유는 제안 카드·팝업이 사용자에게 그대로 보여준다. */
type BootResult = { ok: true } | { ok: false; reason: string }

/**
 * 이 페이지가 기사로 인식되는지 확인한다. 네트워크는 쓰지 않는다.
 * @returns 기사면 추출 결과, 아니면 null.
 */
function detectArticle(): ExtractResult | null {
  if (isNonArticleUrl(location.href)) return null

  const extract = extractArticle()
  if (!extract || extract.paragraphs.length < MIN_ARTICLE_PARAGRAPHS) return null

  return extract
}

async function boot(): Promise<BootResult> {
  // 0~1) URL 게이트 + 본문 추출. 시작 시점의 DOM 으로 다시 추출한다
  //      (제안 카드가 뜬 뒤 본문이 더 로드됐을 수 있다. extractArticle 은 idempotent).
  if (isNonArticleUrl(location.href)) {
    return { ok: false, reason: '기사 페이지가 아닙니다. 기사를 연 뒤 다시 눌러주세요.' }
  }

  const extract = extractArticle()
  if (!extract || extract.paragraphs.length < MIN_ARTICLE_PARAGRAPHS) {
    return { ok: false, reason: '이 페이지에서 기사 본문을 찾지 못했습니다.' }
  }

  // 2) 퀴즈 트리 요청. 실패·빈 응답이면 패널 없이 중단.
  let quizzes: Quiz[]
  try {
    quizzes = await requestQuiz(extract.title, extract.body)
  } catch {
    return { ok: false, reason: '질문을 만들지 못했습니다. 잠시 후 다시 시도해주세요.' }
  }
  if (quizzes.length === 0) {
    return { ok: false, reason: '이 기사에서 낼 질문을 찾지 못했습니다.' }
  }

  // 3) 앵커 매칭.
  const anchor = anchorQuizzes(quizzes, extract.paragraphs)

  // 4~5) 제출 큐 + 관찰기(콜백은 아래에서 컨트롤러가 소유).
  const queue = createSessionQueue()
  const observer = createParagraphObserver()

  // 6) 패널 마운트. onEnd = 스크랩 전송 + 세션 정지(종료 후 새 문항 방지).
  //    ended 상태 UI는 B가 종료 버튼 내부에서 렌더(SessionStore 무변경).
  mountPanel({
    onEnd: () => {
      const results = useSession.getState().flushResults()
      chrome.runtime
        .sendMessage(
          {
            type: 'SEND_SCRAP',
            // 원문은 싣지 않는다(명세 §3.4). /quiz 에서 이미 보냈고, 출처는 URL로 식별한다.
            payload: {
              articleUrl: location.href,
              articleTitle: extract.title,
              results,
              // 트리가 이미 아는 선행 관계. 사용자가 다 맞혀도 관계는 남아야 한다.
              relations: relationsOf(quizzes),
            },
          } satisfies ChromeMessage,
        )
        .catch(() => {
          // 전송 실패 시 재시도 큐는 C의 T=4/Step 8 소관.
        })
      queue.dispose() // phase 구독 해제 → 이후 pump 중단
      observer.disconnect() // 이후 문단 진입 발화 중단
    },
  })

  // 7) 단일 콜백을 컨트롤러가 소유: 진입 idx의 Quiz를 큐에 넣고,
  //    마지막 문단 도달 시 unanchored(하단 강등)를 큐 뒤에 1회 append(§2b-확정 결정4).
  const lastIdx = extract.paragraphs[extract.paragraphs.length - 1]?.idx
  let unanchoredFlushed = false
  observer.onParagraphEnter((idx) => {
    const qs = anchor.byParagraph.get(idx)
    if (qs) queue.enqueue(qs)
    if (!unanchoredFlushed && idx === lastIdx && anchor.unanchored.length > 0) {
      unanchoredFlushed = true
      queue.enqueue(anchor.unanchored)
    }
  })

  // 8) 앵커된 문단 + 마지막 문단(unanchored flush 트리거용)만 관찰.
  const watched = extract.paragraphs.filter(
    (p) => anchor.byParagraph.has(p.idx) || p.idx === lastIdx,
  )
  observer.observe(watched)

  // MVP: SPA 재이동/이탈 teardown은 Step 10 여력 시.
  return { ok: true }
}

// ─── 활성화 ──────────────────────────────────────────────────────────────────
// 세션을 자동으로 시작하지는 않는다. 대신 기사로 인식되면 우하단에 제안 카드를
// 띄우고, 사용자가 "읽기 시작"을 눌렀을 때만 /quiz 를 호출하고 패널을 연다.
// 팝업의 "이 기사에서 시작" 버튼도 같은 경로를 탄다.

let sessionStarted = false
let dismissed = false

/** 세션 시작(중복 방지 포함). 성공하면 제안 카드를 내린다. */
async function startSession(): Promise<BootResult> {
  if (sessionStarted) return { ok: false, reason: '이미 이 기사에서 실행 중입니다.' }

  const result = await boot()
  if (result.ok) {
    sessionStarted = true
    unmountStartPrompt()
  }
  return result
}

/** 기사로 인식되면 제안 카드를 띄운다. 본문을 늦게 그리는 사이트를 위해 재시도한다. */
function offerStart(): void {
  for (const delay of DETECT_RETRY_DELAYS_MS) {
    window.setTimeout(() => {
      if (sessionStarted || dismissed) return
      if (!detectArticle()) return

      mountStartPrompt({
        onStart: startSession,
        onDismiss: () => {
          dismissed = true
          unmountStartPrompt()
        },
      })
    }, delay)
  }
}

offerStart()

// 팝업에서 온 시작 요청(제안 카드를 닫았거나 감지에 실패한 경우의 수동 경로).
chrome.runtime.onMessage.addListener((message: ChromeMessage, _sender, sendResponse) => {
  if (message.type !== 'START_SESSION') return undefined

  void startSession().then((result) => {
    sendResponse(
      result.ok
        ? { type: 'SESSION_STARTED' }
        : { type: 'SESSION_UNAVAILABLE', reason: result.reason },
    )
  })

  return true // 비동기 응답
})
