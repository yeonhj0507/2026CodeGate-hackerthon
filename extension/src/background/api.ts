// =============================================================================
// background/api.ts — 서버 호출 (Stream C 담당)
// T=3: /quiz 연동 완성 — Bearer 토큰 best-effort 첨부 + VITE_MOCK_QUIZ mock 모드.
// T=4: /scrap 연동 완성 — Bearer 토큰 재사용 + 빈 배치 방어 + 재시도 큐 + VITE_MOCK_SCRAP.
// =============================================================================

import { ENDPOINTS, STORAGE_KEYS } from '../shared/constants'
import type { Quiz, ScrapRequest } from '../shared/types'
import { buildMockQuizzes } from './mockQuiz'

/** chrome.storage.local에서 토큰 조회. 없으면 null(로그인 전에도 호출 가능해야 함). */
async function getAccessToken(): Promise<string | null> {
  const result = await chrome.storage.local.get(STORAGE_KEYS.ACCESS_TOKEN)
  const token = result[STORAGE_KEYS.ACCESS_TOKEN]
  return typeof token === 'string' && token.length > 0 ? token : null
}

/** 토큰이 있으면 Authorization 헤더 포함, 없으면 생략(빈 Bearer 전송 안 함). T=3 §T3.5 확정. */
async function buildHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  const token = await getAccessToken()
  if (token) headers['Authorization'] = `Bearer ${token}`
  return headers
}

// ─── 인증 (Step 9: 팝업 로그인) ──────────────────────────────────────────────
//
// 로컬 앱(local_app)과 토큰을 공유하지 않는 독립 로그인이다(명세 §4.1).
// 서버 계약: POST /auth/login {email,password,client} → {accessToken,expiresIn,userId},
//            GET /auth/me (Bearer) → {userId,email,displayName}.
// /auth/logout 은 서버에 없다(JWT 무상태) — 로그아웃은 로컬 토큰 폐기로 처리한다.
// VITE_MOCK_AUTH=true면 서버 없이 로그인 성공 처리(VITE_MOCK_QUIZ/SCRAP와 짝, 무서버 e2e).

/**
 * Vite 가 주입하는 플래그를 안전하게 읽는다.
 *
 * qa/*.ts 는 rolldown 으로 번들해 Node 에서 돌리는데, 그쪽엔 import.meta.env 자체가
 * 없어 최상위에서 바로 접근하면 모듈 로드가 터진다(qa:scrap 이 그렇게 깨져 있었다).
 */
function viteFlag(name: string): boolean {
  const env = (import.meta as { env?: Record<string, string | undefined> }).env
  return env?.[name] === 'true'
}

const MOCK_AUTH = viteFlag('VITE_MOCK_AUTH')
const MOCK_TOKEN = 'mock-access-token'

async function setSession(token: string, email: string): Promise<void> {
  await chrome.storage.local.set({
    [STORAGE_KEYS.ACCESS_TOKEN]: token,
    [STORAGE_KEYS.USER_EMAIL]: email,
  })
}

async function clearSession(): Promise<void> {
  await chrome.storage.local.remove([STORAGE_KEYS.ACCESS_TOKEN, STORAGE_KEYS.USER_EMAIL])
}

/** 서버 통일 에러 포맷 {error:{code,message}}에서 사람이 읽을 메시지를 뽑는다(errors.py §8). */
async function extractApiError(res: Response, fallback: string): Promise<string> {
  try {
    const data = (await res.json()) as { error?: { message?: string } }
    if (data?.error?.message) return data.error.message
  } catch {
    /* JSON 아님 — fallback 사용 */
  }
  return `${fallback} (${res.status})`
}

/** 로그인 결과. 성공 시 토큰을 저장하고 사용자 식별 정보를 돌려준다. */
export interface LoginResult {
  userId: string
  email: string
}

