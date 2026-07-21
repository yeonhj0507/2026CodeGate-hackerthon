// =============================================================================
// content/ui/Explanation.tsx — 오답 설명 + 다음 액션 (Stream B)
//
// 설명(explanation)은 답 제출 전 항상 숨김 → 오답 채점 후에만 이 컴포넌트 노출.
// 선행 개념 재질문이 남아 있으면 "짚어보기"(descend), 아니면 "계속 읽기".
// =============================================================================

interface Props {
  text: string
  canDescend: boolean
  onNext: () => void
}

export function Explanation({ text, canDescend, onNext }: Props) {
  return (
    <div className="explain">
      <div className="banner">
        <span>✕ 아쉬워요</span>
      </div>
      <div className="text">{text}</div>

      <button
        type="button"
        className={canDescend ? 'next-btn descend' : 'next-btn'}
        onClick={onNext}
      >
        {canDescend ? '선행 개념 짚어보기 →' : '계속 읽기'}
      </button>

      {canDescend && (
        <div className="hint">이 개념을 이해하려면 먼저 알아야 할 것이 있어요</div>
      )}
    </div>
  )
}
