// =============================================================================
// popup/Popup.tsx — 팝업 UI (Step 9: 로그인)
// 로컬 앱과 토큰을 공유하지 않는 독립 로그인(명세 §4.1). 네트워크·토큰 저장은
// background(api.ts)에 위임하고, 여기서는 메시지만 주고받는다.
// =============================================================================

import { useEffect, useState } from 'react'
import type { ChromeMessage } from '../shared/types'

const MOCK_AUTH = import.meta.env.VITE_MOCK_AUTH === 'true'

/** background로 메시지를 보내고 typed 응답을 받는다. */
function send(message: ChromeMessage): Promise<ChromeMessage> {
  return chrome.runtime.sendMessage(message) as Promise<ChromeMessage>
}

type AuthState =
  | { phase: 'loading' }
  | { phase: 'signedOut' }
  | { phase: 'signedIn'; email: string }

export function Popup() {
  const [auth, setAuth] = useState<AuthState>({ phase: 'loading' })

  async function refreshStatus() {
    const res = await send({ type: 'GET_AUTH_STATUS' })
    if (res.type === 'AUTH_STATUS' && res.loggedIn) {
      setAuth({ phase: 'signedIn', email: res.email ?? '' })
    } else {
      setAuth({ phase: 'signedOut' })
    }
  }

  useEffect(() => {
    void refreshStatus()
  }, [])

  if (auth.phase === 'loading') {
    return (
      <Shell>
        <p style={styles.muted}>불러오는 중…</p>
      </Shell>
    )
  }

  if (auth.phase === 'signedIn') {
    return <SignedIn email={auth.email} onSignedOut={refreshStatus} />
  }

  return <LoginForm onSignedIn={refreshStatus} />
}

// ─── 로그인 폼 ────────────────────────────────────────────────────────────────

function LoginForm({ onSignedIn }: { onSignedIn: () => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [signupMode, setSignupMode] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (busy) return
    if (!email.includes('@')) return setError('이메일을 입력하세요.')
    if (password.length < 8) return setError('비밀번호는 8자 이상이어야 합니다.')

    setBusy(true)
    setError(null)
    const res = await send({ type: 'LOGIN', email: email.trim(), password, signup: signupMode })
    setBusy(false)

    if (res.type === 'LOGIN_RESPONSE') {
      onSignedIn()
    } else if (res.type === 'LOGIN_ERROR') {
      setError(res.error)
    } else {
      setError('알 수 없는 오류가 발생했습니다.')
    }
  }

  return (
    <Shell>
      <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="이메일"
          autoFocus
          disabled={busy}
          style={styles.input}
        />
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="비밀번호 (8자 이상)"
          disabled={busy}
          style={styles.input}
        />
        {error && <div style={styles.error}>{error}</div>}
        <button type="submit" disabled={busy} style={styles.primaryBtn}>
          {busy ? '처리 중…' : signupMode ? '회원가입' : '로그인'}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => {
            setSignupMode((v) => !v)
            setError(null)
          }}
          style={styles.linkBtn}
        >
          {signupMode ? '이미 계정이 있어요 — 로그인' : '계정이 없어요 — 회원가입'}
        </button>
        {MOCK_AUTH && (
          <p style={styles.muted}>
            Mock 모드 — 서버 없이 동작합니다. 아무 이메일과 8자 이상 비밀번호로 들어오세요.
          </p>
        )}
      </form>
    </Shell>
  )
}

// ─── 로그인된 상태 ────────────────────────────────────────────────────────────

