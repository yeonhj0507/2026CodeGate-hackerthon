// =============================================================================
// content/anchor.ts — 퀴즈 ↔ 실제 DOM 문단 앵커 매칭 (Stream A / Step 4)
// ⚠️ 최대 구현 리스크. 실패 시 퀴즈가 엉뚱한 문단에 표시됨.
//
// 책임 (shared_contract.md §Stream A):
//   입력: Quiz[] + Paragraph[]
//   출력: 각 Quiz가 어느 Paragraph에 걸리는지의 매핑
//
// ── 계약 표기 관련 note ──────────────────────────────────────────────────────
//   contract 문구는 "Map<number, Paragraph> (claimId → Paragraph)"라고 적혀 있으나
//   claimId는 string이므로 키 타입이 상충한다. 또한 실제 소비자(observer.ts)는
//   "문단 idx → Quiz[]" 방향이 필요하다(진입한 문단에서 어떤 퀴즈를 띄울지).
//   → 두 방향을 모두 담는 AnchorResult를 반환한다. claimId→Paragraph 매핑은
//     byClaim.get(claimId).paragraph 로 그대로 얻을 수 있어 계약 의도를 만족한다.
//   (anchor↔observer는 둘 다 Stream A 내부. 이 표기 불일치는 팀 align 항목으로 공유.)
//
// 매칭 우선순위 (plan §3.3):
//   1) anchorText 부분/정확 일치        → 가장 신뢰
//   2) 문자열 유사도(Dice bigram) 최고 문단
//   3) paragraphIndex 번호 직접 접근     → LLM이 틀릴 수 있는 보조 수단
//   4) 완전 실패 → unanchored (기사 하단 일괄 노출로 강등)
// =============================================================================

import type { Paragraph, Quiz } from '../shared/types'
import { ANCHOR_COMPARE_LENGTH, ANCHOR_SIMILARITY_THRESHOLD } from '../shared/constants'
import { normalizeText } from './extractor'

// ─── 결과 타입 ───────────────────────────────────────────────────────────────

export type AnchorMethod = 'exact' | 'partial' | 'similarity' | 'index' | 'none'

export interface AnchorMatch {
  quiz: Quiz
  paragraph: Paragraph | null // null이면 매칭 실패 → 하단 강등 대상
  method: AnchorMethod
  score: number // 0~1 (index/exact는 관례상 1, none은 0)
}

export interface AnchorResult {
  /** claimId → 매칭 결과. (계약의 "claimId → Paragraph"는 .paragraph로 획득) */
  byClaim: Map<string, AnchorMatch>
  /** 문단 idx → 그 문단에 걸린 Quiz[]. observer가 진입 시 이 맵으로 퀴즈를 찾는다. */
  byParagraph: Map<number, Quiz[]>
  /** 매칭 실패해 기사 하단에 일괄 노출해야 할 Quiz[]. */
  unanchored: Quiz[]
}

// ─── 메인 진입점 ─────────────────────────────────────────────────────────────

/**
 * 각 Quiz를 가장 그럴듯한 Paragraph에 연결한다.
 * @param quizzes    서버가 내려준 퀴즈 트리(최상위 노드들)
 * @param paragraphs extractArticle이 만든 문단 배열
 */
export function anchorQuizzes(quizzes: Quiz[], paragraphs: Paragraph[]): AnchorResult {
  const byClaim = new Map<string, AnchorMatch>()
  const byParagraph = new Map<number, Quiz[]>()
  const unanchored: Quiz[] = []

  // 문단별 정규화·소문자 leading 텍스트를 미리 계산(퀴즈마다 재계산 방지).
  const heads = paragraphs.map((p) => normalizeText(p.text).slice(0, ANCHOR_COMPARE_LENGTH).toLowerCase())

  for (const quiz of quizzes) {
    const match = matchOne(quiz, paragraphs, heads)
    byClaim.set(quiz.claimId, match)

    if (match.paragraph) {
      const idx = match.paragraph.idx
      const list = byParagraph.get(idx)
      if (list) list.push(quiz)
      else byParagraph.set(idx, [quiz])
    } else {
      unanchored.push(quiz)
    }
  }

  return { byClaim, byParagraph, unanchored }
}

