# Prober 확장 — Stream B QA & 핸드오프 (T=5 / Step 10)

> **작성: Stream B (Logic + UI).** 세션 상태머신(`session.ts`)·제출 큐(`session-bind.ts`)·in-page UI(`ui/**`)의 QA 결과와, 후속 개발자가 알아야 할 것을 모아둔 핸드오프 문서.
> 관련: [stream_b_align.md](./stream_b_align.md)(B 설계·결정) · [stream_a_qa.md](./stream_a_qa.md)(앵커 QA·통합 브라우저 체크리스트) · [stream_c_align.md](./stream_c_align.md)
> 최종 업데이트: 2026-07-21

---

## 0. B 영역 완성도

| 영역 | 상태 | 검증 |
|------|------|------|
| 진단 루프 상태머신 (`session.ts`) | ✅ 완성 | 자동 QA(§1) + T=3 certify 21/21 |
| 제출 큐 (`session-bind.ts`, `createSessionQueue`) | ✅ 완성 | 자동 QA(§1) + T=2 9/9 |
| in-page UI (`ui/{Panel,QuestionView,Explanation}` + ended 상태) | ✅ 완성 | dev 하니스 브라우저 실측(§2) |
| Shadow DOM 마운트·격리 (`ui/mount.tsx`, `ui/theme.ts`) | ✅ | 브라우저 실측 |
| A 오케스트레이터와의 배선(`mountPanel`/`createSessionQueue`/`useSession`) | ✅ 시그니처 일치 | 통합 `tsc`+`vite build` 통과 |

**결론: B 몫의 QA는 완료.** 로직은 헤드리스 자동 QA로 재현 검증, UI는 브라우저 실측 완료. 남은 것은 **실제 언팩 확장 통합 e2e**(A/B/C 합동, 사람 확인) 뿐이며 이는 B 전용이 아니라 `stream_a_qa.md §4` 공통 체크리스트가 흡수한다.

---

## 1. 자동 QA — `npm run qa:session` (22/22 통과)

```bash
cd extension
npm run qa:session      # rolldown으로 session.ts + session-bind.ts 번들 → node 실행
```

하니스: `extension/qa/session-qa.ts` (실제 `useSession`·`createSessionQueue` import, DOM/observer/UI 불필요한 순수 로직).

검증 범위(22 assertion):

| 그룹 | 확인 내용 |
|------|-----------|
| 진단 루프 | main 오답 → 설명 → **L1 강등 → L2 강등 → IDLE** 전이 |
| 엣지 복원 | `parentConcept` 체인 `null→기준금리→통화정책`, `conceptTag` echo, `level` 0/1/2 |
| 정답 경로 | main 정답 시 재질문 스킵하고 즉시 IDLE |
| flush | `flushResults()` 누적 반환 + 버퍼 비움 + **멱등**(재호출 빈배열) |
| 가드 | IDLE에서 submit/dismiss 무시, ASKING 중 startQuestion 무시 |
| 제출 큐 | 풀이 중 enqueue **유실 없이 순차 제시**, 한 번에 다중 Quiz, `dispose` 후 자동 pump 중단 |

> 회귀 게이트: A(오케스트레이터)·C(`/scrap`)가 트리를 바꾼 뒤에도 위 QA + 전체 `tsc --noEmit` 통과 재확인함(T=5).

---

## 2. UI 브라우저 실측 (dev 하니스)

`demo/`(gitignore 산출물, 실제 확장 빌드 미포함) + `npm run`(vite.demo.config.ts)로 Shadow DOM 패널을 실제 렌더해 확인:

- IDLE 안내 → ASKING(개념 chip·4지선다·제출) → **오답 채점(정답 초록✓/오답 빨강✕)** → "선행 개념 짚어보기" 강등 → 재질문 1단계(보기 초기화) → 정답 시 진행률 갱신·IDLE 복귀
- **"학습 종료" → ended 상태**("🎉 학습을 마쳤어요 · 맞힘 X/푼 문항 Y · 진단 결과를 저장했어요", 종료 버튼·진행률 숨김). 요약은 flush 전 스냅샷이라 0 표시 안 됨.
- Shadow DOM CSS 격리·페이지 오른쪽 여백 밀기 확인.

---

## 3. B 관련 통합 브라우저 체크리스트 (사람 확인 — `stream_a_qa.md §4`에 위치)

실제 언팩 확장 + 실제 기사 + IntersectionObserver·스크롤이 필요한 아래 항목은 `stream_a_qa.md §4` 공통 체크리스트에서 확인. **모두 B 표면이 이미 커버됨**(별도 B 체크리스트 불필요):

- **진단 루프**: 정답 초록 / 오답 빨강+설명 → 재질문 1·2단계 → IDLE
- **큐(유실 방지)**: 한 문단 풀이 중 스크롤로 다른 문단 진입 → 현재 문항 끝난 뒤 **순차 제시**
- **종료(onEnd 회귀)**: "학습 종료" 후 **새 문항 안 뜸** + ended 상태 표시
- **스크랩 payload**: `results[].parentConcept` 채워짐 (B `flushResults` 출력)

> 이 항목들의 자동화 불가 이유 = 실제 IntersectionObserver 진입 타이밍(`rootMargin`, A 튜닝 대상)·실제 스크롤·Shadow DOM 렌더. 로직 자체는 §1에서 이미 green.

---

## 4. 알려진 한계 (B 범위, MVP 밖)

- **큐 상한/만료 없음**: 안 풀고 계속 스크롤하면 대기 퀴즈가 쌓임(무제한 FIFO). 필요 시 `session-bind.ts`에 상한·"지나간 문단 만료" 추가. (Step 10 관찰)
- **하단 강등 전용 UI 없음**: `unanchored`는 오케스트레이터가 큐에 append → 기존 단일 패널로 순차 노출(A 확정). 별도 하단 목록 UI는 post-MVP.
- **correct 피드백은 토스트 1.4s**: 정답 시 별도 phase 없이 IDLE 복귀 + 토스트. 상태머신 계약(`phase: IDLE|ASKING|SHOW_EXPLANATION`)을 지키기 위한 선택.
- **flush 후 전송 실패 창(inherent)**: `flushResults`가 store를 먼저 비운 뒤 A가 전송 → sendMessage 자체가 실패(확장 컨텍스트 무효화 등)하면 그 배치 유실. content→background 핸드오프는 즉시라 창이 매우 좁음. 내구성은 C 재시도 큐가 담당(§stream_b_align T4).

---

## 5. 한 장 요약

- **B QA 완료.** 로직 자동 QA `npm run qa:session` **22/22**, UI 브라우저 실측 완료, 통합 `tsc`/`build` green.
- **재현**: `npm run qa:session` (A의 `qa:anchor`, C의 `qa:scrap`와 동일 패턴).
- **남은 통합 e2e**(실 확장 로드·실 스크롤)는 B 전용 아님 → `stream_a_qa.md §4` 공통 체크리스트에서 확인, B 표면 전부 포함됨.
- **B 공개 API**(후속 참고): `useSession`(store·`flushResults`), `createSessionQueue()`, `mountPanel({onEnd})` — `stream_b_align.md §1`.