/**
 * 로그인(또는 signup=true면 회원가입 후 이어서 로그인).
 * - MOCK_AUTH: 서버 호출 없이 즉시 성공, mock 토큰 저장.
 * - signup: POST /auth/signup(계정 생성, 토큰 미발급)한 뒤 같은 자격증명으로 로그인.
 * 실패 시 서버 메시지를 담아 throw.
 */
export async function login(email: string, password: string, signup = false): Promise<LoginResult> {
  if (MOCK_AUTH) {
    await setSession(MOCK_TOKEN, email)
    return { userId: 'mock-user', email }
  }

  if (signup) {
    const res = await fetch(ENDPOINTS.SIGNUP, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    if (!res.ok) throw new Error(await extractApiError(res, '회원가입에 실패했습니다'))
  }

  const res = await fetch(ENDPOINTS.LOGIN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, client: 'extension' }),
  })
  if (!res.ok) throw new Error(await extractApiError(res, '로그인에 실패했습니다'))

  const data = (await res.json()) as { accessToken: string; userId: string }
  await setSession(data.accessToken, email)
  return { userId: data.userId, email }
}

/** 로그아웃 — 서버 무상태이므로 로컬 세션만 폐기한다. */
export async function logout(): Promise<void> {
  await clearSession()
}

/** 현재 로그인 상태. 토큰이 있으면 /auth/me로 검증(401이면 만료로 보고 세션 폐기). */
export async function getAuthStatus(): Promise<{ loggedIn: boolean; userId?: string; email?: string }> {
  const token = await getAccessToken()
  if (!token) return { loggedIn: false }

  if (MOCK_AUTH) {
    const result = await chrome.storage.local.get(STORAGE_KEYS.USER_EMAIL)
    return { loggedIn: true, userId: 'mock-user', email: result[STORAGE_KEYS.USER_EMAIL] as string }
  }

  const res = await fetch(ENDPOINTS.ME, { headers: await buildHeaders() })
  if (!res.ok) {
    if (res.status === 401) await clearSession() // 만료·무효 토큰 정리
    return { loggedIn: false }
  }
  const me = (await res.json()) as { userId: string; email: string }
  return { loggedIn: true, userId: me.userId, email: me.email }
}

/**
 * POST /quiz 요청. 실패 시 throw.
 * VITE_MOCK_QUIZ=true면 fetch 대신 body에서 뽑은 canned Quiz[] 반환(§T3.4).
 */
export async function sendQuizRequest(title: string, body: string): Promise<Quiz[]> {
  if (viteFlag('VITE_MOCK_QUIZ')) {
    return buildMockQuizzes(body)
  }

  const res = await fetch(ENDPOINTS.QUIZ, {
    method: 'POST',
    headers: await buildHeaders(),
    body: JSON.stringify({ articleTitle: title, articleBody: body }),
  })
  if (!res.ok) throw new Error(`quiz request failed: ${res.status}`)
  const data = (await res.json()) as { quiz: Quiz[] }
  return data.quiz
}

/** 큐에 쌓인 1건. attempts는 head에서 실패한 횟수(poison message 판별용, T4.9 finding #2). */
interface RetryEntry {
  payload: ScrapRequest
  attempts: number
}

/** 이 횟수만큼 연속 실패하면 dead-letter로 버리고 다음 항목으로 넘어간다(큐 영구 정체 방지). */
const MAX_RETRY_ATTEMPTS = 5

async function getRetryQueue(): Promise<RetryEntry[]> {
  const result = await chrome.storage.local.get(STORAGE_KEYS.RETRY_QUEUE)
  const queue = result[STORAGE_KEYS.RETRY_QUEUE]
  return Array.isArray(queue) ? (queue as RetryEntry[]) : []
}

async function setRetryQueue(queue: RetryEntry[]): Promise<void> {
  await chrome.storage.local.set({ [STORAGE_KEYS.RETRY_QUEUE]: queue })
}

