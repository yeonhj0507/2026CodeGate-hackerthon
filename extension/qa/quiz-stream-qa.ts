// =============================================================================
// qa/quiz-stream-qa.ts — /quiz/stream NDJSON 수신 QA 하니스
//
// scrap-qa.ts 와 같은 패턴: 실제 background/api.ts 를 그대로 불러와 fetch·chrome
// 만 스텁으로 갈아 끼운다.
//
// 여기서 지키려는 것 둘:
//   1. 문항이 **도착하는 대로** 나온다. 스트림이 끝나야 나오면 이 기능은 의미가 없다.
//   2. 문항을 넘긴 뒤 끊기면 **폴백하지 않는다**. 폴백은 /quiz 를 처음부터 다시
//      받으므로, 이미 낸 문항이 한 번 더 출제된다.
//
// 실행: npm run qa:quiz-stream
// =============================================================================

import { streamQuizRequest } from '../src/background/api'
import type { Quiz } from '../src/shared/types'

// ─── 스텁 ────────────────────────────────────────────────────────────────────

;(globalThis as unknown as { chrome: unknown }).chrome = {
  storage: { local: { get: async () => ({}), set: async () => {} } },
}

function quiz(claimId: string): Quiz {
  return {
    claimId,
    conceptTag: `개념-${claimId}`,
    anchorText: '앵커',
    paragraphIndex: 0,
    question: '질문?',
    options: ['1', '2', '3', '4'],
    answerIndex: 0,
    explanation: '설명',
    followups: [],
  }
}

/** 청크를 순서대로 흘려보내는 가짜 스트림 응답. */
function streamingResponse(chunks: string[]) {
  const encoder = new TextEncoder()
  let i = 0
  return {
    ok: true,
    body: {
      getReader: () => ({
        read: async () =>
          i < chunks.length
            ? { done: false, value: encoder.encode(chunks[i++]) }
            : { done: true, value: undefined },
      }),
    },
  }
}

function line(obj: unknown): string {
  return JSON.stringify(obj) + '\n'
}

let fetchCalls: string[] = []

function installFetch(handler: (url: string) => unknown) {
  fetchCalls = []
  ;(globalThis as unknown as { fetch: unknown }).fetch = async (url: string) => {
    fetchCalls.push(url)
    const res = handler(url)
    if (res instanceof Error) throw res
    return res
  }
}

// ─── 러너 ────────────────────────────────────────────────────────────────────

let passed = 0
let failed = 0

function check(name: string, cond: boolean, detail = '') {
  if (cond) {
    passed++
    console.log(`  ok   ${name}`)
  } else {
    failed++
    console.log(`  FAIL ${name} ${detail}`)
  }
}

async function main() {
  // 1. 도착하는 대로 넘어온다 — 스트림이 끝나기 전에 이미 콜백이 불려 있어야 한다.
  {
    installFetch(() =>
      streamingResponse([line({ item: quiz('c1') }), line({ item: quiz('c2') }), line({ done: true, total: 2 })]),
    )
    const seen: string[] = []
    const total = await streamQuizRequest('제목', '본문', (q) => seen.push(q.claimId))
    check('문항을 순서대로 넘긴다', seen.join(',') === 'c1,c2', seen.join(','))
    check('총 개수를 반환한다', total === 2, String(total))
    check('스트림 엔드포인트를 쓴다', fetchCalls[0].endsWith('/quiz/stream'), fetchCalls[0])
  }

  // 2. 한 줄이 청크 경계에 걸쳐 잘려도 복원된다(TCP 는 줄 단위로 오지 않는다).
  {
    const whole = line({ item: quiz('c1') }) + line({ item: quiz('c2') })
    const cut = Math.floor(whole.length / 2)
    installFetch(() => streamingResponse([whole.slice(0, cut), whole.slice(cut)]))
    const seen: string[] = []
    await streamQuizRequest('제목', '본문', (q) => seen.push(q.claimId))
    check('잘린 줄을 이어붙여 파싱한다', seen.join(',') === 'c1,c2', seen.join(','))
  }

  // 3. 문항 전에 실패하면 조용히 /quiz 로 폴백한다.
  {
    installFetch((url) => {
      if (url.endsWith('/quiz/stream')) return new Error('boom')
      return { ok: true, json: async () => ({ quiz: [quiz('f1'), quiz('f2')] }) }
    })
    const seen: string[] = []
    const total = await streamQuizRequest('제목', '본문', (q) => seen.push(q.claimId))
    check('폴백이 문항을 채운다', seen.join(',') === 'f1,f2', seen.join(','))
    check('폴백 개수를 반환한다', total === 2, String(total))
    check('폴백은 /quiz 를 부른다', fetchCalls[1].endsWith('/quiz'), fetchCalls[1])
  }

  // 4. 구버전 서버(404)도 폴백 경로를 탄다.
  {
    installFetch((url) => {
      if (url.endsWith('/quiz/stream')) return { ok: false, status: 404 }
      return { ok: true, json: async () => ({ quiz: [quiz('f1')] }) }
    })
    const seen: string[] = []
    await streamQuizRequest('제목', '본문', (q) => seen.push(q.claimId))
    check('404 면 폴백한다', seen.join(',') === 'f1', seen.join(','))
  }

  // 5. **문항을 넘긴 뒤** 실패하면 폴백하지 않는다 — 중복 출제 방지.
  {
    installFetch((url) => {
      if (url.endsWith('/quiz/stream')) {
        return streamingResponse([
          line({ item: quiz('c1') }),
          line({ error: { code: 'INTERNAL', message: '중간 실패' } }),
        ])
      }
      return { ok: true, json: async () => ({ quiz: [quiz('f1')] }) }
    })
    const seen: string[] = []
    let thrown: Error | null = null
    try {
      await streamQuizRequest('제목', '본문', (q) => seen.push(q.claimId))
    } catch (err) {
      thrown = err as Error
    }
    check('중간 실패를 에러로 올린다', thrown?.message === '중간 실패', String(thrown?.message))
    check('받은 문항은 그대로 유지된다', seen.join(',') === 'c1', seen.join(','))
    check('폴백을 부르지 않는다(중복 방지)', fetchCalls.length === 1, String(fetchCalls.length))
  }

  console.log(`\n${passed} passed, ${failed} failed`)
  if (failed > 0) process.exit(1)
}

void main()
