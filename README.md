# Prober

> 기사를 읽는 동안 **"내가 무엇을 모르는지"** 를 능동적으로 진단하고, 그 결과를 **생각 지도**(지식그래프)로 쌓아 학습 길잡이를 주는 서비스.

Prober는 경제 기사를 읽는 흐름을 끊지 않으면서 문단마다 질문을 던진다. 틀리면 그 자리에서 설명하고 한 단계 더 얕은 **선행 개념**으로 좁혀 물어, "무엇을 모르는지"를 정확히 짚는다. 진단 결과는 개인의 **지식그래프**에 누적되고, 이 그래프가 곧 다음에 무엇을 읽고 배울지의 길잡이가 된다.

핵심 산출물은 지식그래프 하나다. 개인화 요약·추천은 별도 기능이 아니라 이 그래프에서 흘러나온다.

---

## 구성

Prober는 세 컴포넌트로 이루어진 모노레포다. **익스텐션과 로컬 앱은 서로 직접 통신하지 않고**, 모든 상호작용은 서버를 경유한다.

| 컴포넌트 | 기술 | 역할 |
|---|---|---|
| [`extension/`](extension/) | Chrome MV3 · Vite + React + TypeScript | 기사 본문 인식, 진단 퀴즈 표시·채점, 진단 결과(스크랩) 전송 |
| [`local_app/`](local_app/) | Flutter (Windows) · Riverpod + drift | 생각 지도 **원본**(로컬 SQLite) 보유·시각화, 서버 동기화, 추천 열람 |
| [`server/`](server/) | FastAPI · PostgreSQL(pgvector) · Claude | 퀴즈 생성(LLM), 그래프 병합·추천 연산, 계정·인증, 스크랩 임시 버퍼 |

**저장 주체가 다르다.** 서버 DB는 계정·인증만 소유하고, 사용자의 학습 데이터(그래프·학습이력·기사 선호)는 **전부 로컬 앱이 원본**을 갖는다. 서버의 스크랩 버퍼는 동기화로 그래프에 반영되면 삭제되는 임시 데이터다.

### 데이터 흐름

```mermaid
flowchart LR
    subgraph browser["크롬 브라우저"]
      EXT["익스텐션<br/>(진단 퀴즈)"]
    end
    subgraph desktop["데스크톱"]
      APP["로컬 앱<br/>(생각 지도 · 원본)"]
    end
    SRV["FastAPI 서버<br/>(퀴즈 · 그래프 연산 · 인증)"]

    EXT -- "① 기사 원문 → 퀴즈 트리" --> SRV
    EXT -- "② 진단 결과(스크랩)" --> SRV
    APP -- "③ 현재 그래프 + 컨텍스트" --> SRV
    SRV -- "④ 갱신된 그래프 + 추천" --> APP
```

**흐름 A — 읽기 중 진단 (익스텐션 ↔ 서버):** 익스텐션이 기사 제목·원문을 보내면 서버가 핵심 주장 2~4개를 뽑아 문단에 태깅하고, 오답 시 선행개념 재질문(최대 2단계)까지 포함한 퀴즈 트리를 통째로 만들어 돌려준다. 문단에 들어설 때 질문이 뜨고, 채점 결과(기사 URL·제목 + 개념 태그 + 정답/오답, **원문 재전송 없음**)가 서버 버퍼에 쌓인다.

**흐름 B — 생각 지도 업데이트 (로컬 ↔ 서버):** 앱 실행 시 1회 자동 + "내 이력 가져오기" 수동(폴링 없음). 로컬이 현재 그래프와 사용자 컨텍스트를 보내면, 서버가 버퍼의 스크랩과 종합해 그래프를 갱신하고 추천을 만들어 돌려준다. 반영이 끝나면 소비된 스크랩을 서버에서 지운다.

---

## 빠른 시작

서버 → 로컬 앱 → 익스텐션 순으로 띄운다.

### 1. 서버 (FastAPI)

Python 3.12 기준. 기본은 **mock LLM** 모드라 API 키 없이도 전 파이프라인이 결정론적으로 동작한다.

```bash
cd server
python -m venv .venv && . .venv/Scripts/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                                   # 값 채우기 (아래 '환경 변수' 참고)
alembic upgrade head                                   # 스키마 생성
python scripts/seed.py                                 # (선택) 시드 데이터
uvicorn app.main:app --reload                          # http://127.0.0.1:8000/docs
```

### 2. 로컬 앱 (Flutter · Windows)

Flutter 3.44.7 / Dart 3.12.2, Visual Studio 2022(C++ 데스크톱 워크로드) 필요.

