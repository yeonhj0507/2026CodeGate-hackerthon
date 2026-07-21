// =============================================================================
// qa/scrap-qa.ts — /scrap 재시도 큐 · mock 퀴즈 QA 하니스 (Stream C / Step 10 · T=5)
//
// 목적: A의 qa/anchor-qa.ts와 같은 패턴 — 실제 background/api.ts·mockQuiz.ts
//   코드를 그대로 불러와(재구현 아님) chrome.storage.local·fetch만 스텁으로 갈아
//   끼워서 검증한다. 특히 T4.9에서 B가 발견한 엣지 결함 2건(레이스·poison message)의
//   수정이 실제 코드에서 의도대로 동작하는지, Bearer 토큰 best-effort 첨부가
//   맞는지를 확인한다.
//
// import.meta.env.VITE_MOCK_QUIZ/VITE_MOCK_SCRAP 체크가 있는 sendQuizRequest/
// sendScrapRequest 자체는 (플레인 node 실행 환경엔 import.meta.env가 없어 별도
// 번들 설정 없이는 호출 시 즉시 throw함) 대상에서 제외 — 그 두 줄은 단순 문자열
// 비교라 리스크가 낮고, 대신 그 아래 실제 로직(drainRetryQueue·postScrap 경유)은
// drainRetryQueue를 직접 호출해 전부 커버한다.
//
// 실행: npm run qa:scrap (rolldown으로 번들 → node 실행)
// =============================================================================

import { drainRetryQueue } from '../src/background/api'
import { buildMockQuizzes } from '../src/background/mockQuiz'
import { STORAGE_KEYS } from '../src/shared/constants'
import type { ScrapRequest } from '../src/shared/types'

// ─── chrome.storage.local 스텁 (메모리 기반) ─────────────────────────────────

let storageState: Record<string, unknown> = {}

function resetStorage(seed: Record<string, unknown> = {}) {
  storageState = { ...seed }
}

;(globalThis as unknown as { chrome: unknown }).chrome = {
  storage: {
    local: {
      get: async (key: string) => ({ [key]: storageState[key] }),
      set: async (obj: Record<string, unknown>) => {
        Object.assign(storageState, obj)
      },
    },
  },
}

// ─── fetch 스텁 ────────────────────────────────────────────────────────────

interface FetchCall {
  title: string
  auth?: string
}

let calls: FetchCall[] = []
let outcomeFor: Record<string, 'ok' | 'fail'> = {}
let delayForMs: Record<string, number> = {}

function installFetchStub() {
  calls = []
  outcomeFor = {}
  delayForMs = {}
  ;(globalThis as unknown as { fetch: unknown }).fetch = async (
    _url: unknown,
    init?: { body?: string; headers?: Record<string, string> },
  ) => {
    const body = JSON.parse(init?.body ?? '{}') as { articleTitle: string }
    const headers = init?.headers ?? {}
    calls.push({ title: body.articleTitle, auth: headers['Authorization'] })
    const wait = delayForMs[body.articleTitle] ?? 0
    if (wait) await new Promise((r) => setTimeout(r, wait))
    const outcome = outcomeFor[body.articleTitle] ?? 'ok'
    if (outcome === 'fail') return { ok: false, status: 500 } as Response
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }
}

// ─── 픽스처 헬퍼 ──────────────────────────────────────────────────────────────

function payload(title: string): ScrapRequest {
  return {
    articleTitle: title,
    articleBody: 'body',
    results: [{ conceptTag: 'c', parentConcept: null, level: 0, correct: true }],
  }
}

function entry(title: string, attempts = 0) {
  return { payload: payload(title), attempts }
}

// ─── 결과 집계 ────────────────────────────────────────────────────────────────

let pass = 0
let fail = 0
const failures: string[] = []

function check(label: string, ok: boolean, detail?: string) {
  if (ok) {
    pass++
    console.log(`  ✓ ${label}`)
  } else {
    fail++
    const line = `  ✗ ${label}${detail ? ` — ${detail}` : ''}`
    failures.push(line)
    console.log(line)
  }
}

