// =============================================================================
// content/ui/Explanation.tsx — 채점 설명 + 다음 액션 (Stream B)
//
// 채점(정답/오답) 후 공통으로 쓰는 뷰. 오답이면 선행 개념 재질문이 남아 있을 때
// "짚어보기"(descend)로 이어지고, 정답이면 재질문 없이 바로 "계속 읽기".
// =============================================================================

interface Props {
  text: string
  correct: boolean
  canDescend: boolean
  onNext: () => void
}

export function Explanation({ text, correct, canDescend, onNext }: Props) {
  return (
    <div className={correct ? 'explain explain-ok' : 'explain'}>
      <div className="banner">
        <span>{correct ? '✓ 정답이에요!' : '✕ 아쉬워요'}</span>
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