function SignedIn({ email, onSignedOut }: { email: string; onSignedOut: () => void }) {
  const [busy, setBusy] = useState(false)
  const [starting, setStarting] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  async function signOut() {
    setBusy(true)
    await send({ type: 'LOGOUT' })
    onSignedOut()
  }

  /** 현재 탭의 content script 에 세션 시작을 요청한다(사용자가 고른 기사에서만 열림). */
  async function startSession() {
    if (starting) return
    setStarting(true)
    setNotice(null)

    let tabUrl = ''
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })
      if (tab?.id === undefined) throw new Error('no tab')
      tabUrl = tab.url ?? ''

      const res = (await chrome.tabs.sendMessage(tab.id, {
        type: 'START_SESSION',
      } satisfies ChromeMessage)) as ChromeMessage

      if (res?.type === 'SESSION_STARTED') {
        window.close() // 패널이 떴으니 팝업은 비켜준다
        return
      }
      setNotice(res?.type === 'SESSION_UNAVAILABLE' ? res.reason : '시작하지 못했습니다.')
    } catch {
      // content script 가 응답하지 않는 경우. 두 가지가 섞여 있어 구분해 안내한다.
      //   (1) 확장을 새로 설치·갱신하기 전부터 열려 있던 탭 → 예전 content script 가
      //       남아 연결이 끊긴 상태다. 새로고침하면 해결된다.
      //   (2) chrome:// · 웹스토어 등 content script 가 아예 주입되지 않는 페이지.
      setNotice(
        /^https?:/.test(tabUrl)
          ? '페이지를 새로고침(F5)한 뒤 다시 눌러주세요.'
          : '이 페이지에서는 사용할 수 없습니다.',
      )
    } finally {
      setStarting(false)
    }
  }

  return (
    <Shell>
      <p style={{ fontSize: 13, margin: '0 0 10px' }}>
        <span style={styles.muted}>로그인됨</span>
        <br />
        <strong>{email || '사용자'}</strong>
      </p>

      <button type="button" disabled={starting} onClick={startSession} style={styles.primaryBtn}>
        {starting ? '여는 중…' : '이 기사에서 시작'}
      </button>
      <p style={{ ...styles.muted, marginTop: 8 }}>
        기사를 열면 화면 오른쪽 아래에 시작 카드가 자동으로 뜹니다. 카드를 닫았거나
        뜨지 않을 때 이 버튼으로 시작하세요.
      </p>

      {notice && <div style={{ ...styles.error, marginTop: 8 }}>{notice}</div>}

      <button
        type="button"
        disabled={busy}
        onClick={signOut}
        style={{ ...styles.linkBtn, marginTop: 10 }}
      >
        {busy ? '로그아웃 중…' : '로그아웃'}
      </button>
    </Shell>
  )
}

// ─── 공통 셸 · 스타일 ─────────────────────────────────────────────────────────

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ padding: 16, background: '#FBFAF9', minHeight: '100%' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '0 0 12px' }}>
        <span
          style={{
            width: 18,
            height: 18,
            borderRadius: 6,
            background: 'linear-gradient(135deg, #FF7A93, #E63B5C)',
          }}
        />
        <h1 style={{ fontSize: 16, fontWeight: 700, color: '#E63B5C', margin: 0 }}>프로버</h1>
      </div>
      {children}
    </div>
  )
}

const styles = {
  input: {
    padding: '8px 10px',
    fontSize: 13,
    border: '1px solid #ECE7E0',
    borderRadius: 8,
    outline: 'none',
    background: '#fff',
  },
  primaryBtn: {
    padding: '9px 10px',
    fontSize: 13,
    fontWeight: 600,
    color: '#fff',
    background: '#E63B5C',
    border: 'none',
    borderRadius: 8,
    cursor: 'pointer',
  },
  linkBtn: {
    padding: '4px',
    fontSize: 12,
    color: '#E63B5C',
    background: 'none',
    border: 'none',
    cursor: 'pointer',
  },
  error: {
    padding: '8px 10px',
    fontSize: 12,
    color: '#dc2626',
    background: '#fef2f2',
    borderRadius: 8,
  },
  muted: { fontSize: 12, color: '#6b7280', margin: 0 },
} satisfies Record<string, React.CSSProperties>
