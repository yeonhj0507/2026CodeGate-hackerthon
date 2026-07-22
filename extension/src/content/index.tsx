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
import { useQuizFeed } from './quiz-feed'
import { useSessionEnd } from './session-end'
import { DETECT_RETRY_DELAYS_MS } from '../shared/constants'
import { relationsOf } from '../shared/relations'
import { debugLog } from '../shared/debug'
import { QUIZ_PORT } from '../shared/types'
import type {
  ChromeMessage,
  Quiz,
  QuizStreamEvent,
  StartQuizStream,
} from '../shared/types'

/** 이보다 문단이 적으면 기사로 보지 않고 중단(비기사 페이지에서 /quiz 남발 방지, §T3.2). */
const MIN_ARTICLE_PARAGRAPHS = 3

// 한 번에 받아 오던 requestQuiz 는 없앴다. 전체 대기(≈55초) 대신 스트림으로 받는다.
// 폴백(기존 POST /quiz)은 background 의 streamQuizRequest 안에서 처리하므로
// content 는 스트림 하나만 알면 된다.

/** 퀴즈 스트림을 열고 도착하는 대로 콜백에 넘긴다. 반환값으로 스트림을 끊을 수 있다. */
function openQuizStream(
  title: string,
  body: string,
  handlers: {
    onItem: (quiz: Quiz) => void
    onDone: (total: number) => void
    onError: (error: string) => void
  },
): () => void {
  const port = chrome.runtime.connect({ name: QUIZ_PORT })
  debugLog('stream port connected')

  port.onMessage.addListener((event: QuizStreamEvent) => {
    debugLog('port message:', event.type)
    if (event.type === 'QUIZ_ITEM') handlers.onItem(event.quiz)
    else if (event.type === 'QUIZ_DONE') handlers.onDone(event.total)
    else if (event.type === 'QUIZ_STREAM_ERROR') handlers.onError(event.error)
  })

  // 서비스워커가 죽거나 재시작하면 done 없이 끊긴다. 대기 표시가 영원히 남지 않게 한다.
  port.onDisconnect.addListener(() => {
    debugLog('port disconnected; lastError:', chrome.runtime.lastError?.message)
    handlers.onDone(-1)
  })

  port.postMessage({ type: 'START_QUIZ_STREAM', title, body } satisfies StartQuizStream)
  debugLog('START_QUIZ_STREAM sent; bodyLen=', body.length)
  return () => port.disconnect()
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
  // 0) 로그인 확인 — 서버 /quiz·/scrap 은 인증이 필요하다(계정별 지식그래프).
  //    미로그인이면 여기서 멈추고, 이 사유를 시작 카드/팝업이 그대로 보여준다.
  let auth: ChromeMessage | null = null
  try {
    auth = (await chrome.runtime.sendMessage({
      type: 'GET_AUTH_STATUS',
    } satisfies ChromeMessage)) as ChromeMessage
  } catch {
    auth = null
  }
  if (!auth || auth.type !== 'AUTH_STATUS' || !auth.loggedIn) {
    return {
      ok: false,
      reason: '로그인이 필요합니다. 오른쪽 위 프로버(Prober) 아이콘을 눌러 로그인해 주세요.',
    }
  }

  // 0~1) URL 게이트 + 본문 추출. 시작 시점의 DOM 으로 다시 추출한다
  //      (제안 카드가 뜬 뒤 본문이 더 로드됐을 수 있다. extractArticle 은 idempotent).
  if (isNonArticleUrl(location.href)) {
    return { ok: false, reason: '기사 페이지가 아닙니다. 기사를 연 뒤 다시 눌러주세요.' }
  }

  const extract = extractArticle()
  if (!extract || extract.paragraphs.length < MIN_ARTICLE_PARAGRAPHS) {
    return { ok: false, reason: '이 페이지에서 기사 본문을 찾지 못했습니다.' }
  }

  // 2) 첫 문항을 **기다리지 않는다**. 전체 트리 생성은 1분 가까이 걸리는데, 그동안
  //    패널조차 안 뜨면 사용자는 빈 화면을 보고 있게 된다. 스트림을 열어 두고
  //    도착하는 대로 채운다(서버 /quiz/stream). 실측 첫 문항 ≈ 17초.
  const quizzes: Quiz[] = [] // 누적본. onEnd 의 relationsOf 가 이걸 쓴다.
  const byParagraph = new Map<number, Quiz[]>()
  const unanchored: Quiz[] = []
  const passed = new Set<number>() // 사용자가 이미 지나친 문단
  let streamEnded = false

  // 4~5) 제출 큐 + 관찰기(콜백은 아래에서 컨트롤러가 소유).
  const queue = createSessionQueue()
  const observer = createParagraphObserver()

  // 6) 세션 종료 — 수동 버튼과 자동 완료가 공유한다. 한 번만 실행(재진입 방지):
  //    스크랩 전송 + 완료화면 표시 + 세션 정지(종료 후 새 문항 방지).
  let sessionEnded = false
  let unsubComplete: (() => void) | null = null
  const endSession = () => {
    if (sessionEnded) return
    sessionEnded = true
    unsubComplete?.() // 이후 IDLE 전이에 자동완료가 다시 발화하지 않게
    const results = useSession.getState().flushResults()
    // 완료화면 요약은 flushResults 로 results 가 비워지기 전 스냅샷(여기선 반환값 사용).
    useSessionEnd.getState().markEnded({
      solved: results.length,
      correct: results.filter((r) => r.correct).length,
    })
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
    closeStream() // 남은 문항을 더 받지 않는다
  }

  // 아직 제시 안 됐거나 앵커 대기 중인 문항 수. 0 이면 낼 게 없다.
  const pendingCount = () => {
    let n = queue.size() + unanchored.length
    for (const qs of byParagraph.values()) n += qs.length
    return n
  }

  // 문항 루프를 다 돌면 자동으로 학습 종료:
  //   스트림 끝 + 대기 문항 0 + 지금 푸는 문항 없음(IDLE) + 1개 이상 답함.
  const maybeAutoComplete = () => {
    if (sessionEnded || !streamEnded) return
    const s = useSession.getState()
    if (s.phase !== 'IDLE' || s.results.length === 0) return
    if (pendingCount() > 0) return
    endSession()
  }

  // 문항 하나가 완결돼 IDLE 로 돌아올 때마다 완료 여부를 점검한다
  // (재질문 체인까지 끝나야 IDLE 로 오므로, 트리 전체 소진 시점에만 발화).
  unsubComplete = useSession.subscribe((state, prev) => {
    if (state.phase === 'IDLE' && prev.phase !== 'IDLE') maybeAutoComplete()
  })

  mountPanel({ onEnd: endSession })

  // 7) 단일 콜백을 컨트롤러가 소유: 진입 idx의 Quiz를 큐에 넣고,
  //    마지막 문단 도달 시 unanchored(하단 강등)를 큐 뒤에 1회 append(§2b-확정 결정4).
  const lastIdx = extract.paragraphs[extract.paragraphs.length - 1]?.idx
  let unanchoredFlushed = false
  let reachedLast = false

  /**
   * unanchored 는 **스트림이 끝난 뒤에만** 낸다. 아직 오는 중이라면 뒤에 도착할
   * 문항이 이 문단에 앵커될 수도 있어서, 먼저 하단으로 강등해 버리면 순서가 뒤집힌다.
   */
  const flushUnanchored = () => {
    if (unanchoredFlushed || !reachedLast || !streamEnded) return
    if (unanchored.length === 0) return
    unanchoredFlushed = true
    queue.enqueue(unanchored.splice(0))
  }

  observer.onParagraphEnter((idx) => {
    passed.add(idx)
    const qs = byParagraph.get(idx)
    debugLog('enter idx', idx, '| queued quizzes:', qs?.length ?? 0)
    if (qs && qs.length > 0) queue.enqueue(qs.splice(0)) // 같은 문단 재진입 시 중복 출제 방지
    if (idx === lastIdx) reachedLast = true
    flushUnanchored()
  })

  // 8) **전 문단을 관찰한다.** 어느 문단에 문항이 붙을지는 문항이 도착해 봐야 알고,
  //    그때는 사용자가 이미 그 문단을 지났을 수 있다. 미리 다 걸어 두고 passed 로
  //    "이미 지나갔음"을 기록해, 늦게 온 문항을 즉시 낼 수 있게 한다.
  observer.observe(extract.paragraphs)

  // 9) 스트림 개시. 도착할 때마다 앵커를 갱신하고, 지나친 문단이면 바로 큐에 넣는다.
  useQuizFeed.getState().begin()
  const closeStream = openQuizStream(extract.title, extract.body, {
    onItem: (quiz) => {
      quizzes.push(quiz)
      useQuizFeed.getState().arrive()

      // 앵커는 문항 1건씩 돌려도 결과가 같다(anchorQuizzes 는 순수 함수).
      const anchored = anchorQuizzes([quiz], extract.paragraphs)
      debugLog(
        'onItem:', quiz.conceptTag,
        '| byParagraph keys:', [...anchored.byParagraph.keys()],
        '| unanchored:', anchored.unanchored.length,
        '| passed:', [...passed],
      )
      for (const [idx, qs] of anchored.byParagraph) {
        if (passed.has(idx)) {
          queue.enqueue(qs) // 이미 읽고 지나간 문단 — 기다릴 이유가 없다
          continue
        }
        const bucket = byParagraph.get(idx)
        if (bucket) bucket.push(...qs)
        else byParagraph.set(idx, [...qs])
      }
      unanchored.push(...anchored.unanchored)
      flushUnanchored()
    },
    onDone: () => {
      streamEnded = true
      useQuizFeed.getState().finish()
      flushUnanchored()
      maybeAutoComplete() // 마지막 답을 스트림 끝나기 전에 냈다면 여기서 완료 확정
    },
    onError: (error) => {
      streamEnded = true
      useQuizFeed.getState().fail(error)
      flushUnanchored()
      maybeAutoComplete()
    },
  })

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
