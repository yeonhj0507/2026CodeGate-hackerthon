// =============================================================================
// content/quiz-feed.ts — 퀴즈 스트림 진행 상태 (패널 대기 표시용)
//
// session.ts(Stream B)와 분리한 이유: 저 스토어는 "지금 푸는 문항"의 상태머신이고,
// 여기는 "문항이 아직 오는 중인가"라는 별개의 축이다. 섞으면 phase 전이 규칙에
// 스트림 사정이 끼어든다.
//
// 패널이 대기를 표시할 조건은 이 스토어 혼자로는 정해지지 않는다:
//   streaming(여기) && phase === 'IDLE' && !active(session)
// = "낼 문항이 지금 없는데 아직 만드는 중" = 읽는 속도가 생성 속도를 앞질렀다.
// 어느 문단에 문항이 붙을지는 LLM 이 정하므로 문단 단위로는 예측할 수 없다.
// 이 조건은 예측 없이 사후로만 판정하므로 오탐이 없다.
// =============================================================================

import { create } from 'zustand'

export interface QuizFeedStore {
  /** 서버가 아직 문항을 보내고 있는가. */
  streaming: boolean
  /** 지금까지 도착한 문항 수(재질문 제외, 주장 문항 기준). */
  ready: number
  /** 스트림이 문항을 하나도 못 준 채 끝났을 때의 사유. */
  error: string | null

  begin: () => void
  arrive: () => void
  finish: () => void
  fail: (error: string) => void
}

export const useQuizFeed = create<QuizFeedStore>((set) => ({
  streaming: false,
  ready: 0,
  error: null,

  begin: () => set({ streaming: true, ready: 0, error: null }),
  arrive: () => set((s) => ({ ready: s.ready + 1 })),
  finish: () => set({ streaming: false }),
  // 도중에 끊겨도 이미 받은 문항은 그대로 푼다. streaming 만 내려 대기 표시를 지운다.
  fail: (error) => set({ streaming: false, error }),
}))
