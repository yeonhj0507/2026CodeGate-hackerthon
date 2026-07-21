// =============================================================================
// content/ui/StartPrompt.tsx — 기사 감지 시 뜨는 시작 제안 카드
//
// 기사로 인식된 페이지에서 자동으로 떠서, 사용자가 원할 때만 세션을 시작하게 한다.
// (팝업을 열어 버튼을 누르는 2단계 없이 한 번에 시작하기 위함)
//
// 이 카드가 떠 있는 동안에는 서버를 호출하지 않는다 — /quiz 요청은 사용자가
// "읽기 시작"을 눌렀을 때 처음 나간다.
// =============================================================================

import { useState } from 'react'

export type StartResult = { ok: true } | { ok: false; reason: string }

export interface StartPromptProps {
  /** 세션 시작. 실패 시 사유를 카드 안에 그대로 보여준다. */
  onStart: () => Promise<StartResult>
  /** 닫기(이 페이지에서 다시 띄우지 않음). */
  onDismiss: () => void
}

export function StartPrompt({ onStart, onDismiss }: StartPromptProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function start() {
    if (busy) return
    setBusy(true)
    setError(null)

    const result = await onStart()
    // 성공하면 카드가 통째로 언마운트되므로 상태를 되돌릴 필요가 없다.
    if (!result.ok) {
      setError(result.reason)
      setBusy(false)
    }
  }

  return (
    <div className="prompt">
      <button className="prompt-close" onClick={onDismiss} aria-label="닫기">
        ×
      </button>

      <div className="prompt-brand">프로버</div>
      <p className="prompt-desc">
        이 기사, 제대로 이해했는지
        <br />
        질문으로 확인하며 읽어볼까요?
      </p>

      {error && <div className="prompt-error">{error}</div>}

      <button className="prompt-cta" onClick={start} disabled={busy}>
        {busy ? '여는 중…' : '읽기 시작'}
      </button>
    </div>
  )
}