/** 실제 /scrap 호출 1건. mock 분기 없이 순수 네트워크만 담당(재시도 큐 drain에서도 재사용). */
async function postScrap(payload: ScrapRequest): Promise<void> {
  const res = await fetch(ENDPOINTS.SCRAP, {
    method: 'POST',
    headers: await buildHeaders(),
    body: JSON.stringify(payload),
  })
  if (!res.ok) throw new Error(`scrap request failed: ${res.status}`)
}

// RETRY_QUEUE를 건드리는 모든 연산(enqueue·drain)을 하나의 체인으로 직렬화한다.
// sendScrapRequest 실패 시의 "읽고-추가하고-쓰기"와 drainRetryQueue의 "읽고-빼고-쓰기"가
// 동시에 실행되면 서로 상대의 쓰기를 덮어써 배치가 유실될 수 있었다(T4.9 finding #1,
// read-modify-write 레이스). 이제 큐에 손대는 코드는 반드시 이 락을 거쳐 순서대로만 실행된다.
let queueLock: Promise<unknown> = Promise.resolve()
function withQueueLock<T>(fn: () => Promise<T>): Promise<T> {
  const run = queueLock.then(fn, fn)
  queueLock = run.then(
    () => undefined,
    () => undefined,
  )
  return run
}

async function enqueueRetry(payload: ScrapRequest): Promise<void> {
  await withQueueLock(async () => {
    const queue = await getRetryQueue()
    queue.push({ payload, attempts: 0 })
    await setRetryQueue(queue)
  })
}

/**
 * 재시도 큐를 앞에서부터 순서대로 비운다.
 * - head가 성공하면 제거하고 다음으로 진행.
 * - head가 실패하면 attempts를 올리고, MAX_RETRY_ATTEMPTS 미만이면 그 자리에 둔 채 이번 drain을
 *   멈춘다(순서 보존, 다음 기회 대기). MAX_RETRY_ATTEMPTS에 도달하면 **버리고 다음 항목으로
 *   계속 진행** — 영구 실패 항목(poison message) 하나가 뒤 전체를 막지 못하게 한다(T4.9 finding #2).
 * 호출 시점(T4.4): sendScrapRequest 성공 직후, 서비스워커 시작 시 1회.
 */
export async function drainRetryQueue(): Promise<void> {
  await withQueueLock(async () => {
    let queue = await getRetryQueue()
    while (queue.length > 0) {
      const [head, ...rest] = queue
      try {
        await postScrap(head.payload)
      } catch {
        const attempts = head.attempts + 1
        if (attempts >= MAX_RETRY_ATTEMPTS) {
          queue = rest // dead-letter: 버리고 다음 항목 계속
          await setRetryQueue(queue)
          continue
        }
        queue = [{ ...head, attempts }, ...rest]
        await setRetryQueue(queue)
        break // 아직 재시도 여지 있음 — 이번 drain은 여기서 멈추고 다음 기회로
      }
      queue = rest
      await setRetryQueue(queue)
    }
  })
}

/**
 * POST /scrap 요청.
 * - 빈 results는 네트워크 호출 없이 즉시 성공 처리(T4.2, 송신측 A도 가드하지만 방어적으로 이중 처리).
 * - VITE_MOCK_SCRAP=true면 fetch 없이 즉시 성공(무서버 e2e, T4.6).
 * - 실패 시 throw 대신 RETRY_QUEUE에 적재 후 정상 반환 — content는 fire-and-forget(T4.5)이라
 *   여기서 에러를 던져도 호출부가 무시하므로, "받아서 재시도 예약함"을 성공으로 간주.
 */
export async function sendScrapRequest(payload: ScrapRequest): Promise<void> {
  if (payload.results.length === 0) return

  if (viteFlag('VITE_MOCK_SCRAP')) return

  try {
    await postScrap(payload)
    void drainRetryQueue() // 이번 성공 참에 밀려있던 큐도 비워본다(T4.4-a)
  } catch {
    await enqueueRetry(payload)
  }
}