console.log('\n=== /scrap 재시도 큐 · mock 퀴즈 QA (실제 코드 import) ===\n')

// ─── 그룹 1: 전부 성공 — FIFO 순서·큐 완전 소진 ───────────────────────────────

console.log('[1] drainRetryQueue — 전부 성공')
{
  installFetchStub()
  resetStorage({ [STORAGE_KEYS.RETRY_QUEUE]: [entry('a'), entry('b'), entry('c')] })
  await drainRetryQueue()
  const finalQueue = storageState[STORAGE_KEYS.RETRY_QUEUE] as unknown[]
  check('큐가 완전히 비었는가', finalQueue.length === 0, JSON.stringify(finalQueue))
  check(
    'a, b, c 순서대로 전송됐는가',
    calls.map((c) => c.title).join(',') === 'a,b,c',
    calls.map((c) => c.title).join(','),
  )
}

// ─── 그룹 2: 중간 실패 — 앞은 제거, 실패 지점부터는 순서 보존 ────────────────────

console.log('\n[2] drainRetryQueue — 중간(b) 실패')
{
  installFetchStub()
  outcomeFor.b = 'fail'
  resetStorage({ [STORAGE_KEYS.RETRY_QUEUE]: [entry('a'), entry('b'), entry('c')] })
  await drainRetryQueue()
  const finalQueue = storageState[STORAGE_KEYS.RETRY_QUEUE] as { payload: ScrapRequest; attempts: number }[]
  check('a는 제거됐는가', !finalQueue.some((e) => e.payload.articleTitle === 'a'))
  check(
    'b는 attempts=1로 남고, c는 그 뒤에 순서 보존됐는가',
    finalQueue.length === 2 &&
      finalQueue[0].payload.articleTitle === 'b' &&
      finalQueue[0].attempts === 1 &&
      finalQueue[1].payload.articleTitle === 'c',
    JSON.stringify(finalQueue),
  )
  check('c는 시도조차 안 됐는가(순서 보존)', !calls.some((c) => c.title === 'c'))
}

// ─── 그룹 3: poison message — 상한 도달 시 드롭, 뒤는 풀림 (T4.9 finding #2) ───

console.log('\n[3] drainRetryQueue — poison message(영구 실패) 5회 후 드롭')
{
  installFetchStub()
  outcomeFor.poison = 'fail'
  resetStorage({
    [STORAGE_KEYS.RETRY_QUEUE]: [entry('poison'), entry('b'), entry('c')],
  })
  for (let i = 0; i < 6; i++) await drainRetryQueue() // MAX_RETRY_ATTEMPTS(5) 초과분까지 트리거
  const finalQueue = storageState[STORAGE_KEYS.RETRY_QUEUE] as unknown[]
  check('poison은 드롭되고 b, c는 처리되어 큐가 비었는가', finalQueue.length === 0, JSON.stringify(finalQueue))
  check('b, c는 실제로 전송됐는가', calls.some((c) => c.title === 'b') && calls.some((c) => c.title === 'c'))
}

// ─── 그룹 4: 동시 drain — 뮤텍스로 레이스 방지 (T4.9 finding #1) ────────────────

console.log('\n[4] drainRetryQueue — 동시 호출 시 유실 없음(뮤텍스)')
{
  installFetchStub()
  delayForMs.a = 30 // a 처리 중 두 번째 drain이 겹치도록 지연
  resetStorage({ [STORAGE_KEYS.RETRY_QUEUE]: [entry('a'), entry('b')] })
  await Promise.all([drainRetryQueue(), drainRetryQueue()])
  const finalQueue = storageState[STORAGE_KEYS.RETRY_QUEUE] as unknown[]
  check('큐가 완전히 비었는가(유실·중복 없음)', finalQueue.length === 0, JSON.stringify(finalQueue))
  check(
    'a, b 각각 정확히 1번씩만 전송됐는가(중복 없음)',
    calls.filter((c) => c.title === 'a').length === 1 && calls.filter((c) => c.title === 'b').length === 1,
    JSON.stringify(calls),
  )
}

