// =============================================================================
// qa/session-qa.ts — 세션 상태머신 + 제출 큐 QA 하니스 (Stream B / Step 10 · T=5)
//
// 목적: session.ts(진단 루프 상태머신)와 session-bind.ts(제출 큐)를 실제 코드
//   그대로 불러와, 진단 루프 전 경로·parentConcept 엣지 체인·유실 방지 큐 동작을
//   자동 검증한다. UI/observer 없이 순수 로직만(DOM 미접근)이라 헤드리스로 재현 가능.
//   ※ 브라우저(IntersectionObserver·실제 스크롤·Shadow DOM 렌더)가 필요한 항목은
//     docs/stream_a_qa.md §4 통합 체크리스트에서 사람이 확인.
//
// 실행: npm run qa:session  (rolldown 번들 후 node)
//   자세한 건 docs/stream_b_qa.md 참고.
// =============================================================================

import type { Quiz, Followup } from '../src/shared/types'
import { useSession } from '../src/content/session'
import { createSessionQueue } from '../src/content/session-bind'

// ─── 미니 assert 프레임워크 ──────────────────────────────────────────────────

let passN = 0
let failN = 0
function check(label: string, cond: boolean): void {
  if (cond) passN++
  else failN++
  console.log(`${cond ? 'PASS' : 'FAIL'} — ${label}`)
}

const s = () => useSession.getState()
/** store를 초기 상태로 되돌린다(각 시나리오 독립). parentConcept는 내부 필드. */
const reset = () =>
  useSession.setState({ phase: 'IDLE', active: null, results: [], parentConcept: null } as never)

// ─── 픽스처: 2단계 재질문 트리를 가진 Quiz + 단문항 Quiz ─────────────────────

const O = ['보기A', '보기B', '보기C', '보기D']
const L2: Followup = { level: 2, prereqConceptTag: '인플레이션', question: 'l2', options: O, answerIndex: 1, explanation: '설명2', followups: [] }
const L1: Followup = { level: 1, prereqConceptTag: '통화정책', question: 'l1', options: O, answerIndex: 1, explanation: '설명1', followups: [L2] }
const QMAIN: Quiz = { claimId: 'c2', conceptTag: '기준금리', anchorText: '', paragraphIndex: 2, question: 'main', options: O, answerIndex: 1, explanation: '설명0', followups: [L1] }
const QSOLO: Quiz = { claimId: 'c1', conceptTag: '무역수지', anchorText: '', paragraphIndex: 5, question: 'solo', options: O, answerIndex: 0, explanation: '설명', followups: [] }
const QX: Quiz = { ...QSOLO, claimId: 'c3', conceptTag: '환율' }

// ─── 1) 진단 루프: 오답 → L1 → L2 → IDLE + parentConcept 엣지 체인 ──────────

reset()
s().startQuestion(QMAIN)
check('start → ASKING(level 0)', s().phase === 'ASKING' && s().active?.level === 0)
s().submitAnswer(0) // 오답(정답 idx 1)
check('오답 → SHOW_EXPLANATION', s().phase === 'SHOW_EXPLANATION')
s().dismissExplanation()
check('설명 후 L1 강등(ASKING level 1)', s().phase === 'ASKING' && s().active?.level === 1)
s().submitAnswer(0)
s().dismissExplanation()
check('L1 오답 후 L2 강등(level 2)', s().active?.level === 2)
s().submitAnswer(0)
s().dismissExplanation()
check('L2 오답 후(재질문 소진) IDLE', s().phase === 'IDLE' && s().active === null)
check(
  'parentConcept 엣지 체인 = null→기준금리→통화정책 (서버 선행→후행 복원용)',
  s().results.map((r) => r.parentConcept).join('>') === '>기준금리>통화정책',
)
check(
  'conceptTag echo = 기준금리(main)→통화정책(L1)→인플레이션(L2)',
  s().results.map((r) => r.conceptTag).join('>') === '기준금리>통화정책>인플레이션',
)
check('level 기록 = 0,1,2', s().results.map((r) => r.level).join(',') === '0,1,2')
check('전부 오답 기록', s().results.every((r) => !r.correct) && s().results.length === 3)

