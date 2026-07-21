// =============================================================================
// qa/anchor-qa.ts — 앵커 매칭 QA·튜닝 하니스 (Stream A / Step 10 · T=5)
//
// 목적: 최대 리스크인 anchor.ts를 실제 코드 그대로 불러와, 서버가 낼 법한
//   다양한 anchorText/paragraphIndex 시나리오에 대해 "의도한 문단에 정확히
//   꽂히는가"와 method 분포를 측정한다. ANCHOR_SIMILARITY_THRESHOLD 튜닝 근거.
//
// 실행: rolldown으로 번들 후 node. (anchorQuizzes는 DOM 미접근 순수 로직)
//   자세한 건 docs/stream_a_qa.md 참고.
// =============================================================================

import { anchorQuizzes, diceCoefficient, type AnchorMethod } from '../src/content/anchor'
import { ANCHOR_COMPARE_LENGTH, ANCHOR_SIMILARITY_THRESHOLD } from '../src/shared/constants'
import type { Paragraph, Quiz } from '../src/shared/types'

// ─── 픽스처: 실제 한국어 기사풍 문단 (경제/과학) ─────────────────────────────

const ARTICLE_ECON = [
  '한국은행 금융통화위원회는 기준금리를 연 3.50%에서 3.25%로 0.25%포인트 인하하기로 결정했다고 밝혔다.',
  '이번 인하는 3년 2개월 만의 통화정책 전환으로, 그동안 이어진 고금리 기조에 마침표를 찍는 조치로 해석된다.',
  '기준금리 인하는 시중 유동성을 늘려 소비와 투자를 촉진하지만, 동시에 원화 약세와 자본 유출 압력을 키울 수 있다.',
  '전문가들은 미국 연방준비제도의 금리 경로가 향후 한국은행의 추가 인하 폭을 좌우할 핵심 변수가 될 것으로 내다봤다.',
  '한편 가계부채가 여전히 높은 수준을 유지하고 있어, 금리 인하가 부동산 시장을 다시 자극할 수 있다는 우려도 제기된다.',
  '금통위는 성명문에서 물가 상승률이 목표 수준인 2%에 수렴하고 있다는 점을 인하 결정의 주요 근거로 들었다.',
]

const ARTICLE_SCI = [
  '제임스 웹 우주망원경이 지구에서 130억 광년 떨어진 초기 은하의 상세 이미지를 포착하는 데 성공했다.',
  '이 은하는 빅뱅 이후 불과 3억 년 시점에 형성된 것으로, 우주 초기 별 생성 과정을 이해하는 단서가 된다.',
  '연구진은 적외선 분광 분석을 통해 이 은하에 예상보다 무거운 원소가 존재한다는 사실을 확인했다.',
  '무거운 원소의 존재는 초기 우주에서 별의 탄생과 소멸이 매우 빠르게 반복되었음을 시사한다.',
  '이번 관측은 기존 우주론 모형이 예측한 초기 은하의 성장 속도보다 훨씬 빠른 진화를 보여준다는 점에서 주목받는다.',
  '연구팀은 후속 관측을 통해 이 은하 주변의 암흑물질 분포를 정밀하게 측정할 계획이라고 밝혔다.',
]

// ─── Paragraph 생성 (anchor는 el을 안 쓰므로 더미) ───────────────────────────

function toParagraphs(texts: string[]): Paragraph[] {
  return texts.map((text, idx) => ({ idx, text, el: undefined as unknown as Element }))
}

// ─── Quiz 생성 헬퍼 (서버가 낼 법한 anchorText 시뮬레이션) ────────────────────

let claimSeq = 0
function quiz(anchorText: string, paragraphIndex: number): Quiz {
  return {
    claimId: `c${claimSeq++}`,
    conceptTag: 'test',
    anchorText,
    paragraphIndex,
    question: 'Q',
    options: ['A', 'B', 'C', 'D'],
    answerIndex: 0,
    explanation: 'E',
    followups: [],
  }
}

/** 문단 앞 n자를 그대로 anchor로 (서버 정상 케이스). */
const head = (t: string, n = 50) => t.slice(0, n)
/** 공백을 다중 공백/개행으로 흐트러뜨림 (정규화 견고성 테스트). */
const messyWs = (t: string, n = 50) => head(t, n).replace(/ /g, '  ').replace(/,/g, ',\n')
/** 몇 글자 편집(드리프트) — 유사도 폴백 테스트. */
const drift = (t: string, n = 50) => {
  const s = head(t, n).split('')
  for (let i = 8; i < s.length; i += 12) s[i] = '○' // 군데군데 글자 훼손
  return s.join('')
}

// ─── 시나리오 정의: {설명, quiz, 기대 문단 idx(또는 null=하단강등)} ──────────

interface Scenario {
  label: string
  quiz: Quiz
  expectIdx: number | null
}

