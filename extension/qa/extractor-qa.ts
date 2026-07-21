// =============================================================================
// qa/extractor-qa.ts — 본문 추출 QA 하니스 (<br> 폴백 회귀 고정)
//
// 목적: extractor.ts 를 실제 코드 그대로 불러와, 한국 언론사에서 실측된 세 가지
//   DOM 구조에 대해 문단 분할이 의도대로 되는지 확인한다.
//
//   네이버뉴스형  <p> 없이 텍스트 + <br> 만 → 폴백이 없으면 문단 0개 (원래 버그)
//   연합뉴스형    <p> 기반 + 추천/댓글 노이즈 → 정상 경로 유지 (회귀 감시)
//   중앙일보형    <p> 기반 + 노이즈 대량      → 정상 경로 유지 (회귀 감시)
//
// 실행: rolldown 번들 후 node (jsdom 으로 DOM 제공).
//   npm run qa:extractor
// =============================================================================

import { JSDOM } from 'jsdom'
import { extractArticle, PROBER_IDX_ATTR } from '../src/content/extractor'

// ─── 픽스처 본문 (실제 기사풍 한국어, 문단당 20자 이상) ──────────────────────

const BODY_SENTENCES = [
  '한국은행 금융통화위원회는 기준금리를 연 3.50%에서 3.25%로 0.25%포인트 인하하기로 결정했다고 21일 밝혔다.',
  '이번 인하는 3년 2개월 만의 통화정책 전환으로, 그동안 이어진 고금리 기조에 마침표를 찍는 조치로 해석된다.',
  '기준금리 인하는 시중 유동성을 늘려 소비와 투자를 촉진하지만, 동시에 원화 약세와 자본 유출 압력을 키울 수 있다.',
  '전문가들은 미국 연방준비제도의 금리 경로가 향후 한국은행의 추가 인하 폭을 좌우할 핵심 변수가 될 것으로 내다봤다.',
  '한편 가계부채가 여전히 높은 수준을 유지하고 있어, 금리 인하가 부동산 시장을 다시 자극할 수 있다는 우려도 제기된다.',
  '금통위는 성명문에서 물가 상승률이 목표 수준인 2%에 수렴하고 있다는 점을 인하 결정의 주요 근거로 들었다.',
  '시장에서는 연내 추가 인하 가능성을 두고 전망이 엇갈리고 있으며, 채권 금리는 발표 직후 소폭 하락했다.',
  '이창용 총재는 기자간담회에서 물가와 성장의 균형을 고려한 신중한 접근을 이어가겠다고 강조했다.',
  '수출 회복세가 이어지고 있으나 내수 부진이 길어지면서 성장 경로의 불확실성은 여전히 크다는 평가다.',
  '정부는 금리 인하 효과가 실물경제로 파급되도록 재정 집행 속도를 높이겠다는 방침을 함께 밝혔다.',
  '가계대출 증가세가 다시 확대될 경우 거시건전성 규제를 강화하는 방안도 검토 대상에 오를 전망이다.',
  '전문가들은 이번 결정이 부동산 프로젝트파이낸싱 부실 정리에도 영향을 줄 것으로 보고 있다.',
]

const NOISE_HTML = `
  <div class="related_list"><a href="#">추천기사 하나</a><a href="#">추천기사 둘</a></div>
  <div class="comment_area"><p>댓글로 남긴 짧은 의견입니다. 본문이 아니므로 걸러져야 합니다.</p></div>
  <div class="ad_banner"><p>광고 문구가 들어가는 자리입니다. 문단으로 잡히면 안 됩니다.</p></div>
  <div class="tag_wrap"><a href="#">기준금리</a><a href="#">통화정책</a></div>
`

// ─── 픽스처 빌더 ─────────────────────────────────────────────────────────────

/** 네이버뉴스형: <p> 없이 텍스트 노드 + <br> 로만 구성. */
function naverLike(): Document {
  const body = BODY_SENTENCES.join('<br><br>')
  return html(`
    <div id="newsct_article">
      <article id="dic_area">${body}</article>
    </div>
    ${NOISE_HTML}
  `)
}

/** 연합뉴스형: <p> 기반 정상 구조 + 노이즈. */
function yonhapLike(): Document {
  const body = BODY_SENTENCES.map((s) => `<p>${s}</p>`).join('\n')
  return html(`
    <article class="story-news">
      <h2>기준금리 0.25%포인트 인하</h2>
      ${body}
    </article>
    ${NOISE_HTML}
  `)
}