// ─── 2) 정답도 채점된 보기를 보여준 뒤 dismiss해야 IDLE(재질문은 안 탐) + flush 멱등 ──

reset()
s().startQuestion(QMAIN)
s().submitAnswer(1) // 정답
check(
  'main 정답 → SHOW_CORRECT(채점된 보기 유지, active 그대로)',
  s().phase === 'SHOW_CORRECT' && s().active?.quiz.claimId === 'c2',
)
s().dismissExplanation()
check('정답 확인 후 dismiss → IDLE(재질문 스킵)', s().phase === 'IDLE' && s().active === null)
const only = s().results[0]
check(
  '결과 1건 correct/level0/parent null',
  s().results.length === 1 &&
    only.conceptTag === '기준금리' &&
    only.parentConcept === null &&
    only.level === 0 &&
    only.correct === true,
)
// OX 퀴즈 재료(서버가 개념 상세용 O/X 를 만들 근거)가 함께 실려야 한다.
check(
  'OX 재료 기록 — question/selectedOption/correctOption',
  !!only.question && only.selectedOption === QMAIN.options[1] && only.correctOption === QMAIN.options[QMAIN.answerIndex],
)
const drained = s().flushResults()
check('flush가 누적 반환(1건)', drained.length === 1)
check('flush 후 버퍼 빔 + 재flush 빈배열', s().results.length === 0 && s().flushResults().length === 0)

// ─── 3) 가드: 잘못된 시점 호출은 무시 ────────────────────────────────────────

reset()
s().submitAnswer(0)
check('IDLE에서 submit 무시(결과 없음)', s().results.length === 0 && s().phase === 'IDLE')
s().dismissExplanation()
check('IDLE에서 dismiss 무시', s().phase === 'IDLE')
s().startQuestion(QMAIN)
s().startQuestion(QSOLO)
check('ASKING 중 startQuestion 무시(문항 유지)', s().active?.quiz.claimId === 'c2')

// ─── 4) 제출 큐(session-bind): 유실 방지 + 순차 + 다중 + dispose ─────────────

reset()
const q = createSessionQueue()
q.enqueue([QSOLO])
check('enqueue 즉시 제시(IDLE였으므로)', s().phase === 'ASKING' && s().active?.quiz.claimId === 'c1')
q.enqueue([QMAIN, QX]) // 풀이 중 2건 진입(한 문단 다중 상당) → 대기
check('풀이 중 enqueue는 대기(현재 문항 유지)', s().active?.quiz.claimId === 'c1')
s().submitAnswer(0) // QSOLO 정답 → SHOW_CORRECT
s().dismissExplanation() // 확인 후 dismiss → IDLE → pump
check('앞 문항 종료 후 다음(QMAIN) 순차 제시', s().active?.quiz.claimId === 'c2')
s().submitAnswer(1) // QMAIN 정답 → SHOW_CORRECT
s().dismissExplanation() // → IDLE → pump
check('그 다음(QX) 순차 제시 — 유실 없음', s().active?.quiz.claimId === 'c3')
s().submitAnswer(0) // QX 정답 → SHOW_CORRECT
s().dismissExplanation() // → 큐 소진 → IDLE
check('큐 소진 후 IDLE', s().phase === 'IDLE' && s().active === null)
q.dispose()
q.enqueue([QSOLO]) // dispose 후에도 enqueue는 IDLE이라 즉시 pump는 되지만,
s().submitAnswer(0)
s().dismissExplanation() // 이후 IDLE 복귀 시 자동 pump는 없어야 함(구독 해제)
q.enqueue([QMAIN])
check('dispose 후: IDLE 복귀 자동 pump 없음(수동 enqueue만 즉시 반영)', s().active?.quiz.claimId === 'c2')

// ─── 요약 ────────────────────────────────────────────────────────────────────

console.log(`\n${failN === 0 ? '✅ ALL PASS' : '❌ FAILED'} — ${passN} passed, ${failN} failed`)
if (failN > 0) process.exit(1)
