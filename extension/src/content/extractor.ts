// =============================================================================
// content/extractor.ts — 본문 추출 + 문단 인덱싱 (Stream A / Step 2)
//
// 책임 (shared_contract.md §Stream A):
//   - 출력: paragraphs: Paragraph[] (각 el에 data-prober-idx 부여)
//   - articleTitle / articleBody(평문) 함께 반환 (POST /quiz 요청용)
//
// 전략:
//   Readability는 "정제된 본문 텍스트(화이트리스트)"를 얻는 용도로만 쓰고,
//   실제 관찰·앵커링에 쓸 DOM 노드는 라이브 DOM을 직접 순회해 확보한다.
//   → Readability가 반환하는 content는 원본과 분리된(disconnected) 새 DOM이라
//     data-prober-idx를 붙이거나 IntersectionObserver로 관찰할 수 없기 때문.
// =============================================================================

import { Readability } from '@mozilla/readability'
import type { Paragraph } from '../shared/types'

// ─── extractor 내부 튜닝 상수 (cross-stream 계약 아님) ───────────────────────

/** 문단으로 인정할 블록 요소. 리스트·인용·소제목도 독립 문단으로 취급(앵커 정밀도↑). */
const BLOCK_SELECTOR = 'p, li, blockquote, h1, h2, h3, h4, pre, dd'

/** 소제목이 아닌 일반 문단의 최소 글자 수(정규화 후). 짧은 캡션·광고 조각 제거. */
const MIN_PARAGRAPH_LEN = 20

/** 소제목(heading)의 최소 글자 수. 소제목은 짧아도 앵커 포인트로 유효. */
const MIN_HEADING_LEN = 2

/** 화이트리스트 매칭 시 문단 앞부분 몇 글자를 Readability 텍스트에서 찾을지. */
const WHITELIST_PROBE_LEN = 40

/** 텍스트 밀도 폴백에서 컨테이너로 인정할 최소 글자 수. */
const MIN_CONTAINER_TEXT = 200

/** 광고·댓글·추천·내비 등 노이즈 영역 판별용 class/id 패턴. */
const NOISE_PATTERN =
  /(^|[-_\s])(ad|ads|advert|sponsor|promo|comment|reply|recommend|related|share|social|sns|nav|footer|header|sidebar|aside|widget|banner|newsletter|subscribe|cookie|popup|modal|paging|pagination|breadcrumb|byline|caption|copyright|tag|toolbar)([-_\s]|$)/i

/** 소제목 태그 집합. */
const HEADING_TAGS = new Set(['H1', 'H2', 'H3', 'H4'])

// ─── 공개 상수/타입 ──────────────────────────────────────────────────────────

/** extractor가 각 문단 DOM에 부여하는 속성명. observer.ts가 이 값으로 질의. */
export const PROBER_IDX_ATTR = 'data-prober-idx'

/** extractArticle 결과. */
export interface ExtractResult {
  title: string
  /** paragraphs를 순서대로 이어붙인 평문. 서버 paragraphIndex ↔ Paragraph.idx 정렬 목적. */
  body: string
  paragraphs: Paragraph[]
}

// ─── 텍스트 유틸 (anchor.ts도 import) ────────────────────────────────────────

/** 공백 정규화 + 트림. 표시·매칭 공통 기준 텍스트를 만든다(대소문자는 보존). */
export function normalizeText(s: string | null | undefined): string {
  return (s ?? '').replace(/\s+/g, ' ').trim()
}

// ─── 메인 진입점 ─────────────────────────────────────────────────────────────

/**
 * 현재 문서에서 기사 제목·본문·문단 배열을 추출한다.
 * @returns 문단을 1개 이상 찾으면 ExtractResult, 본문으로 볼 만한 게 없으면 null.
 */
export function extractArticle(doc: Document = document): ExtractResult | null {
  // 1) Readability로 정제 텍스트(화이트리스트) + 제목 확보. 원본은 건드리지 않도록 clone에 실행.
  const parsed = runReadability(doc)
  const readableText = parsed ? normalizeText(parsed.textContent) : ''
  const readableLower = readableText.toLowerCase()

  // 2) 라이브 DOM에서 본문 루트 결정 (폴백 체인).
  const root = findArticleRoot(doc)

  // 3) 루트 하위의 leaf 블록 요소 수집 → 노이즈·화이트리스트 필터.
  const blocks = collectLeafBlocks(root)

  clearPreviousIndices(doc)

  const paragraphs: Paragraph[] = []
  for (const el of blocks) {
    if (isInNoise(el)) continue

    const text = normalizeText(el.textContent)
    const isHeading = HEADING_TAGS.has(el.tagName)
    const minLen = isHeading ? MIN_HEADING_LEN : MIN_PARAGRAPH_LEN
    if (text.length < minLen) continue

    // Readability가 본문으로 인정한 텍스트에 포함될 때만 채택(광고·댓글 잔여 제거).
    // Readability 실패 시엔 화이트리스트 없이 통과(폴백 신뢰).
    if (readableLower && !isWhitelisted(text, readableLower)) continue

    const idx = paragraphs.length
    el.setAttribute(PROBER_IDX_ATTR, String(idx))
    paragraphs.push({ idx, text, el })
  }

  if (paragraphs.length === 0) return null

  const title = normalizeText(parsed?.title) || normalizeText(doc.title)
  const body = paragraphs.map((p) => p.text).join('\n\n')

  return { title, body, paragraphs }
}

