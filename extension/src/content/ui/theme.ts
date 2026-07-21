// =============================================================================
// content/ui/theme.ts — Shadow DOM에 주입할 스타일 (Stream B)
//
// 기사 페이지 CSS와 격리하기 위해 이 문자열을 shadow root의 <style>에 넣는다.
// 셀렉터는 shadow 경계 안에서만 유효하므로 짧은 클래스명을 쓴다.
// 색/간격은 CSS 변수로 모아 QA 단계(Step 10) 조정을 쉽게 한다.
// =============================================================================

import { PANEL_WIDTH_PX } from '../../shared/constants'

// 본문은 프리텐다드, "prober" 워드마크만 피그마 지정 폰트(Poppins Bold)를 쓴다.
// 두 shadow root(Panel/StartPrompt) 각각에 주입해야 폰트가 로드된다 — 호스트
// 페이지의 CSP가 막으면 조용히 다음 폴백 폰트로 내려간다(치명적이지 않음).
const FONT_IMPORTS = /* css */ `
@import url('https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.css');
@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@700&display=swap');
`

const FONT_BODY =
  "'Pretendard', -apple-system, BlinkMacSystemFont, 'Malgun Gothic', Roboto, sans-serif"
const FONT_WORDMARK = "'Poppins', sans-serif"

export const PANEL_CSS = /* css */ `
${FONT_IMPORTS}
:host { all: initial; }
* { box-sizing: border-box; }

.root {
  --bg: #ffffff;
  --surface: #FBFAF9;
  --fg: #1a1c1e;
  --muted: #6b7280;
  --line: #ECE7E0;
  --accent: #E63B5C;
  --accent-weak: #FFE3E9;
  --accent-soft: #E98BA0;
  --accent-disabled: #E6D6DA;
  --chip: #7A6A5D;
  --chip-weak: #EFE8E0;
  --ok: #059669;
  --ok-weak: #ecfdf5;
  --bad: #dc2626;
  --bad-weak: #fef2f2;
  --radius: 12px;
  --shadow: 0 8px 30px rgba(0, 0, 0, 0.12);

  position: fixed;
  top: 0;
  right: 0;
  z-index: 2147483647;
  width: ${PANEL_WIDTH_PX}px;
  height: 100vh;
  display: flex;
  flex-direction: column;
  background: var(--bg);
  color: var(--fg);
  border-left: 1px solid var(--line);
  box-shadow: var(--shadow);
  font-family: ${FONT_BODY};
  font-size: 14px;
  line-height: 1.6;
}

/* ── 헤더 ── */
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  background: var(--surface);
  border-bottom: 1px solid var(--line);
  flex: 0 0 auto;
}
.brand { display: flex; align-items: center; gap: 8px; }
.wordmark {
  font-family: ${FONT_WORDMARK};
  font-weight: 700;
  font-size: 15px;
  color: var(--fg);
}
.end-btn {
  border: none; background: none; color: var(--accent); font-weight: 700;
  font-size: 12px; cursor: pointer; padding: 4px 6px; border-radius: 6px;
}
.end-btn:hover { background: var(--accent-weak); color: var(--accent); }

/* ── 진행률 바(정답률) — 헤더와 분리된 별도 줄. 문항 수 상한이 없어도
   비율만 채우면 되므로 총 문항 수에 무관하게 항상 정확하다. ── */
.progress-row {
  display: flex; align-items: center; gap: 8px;
  padding: 8px 16px;
  background: var(--surface);
  flex: 0 0 auto;
}
.progress-track {
  flex: 1 1 auto;
  height: 10px;
  border-radius: 999px;
  background: var(--accent-weak);
  overflow: hidden;
}
.progress-fill {
  height: 100%;
  border-radius: 999px;
  background: var(--accent);
  transition: width .2s ease-out;
}
.progress-label {
  flex: 0 0 auto;
  font-size: 11px; font-weight: 600; color: var(--muted);
}

/* ── 본문 스크롤 영역 ── */
.body {
  flex: 1 1 auto;
  overflow-y: auto;
  padding: 16px;
  background: var(--surface);
}

/* ── IDLE 안내 ── */
.idle {
  height: 100%;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  text-align: center; color: var(--muted); gap: 10px;
  padding: 24px;
}
.idle .emoji { font-size: 30px; }

/* ── 학습 종료(ended) ── */
.ended .ended-title { font-weight: 700; font-size: 16px; color: var(--fg); }
.ended .summary {
  font-size: 13px; color: var(--accent); font-weight: 600;
  background: var(--accent-weak); padding: 6px 12px; border-radius: 999px;
}
.ended .ended-note { font-size: 13px; color: var(--muted); }

/* ── 개념 태그 / 레벨 배지 ── */
.tags {
  display: flex; align-items: center; justify-content: center;
  gap: 6px; margin-bottom: 12px; flex-wrap: wrap;
}
.chip {
  font-size: 11px; font-weight: 600; padding: 3px 9px;
  border: 1px solid var(--line); border-radius: 20px;
  background: var(--bg); color: var(--chip); text-align: center;
}
.chip.level { border: none; background: var(--surface); color: var(--accent-soft); }

/* ── 질문 ── */
.question {
  font-size: 15px; font-weight: 600; margin: 0 0 14px;
  line-height: 1.5;
  text-align: center;
  text-wrap: balance; /* 줄 길이를 고르게 — 마지막 줄에 몇 글자만 남는 것 방지 */
}

/* 선행 개념 레벨 배지 — 질문 아래 가운데 (재질문일 때만 렌더) */
.level-row { text-align: center; margin: 0 0 14px; }

/* ── 보기 ── */
.options { display: flex; flex-direction: column; gap: 8px; }
.option {
  display: flex; align-items: flex-start; gap: 10px;
  width: 100%; text-align: left;
  padding: 11px 12px;
  border: 1px solid var(--line); border-radius: 10px;
  background: var(--bg); color: var(--fg);
  font: inherit; cursor: pointer;
  transition: border-color .12s, background .12s;
}
.option:hover:not(:disabled) { border-color: var(--accent); background: var(--accent-weak); }
.option:disabled { cursor: default; }
.option .key {
  flex: 0 0 auto;
  width: 20px; height: 20px; border-radius: 6px;
  display: inline-flex; align-items: center; justify-content: center;
  font-size: 11px; font-weight: 700;
  background: #f3f4f6; color: var(--muted);
}
.option.selected { border-color: var(--accent); background: var(--accent-weak); }
.option.selected .key { background: var(--accent); color: #fff; }

/* 채점 후 표시 */
.option.correct { border-color: var(--ok); background: var(--ok-weak); }
.option.correct .key { background: var(--ok); color: #fff; }
.option.wrong { border-color: var(--bad); background: var(--bad-weak); }
.option.wrong .key { background: var(--bad); color: #fff; }
.option .mark { margin-left: auto; font-size: 13px; }

/* ── 제출 버튼 ── */
.submit {
  margin-top: 16px; width: 100%;
  padding: 11px 14px; border: none; border-radius: 10px;
  background: var(--accent); color: #fff;
  font: inherit; font-weight: 600; cursor: pointer;
}
.submit:disabled { background: var(--accent-disabled); cursor: not-allowed; }

/* ── 설명(오답 후) ── */
.explain {
  margin-top: 4px;
  border: 1px solid var(--bad-weak); border-radius: 10px;
  background: var(--bad-weak); padding: 13px 14px;
}
.explain .banner {
  display: flex; align-items: center; gap: 6px;
  font-weight: 700; color: var(--bad); margin-bottom: 6px; font-size: 13px;
}
.explain .text { color: var(--fg); font-size: 13.5px; }
.explain.explain-ok {
  border-color: var(--ok-weak);
  background: var(--ok-weak);
}
.explain.explain-ok .banner { color: var(--ok); }
.next-btn {
  margin-top: 14px; width: 100%;
  padding: 11px 14px; border: none; border-radius: 10px;
  background: var(--fg); color: #fff;
  font: inherit; font-weight: 600; cursor: pointer;
}
.next-btn.descend { background: var(--accent); }
.hint { margin-top: 8px; font-size: 12px; color: var(--muted); text-align: center; }
`

