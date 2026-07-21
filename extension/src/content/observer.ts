// =============================================================================
// content/observer.ts — 문단 진입 감지 (Stream A / Step 5)
//
// 책임 (shared_contract.md §Stream A):
//   - onParagraphEnter(idx: number) 콜백을 외부(session.ts)가 등록할 수 있게 노출
//   - 문단당 1회만 트리거 (중복 방지)
//   - IntersectionObserver로 data-prober-idx 문단 관찰
//
// 동작 (plan §3.4):
//   - OBSERVER_OPTIONS(rootMargin '-40% 0px -60% 0px')로 "문단 상단이 뷰포트
//     상단 40% 지점 통과" 시점을 진입으로 판정. ⚠️ Step 10 튜닝 대상.
//   - 진입 순서 무관, 각 문단 독립 처리(아래로 점프해도 동작).
//   - observer는 퀴즈를 알지 못한다(idx 기반). idx→Quiz 해석은 호출부가
//     anchor의 byParagraph로 수행. → 앵커 매칭된 문단만 observe()에 넘기면
//     불필요한 발화를 피할 수 있다.
// =============================================================================

import type { Paragraph } from '../shared/types'
import { OBSERVER_OPTIONS } from '../shared/constants'
import { PROBER_IDX_ATTR } from './extractor'

export type ParagraphEnterCallback = (idx: number) => void

export interface ParagraphObserver {
  /** 관찰 대상 문단 등록. 여러 번 호출 시 누적 관찰. */
  observe(targets: Paragraph[]): void
  /** 진입 콜백 등록(단일). 재호출 시 교체. */
  onParagraphEnter(cb: ParagraphEnterCallback): void
  /** 특정 문단을 다시 발화 가능하도록 되돌림(재관찰). */
  rearm(idx: number): void
  /** 발화 이력 초기화(재추출 시). 관찰 대상은 유지되지 않으니 observe 재호출 필요. */
  reset(): void
  /** 관찰 전면 중단 + 정리. */
  disconnect(): void
}

/**
 * 문단 진입 감지기 생성.
 * @param doc 테스트/멀티프레임 대비 주입 가능. 기본 document.
 */
export function createParagraphObserver(doc: Document = document): ParagraphObserver {
  let callback: ParagraphEnterCallback | null = null
  const fired = new Set<number>() // 이미 진입 발화한 문단 idx (중복 방지)
  const observedEls = new Set<Element>()

  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue

      const idx = readIdx(entry.target)
      if (idx === null) continue
      if (fired.has(idx)) continue

      fired.add(idx)
      io.unobserve(entry.target) // 1회 트리거: 발화 후 관찰 해제
      observedEls.delete(entry.target)

      callback?.(idx)
    }
  }, OBSERVER_OPTIONS)

  return {
    observe(targets: Paragraph[]) {
      for (const p of targets) {
        if (!p.el || observedEls.has(p.el) || fired.has(p.idx)) continue
        observedEls.add(p.el)
        io.observe(p.el)
      }
    },

    onParagraphEnter(cb: ParagraphEnterCallback) {
      callback = cb
    },

    rearm(idx: number) {
      fired.delete(idx)
      const el = doc.querySelector(`[${PROBER_IDX_ATTR}="${CSS.escape(String(idx))}"]`)
      if (el && !observedEls.has(el)) {
        observedEls.add(el)
        io.observe(el)
      }
    },

    reset() {
      fired.clear()
      for (const el of observedEls) io.unobserve(el)
      observedEls.clear()
    },

    disconnect() {
      io.disconnect()
      observedEls.clear()
      fired.clear()
      callback = null
    },
  }
}

/** 요소의 data-prober-idx를 정수로 읽는다. 없거나 파싱 실패 시 null. */
function readIdx(el: Element): number | null {
  const raw = el.getAttribute(PROBER_IDX_ATTR)
  if (raw === null) return null
  const n = Number.parseInt(raw, 10)
  return Number.isInteger(n) ? n : null
}
