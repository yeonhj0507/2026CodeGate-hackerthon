// =============================================================================
// content/session-end.ts — 세션 종료(학습 완료) 상태 (Stream B)
//
// "학습 종료"는 두 경로로 일어난다: (1) 사용자가 종료 버튼 클릭, (2) 문항 루프를
// 다 돌아 자동 완료(컨트롤러가 감지). 둘 다 같은 완료 화면을 띄워야 하므로 종료
// 여부·요약을 Panel 로컬 state 가 아니라 이 store 에 둔다. 컨트롤러(content/index.tsx)
// 와 Panel 이 함께 읽고 쓴다.
// =============================================================================

import { create } from 'zustand'

export interface EndedSummary {
  /** 푼 문항 수(재질문 포함). */
  solved: number
  /** 그중 맞힌 수. */
  correct: number
}

interface SessionEndStore {
  /** 세션이 끝났는가(수동 종료 또는 자동 완료). */
  ended: boolean
  /** 종료 시점 스냅샷. flushResults 로 results 가 비워지기 전에 잡아 둔다. */
  summary: EndedSummary | null
  /** 종료 표시. 한 번만 유효(이미 ended 면 무시). */
  markEnded: (summary: EndedSummary) => void
}

export const useSessionEnd = create<SessionEndStore>((set, get) => ({
  ended: false,
  summary: null,
  markEnded: (summary) => {
    if (get().ended) return
    set({ ended: true, summary })
  },
}))
