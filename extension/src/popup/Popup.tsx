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

  async function signOut() {
    setBusy(true)
    await send({ type: 'LOGOUT' })
    onSignedOut()
  }

  return (
    <Shell>
      <p style={{ fontSize: 13, margin: '0 0 4px' }}>
        <span style={styles.muted}>로그인됨</span>
        <br />
        <strong>{email || '사용자'}</strong>
      </p>
      <p style={styles.muted}>기사를 읽으면 프로버가 배경지식을 짚어줍니다.</p>
      <button type="button" disabled={busy} onClick={signOut} style={styles.linkBtn}>
        {busy ? '로그아웃 중…' : '로그아웃'}
      </button>
    </Shell>
  )
}

// ─── 공통 셸 · 스타일 ─────────────────────────────────────────────────────────

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ padding: 16 }}>
      <h1 style={{ fontSize: 16, margin: '0 0 12px' }}>프로버</h1>
      {children}
    </div>
  )
}

const styles = {
  input: {
    padding: '8px 10px',
    fontSize: 13,
    border: '1px solid #d0d0d0',
    borderRadius: 6,
    outline: 'none',
  },
  primaryBtn: {
    padding: '9px 10px',
    fontSize: 13,
    fontWeight: 600,
    color: '#fff',
    background: '#2563eb',
    border: 'none',
    borderRadius: 6,
    cursor: 'pointer',
  },
  linkBtn: {
    padding: '4px',
    fontSize: 12,
    color: '#2563eb',
    background: 'none',
    border: 'none',
    cursor: 'pointer',
  },
  error: {
    padding: '8px 10px',
    fontSize: 12,
    color: '#b91c1c',
    background: '#fee2e2',
    borderRadius: 6,
  },
  muted: { fontSize: 12, color: '#666', margin: 0 },
} satisfies Record<string, React.CSSProperties>
