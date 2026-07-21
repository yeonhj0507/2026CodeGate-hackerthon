// =============================================================================
// content/ui/Panel.tsx — 패널 루트 (Stream B)
//
// SessionStore만 구독한다. DOM·서버·chrome API 직접 접근 없음.
// "학습 종료"의 실제 스크랩 전송은 이 UI가 아니라 주입된 onEnd 콜백이 담당
// (background 호출은 content orchestrator가 연결 — T=3 align).
// =============================================================================

import { useState } from 'react'
import { useQuizFeed } from '../quiz-feed'
import { useSession } from '../session'
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

  // "학습 종료" 후 표시할 요약. null이면 세션 진행 중, 값이 있으면 종료됨.
  // onEnd가 flushResults로 버퍼를 비우므로 요약은 호출 "전에" 스냅샷으로 잡는다.
  const [endedSummary, setEndedSummary] = useState<{ solved: number; correct: number } | null>(null)
  const ended = endedSummary !== null

  const handleEnd = () => {
    const snapshot = { solved: results.length, correct: results.filter((r) => r.correct).length }
    if (onEnd) onEnd()
    else flushResults()
    setEndedSummary(snapshot) // A의 onEnd 배선이 세션을 정지(dispose/disconnect)하므로 종료 확정 표시
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
            {endedSummary.solved > 0 && (
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
              <div>
                읽는 속도가 더 빠르네요.
                <br />
                다음 질문을 만들고 있어요.
              </div>
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