/**
 * idx로 라이브 DOM 문단 요소를 다시 찾는다(observer/anchor 재조회용).
 * extractArticle 이후에만 유효.
 */
export function paragraphElement(idx: number, doc: Document = document): Element | null {
  return doc.querySelector(`[${PROBER_IDX_ATTR}="${CSS.escape(String(idx))}"]`)
}

// ─── 내부 구현 ───────────────────────────────────────────────────────────────

interface ReadabilityResult {
  title: string
  textContent: string
}

/** clone에 Readability 실행. 실패(비기사 페이지 등) 시 null. */
function runReadability(doc: Document): ReadabilityResult | null {
  try {
    const clone = doc.cloneNode(true) as Document
    const parsed = new Readability(clone).parse()
    if (!parsed || !parsed.textContent) return null
    return { title: parsed.title ?? '', textContent: parsed.textContent }
  } catch {
    return null
  }
}

/** 문단 앞부분이 Readability 본문 텍스트에 포함되는지(부분 일치)로 화이트리스트 판정. */
function isWhitelisted(text: string, readableLower: string): boolean {
  const probe = text.slice(0, WHITELIST_PROBE_LEN).toLowerCase()
  if (!probe) return false
  return readableLower.includes(probe)
}

/**
 * 본문 루트 결정 폴백 체인: <article> → <main> → 최대 텍스트 밀도 컨테이너.
 * (Readability는 라이브 노드를 돌려주지 못하므로 루트 탐색은 독립 수행.)
 */
function findArticleRoot(doc: Document): Element {
  const article = doc.querySelector('article')
  if (article && (article.textContent?.length ?? 0) > MIN_CONTAINER_TEXT) return article

  const main = doc.querySelector('main')
  if (main && (main.textContent?.length ?? 0) > MIN_CONTAINER_TEXT) return main

  return maxTextDensityContainer(doc)
}

/** div/section 중 "요소 대비 텍스트량"이 가장 높은 컨테이너를 본문으로 추정. */
function maxTextDensityContainer(doc: Document): Element {
  let best: Element = doc.body ?? doc.documentElement
  let bestScore = 0

  for (const el of Array.from(doc.querySelectorAll('div, section'))) {
    if (isInNoise(el)) continue
    const len = el.textContent?.length ?? 0
    if (len < MIN_CONTAINER_TEXT) continue
    const descendants = el.querySelectorAll('*').length + 1
    const score = len / Math.sqrt(descendants) // 텍스트가 밀집(래퍼가 적을수록)일수록 높음
    if (score > bestScore) {
      bestScore = score
      best = el
    }
  }
  return best
}

/**
 * 루트 하위에서 다른 블록을 포함하지 않는 leaf 블록만 수집.
 * → <li>가 <p>를 감싸는 등 중첩으로 인한 중복 문단 방지.
 */
function collectLeafBlocks(root: Element): Element[] {
  const all = Array.from(root.querySelectorAll(BLOCK_SELECTOR))
  return all.filter((el) => el.querySelector(BLOCK_SELECTOR) === null)
}

/** 자신 또는 조상의 class/id가 노이즈 패턴에 걸리는지. */
function isInNoise(el: Element): boolean {
  let cur: Element | null = el
  while (cur) {
    if (NOISE_PATTERN.test(cur.id) || NOISE_PATTERN.test(classNameOf(cur))) return true
    cur = cur.parentElement
  }
  return false
}

/** className이 문자열이 아닌 경우(SVGAnimatedString 등) 방어. */
function classNameOf(el: Element): string {
  const c = (el as HTMLElement).className
  return typeof c === 'string' ? c : ''
}

/** 이전 실행이 남긴 data-prober-idx 제거(재실행 idempotent 보장). */
function clearPreviousIndices(doc: Document): void {
  for (const el of Array.from(doc.querySelectorAll(`[${PROBER_IDX_ATTR}]`))) {
    el.removeAttribute(PROBER_IDX_ATTR)
  }
}
