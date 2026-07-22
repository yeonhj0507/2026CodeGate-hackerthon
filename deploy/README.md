# Prober 배포 자동화 (데스크톱 앱 설치기)

최신 커밋에서 **Flutter 데스크톱 앱**을 빌드해, 사용자가 한 번 실행하면 설치되는
**단일 Windows 설치 프로그램(`ProberSetup-*.exe`)** 을 만든다.

> **Chrome 익스텐션은 이 설치기에 포함하지 않는다**(별도 배포). 설치기는 데스크톱 앱만 담는다.
>
> **서버 + DB(PostgreSQL)**는 Render 에 배포한다 → [`../server/DEPLOY.md`](../server/DEPLOY.md).
> 클라이언트가 바라볼 서버 주소는 빌드 시 `-ApiBaseUrl` 로 주입한다.

## 사전 요구사항

| 도구 | 용도 | 비고 |
|---|---|---|
| **PowerShell 7+** (`pwsh`) | 빌드 스크립트 | Windows PowerShell 5.1 로는 실행 불가 |
| **Flutter** (Windows desktop) | 앱 빌드 | `flutter` PATH 등록 |
| **Inno Setup 6** | 설치기 컴파일 | https://jrsoftware.org/isdl.php , `ISCC.exe` |

## 사용법

```powershell
# 개발용(localhost 서버)
pwsh ./build.ps1

# 배포용 — Render 서버 URL 주입
pwsh ./build.ps1 -ApiBaseUrl https://prober-api.onrender.com

# 설치기만 재생성 (Flutter 재빌드 생략)
pwsh ./build.ps1 -SkipFlutter
```

산출물: `deploy/dist/ProberSetup-<버전>.exe` — 최종 설치 프로그램.

## 동작 원리

### 서버 URL 주입
`flutter build ... --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=<url>`
(`local_app/lib/core/config.dart` 가 이미 지원 — 코드 변경 없음).

### 설치기가 하는 일
- Flutter 릴리스 산출물 일체(exe + dll + data)를 `Program Files\Prober` 에 설치.
- 시작 메뉴 + (선택) 바탕화면 바로가기 생성.
- 언인스톨러 등록.

## 알려진 제약

- **코드 서명 없음**: 설치기가 미서명이라 Windows SmartScreen("추가 정보 → 실행")
  경고가 뜰 수 있다. 정식 배포에는 코드 서명 인증서가 필요하다.
- **관리자 권한**: 기본 `Program Files` 설치를 위해 관리자 권한으로 실행된다. 사용자 폴더
  설치를 원하면 `installer/prober.iss` 의 `PrivilegesRequired` 를 `lowest` 로 바꾼다.

## 익스텐션은?
Chrome 익스텐션은 이 파이프라인에서 빠졌다. 별도로 빌드·배포한다:

```powershell
cd ../extension
$env:VITE_API_BASE_URL = "https://prober-api.onrender.com"
npm ci; npm run build      # → extension/dist/ 를 웹스토어 업로드 또는 수동 로드
```
