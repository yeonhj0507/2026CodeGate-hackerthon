// =============================================================================
// content/session-bind.ts — session 제출 큐 (Stream B)
//
// T=2 A↔B align 최종 결정(옵션 1, stream_a_align.md §2b-확정):
//   "큐+pump 메커니즘은 B 모듈, 단일 observer 콜백은 컨트롤러 소유."
//
// 이 모듈은 observer/anchor를 모른다. 컨트롤러(content/index.tsx, T=3)가
// observer.onParagraphEnter 안에서 anchor.byParagraph.get(idx)로 Quiz[]를 뽑아
// enqueue()로 넘긴다. 여기서는 "언제 startQuestion 할지"만 책임진다.
//
// 왜 큐가 필요한가:
//   observer는 문단당 1회 발화 후 unobserve(one-shot). 사용자가 문항 풀이 중
//   (phase !== 'IDLE') 다른 문단이 진입하면 startQuestion이 드롭되는데, 그 문단은
//   이미 fired 처리라 재발화되지 않음 → 퀴즈 유실. 큐에 쌓아 IDLE 복귀 시 pump해
//   유실을 막는다(한 문단 다중 Quiz·빠른 스크롤 다문단 진입 모두 커버).
//
// 계약 경계:
//   - session의 공개 진입점 startQuestion / phase 구독만 사용. store 내부 미접근.
//   - enqueue 순서 = 제시 순서(FIFO). 상한 없음(MVP, Step 10 재검토).
// =============================================================================

import type { Quiz } from '../shared/types'
import { useSession } from './session'

export interface SessionQueue {
  /** Quiz들을 대기열에 넣는다. session이 IDLE이면 즉시 다음 문항을 제시. */
  enqueue: (quizzes: Quiz[]) => void
  /** 아직 제시하지 못한(대기 중인) 문항 수. 자동 완료 판정에 쓴다. */
  size: () => number
  /** phase 구독을 해제한다. 재추출·페이지 이탈 시 호출. */
  dispose: () => void
}

/**
 * observer 진입 이벤트를 session에 흘려보내는 FIFO 제출 큐를 만든다.
 * observer/anchor와 무관 — 컨트롤러가 Quiz[]를 enqueue로 넘긴다.
 */
export function createSessionQueue(): SessionQueue {
  // 아직 제시하지 못한 Quiz 대기열. 진입 순서 = 제시 순서.
  const queue: Quiz[] = []

  // IDLE이면 큐에서 하나 꺼내 제시. 진행 중이면 그대로 둠(다음 IDLE 복귀 때 재시도).
  const pump = () => {
    if (useSession.getState().phase !== 'IDLE') return
    const next = queue.shift()
    if (next) useSession.getState().startQuestion(next)
  }

  // session이 IDLE로 "복귀"하는 순간마다 큐를 이어서 소진.
  // (정답 → IDLE, 또는 재질문 소진 → IDLE 전이 시)
  const unsubscribe = useSession.subscribe((state, prev) => {
    if (state.phase === 'IDLE' && prev.phase !== 'IDLE') pump()
  })

  return {
    enqueue: (quizzes) => {
      if (quizzes.length > 0) queue.push(...quizzes)
      pump()
    },
    size: () => queue.length,
    dispose: unsubscribe,
  }
}
