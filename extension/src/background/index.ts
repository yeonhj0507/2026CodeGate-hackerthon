// =============================================================================
// background/index.ts — 서비스 워커 엔트리 (Stream C 담당)
// content script ↔ background 메시지 라우팅. 네트워크 호출은 api.ts에 위임.
// =============================================================================

import type { ChromeMessage } from '../shared/types'
import {
  drainRetryQueue,
  getAuthStatus,
  login,
  logout,
  sendQuizRequest,
  sendScrapRequest,
} from './api'

// 서비스워커가 (재)시작될 때마다 1회 재시도 큐 drain 시도 (T4.4-b).
void drainRetryQueue()

chrome.runtime.onMessage.addListener((message: ChromeMessage, _sender, sendResponse) => {
  switch (message.type) {
    case 'REQUEST_QUIZ':
      sendQuizRequest(message.title, message.body)
        .then((quiz) => sendResponse({ type: 'QUIZ_RESPONSE', quiz } satisfies ChromeMessage))
        .catch((err: Error) =>
          sendResponse({ type: 'QUIZ_ERROR', error: err.message } satisfies ChromeMessage),
        )
      return true // 비동기 응답

    case 'SEND_SCRAP':
      sendScrapRequest(message.payload)
        .then(() => sendResponse({ type: 'SCRAP_RESPONSE', ok: true } satisfies ChromeMessage))
        .catch((err: Error) =>
          sendResponse({ type: 'SCRAP_ERROR', error: err.message } satisfies ChromeMessage),
        )
      return true

    case 'GET_AUTH_STATUS':
      getAuthStatus()
        .then((s) =>
          sendResponse({ type: 'AUTH_STATUS', ...s } satisfies ChromeMessage),
        )
        .catch(() => sendResponse({ type: 'AUTH_STATUS', loggedIn: false } satisfies ChromeMessage))
      return true

    case 'LOGIN':
      login(message.email, message.password, message.signup)
        .then(({ userId, email }) =>
          sendResponse({ type: 'LOGIN_RESPONSE', userId, email } satisfies ChromeMessage),
        )
        .catch((err: Error) =>
          sendResponse({ type: 'LOGIN_ERROR', error: err.message } satisfies ChromeMessage),
        )
      return true

    case 'LOGOUT':
      logout().then(() => sendResponse({ type: 'LOGOUT_RESPONSE' } satisfies ChromeMessage))
      return true

    default:
      return false
  }
})