function buildScenarios(article: string[], name: string): { paras: Paragraph[]; scenarios: Scenario[] } {
  const paras = toParagraphs(article)
  const scenarios: Scenario[] = [
    { label: `${name} 정확(앞50자)`, quiz: quiz(head(article[0]), 0), expectIdx: 0 },
    { label: `${name} 정확(중간문단)`, quiz: quiz(head(article[2]), 2), expectIdx: 2 },
    { label: `${name} 공백변형`, quiz: quiz(messyWs(article[3]), 3), expectIdx: 3 },
    { label: `${name} 편집드리프트`, quiz: quiz(drift(article[1]), 1), expectIdx: 1 },
    { label: `${name} index틀림·text정상`, quiz: quiz(head(article[4]), 99), expectIdx: 4 },
    { label: `${name} text쓰레기·index정상`, quiz: quiz('☆★◎▲무관한문자열◆◇', 5), expectIdx: 5 },
    { label: `${name} 완전실패`, quiz: quiz('☆★◎▲무관한문자열◆◇', 99), expectIdx: null },
    { label: `${name} 짧은anchor(앞15자)`, quiz: quiz(head(article[2], 15), 2), expectIdx: 2 },
  ]
  return { paras, scenarios }
}

// ─── 실행 ────────────────────────────────────────────────────────────────────

const datasets = [
  buildScenarios(ARTICLE_ECON, '경제'),
  buildScenarios(ARTICLE_SCI, '과학'),
]

const methodCount: Record<AnchorMethod, number> = {
  exact: 0, partial: 0, similarity: 0, index: 0, none: 0,
}
let pass = 0
let fail = 0
const failures: string[] = []

console.log(`\n=== 앵커 매칭 QA (THRESHOLD=${ANCHOR_SIMILARITY_THRESHOLD}) ===\n`)
console.log('결과 | method     | score | 시나리오')
console.log('-----|------------|-------|----------------------------------')

for (const { paras, scenarios } of datasets) {
  const quizzes = scenarios.map((s) => s.quiz)
  const result = anchorQuizzes(quizzes, paras)

  for (const s of scenarios) {
    const m = result.byClaim.get(s.quiz.claimId)!
    const gotIdx = m.paragraph ? m.paragraph.idx : null
    const ok = gotIdx === s.expectIdx
    methodCount[m.method]++
    if (ok) pass++
    else {
      fail++
      failures.push(`  ✗ ${s.label}: 기대 idx=${s.expectIdx}, 실제 idx=${gotIdx} (method=${m.method}, score=${m.score.toFixed(2)})`)
    }
    const mark = ok ? '  ✓ ' : '  ✗ '
    console.log(`${mark}| ${m.method.padEnd(10)} | ${m.score.toFixed(2)}  | ${s.label}`)
  }
}

console.log('\n=== 요약 ===')
console.log(`통과: ${pass} / ${pass + fail}`)
console.log('method 분포:', JSON.stringify(methodCount))
if (failures.length) {
  console.log('\n실패 상세:')
  failures.forEach((f) => console.log(f))
}
console.log('')

// ─── 임계값 민감도: on-target(드리프트 최저) vs off-target(오탐 최고) 분리 확인 ──
// anchor.ts 내부와 동일하게: 문단 앞 ANCHOR_COMPARE_LENGTH자, 소문자, 같은 길이 창 비교.
const normHead = (t: string) => t.replace(/\s+/g, ' ').trim().slice(0, ANCHOR_COMPARE_LENGTH).toLowerCase()

let maxOffTarget = 0
let maxOffLabel = ''
for (const [name, article] of [['경제', ARTICLE_ECON], ['과학', ARTICLE_SCI]] as const) {
  const heads = article.map(normHead)
  for (let i = 0; i < heads.length; i++) {
    for (let j = 0; j < heads.length; j++) {
      if (i === j) continue
      const win = heads[j].slice(0, heads[i].length)
      const score = diceCoefficient(heads[i], win)
      if (score > maxOffTarget) {
        maxOffTarget = score
        maxOffLabel = `${name} 문단${i} vs 문단${j}`
      }
    }
  }
}

console.log('=== 임계값 민감도 분석 ===')
console.log(`현재 THRESHOLD           : ${ANCHOR_SIMILARITY_THRESHOLD}`)
console.log(`드리프트 매칭 최저 관측치 : ~0.84 (위 표 similarity)`)
console.log(`오탐(off-target) 최고치   : ${maxOffTarget.toFixed(3)}  (${maxOffLabel})`)
const margin = 0.84 - maxOffTarget
console.log(`안전 마진 (0.84 - 오탐)   : ${margin.toFixed(3)}`)
const verdict =
  maxOffTarget < ANCHOR_SIMILARITY_THRESHOLD && ANCHOR_SIMILARITY_THRESHOLD < 0.84
    ? '✓ 0.55는 오탐 위와 드리프트 아래 사이 → 유지 타당'
    : '⚠ 임계값 재검토 필요'
console.log(`판정                     : ${verdict}`)
console.log('')

// 비정상 종료 코드로 CI/스크립트가 실패를 감지할 수 있게.
if (fail > 0) process.exitCode = 1