```bash
cd local_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift 코드 생성
# 실서버 연동 실행:
flutter run -d windows --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

`--dart-define` 없이 실행하면 `USE_MOCK=true`로 서버 없이 목 데이터로 뜬다. 검증: `flutter analyze && flutter test`.

### 3. 익스텐션 (Chrome MV3)

```bash
cd extension
npm ci
VITE_API_BASE_URL=http://127.0.0.1:8000 npm run build   # → extension/dist/
```

`chrome://extensions` → 개발자 모드 → **압축해제된 확장 프로그램을 로드** → `extension/dist/` 선택. 같은 계정으로 로그인하면 로컬 앱과 이력이 이어진다.

---

## API 개요

| 메서드 · 경로 | 채널 | 역할 |
|---|---|---|
| `POST /auth/signup` · `/auth/login` | 공통 | 계정 생성 · 로그인(토큰 발급) |
| `GET /auth/me` · `DELETE /auth/me` | 공통 | 현재 사용자 조회 · 탈퇴 |
| `POST /quiz` · `/quiz/stream` | 익스텐션 | 기사 원문 → 재질문 트리 포함 퀴즈 생성(저장 안 함) |
| `POST /scrap` | 익스텐션 | 세션 진단 결과를 계정 단위로 버퍼링 |
| `POST /thoughtmap/update` | 로컬 앱 | `{graph, userContext}` → 갱신 그래프 + 추천 |
| `POST /thoughtmap/ack` | 로컬 앱 | 반영 완료 스크랩을 버퍼에서 삭제 |
| `POST /explore` | 로컬 앱 | 키워드 2~3개 → 묶음 설명 + 관련 기사 |
| `GET /download` · `/download/win` | 웹 | 설치 랜딩 페이지 · 최신 설치기로 리다이렉트 |
| `GET /health` | — | 헬스체크 |

전체 요청/응답 스키마와 LLM 호출 정책은 [`server/README.md`](server/README.md)를 참고.

---

## 환경 변수 (`server/.env`)

`server/.env.example` 참고. `.env`는 **ASCII 전용**으로 둔다(Windows cp949에서 설정 로딩 크래시 방지).

| 키 | 기본/비고 |
|---|---|
| `DATABASE_URL` | PostgreSQL(asyncpg). 로컬 스모크는 sqlite 지원 |
| `JWT_SECRET` · `JWT_ALGORITHM` · `ACCESS_TOKEN_EXPIRE_MINUTES` | 인증 토큰 (HS256, 1440분) |
| `LLM_PROVIDER` | `mock`(기본, 키 불필요) 또는 `claude` |
| `ANTHROPIC_API_KEY` · `ANTHROPIC_MODEL` | `claude` 모드일 때. 모델 `claude-opus-4-8` |
| `SCRAP_BUFFER_TTL_DAYS` · `SCRAP_BUFFER_MAX_ROWS` | 스크랩 버퍼 한도 (7일 / 200행) |
| `NAVER_CLIENT_ID` · `NAVER_CLIENT_SECRET` | (선택) 네이버 뉴스 검색. 없으면 제휴 데이터셋만 사용 |

---

## 저장소 구조

```
2026CodeGate-hackerthon/
├─ extension/      크롬 익스텐션 (Vite + React, MV3)
├─ local_app/      Flutter Windows 앱 (생각 지도 원본·시각화)
├─ server/         FastAPI 백엔드 (퀴즈·그래프·인증)
├─ deploy/         Windows 설치기 빌드 (build.ps1 + Inno Setup, 앱+익스텐션)
└─ render.yaml     서버 배포 Blueprint (Render: FastAPI 앱 + PostgreSQL)
```

각 디렉터리의 README에 상세 설명이 있다: [익스텐션](extension/) · [로컬 앱](local_app/README.md) · [서버](server/README.md) · [배포](deploy/README.md).

---

## 배포

- **서버 + DB:** Render 한 곳에 FastAPI 앱과 PostgreSQL(pgvector)을 함께 올린다(`render.yaml` Blueprint, `DATABASE_URL` 자동 연결). [`server/DEPLOY.md`](server/DEPLOY.md). *DB를 Supabase·Neon 등으로 바꿔도 코드 변경은 없다.*
- **설치기(앱 + 익스텐션):** `deploy/build.ps1`이 서버 URL을 주입해 Flutter 앱과 크롬 익스텐션을 함께 빌드하고, Inno Setup으로 **둘을 담은 단일 설치기**(`ProberSetup-<버전>.exe`)를 만든다. 설치 마지막에 크롬 확장 등록을 안내한다(가이드형 압축해제 로드). [`deploy/README.md`](deploy/README.md).
- **다운로드:** 배포된 서버가 `GET /download` 로 설치 랜딩 페이지를 제공하고, `/download/win` 이 GitHub Releases 의 최신 설치기(`ProberSetup-<버전>.exe`)로 리다이렉트한다. 사용자에게는 `<서버>/download` 링크만 안내하면 된다.
