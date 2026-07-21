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

// <br> 폴백 (네이버뉴스류 대응):
//   본문이 <p> 없이 텍스트 노드 + <br> 로만 구성된 문서가 있다. 이 경우 leaf 블록이
//   0개라 extractArticle 이 null 을 반환하고 /quiz 요청 자체가 나가지 않았다.
//   한국 언론사에 흔한 구조라 데모 경로에서 치명적이었다.
//
//   실측 (2026-07-21, 실제 기사 3건 계측):
//     네이버뉴스  Readability 성공(1832자) · 루트 <article id="dic_area"> 정확 탐지
//                 → BLOCK_SELECTOR 0개 · <br> 32개 · 최종 문단 0개  ← 이 폴백의 대상
//     연합뉴스    leaf 23 → 문단 10개 (정상)
//     중앙일보    leaf 62 → 문단 9개 (정상)
//
//   해결: leaf 문단이 극소수인데 <br> 이 많으면, <br> 경계로 자식 노드를 묶어
//   <span> 으로 감싼 뒤 그 span 을 문단 요소로 쓴다. observer.ts(IntersectionObserver)
//   와 anchor.ts 가 **실제 DOM 요소**를 필요로 하므로 텍스트만 잘라내면 안 되고 래핑이
//   필요하다. span 은 inline 이라 원본 레이아웃을 깨지 않는다.
//
//   중앙일보의 노이즈컷 48개는 오탐이 아니라 추천기사·태그·댓글이 제대로 걸러진 것이라
//   NOISE_PATTERN 은 손대지 않았다.

/**
 * <br> 폴백을 시도할 조건: 정상 경로가 찾은 **본문 문단**(소제목 제외)이 이 값 미만일 때.
 *
 * 소제목을 세지 않는 이유: 글로벌이코노믹처럼 소제목만 <h3> 이고 본문은 전부 <br> 로
 * 나뉜 사이트가 있다. 문단 수만 보면 3개(소제목)라 폴백이 발동하지 않아 본문이
 * 통째로 빠졌다.
 */
const BR_FALLBACK_MIN_BODY = 3

/** <br> 폴백을 시도할 조건: 한 요소의 직계 자식 <br> 이 이 개수 이상일 때. */
const BR_FALLBACK_MIN_BR = 4

/** <br> 폴백이 만든 래퍼 span 표식. 재실행 시 원상복구(unwrap) 대상. */
const PROBER_WRAP_ATTR = 'data-prober-wrap'

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
  // 0) 이전 실행 흔적 원복. 래퍼 unwrap 이 먼저여야 Readability·루트 탐색이 원본 구조를 본다.
  clearPreviousIndices(doc)
  unwrapPreviousSegments(doc)

  // 1) Readability로 정제 텍스트(화이트리스트) + 제목 확보. 원본은 건드리지 않도록 clone에 실행.
  const parsed = runReadability(doc)
  const readableText = parsed ? normalizeText(parsed.textContent) : ''
  const readableLower = readableText.toLowerCase()

  // 2) 라이브 DOM에서 본문 루트 결정 (폴백 체인).
  const root = findArticleRoot(doc)

  // 3) 루트 하위의 leaf 블록 요소 수집 → 노이즈·화이트리스트 필터.
  let candidates: Candidate[] = []
  for (const el of collectLeafBlocks(root)) {
    if (isInNoise(el)) continue
    const text = normalizeText(el.textContent)
    if (!acceptsText(text, HEADING_TAGS.has(el.tagName), readableLower)) continue
    candidates.push({ el, text })
  }

  // 4) <p> 없이 <br> 로만 나뉜 본문(네이버뉴스·글로벌이코노믹류) 폴백.
  //    본문 문단을 사실상 못 찾았을 때만 시도하므로 <p> 기반 문서는 영향받지 않는다.
  const bodyCount = candidates.filter((c) => !HEADING_TAGS.has(c.el.tagName)).length
  if (bodyCount < BR_FALLBACK_MIN_BODY) {
    const fromBr = collectBrSegments(root, doc, readableLower)
    if (fromBr.length > candidates.length) candidates = fromBr
  }

  if (candidates.length === 0) return null

  const paragraphs: Paragraph[] = candidates.map(({ el, text }, idx) => {
    el.setAttribute(PROBER_IDX_ATTR, String(idx))
    return { idx, text, el }
  })

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

/** idx 부여 전 문단 후보(요소 + 정규화 텍스트). */
interface Candidate {
  el: Element
  text: string
}