// ─── 그룹 5: Bearer 토큰 best-effort (buildHeaders → postScrap 경유) ───────────

console.log('\n[5] Bearer 토큰 best-effort 첨부')
{
  installFetchStub()
  resetStorage({ [STORAGE_KEYS.RETRY_QUEUE]: [entry('no-token')] }) // ACCESS_TOKEN 없음
  await drainRetryQueue()
  check('토큰 없으면 Authorization 헤더 자체가 생략되는가', calls[0]?.auth === undefined, calls[0]?.auth)
}
{
  installFetchStub()
  resetStorage({
    [STORAGE_KEYS.RETRY_QUEUE]: [entry('with-token')],
    [STORAGE_KEYS.ACCESS_TOKEN]: 'abc123',
  })
  await drainRetryQueue()
  check(
    '토큰 있으면 Authorization: Bearer <token>이 첨부되는가',
    calls[0]?.auth === 'Bearer abc123',
    calls[0]?.auth,
  )
}

// ─── 그룹 6: buildMockQuizzes — 실제 body 문단에서 anchorText 파생 ──────────────

console.log('\n[6] buildMockQuizzes — 실제 문단 기반 anchorText/paragraphIndex')
{
  const paragraphs = [
    '첫 번째 문단입니다. 도입부 내용을 담고 있습니다.',
    '두 번째 문단입니다. 배경 설명이 이어집니다.',
    '세 번째 문단입니다. 핵심 주장이 여기 나옵니다.',
    '네 번째 문단입니다. 반론 또는 보충 설명입니다.',
    '다섯 번째 문단입니다. 마무리 요약입니다.',
  ]
  const body = paragraphs.join('\n\n')
  const quizzes = buildMockQuizzes(body)

  check('퀴즈 2건이 생성되는가', quizzes.length === 2, String(quizzes.length))
  const [q1, q2] = quizzes
  check(
    'q1.anchorText가 실제 해당 문단 텍스트로 시작하는가',
    !!q1 && paragraphs[q1.paragraphIndex]?.startsWith(q1.anchorText),
    q1 ? `idx=${q1.paragraphIndex} anchor="${q1.anchorText}"` : 'undefined',
  )
  check(
    'q2.anchorText가 실제 해당 문단 텍스트로 시작하는가',
    !!q2 && paragraphs[q2.paragraphIndex]?.startsWith(q2.anchorText),
    q2 ? `idx=${q2.paragraphIndex} anchor="${q2.anchorText}"` : 'undefined',
  )
  check('q1, q2의 paragraphIndex가 서로 다른가', !!q1 && !!q2 && q1.paragraphIndex !== q2.paragraphIndex)
  check('q1은 2단계 재질문 트리를 포함하는가(followup UI 검증용)', (q1?.followups.length ?? 0) > 0 && (q1?.followups[0]?.followups.length ?? 0) > 0)

  // 최소 문단 수(MIN_ARTICLE_PARAGRAPHS=3, A 게이트) 케이스
  const minBody = ['P0', 'P1', 'P2'].join('\n\n')
  const minQuizzes = buildMockQuizzes(minBody)
  check(
    '최소 3문단 케이스에서도 두 앵커 인덱스가 겹치지 않는가',
    minQuizzes.length === 2 && minQuizzes[0].paragraphIndex !== minQuizzes[1].paragraphIndex,
    JSON.stringify(minQuizzes.map((q) => q.paragraphIndex)),
  )
}

// ─── 요약 ────────────────────────────────────────────────────────────────────

console.log('\n=== 요약 ===')
console.log(`통과: ${pass} / ${pass + fail}`)
if (failures.length) {
  console.log('\n실패 상세:')
  failures.forEach((f) => console.log(f))
}
console.log('')

if (fail > 0) process.exitCode = 1