// ─── 단일 퀴즈 매칭 ──────────────────────────────────────────────────────────

function matchOne(quiz: Quiz, paragraphs: Paragraph[], heads: string[]): AnchorMatch {
  if (paragraphs.length === 0) {
    return { quiz, paragraph: null, method: 'none', score: 0 }
  }

  const anchor = normalizeText(quiz.anchorText).slice(0, ANCHOR_COMPARE_LENGTH).toLowerCase()

  // ── 1) 부분/정확 일치 ──────────────────────────────────────────────────────
  if (anchor.length >= 2) {
    let containHit: { i: number; exact: boolean } | null = null
    for (let i = 0; i < heads.length; i++) {
      const head = heads[i]
      if (!head) continue
      if (head === anchor) {
        containHit = { i, exact: true }
        break
      }
      // 한쪽이 다른 쪽을 포함하면 부분 일치. (anchor는 문단 앞 40~60자라는 계약)
      if (head.includes(anchor) || anchor.includes(head)) {
        if (!containHit) containHit = { i, exact: false }
      }
    }
    if (containHit) {
      return {
        quiz,
        paragraph: paragraphs[containHit.i],
        method: containHit.exact ? 'exact' : 'partial',
        score: 1,
      }
    }
  }

  // ── 2) 문자열 유사도 (Dice bigram) ─────────────────────────────────────────
  if (anchor.length >= 2) {
    let bestI = -1
    let bestScore = 0
    for (let i = 0; i < heads.length; i++) {
      const head = heads[i]
      if (head.length < 2) continue
      // 같은 길이 창으로 비교(문단 앞부분이 anchor와 얼마나 겹치는지).
      const window = head.slice(0, anchor.length)
      const score = diceCoefficient(anchor, window)
      if (score > bestScore) {
        bestScore = score
        bestI = i
      }
    }
    if (bestI >= 0 && bestScore >= ANCHOR_SIMILARITY_THRESHOLD) {
      return { quiz, paragraph: paragraphs[bestI], method: 'similarity', score: bestScore }
    }
  }

  // ── 3) paragraphIndex 직접 접근 (보조 수단) ────────────────────────────────
  const pIdx = quiz.paragraphIndex
  if (Number.isInteger(pIdx) && pIdx >= 0 && pIdx < paragraphs.length) {
    return { quiz, paragraph: paragraphs[pIdx], method: 'index', score: 0.5 }
  }

  // ── 4) 완전 실패 → 하단 강등 ───────────────────────────────────────────────
  return { quiz, paragraph: null, method: 'none', score: 0 }
}

// ─── Dice 유사도 (bigram 기반) ───────────────────────────────────────────────

/**
 * 두 문자열의 Dice 계수(0~1). 문자 bigram 다중집합 겹침 기준.
 * 한국어도 문자 단위 bigram으로 잘 동작.
 */
export function diceCoefficient(a: string, b: string): number {
  if (a === b) return 1
  if (a.length < 2 || b.length < 2) return 0

  const bgA = bigrams(a)
  const bgB = bigrams(b)

  let total = 0
  for (const v of bgA.values()) total += v
  for (const v of bgB.values()) total += v
  if (total === 0) return 0

  let overlap = 0
  for (const [bg, ca] of bgA) {
    const cb = bgB.get(bg)
    if (cb) overlap += Math.min(ca, cb)
  }
  return (2 * overlap) / total
}

/** 문자열의 인접 문자쌍(bigram) 다중집합. */
function bigrams(s: string): Map<string, number> {
  const m = new Map<string, number>()
  for (let i = 0; i < s.length - 1; i++) {
    const bg = s.slice(i, i + 2)
    m.set(bg, (m.get(bg) ?? 0) + 1)
  }
  return m
}
