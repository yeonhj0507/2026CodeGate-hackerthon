// =============================================================================
// content/ui/Panel.tsx — 패널 루트 (Stream B)
//
// SessionStore만 구독한다. DOM·서버·chrome API 직접 접근 없음.
// "학습 종료"의 실제 스크랩 전송은 이 UI가 아니라 주입된 onEnd 콜백이 담당
// (background 호출은 content orchestrator가 연결 — T=3 align).
// =============================================================================

import { useEffect, useRef, useState } from 'react'
import { useSession } from '../session'
import { ProberLogo } from './ProberLogo'
import { QuestionView } from './QuestionView'

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

  // 정답으로 IDLE 복귀 시 짧게 확인 토스트를 띄운다(별도 phase 없이 UI 로컬 처리).
  const [toast, setToast] = useState(false)
  const prevLen = useRef(0)
  useEffect(() => {
    if (results.length === 0) {
      prevLen.current = 0
      return
    }
    if (results.length > prevLen.current) {
      prevLen.current = results.length
      if (results[results.length - 1].correct) {
        setToast(true)
        const t = setTimeout(() => setToast(false), 1400)
        return () => clearTimeout(t)
      }
    }
  }, [results])

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
      <header className="header">
        <div className="brand">
          <ProberLogo size={20} />
          <span>프로버</span>
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
          <div className="idle">
            <span className="emoji">{toast ? '✅' : '📖'}</span>
            {toast ? (
              <div>정답이에요! 개념을 이해했어요.</div>
            ) : (
              <div>
                기사를 읽어 내려가면
                <br />
                놓치기 쉬운 지점에서 질문이 나타나요.
              </div>
            )}
          </div>
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
