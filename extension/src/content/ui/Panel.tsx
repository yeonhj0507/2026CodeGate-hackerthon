// =============================================================================
// content/ui/Panel.tsx — 패널 루트 (Stream B)
//
// SessionStore만 구독한다. DOM·서버·chrome API 직접 접근 없음.
// "학습 종료"의 실제 스크랩 전송은 이 UI가 아니라 주입된 onEnd 콜백이 담당
// (background 호출은 content orchestrator가 연결 — T=3 align).
// =============================================================================

import { useQuizFeed } from '../quiz-feed'
import { useSession } from '../session'
import { useSessionEnd } from '../session-end'
import { ProberLogo } from './ProberLogo'
import { QuestionView } from './QuestionView'
import { XpToastLayer } from './XpToastLayer'

interface Props {
  /** "학습 종료" 클릭 시 호출. 미주입 시 flushResults만 수행(mock). */
  onEnd?: () => void
}

export function Panel({ onEnd }: Props) {
  const phase = useSession((s) => s.phase)
  const active = useSession((s) => s.active)
  const results = useSession((s) => s.results)
  const submitAnswer = useSession((s) => s.submitAnswer)
  const dismissExplanation = useSession((s) => s.dismissExplanation)
  const flushResults = useSession((s) => s.flushResults)
  const streaming = useQuizFeed((s) => s.streaming)
  const ready = useQuizFeed((s) => s.ready)

  const solved = results.length
  const correct = results.filter((r) => r.correct).length

  // 종료(수동 버튼 or 문항 루프 완주 시 컨트롤러의 자동 완료)는 session-end store 가
  // 관리한다. 두 경로가 같은 완료화면을 띄우도록 Panel 로컬 state 가 아닌 store 를 읽는다.
  const ended = useSessionEnd((s) => s.ended)
  const endedSummary = useSessionEnd((s) => s.summary)

  const handleEnd = () => {
    if (onEnd) {
      onEnd() // 컨트롤러가 markEnded + 스크랩 전송 + 세션 정지
    } else {
      // onEnd 미주입(mock/테스트 경로): 여기서 직접 완료 표시.
      useSessionEnd.getState().markEnded({
        solved: results.length,
        correct: results.filter((r) => r.correct).length,
      })
      flushResults()
    }
  }

  // active 정체성이 바뀌면(새 문항·재질문 진입) QuestionView를 remount해 selected 초기화.
  const activeKey = active ? `${active.quiz.claimId}-${active.level}` : 'idle'

  return (
    <div className="root">
      <XpToastLayer />
      <header className="header">
        <div className="brand">
          <ProberLogo size={20} />
          <span className="wordmark">prober</span>
        </div>
        {!ended && (
          <button type="button" className="end-btn" onClick={handleEnd}>
            학습 종료
          </button>
        )}
      </header>

      {!ended && solved > 0 && (
        <div className="progress-row">
          <div className="progress-track">
            <div
              className="progress-fill"
              style={{ width: `${(correct / solved) * 100}%` }}
            />
          </div>
          <span className="progress-label">
            {correct}/{solved}
          </span>
        </div>
      )}

      <div className="body">
        {ended ? (
          <div className="idle ended">
            <span className="emoji">🎉</span>
            <div className="ended-title">학습을 마쳤어요</div>
            {endedSummary && endedSummary.solved > 0 && (
              <div className="summary">
                맞힘 {endedSummary.correct} / 푼 문항 {endedSummary.solved}
              </div>
            )}
            <div className="ended-note">진단 결과를 저장했어요.</div>
          </div>
        ) : phase === 'IDLE' || !active ? (
          // 낼 문항이 지금 없다. 아직 만드는 중이면 그 사실을 말해 준다 —
          // 읽는 속도가 생성 속도를 앞지른 상태이고, 안 알려주면 "질문이 안 나온다"로 읽힌다.
          streaming ? (
            <div className="idle">
              <span className="spinner" aria-hidden="true" />
              {ready === 0 ? (
                // 아직 첫 문항 전 — "생성 중"임을 분명히 알린다(빈 화면 오해 방지).
                <div>
                  기사를 분석해
                  <br />
                  질문을 만들고 있어요.
                </div>
              ) : (
                // 이미 몇 개는 준비됐는데 사용자가 그보다 빨리 읽어 내려간 상태.
                <div>
                  읽는 속도가 더 빠르네요.
                  <br />
                  다음 질문을 만들고 있어요.
                </div>
              )}
              {ready > 0 && <div className="feed-note">지금까지 {ready}개 준비됨</div>}
            </div>
          ) : (
            <div className="idle">
              <span className="emoji">📖</span>
              <div>
                기사를 읽어 내려가면
                <br />
                놓치기 쉬운 지점에서 질문이 나타나요.
              </div>
            </div>
          )
        ) : (
          <QuestionView
            key={activeKey}
            active={active}
            phase={phase}
            onSubmit={submitAnswer}
            onNext={dismissExplanation}
          />
        )}
      </div>
    </div>
  )
}
