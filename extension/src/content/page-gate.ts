// =============================================================================
// content/page-gate.ts — 기사 페이지 판별 게이트 (URL 기준 하드코딩)
//
// 문제: 언론사 메인/섹션 페이지에서도 패널이 떴다. 목록 페이지는 기사 카드마다
//   미리보기 텍스트를 길게 넣어둬서(연합 <p class="lead"> 는 900자가 넘는다)
//   extractor 입장에선 정상 문단과 구분되지 않기 때문이다.
//
// DOM 구조로 목록을 판별하는 규칙도 시도했으나 폐기했다. "부모 종류 / 문단 수"
// 비율은 매일경제 기사(0.90)가 목록 구간(연합 1.00 · 중앙 0.50)과 겹쳐 기사에서
// 패널이 사라졌고, 사이트마다 마크업 편차가 커서 임계값을 신뢰할 수 없었다.
// 지금은 URL 하드코딩만 쓴다 — 규칙이 단순하고 틀렸을 때 결과를 예측할 수 있다.
// =============================================================================

/**
 * 목록 페이지 판정을 적용할 국내 언론사 호스트(하드코딩).
 *
 * 이 목록에 없는 사이트는 게이트를 건너뛴다(위키백과·블로그 등 오차단 방지).
 */
const NEWS_HOSTS =
  /(^|\.)(naver\.com|daum\.net|yna\.co\.kr|joongang\.co\.kr|hani\.co\.kr|chosun\.com|donga\.com|khan\.co\.kr|mk\.co\.kr|hankyung\.com|sbs\.co\.kr|kbs\.co\.kr|imbc\.com|ytn\.co\.kr|news1\.kr|newsis\.com|edaily\.co\.kr|seoul\.co\.kr|segye\.com|munhwa\.com|kmib\.co\.kr|hankookilbo\.com|ohmynews\.com|pressian\.com|mt\.co\.kr|fnnews\.com|asiae\.co\.kr|heraldcorp\.com|nocutnews\.co\.kr|mbn\.co\.kr|jtbc\.co\.kr|tvchosun\.com|zdnet\.co\.kr|bloter\.net)$/i

/**
 * 기사 URL 판별: 경로에 4자리 이상 연속 숫자(기사 ID)가 있는가.
 *
 * 국내 언론사 기사 URL 은 예외 없이 숫자 ID 를 갖는 반면 섹션 경로는 갖지 않는다.
 *   기사   /view/AKR20260721131700002 · /article/25401234 · /mnews/article/023/0003988697
 *          · /news/economy/12103563
 *   섹션   / · /economy/all · /money · /arti/economy · /section/101 (3자리라 미매칭)
 *
 * 섹션 경로를 나열하는 블록리스트가 아니라 이 방향을 택한 이유: 규칙이 틀렸을 때
 * "목록에서도 열 수 있다"(현상 유지)로 끝나야지 "기사에서 못 연다"가 되면 안 된다.
 */
const ARTICLE_ID_IN_PATH = /\d{4,}/

/**
 * URL 만으로 "기사 페이지가 아님"이 확실한지.
 * 알려진 언론사 호스트가 아니면 항상 false(판단 보류 → 열 수 있게 둔다).
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