/** 중앙일보형: <p> 기반 + 노이즈 대량(추천기사 스와이퍼 등). */
function joongangLike(): Document {
  const body = BODY_SENTENCES.map((s) => `<p>${s}</p>`).join('\n')
  const heavyNoise = Array.from(
    { length: 12 },
    (_, i) => `<div class="recommend_list_swiper"><p>추천기사 본문 미리보기 ${i} 입니다.</p></div>`,
  ).join('\n')
  return html(`
    <article id="article_body">${body}</article>
    ${heavyNoise}
    ${NOISE_HTML}
  `)
}

/** <p> 가 1개뿐이고 나머지는 <br> 로 나뉜 혼합형(바이라인 <p> + <br> 본문). */
function mixedLike(): Document {
  const body = BODY_SENTENCES.join('<br><br>')
  return html(`
    <article id="dic_area">
      <p>${BODY_SENTENCES[0]}</p>
      ${body}
    </article>
  `)
}

function html(inner: string): Document {
  return new JSDOM(
    `<!doctype html><html><head><title>기준금리 인하 기사</title></head><body>${inner}</body></html>`,
    { url: 'https://news.example.com/article/1' },
  ).window.document
}

// ─── 검증 ────────────────────────────────────────────────────────────────────

let failures = 0

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : ` (기대 ${JSON.stringify(expected)})`))
}

function report(label: string, doc: Document) {
  const result = extractArticle(doc)
  const count = result?.paragraphs.length ?? 0
  console.log(`\n[${label}] 문단 ${count}개`)
  if (result) {
    console.log(`  첫 문단: ${result.paragraphs[0].text.slice(0, 45)}...`)
    console.log(`  끝 문단: ${result.paragraphs[count - 1].text.slice(0, 45)}...`)
  }
  return result
}

console.log('='.repeat(78))
console.log('extractor QA — <br> 폴백 + 정상 경로 회귀')
console.log('='.repeat(78))

// 1) 네이버형: 폴백이 동작해 문단이 잡혀야 한다(원래는 0개 → null).
{
  const doc = naverLike()
  const r = report('네이버뉴스형 (<br> 전용)', doc)
  check('null 이 아니다', r !== null, true)
  check('문단 수 == 본문 문장 수', r?.paragraphs.length, BODY_SENTENCES.length)
  check('본문 텍스트 보존', doc.body.textContent?.includes(BODY_SENTENCES[5]), true)
  check(
    '모든 문단에 data-prober-idx 부여',
    doc.querySelectorAll(`[${PROBER_IDX_ATTR}]`).length,
    BODY_SENTENCES.length,
  )
  check('노이즈(추천/댓글/광고) 미포함', r?.paragraphs.some((p) => p.text.includes('추천기사')), false)
}

// 2) 연합형: 정상 경로 유지(폴백이 끼어들면 안 된다).
{
  const r = report('연합뉴스형 (<p> 기반)', yonhapLike())
  check('문단 수 유지', r?.paragraphs.length, BODY_SENTENCES.length + 1 /* h2 소제목 */)
  check('노이즈 미포함', r?.paragraphs.some((p) => p.text.includes('광고 문구')), false)
}

// 3) 중앙형: 노이즈 대량에도 정상 경로 유지.
{
  const r = report('중앙일보형 (<p> + 노이즈 대량)', joongangLike())
  check('문단 수 유지', r?.paragraphs.length, BODY_SENTENCES.length)
  check('추천기사 미포함', r?.paragraphs.some((p) => p.text.includes('추천기사 본문')), false)
}

// 4) 혼합형: <p> 1개 < 임계값이므로 폴백이 이겨야 한다.
{
  const r = report('혼합형 (<p> 1개 + <br> 본문)', mixedLike())
  check('폴백이 채택되어 문단이 늘어난다', (r?.paragraphs.length ?? 0) > 1, true)
}

// 5) 재실행 idempotent: 두 번 돌려도 결과·DOM 이 같아야 한다(래퍼 중첩 금지).
{
  const doc = naverLike()
  const first = extractArticle(doc)
  const textAfterFirst = doc.body.textContent
  const second = extractArticle(doc)

  console.log('\n[재실행 idempotent]')
  check('문단 수 동일', second?.paragraphs.length, first?.paragraphs.length)
  check('본문 텍스트 동일', doc.body.textContent === textAfterFirst, true)
  check('래퍼 span 중첩 없음', doc.querySelectorAll('[data-prober-wrap] [data-prober-wrap]').length, 0)
  check(
    'idx 중복 없음',
    new Set(
      Array.from(doc.querySelectorAll(`[${PROBER_IDX_ATTR}]`)).map((el) =>
        el.getAttribute(PROBER_IDX_ATTR),
      ),
    ).size,
    second?.paragraphs.length,
  )
}

console.log('\n' + '='.repeat(78))
console.log(failures === 0 ? 'ALL PASS' : `${failures}건 실패`)
console.log('='.repeat(78))
process.exit(failures === 0 ? 0 : 1)
