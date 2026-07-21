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

import { extractArticle } from './extractor'
import { isNonArticleUrl, looksLikeArticleList } from './page-gate'
import { anchorQuizzes } from './anchor'
import { createParagraphObserver } from './observer'
import { createSessionQueue } from './session-bind'
import { mountPanel } from './ui/mount'
import { useSession } from './session'
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

async function boot(): Promise<void> {
  // 0) URL 게이트: 언론사 메인/섹션 페이지면 추출조차 하지 않는다(§page-gate).
  if (isNonArticleUrl(location.href)) return

  // 1) 본문 추출 + 기사 품질 게이트.
  const extract = extractArticle()
  if (!extract || extract.paragraphs.length < MIN_ARTICLE_PARAGRAPHS) return

  // 1b) 구조 게이트: 문단이 기사 카드마다 흩어져 있으면 목록 페이지로 보고 중단.
  if (looksLikeArticleList(extract.paragraphs)) return

  // 2) 퀴즈 트리 요청. 실패/빈 응답이면 패널 없이 조용히 중단(MVP, 페이지 내 에러 UI 없음).
  let quizzes: Quiz[]
  try {
    quizzes = await requestQuiz(extract.title, extract.body)
  } catch {
    return
  }
  if (quizzes.length === 0) return

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
}

void boot()
