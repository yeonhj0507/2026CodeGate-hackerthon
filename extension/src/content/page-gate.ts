// =============================================================================
// content/page-gate.ts — 기사 페이지 판별 게이트
//
// 문제: 언론사 메인/섹션 페이지에서도 패널이 떴다. 목록 페이지는 기사 카드마다
//   미리보기 텍스트를 길게 넣어두는데(연합 <p class="lead"> 는 900자가 넘는다),
//   extractor 입장에선 이게 정상 문단과 구분되지 않기 때문이다.
//
// 실측 (2026-07-21, 실제 페이지에 extractArticle 을 돌려 계측):
//
//                        문단수   부모종류/문단
//   연합 목록(경제)         25       1.00      ← 카드마다 부모가 다름
//   연합 목록(정치)         24       1.00
//   중앙 목록(머니)         50       0.50
//   중앙 목록(메인)         54       0.67
//   중앙 기사                7       0.14      ← 문단들이 한 부모를 공유
//
// 두 겹으로 막는다.
//   1) URL 게이트: 알려진 언론사 호스트에서 기사 URL 형태가 아니면 즉시 중단.
//      추출 전에 끝나므로 가장 싸고 확실하다.
//   2) 구조 게이트: 문단이 여러 카드에 흩어져 있으면 목록으로 본다.
//      하드코딩 목록에 없는 언론사까지 덮는 안전망.
// =============================================================================

import type { Paragraph } from '../shared/types'

/**
 * 목록 페이지 판정을 적용할 국내 언론사 호스트(하드코딩).
 *
 * 이 목록에 없는 사이트는 URL 게이트를 건너뛰고 구조 게이트만 적용한다.
 * → 위키백과·블로그 등 기사 URL 규칙이 다른 곳을 잘못 막지 않기 위함.
 */
const NEWS_HOSTS =
  /(^|\.)(naver\.com|daum\.net|yna\.co\.kr|joongang\.co\.kr|hani\.co\.kr|chosun\.com|donga\.com|khan\.co\.kr|mk\.co\.kr|hankyung\.com|sbs\.co\.kr|kbs\.co\.kr|imbc\.com|ytn\.co\.kr|news1\.kr|newsis\.com|edaily\.co\.kr|seoul\.co\.kr|segye\.com|munhwa\.com|kmib\.co\.kr|hankookilbo\.com|ohmynews\.com|pressian\.com|mt\.co\.kr|fnnews\.com|asiae\.co\.kr|heraldcorp\.com|nocutnews\.co\.kr|mbn\.co\.kr|jtbc\.co\.kr|tvchosun\.com|zdnet\.co\.kr|bloter\.net)$/i

/**
 * 기사 URL 판별: 경로에 4자리 이상 연속 숫자(기사 ID)가 있는가.
 *
 * 국내 언론사 기사 URL 은 예외 없이 숫자 ID 를 갖는 반면 섹션 경로는 갖지 않는다.
 *   기사   /view/AKR20260721131700002 · /article/25401234 · /mnews/article/056/0011234567
 *   섹션   / · /economy/all · /money · /arti/economy · /section/101 (3자리라 미매칭)
 *
 * 블록리스트(섹션 경로 나열)가 아니라 이 방향을 택한 이유: 규칙을 틀렸을 때
 * "목록에서 패널이 뜬다"(현상 유지)로 끝나야지 "기사에서 안 뜬다"(데모 실패)가
 * 되면 안 되기 때문 — 이 판정은 알려진 호스트에만 적용된다.
 */
const ARTICLE_ID_IN_PATH = /\d{4,}/

/** 이 개수 미만이면 구조 게이트를 적용하지 않는다(짧은 기사 오탐 방지). */
const LIST_MIN_PARAGRAPHS = 6

/** 문단 대비 부모 종류 비율이 이 값 이상이면 목록으로 본다. */
const LIST_PARENT_RATIO = 0.5

/**
 * URL 만으로 "기사 페이지가 아님"이 확실한지. 본문 추출 전에 호출한다.
 * 알려진 언론사 호스트가 아니면 항상 false(판단 보류 → 구조 게이트에 맡김).
 */
export function isNonArticleUrl(href: string): boolean {
  let url: URL
  try {
    url = new URL(href)
  } catch {
    return false
  }

  if (!NEWS_HOSTS.test(url.hostname)) return false

  return !ARTICLE_ID_IN_PATH.test(url.pathname)
}

/**
 * 추출된 문단이 "기사 본문"이 아니라 "기사 목록"으로 보이는지.
 *
 * 기사 본문은 문단들이 같은 부모(본문 컨테이너) 아래 나란히 있지만,
 * 목록 페이지는 기사 카드마다 부모가 달라 부모 종류 수가 문단 수에 비례해 늘어난다.
 */
export function looksLikeArticleList(paragraphs: Paragraph[]): boolean {
  if (paragraphs.length < LIST_MIN_PARAGRAPHS) return false

  const parents = new Set<Element | null>()
  for (const p of paragraphs) parents.add(p.el.parentElement)

  return parents.size / paragraphs.length >= LIST_PARENT_RATIO
}
