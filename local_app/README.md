# 프로버 로컬 앱 (Flutter · Windows 데스크톱)

`기능명세서_Prober.md` §5 / `구현계획_3_로컬앱_서버기능.md` §3 구현체.

3개 컴포넌트(크롬 익스텐션 · 로컬 앱 · FastAPI 서버) 중 **로컬 앱**이다.
서버는 계정·인증만 갖고, **학습 데이터(지식그래프·학습이력·기사 선호 패턴)의
원본은 전부 로컬이 보유**한다(명세 §2, §4.5). 그래서 이 앱은 단순 뷰어가 아니라
SQLite 원본 저장소 + 그래프 시각화 + 서버 동기화 클라이언트다.

---

## 개발 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.44.7 stable (Dart 3.12.2) |
| 대상 | Windows 데스크톱 |
| 빌드 툴체인 | Visual Studio 2022 + **C++ ATL (v143, x86/x64)** |

> **ATL 구성 요소는 필수다.** `flutter_secure_storage`의 Windows 구현이
> `atlstr.h`를 포함하므로, 없으면 `flutter build windows`가 C1083으로 실패한다.
> Visual Studio Installer → Build Tools 2022 `수정` → `개별 구성 요소` →
> "최신 v143 빌드 도구용 C++ ATL"을 체크한다.

## 기술 스택

| 항목 | 선택 | 근거 |
|---|---|---|
| 상태관리 | `flutter_riverpod` | DI + `AsyncValue`로 동기화 로딩/에러 표현 |
| 로컬 DB | `drift` (SQLite) | 명세 §3.1 |
| 그래프 시각화 | `graphview` (Sugiyama 계층 레이아웃) | 선행→후행 방향을 층으로 표현 |
| HTTP | `dio` | 명세 §1 |
| 토큰 보관 | `flutter_secure_storage` | 명세 §3.5 |

DTO는 서버와의 계약 문서를 겸하므로 `fromJson`/`toJson`을 직접 작성했다.
코드 생성은 drift 스키마 하나로 제한된다.

---

## 실행

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift 스키마 생성
flutter run -d windows                                      # Mock 모드(기본)
```

서버가 준비되면:

```bash
flutter run -d windows --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8000
```

검증:

```bash
flutter analyze
flutter test
```

### Mock 모드

`lib/core/config.dart`의 `useMock`이 기본 `true`다. `MockApiClient`가
`/thoughtmap/update`의 서버 병합 규칙(같은 id는 갱신·출처 기사 누적, 없으면 추가)을
그대로 흉내내고, **동기화할 때마다 "웨이브"를 하나씩 소비**한다. 서버가 반영 후
`TempScrap`을 삭제하는 동작(명세 §4.3)과 같아서, "내 이력 가져오기"를 누를수록
그래프가 자라는 모습을 서버 없이 시연할 수 있다. 웨이브 3개를 다 쓰면 "반영할 새
진단 기록이 없습니다"로 떨어진다.

로그인은 아무 이메일 + 8자 이상 비밀번호면 통과한다.

---

## 구조

```
lib/
├─ core/            config(Mock 스위치·baseUrl), app_exception(서버 에러 포맷 매핑)
├─ data/
│  ├─ dto/          서버와의 계약 — graph, recommendation, user_context, auth
│  ├─ db/           drift 스키마(tables) + 그래프 반영·컨텍스트 조립(database)
│  ├─ api/          ApiClient 인터페이스 / Dio 구현 / Mock 구현 / 토큰 보관
│  └─ repository/   auth, thoughtmap(동기화 오케스트레이션)
├─ providers/       riverpod — 인프라·인증·그래프 스트림·동기화 컨트롤러
└─ ui/              login, home, graph_view, node_detail_panel, recommendation_panel
```

## 서버 계약 (담당3와 확정 필요)

로컬 앱이 쓰는 엔드포인트는 **셋뿐**이다. 퀴즈 생성·채점에는 관여하지 않는다(명세 §5.4).

| 메서드 | 경로 | 요청 | 응답 |
|---|---|---|---|
| POST | `/auth/signup` | `{email,password}` | `{userId}` |
| POST | `/auth/login` | `{email,password,client:"local"}` | `{accessToken,expiresIn,userId}` |
| GET | `/auth/me` | Bearer | `{userId,email,displayName}` |
| POST | `/thoughtmap/update` | `{graph,userContext}` | `{graph,recommendations}` |

```jsonc
// graph
{
  "nodes": [{
    "id": "c_실질금리",
    "concept": "실질금리",
    "state": "understood" | "not_understood" | "unknown",
    "isPrereq": true,
    "sourceArticles": [{ "url": "https://...", "title": "기사 제목" }],  // URL이 식별자, 크로스기사 병합 시 누적
    "summaryMeta": "미이해 개념 재요약(명세 §4.4 개인화 요약 흡수분)",
    "promoted": true                          // 그래프 노출 여부(확장 후보 예약 필드)
  }],
  "edges": [{ "from": "c_물가상승률", "to": "c_실질금리", "type": "prereq" | "related" }]
}

// userContext — 서버는 보관하지 않고 참조만 한다(명세 §4.5)
{
  "learningHistory":    [{ "conceptTag", "parentConcept", "level", "correct", "articleTitle", "occurredAt" }],
  "articlePreferences": [{ "keyword", "category", "weight" }]
}

// recommendations — 결핍 / 확장 / 기사 세 갈래(명세 §4.4)
{
  "gapConcepts":       [{ "conceptId", "conceptTag", "reason" }],          // reason 은 자연어
  "expansionConcepts": [{ "conceptId", "conceptTag", "reason" }],          // reason 은 "retry" | "sibling"
  "articles":          [{ "title", "url", "publisher", "reason" }]
}
```

에러는 공통 포맷 `{"error":{"code":"...","message":"..."}}`을 기대한다(구현계획② §4).
`state`는 enum이 아니라 문자열로 보존하므로, 서버가 새 값을 도입해도 렌더가 깨지지 않는다.

## 동작 규칙

- **동기화 트리거는 딱 둘.** 앱 실행 후 최초 1회 자동 + "내 이력 가져오기" 수동.
  실시간 폴링은 하지 않는다(명세 §5.2).
- **병합 정책:** 서버가 기존 graph를 입력받아 갱신하므로 응답본이 최신이다.
  로컬은 트랜잭션 안에서 전량 교체한다. 충돌 해소는 서버 책임.
- **인증:** 익스텐션과 토큰을 공유하지 않는 독립 로그인. 동일 계정이면 서버가
  `sub`로 같은 사용자로 묶는다(명세 §4.1). 401이면 토큰을 버리고 로그인 화면으로.
- 크로스기사 연결은 그래프에 내재하므로 별도 탐색 화면이 없다. 노드 상세의
  "출처 기사 N건"으로 드러난다(명세 §5.1).
