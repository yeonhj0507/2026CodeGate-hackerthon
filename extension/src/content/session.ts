// =============================================================================
// content/session.ts — 진단 루프 상태머신 (Stream B / Step 6)
//
// 책임 (shared_contract.md §Stream B):
//   - SessionStore 인터페이스를 zustand store로 구현
//   - startQuestion(quiz) 진입점을 observer(Stream A)가 호출
//   - flushResults()는 스크랩 전송 후 results[] 초기화까지 포함
//   - UI(ui/**)는 이 store만 구독 (DOM 직접 접근 금지)
//
// 상태 전이 (extension_implementation_plan.md §3.5):
//   IDLE
//     → (문단 진입: startQuestion) → ASKING(main, level 0)
//     → (답 제출: submitAnswer)     → 채점
//          정답 → 결과기록 + SHOW_CORRECT (채점된 보기 그대로 보여줌)
//          오답 → 결과기록 + SHOW_EXPLANATION
//     → (닫기: dismissExplanation)
//          SHOW_CORRECT              → IDLE (다음 문단 대기, 재질문 없음)
//          SHOW_EXPLANATION —
//            followup 있고 level < 2 → ASKING(followup[level+1])
//            없거나 2단계 소진        → IDLE
//
// 재질문 분기는 이미 수신한 Quiz 트리 내부에서만 처리 (추가 서버 호출 없음).
// =============================================================================

import { create } from 'zustand'
import type {
  SessionStore,
  ActiveQuestion,
  Followup,
  ScrapResult,
} from '../shared/types'
import { MAX_FOLLOWUP_LEVEL } from '../shared/constants'

// ─── 내부 상태 (SessionStore에 노출하지 않음, UI는 구독하지 않는다) ───────────

interface InternalState {
  /**
   * 현재 active.item의 부모 개념명. 스크랩 ScrapResult.parentConcept 기록용.
   * main(level 0)=null, 재질문이면 자신을 파생시킨 상위 문항의 개념명.
   */
  parentConcept: string | null
}

type Store = SessionStore & InternalState

// ─── 헬퍼 ────────────────────────────────────────────────────────────────────

/**
 * active 문항이 검사하는 개념명.
 * level 0 → 최상위 Quiz.conceptTag, 재질문 → Followup.prereqConceptTag.
 * (스크랩 conceptTag는 퀴즈 트리 값을 그대로 echo — shared_contract 계약)
 */
function conceptOf(active: ActiveQuestion): string {
  return active.level === 0
    ? active.quiz.conceptTag
    : (active.item as Followup).prereqConceptTag
}

// ─── Store ───────────────────────────────────────────────────────────────────

export const useSession = create<Store>((set, get) => ({
  phase: 'IDLE',
  active: null,
  results: [],
  parentConcept: null,

  /**
   * observer가 문단 진입 시 호출. anchor 매칭된 최상위 Quiz를 받아 main 문항 제시.
   * 이미 다른 문항 진행 중(ASKING/SHOW_EXPLANATION/SHOW_CORRECT)이면 무시 —
   * 한 번에 한 문항만.
   */
  startQuestion: (quiz) => {
    if (get().phase !== 'IDLE') return
    set({
      phase: 'ASKING',
      active: { quiz, item: quiz, level: 0 },
      parentConcept: null,
    })
  },

  /**
   * 사용자가 보기를 제출. 클라이언트에서 answerIndex 비교로 즉시 채점.
   * 정답·오답 모두 채점된 보기를 그대로 보여준다 — 오답과 같은 방식으로
   * "무엇을 골랐고 정답이 무엇인지"를 확인시킨 뒤 닫게 한다(dismissExplanation).
   */
  submitAnswer: (selectedIndex) => {
    const { phase, active, parentConcept, results } = get()
    if (phase !== 'ASKING' || !active) return

    const correct = selectedIndex === active.item.answerIndex
    const { question, options, answerIndex } = active.item
    const result: ScrapResult = {
      conceptTag: conceptOf(active),
      parentConcept,
      level: active.level,
      correct,
      // 서버가 이 개념의 OX 문항을 만들 재료. 고른 보기가 곧 "틀린 진술"이 된다.
      question,
      selectedOption: options[selectedIndex],
      correctOption: options[answerIndex],
    }

    set({
      results: [...results, result],
      phase: correct ? 'SHOW_CORRECT' : 'SHOW_EXPLANATION',
    })
  },

  /**
   * 설명/정답 확인 후 호출.
   * - SHOW_CORRECT: 재질문 없이 바로 IDLE로 복귀(정답은 선행 개념을 팔 필요가 없다).
   * - SHOW_EXPLANATION: 선행 개념 재질문이 있고 아직 2단계 미만이면 한 단계
   *   파고들고, 없으면 세션을 IDLE로 되돌린다.
   */
  dismissExplanation: () => {
    const { phase, active } = get()
    if (!active) return

    if (phase === 'SHOW_CORRECT') {
      set({ phase: 'IDLE', active: null, parentConcept: null })
      return
    }
    if (phase !== 'SHOW_EXPLANATION') return

    const followups = active.item.followups
    const canDescend = followups.length > 0 && active.level < MAX_FOLLOWUP_LEVEL

    if (canDescend) {
      const next = followups[0]
      set({
        phase: 'ASKING',
        active: { quiz: active.quiz, item: next, level: next.level },
        parentConcept: conceptOf(active), // 방금 틀린 문항이 이 재질문의 부모
      })
    } else {
      set({ phase: 'IDLE', active: null, parentConcept: null })
    }
  },

  /**
   * 누적 결과를 반환하고 버퍼를 비운다. background가 /scrap 전송 직전에 호출.
   * 반환값이 전송 페이로드의 results[]가 됨.
   */
  flushResults: () => {
    const drained = get().results
    set({ results: [] })
    return drained
  },
}))