// ─── 시작 제안 카드 (StartPrompt) ────────────────────────────────────────────
// 패널과 별도의 shadow root 에 주입된다. 익스텐션 아이콘과 가까운 우측 상단에 뜬다.

export const PROMPT_CSS = /* css */ `
${FONT_IMPORTS}
:host { all: initial; }
* { box-sizing: border-box; }

.prompt {
  --fg: #1a1c1e;
  --muted: #6b7280;
  --accent: #E63B5C;
  --bad: #dc2626;
  --bad-weak: #fef2f2;

  position: fixed;
  right: 20px;
  top: 20px;
  z-index: 2147483000;

  width: 260px;
  padding: 16px 18px 18px;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  background: #fff;
  box-shadow: 0 10px 34px rgba(0, 0, 0, 0.16);

  font-family: ${FONT_BODY};
  color: var(--fg);
  animation: prompt-in 220ms ease-out;
}

@keyframes prompt-in {
  from { opacity: 0; transform: translateY(-8px); }
  to   { opacity: 1; transform: none; }
}

@media (prefers-reduced-motion: reduce) {
  .prompt { animation: none; }
}

.prompt-brand { display: flex; align-items: center; gap: 6px; }
.prompt-brand .wordmark {
  font-family: ${FONT_WORDMARK};
  font-weight: 700;
  font-size: 13px;
  color: var(--accent);
}

.prompt-desc {
  margin: 6px 0 0;
  font-size: 13.5px;
  line-height: 1.5;
  color: var(--fg);
}

.prompt-error {
  margin-top: 10px;
  padding: 8px 10px;
  border-radius: 8px;
  background: var(--bad-weak);
  color: var(--bad);
  font-size: 12px;
  line-height: 1.45;
}

.prompt-cta {
  margin-top: 14px;
  width: 100%;
  padding: 10px 14px;
  border: none;
  border-radius: 10px;
  background: var(--accent);
  color: #fff;
  font: inherit;
  font-size: 13.5px;
  font-weight: 600;
  cursor: pointer;
}
.prompt-cta:disabled { background: #E6D6DA; cursor: not-allowed; }

.prompt-close {
  position: absolute;
  top: 8px;
  right: 8px;
  width: 26px;
  height: 26px;
  border: none;
  border-radius: 8px;
  background: none;
  color: var(--muted);
  font-size: 18px;
  line-height: 1;
  cursor: pointer;
}
.prompt-close:hover { background: #f3f4f6; }
`
