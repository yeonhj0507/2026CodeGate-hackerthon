// =============================================================================
// content/xp-toast.ts — 정답·재질문 완주 순간의 "+N XP" 토스트 (Stream B)
//
// ⚠️ 여기 찍히는 숫자는 **낙관적 추정**이다. 실제 XP 원장은 로컬앱에만 있고
// (local_app/lib/data/xp/xp_rules.dart), 그 값은 동기화 시점의 그래프 diff로
// 확정된다 — 익스텐션과 로컬앱은 서버를 통해서만 통신하고 서로 직접 모른다
// (§9 아키텍처 확정). 그래서 이 토스트는 "실제로 몇 XP가 적립됐다"는 보장이
// 아니라 "지금 한 행동이 보통 몇 XP짜리인지"를 즉시 보여주는 긍정 피드백이다.
// 예: 이미 이해완료였던 개념을 다시 맞혀도 여기서는 뜨지만, 로컬앱 원장에는
// 중복이라 실제로 적립되지 않을 수 있다. 사용자가 "왜 숫자가 안 맞지"라고
// 캐물을 만큼 정밀한 자리에는 쓰지 말 것 — 즉각성이 정확성보다 중요한 자리다.
//
// 배점은 local_app의 XpKind와 같은 값을 그대로 옮겨 적었다. 두 코드베이스가
// 다른 언어·다른 레포 경계에 있어(§9) import로 공유할 방법이 없다. 로컬앱의
// 배점을 바꾸면 여기도 손으로 맞춰야 한다.
// =============================================================================

import { create } from 'zustand'

export interface XpToastEvent {
  id: number
  amount: number
  label: string
}

interface XpToastStore {
  toasts: XpToastEvent[]
  push: (amount: number, label: string) => void
  dismiss: (id: number) => void
}

let nextId = 0

export const useXpToast = create<XpToastStore>((set) => ({
  toasts: [],
  push: (amount, label) => {
    const id = nextId++
    set((s) => ({ toasts: [...s.toasts, { id, amount, label }] }))
  },
  // 컴포넌트가 CSS 애니메이션 종료(onAnimationEnd)에서 부른다 — 별도 JS 타이머
  // 없이 화면에 뜬 만큼만 정확히 살아 있다.
  dismiss: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}))

/** 정답(level 0)에 해당하는 배점. local_app XpKind.correctAnswer 와 동일. */
export const XP_TOAST_CORRECT = { amount: 10, label: '정답' } as const

/** 재질문 완주(level 1/2)에 해당하는 배점. local_app XpKind.followupCompleted 와 동일. */
export const XP_TOAST_FOLLOWUP = { amount: 15, label: '재질문 완주' } as const
