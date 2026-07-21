// =============================================================================
// content/ui/mount.tsx — Shadow DOM 마운트 (Stream B)
//
// 기사 페이지와 CSS 격리를 위해 custom element(prober-panel)에 shadow root를
// 붙이고 그 안에 React 패널을 렌더한다. DOM/브라우저 접근은 이 글루 계층에만
// 두고, React 컴포넌트(Panel 이하)는 SessionStore만 다루도록 유지한다.
//
// content orchestrator(content/index.tsx, T=3 align)가 이 mountPanel을 호출한다.
// =============================================================================

import { createRoot, type Root } from 'react-dom/client'
import { PANEL_WIDTH_PX, PROMPT_HOST_TAG, SHADOW_HOST_TAG } from '../../shared/constants'
import { Panel } from './Panel'
import { StartPrompt, type StartPromptProps } from './StartPrompt'
import { PANEL_CSS, PROMPT_CSS } from './theme'

export interface MountOptions {
  /** "학습 종료" 시 실행. background로 스크랩 전송을 트리거하는 콜백을 넘긴다. */
  onEnd?: () => void
}

export interface PanelHandle {
  unmount: () => void
}

let handle: PanelHandle | null = null

/**
 * 패널을 페이지에 1회 마운트. 이미 있으면 기존 핸들을 반환(중복 방지).
 * 패널이 본문을 가리지 않도록 <html>에 오른쪽 여백을 준다(글루 계층의 DOM 조작).
 */
export function mountPanel(options: MountOptions = {}): PanelHandle {
  if (handle) return handle

  const host = document.createElement(SHADOW_HOST_TAG)
  document.body.appendChild(host)

  const shadow = host.attachShadow({ mode: 'open' })
  const style = document.createElement('style')
  style.textContent = PANEL_CSS
  shadow.appendChild(style)

  const mountEl = document.createElement('div')
  shadow.appendChild(mountEl)

  const root: Root = createRoot(mountEl)
  root.render(<Panel onEnd={options.onEnd} />)

  // 본문이 패널 아래로 가려지지 않도록 페이지를 왼쪽으로 밀어준다.
  const prevPadding = document.documentElement.style.paddingRight
  document.documentElement.style.paddingRight = `${PANEL_WIDTH_PX}px`

  handle = {
    unmount: () => {
      root.unmount()
      host.remove()
      document.documentElement.style.paddingRight = prevPadding
      handle = null
    },
  }
  return handle
}

// ─── 시작 제안 카드 ──────────────────────────────────────────────────────────

let promptHandle: PanelHandle | null = null

/**
 * 기사 감지 시 우하단에 시작 제안 카드를 띄운다. 이미 떠 있으면 기존 핸들 반환.
 * 패널과 달리 페이지 레이아웃은 건드리지 않는다(고정 오버레이).
 */
export function mountStartPrompt(props: StartPromptProps): PanelHandle {
  if (promptHandle) return promptHandle

  const host = document.createElement(PROMPT_HOST_TAG)
  document.body.appendChild(host)

  const shadow = host.attachShadow({ mode: 'open' })
  const style = document.createElement('style')
  style.textContent = PROMPT_CSS
  shadow.appendChild(style)

  const mountEl = document.createElement('div')
  shadow.appendChild(mountEl)

  const root: Root = createRoot(mountEl)
  root.render(<StartPrompt {...props} />)

  promptHandle = {
    unmount: () => {
      root.unmount()
      host.remove()
      promptHandle = null
    },
  }
  return promptHandle
}

/** 제안 카드가 떠 있으면 내린다(세션 시작·닫기 시). */
export function unmountStartPrompt(): void {
  promptHandle?.unmount()
}