/**
 * 문단 텍스트 채택 기준: 최소 길이 + Readability 화이트리스트.
 * (노이즈 판정은 요소 조상을 봐야 하므로 호출부에서 별도로 수행.)
 */
function acceptsText(text: string, isHeading: boolean, readableLower: string): boolean {
  const minLen = isHeading ? MIN_HEADING_LEN : MIN_PARAGRAPH_LEN
  if (text.length < minLen) return false

  // Readability가 본문으로 인정한 텍스트에 포함될 때만 채택(광고·댓글 잔여 제거).
  // Readability 실패 시엔 화이트리스트 없이 통과(폴백 신뢰).
  if (readableLower && !isWhitelisted(text, readableLower)) return false

  return true
}

/**
 * <br> 로만 나뉜 본문을 문단으로 쪼갠다.
 * 채택된 구간만 <span data-prober-wrap> 으로 감싸 DOM 변경을 최소화한다.
 * @returns 문단 후보 배열. 대상 컨테이너가 없으면 빈 배열.
 */
function collectBrSegments(root: Element, doc: Document, readableLower: string): Candidate[] {
  const container = findBrContainer(root)
  if (!container || isInNoise(container)) return []

  const out: Candidate[] = []
  for (const nodes of splitByBr(container)) {
    const text = normalizeText(nodes.map((n) => n.textContent ?? '').join(' '))
    if (!acceptsText(text, false, readableLower)) continue
    out.push({ el: wrapSegment(nodes, doc), text })
  }
  return out
}

/**
 * 직계 자식 <br> 이 가장 많은 요소를 찾는다(루트 자신 포함).
 * 본문이 루트 바로 아래가 아니라 한 겹 감싸인 경우까지 잡기 위함.
 */
function findBrContainer(root: Element): Element | null {
  let best: Element | null = null
  let bestCount = 0

  const scan = (el: Element) => {
    let count = 0
    for (const child of Array.from(el.children)) {
      if (child.tagName === 'BR') count++
    }
    if (count > bestCount) {
      bestCount = count
      best = el
    }
  }

  scan(root)
  for (const el of Array.from(root.querySelectorAll('*'))) scan(el)

  return bestCount >= BR_FALLBACK_MIN_BR ? best : null
}

/** 자식 노드를 <br> 경계로 묶는다. 연속 <br> 은 빈 구간이 되어 자연히 버려진다. */
function splitByBr(container: Element): Node[][] {
  const segments: Node[][] = []
  let current: Node[] = []

  for (const node of Array.from(container.childNodes)) {
    // nodeType 1 = ELEMENT_NODE. 전역 Node 에 의존하지 않아야 QA(jsdom)에서도 돈다.
    if (node.nodeType === 1 && (node as Element).tagName === 'BR') {
      if (current.length > 0) segments.push(current)
      current = []
      continue
    }
    current.push(node)
  }
  if (current.length > 0) segments.push(current)

  return segments
}

/** 구간 노드들을 원래 위치에서 <span> 안으로 옮긴다. 텍스트·순서는 보존된다. */
function wrapSegment(nodes: Node[], doc: Document): Element {
  const span = doc.createElement('span')
  span.setAttribute(PROBER_WRAP_ATTR, '')

  const first = nodes[0]
  first.parentNode?.insertBefore(span, first)
  for (const node of nodes) span.appendChild(node)

  return span
}

/** 이전 실행이 만든 래퍼 span 을 제거하고 자식을 제자리로 돌려놓는다(재실행 idempotent). */
function unwrapPreviousSegments(doc: Document): void {
  for (const span of Array.from(doc.querySelectorAll(`[${PROBER_WRAP_ATTR}]`))) {
    const parent = span.parentNode
    if (!parent) continue
    while (span.firstChild) parent.insertBefore(span.firstChild, span)
    parent.removeChild(span)
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
    if (!hasParagraphMaterial(el)) continue
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
 * 이 컨테이너에서 문단을 뽑아낼 재료(블록 요소 또는 <br>)가 있는지.
 *
 * 텍스트만 많고 블록도 <br> 도 없는 요소가 밀도 점수 1위를 차지하는 경우가 있다.
 * 밴쿠버조선의 <div id="floatingLeftWrapper">(3404자·leaf 0·br 0)가 그랬고, 그 결과
 * 루트를 잘못 잡아 본문 추출이 통째로 실패했다. 애초에 후보에서 뺀다.
 */
function hasParagraphMaterial(el: Element): boolean {
  if (el.querySelector(BLOCK_SELECTOR) !== null) return true
  return el.querySelectorAll('br').length >= BR_FALLBACK_MIN_BR
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
