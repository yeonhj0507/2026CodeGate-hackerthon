# Prober 배포 자동화 (데스크톱 앱 + Chrome 익스텐션 설치기)

최신 커밋에서 **Flutter 데스크톱 앱 + Chrome 익스텐션**을 빌드해, 사용자가 한 번 실행하면
앱이 설치되고 익스텐션 등록까지 안내하는 **단일 Windows 설치 프로그램(`ProberSetup-*.exe`)** 을 만든다.

> **서버 + DB(PostgreSQL)**는 Render 에 배포한다 → [`../server/DEPLOY.md`](../server/DEPLOY.md).
> 클라이언트(앱·익스텐션)가 바라볼 서버 주소는 빌드 시 `-ApiBaseUrl` 로 주입한다.

## 사전 요구사항

| 도구 | 용도 | 비고 |
|---|---|---|
| **PowerShell 7+** (`pwsh`) | 빌드 스크립트 | Windows PowerShell 5.1 로는 실행 불가 |
| **Flutter** (Windows desktop) | 앱 빌드 | `flutter` PATH 등록 |
| **Node.js / npm** | 익스텐션 빌드 | `-SkipExtension` 시 불필요 |
| **Inno Setup 6** | 설치기 컴파일 | https://jrsoftware.org/isdl.php , `ISCC.exe` |
| **GitHub CLI** (`gh`) | (선택) 릴리스 업로드 | `-PublishRelease` 시 필요 |

## 사용법

```powershell
# 개발용(localhost 서버)
pwsh ./build.ps1

# 배포용 — Render 서버 URL 주입 + GitHub Releases 업로드
pwsh ./build.ps1 -ApiBaseUrl https://prober-api.onrender.com -PublishRelease

# 부분 재생성 (Flutter/익스텐션 재빌드 생략)
pwsh ./build.ps1 -SkipFlutter -SkipExtension
```

산출물: `deploy/dist/ProberSetup-<버전>.exe` — 최종 설치 프로그램.

## 동작 원리

### 서버 URL 주입
- **앱**: `flutter build ... --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=<url>`
  (`local_app/lib/core/config.dart` 지원 — 코드 변경 없음).
- **익스텐션**: `VITE_API_BASE_URL=<url>` 로 빌드하고, 빌드된 `dist/manifest.json` 의
  `host_permissions` 에 서버 origin 을 추가(원격 서버로 fetch 허용).

### 설치기가 하는 일
1. Flutter 앱 일체를 `Program Files\Prober` 에 설치 + 바로가기 + 언인스톨러 등록.
2. 익스텐션을 `{app}\extension` 에 함께 푼다.
3. 설치 마지막에 **크롬 등록 가이드**를 띄우고, 완료 화면에서
   `chrome://extensions` 와 확장 폴더를 열어 준다.

### 익스텐션 등록 (가이드형 압축해제 로드)
웹스토어 미등록 확장이라, 사용자가 한 번 수동 등록한다(설치기가 안내):
1. `chrome://extensions` 열기 → **개발자 모드** ON
2. **압축해제된 확장 프로그램 로드** 클릭
3. `{app}\extension` (기본 `C:\Program Files\Prober\extension`) 선택

> 완전 무인 등록을 원하면 웹스토어(비공개) 게시가 유일한 깔끔한 길이다(개발자 계정·심사 필요).
> CRX + 레지스트리 강제설치는 최근 크롬이 웹스토어 밖 확장을 자주 차단해 이 파이프라인에선 쓰지 않는다.

## 알려진 제약

- **코드 서명 없음**: 설치기가 미서명이라 Windows SmartScreen("추가 정보 → 실행")
  경고가 뜰 수 있다. 정식 배포에는 코드 서명 인증서가 필요하다.
- **개발자 모드**: 압축해제 로드는 크롬 개발자 모드를 요구한다(위 참고).
- **관리자 권한**: 기본 `Program Files` 설치를 위해 관리자 권한으로 실행된다. 사용자 폴더
  설치를 원하면 `installer/prober.iss` 의 `PrivilegesRequired` 를 `lowest` 로 바꾼다.
