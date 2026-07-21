// =============================================================================
// qa/relations-qa.ts — 퀴즈 트리 → 선행 관계 추출 QA 하니스
//
// 서버 엣지는 원래 parentConcept 로만 생겼고, parentConcept 는 오답으로 재질문에
// 내려갔을 때만 채워졌다. 그래서 다 맞힌 세션에서는 개념이 전부 고립됐다.
// relationsOf() 는 그 관계를 정오답과 무관하게 트리에서 직접 뽑는다.
//
// 실행: npm run qa:relations
// =============================================================================

import { relationsOf } from '../src/shared/relations'
import type { Followup, Quiz } from '../src/shared/types'

let passN = 0
let failN = 0

function check(label: string, ok: boolean) {
  if (ok) {
    passN++
    console.log(`  ✓ ${label}`)
  } else {
    failN++
    console.log(`  ✗ ${label}`)
  }
}

function fu(prereq: string, followups: Followup[] = [], level: 1 | 2 = 1): Followup {
  return {
    level,
    prereqConceptTag: prereq,
    question: `${prereq}?`,
    options: ['a', 'b', 'c', 'd'],
    answerIndex: 0,
    explanation: '',
    followups,
  }
}

function quiz(claimId: string, concept: string, followups: Followup[] = []): Quiz {
  return {
    claimId,
    conceptTag: concept,
    anchorText: '',
    paragraphIndex: 0,
    question: `${concept}?`,
    options: ['a', 'b', 'c', 'd'],
    answerIndex: 0,
    explanation: '',
    followups,
  }
}

const has = (rs: { from: string; to: string }[], from: string, to: string) =>
  rs.some((r) => r.from === from && r.to === to)

// ─── 1) 2단계 체인이 엣지 2개로 펴진다 ───────────────────────────────────────

console.log('\n[1] 체인 전개')
const chain = relationsOf([
  quiz('c1', 'NDF의 환율 전가 경로', [fu('환헤지', [fu('환율', [], 2)])]),
])
check('엣지 2개', chain.length === 2)
check('level1 → main (환헤지 → NDF의 환율 전가 경로)', has(chain, '환헤지', 'NDF의 환율 전가 경로'))
check('level2 → level1 (환율 → 환헤지)', has(chain, '환율', '환헤지'))
check('건너뛴 관계는 만들지 않는다(환율 → NDF…)', !has(chain, '환율', 'NDF의 환율 전가 경로'))

// ─── 2) 사용자의 정오답과 무관하다 ───────────────────────────────────────────

console.log('\n[2] 정오답 무관')
check('풀지 않은 트리에서도 관계가 나온다', relationsOf([quiz('c1', 'A', [fu('B')])]).length === 1)

// ─── 3) 여러 주장 ────────────────────────────────────────────────────────────

console.log('\n[3] 주장 여러 개')
const multi = relationsOf([
  quiz('c1', '기준금리', [fu('통화정책')]),
  quiz('c2', '환율', [fu('국제수지')]),
])
check('주장별 관계가 모두 나온다', multi.length === 2)
check('서로 다른 주장을 가로로 잇지는 않는다', !has(multi, '기준금리', '환율'))

// ─── 4) 방어 ─────────────────────────────────────────────────────────────────

console.log('\n[4] 방어')
check('followups 없으면 빈 배열', relationsOf([quiz('c1', 'A')]).length === 0)
check('퀴즈가 없으면 빈 배열', relationsOf([]).length === 0)
check('자기 자신 관계는 버린다', relationsOf([quiz('c1', 'A', [fu('A')])]).length === 0)
check('공백 개념명은 버린다', relationsOf([quiz('c1', 'A', [fu('   ')])]).length === 0)

const dup = relationsOf([
  quiz('c1', '환율', [fu('환헤지')]),
  quiz('c2', '환율', [fu('환헤지')]),
])
check('같은 관계가 여러 주장에 나와도 한 번만', dup.length === 1)

const trimmed = relationsOf([quiz('c1', ' 환율 ', [fu(' 환헤지 ')])])
check('앞뒤 공백은 다듬는다', has(trimmed, '환헤지', '환율'))

console.log(`\n${failN === 0 ? '✅ ALL PASS' : '❌ FAILED'} — ${passN} passed, ${failN} failed`)
if (failN > 0) process.exit(1)
