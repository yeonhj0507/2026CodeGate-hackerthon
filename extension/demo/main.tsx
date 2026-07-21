// =============================================================================
// demo/main.tsx — Step 3 mock UI dev 하니스 (Stream B, 빌드 산출물에 미포함)
//
// 실제 /quiz·/scrap 서버 없이 세션 store를 mock 퀴즈로 구동해 위젯 UI를 검증한다.
// `vite --config vite.demo.config.ts` 로 실행.
// =============================================================================

import { mountPanel } from '../src/content/ui/mount'
import { useSession } from '../src/content/session'
import { MOCK_QUIZZES } from '../src/content/ui/mock'

mountPanel({
  onEnd: () => {
    // 데모: 실제 배선(A)의 onEnd는 flush + SEND_SCRAP + queue.dispose/observer.disconnect.
    // 여기선 flush만(하니스라 observer/queue 없음). alert는 브라우저 자동화 블로킹이라 미사용.
    const results = useSession.getState().flushResults()
    console.log('[demo] 학습 종료 → flushResults:', results)
  },
})

document.getElementById('devbar')?.addEventListener('click', (e) => {
  const btn = (e.target as HTMLElement).closest('button')
  if (!btn) return
  const i = Number(btn.dataset.quiz)
  useSession.getState().startQuestion(MOCK_QUIZZES[i])
})
