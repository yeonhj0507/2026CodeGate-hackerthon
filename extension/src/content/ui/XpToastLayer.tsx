// =============================================================================
// content/ui/XpToastLayer.tsx — "+N XP" 토스트 레이어 (Stream B)
//
// Panel의 .root(position: fixed)를 포지셔닝 컨텍스트로 삼아 절대 배치된다.
// 개수 제한 없이 쌓이는 게 아니라 CSS 애니메이션 종료(onAnimationEnd)에서
// 스스로 dismiss하므로, 정답을 빠르게 여러 번 맞혀도 오래된 토스트부터 알아서
// 빠진다.
// =============================================================================

import { useXpToast } from '../xp-toast'

export function XpToastLayer() {
  const toasts = useXpToast((s) => s.toasts)
  const dismiss = useXpToast((s) => s.dismiss)

  if (toasts.length === 0) return null

  return (
    <div className="xp-toast-layer" aria-hidden="true">
      {toasts.map((t) => (
        <div key={t.id} className="xp-toast" onAnimationEnd={() => dismiss(t.id)}>
          <span className="xp-amount">+{t.amount}</span>
          <span className="xp-label">{t.label}</span>
        </div>
      ))}
    </div>
  )
}
