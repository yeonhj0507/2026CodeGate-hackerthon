#requires -Version 7.0
<#
.SYNOPSIS
  Prober 배포 자동화 — 최신 커밋에서 Flutter 데스크톱 앱 + Chrome 익스텐션을 빌드하고
  단일 Windows 설치 프로그램(.exe)으로 패키징한다.

.DESCRIPTION
  단계:
    1) 버전 스탬프 (pubspec version + git short hash)
    2) Flutter Windows 릴리스 빌드 (서버 URL을 dart-define 로 주입)
    3) 익스텐션 빌드 (서버 URL을 VITE_API_BASE_URL 로 주입 + manifest host_permissions 패치)
    4) Inno Setup 컴파일 → deploy/dist/ProberSetup-<ver>.exe
    5) (선택) GitHub Releases 업로드

  익스텐션은 설치기에 함께 담기고, 설치 마지막에 "크롬 등록 가이드"가 뜬다
  (chrome://extensions → 개발자 모드 → 압축해제된 확장 로드 → {app}\extension).

  서버(FastAPI)와 DB(PostgreSQL)는 Render 에 배포한다(server/DEPLOY.md 참고).
  클라이언트가 바라볼 서버 주소는 -ApiBaseUrl 로 주입한다. 기본값은 개발용 localhost.

  PowerShell 7+ 가 필요하다. `pwsh` 로 실행할 것.

.EXAMPLE
  pwsh ./build.ps1
  pwsh ./build.ps1 -ApiBaseUrl https://prober-api.onrender.com -PublishRelease
  pwsh ./build.ps1 -SkipFlutter -SkipExtension   # 설치기만 재생성
#>
[CmdletBinding()]
param(
    # 클라이언트(앱·익스텐션)가 바라볼 서버 베이스 URL. 원격 배포(Render) 시 교체.
    [string]$ApiBaseUrl = 'http://localhost:8000',

    # Flutter 빌드에서 Mock API 대신 실서버를 쓰게 한다(config.dart USE_MOCK).
    [ValidateSet('true', 'false')]
    [string]$UseMock = 'false',

    # 이미 빌드된 산출물을 재사용하고 싶을 때.
    [switch]$SkipFlutter,
    [switch]$SkipExtension,

    # 빌드한 설치기를 GitHub Releases(app-latest 태그)에 ProberSetup.exe 로 업로드.
    # /download 페이지가 이 애셋을 가리킨다. gh CLI 로그인 필요.
    [switch]$PublishRelease,

    # 릴리스 애셋을 올릴 태그(고정 롤링 태그). config.py 의 download_url 과 일치해야 함.
    [string]$ReleaseTag = 'app-latest'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── 경로 ─────────────────────────────────────────────────────────────────────
$Deploy      = $PSScriptRoot
$RepoRoot    = Split-Path $Deploy -Parent
$AppDir      = Join-Path $RepoRoot 'local_app'
$ExtDir      = Join-Path $RepoRoot 'extension'
$ExtBuildDir = Join-Path $ExtDir 'dist'
$DistDir     = Join-Path $Deploy 'dist'
$IssPath     = Join-Path $Deploy 'installer/prober.iss'
$ReleaseDir  = Join-Path $AppDir 'build/windows/x64/runner/Release'

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Fail($msg) { Write-Error $msg; exit 1 }

function Resolve-Tool([string]$name, [string[]]$candidates, [string]$hint) {
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    Fail "$name 를 찾지 못했습니다. $hint"
}

# ── 도구 탐지 ────────────────────────────────────────────────────────────────
Write-Step '도구 탐지'
$flutter = Resolve-Tool 'Flutter' @('flutter') 'https://docs.flutter.dev 에서 설치 후 PATH 에 추가하세요.'
$iscc    = Resolve-Tool 'Inno Setup (ISCC)' @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    # winget(JRSoftware.InnoSetup)은 사용자 단위로 여기에 설치한다.
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    'ISCC'
) 'https://jrsoftware.org/isdl.php 에서 Inno Setup 6 을 설치하세요.'
$npm = if ($SkipExtension) { $null } else {
    Resolve-Tool 'npm' @('npm') 'Node.js(https://nodejs.org) 를 설치하세요.'
}
Write-Host "flutter : $flutter"
Write-Host "iscc    : $iscc"
if ($npm) { Write-Host "npm     : $npm" }

# ── 1) 버전 스탬프 ───────────────────────────────────────────────────────────
Write-Step '버전 스탬프'
$pubspec = Get-Content (Join-Path $AppDir 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    Fail 'pubspec.yaml 에서 version 을 읽지 못했습니다.'
}
$AppVersion = $Matches[1]
$GitHash = (& git -C $RepoRoot rev-parse --short HEAD 2>$null)
if (-not $GitHash) { $GitHash = 'nogit' }
$FullVersion = "$AppVersion+$GitHash"
Write-Host "버전: $FullVersion  (서버: $ApiBaseUrl, USE_MOCK=$UseMock)"

# ── 2) Flutter 빌드 ─────────────────────────────────────────────────────────
if ($SkipFlutter) {
    Write-Step 'Flutter 빌드 건너뜀'
    if (-not (Test-Path (Join-Path $ReleaseDir 'prober_local.exe'))) {
        Fail "이전 빌드 산출물이 없습니다: $ReleaseDir\prober_local.exe"
    }
} else {
    Write-Step 'Flutter Windows 릴리스 빌드'
    Push-Location $AppDir
    try {
        & $flutter build windows --release `
            --dart-define=USE_MOCK=$UseMock `
            --dart-define=API_BASE_URL=$ApiBaseUrl
        if ($LASTEXITCODE -ne 0) { Fail 'flutter build 실패' }
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $ReleaseDir 'prober_local.exe'))) {
    Fail "빌드된 exe 를 찾지 못했습니다: $ReleaseDir\prober_local.exe"
}

# ── 3) 익스텐션 빌드 ─────────────────────────────────────────────────────────
if ($SkipExtension) {
    Write-Step '익스텐션 빌드 건너뜀'
    if (-not (Test-Path (Join-Path $ExtBuildDir 'manifest.json'))) {
        Fail "이전 익스텐션 빌드가 없습니다: $ExtBuildDir"
    }
} else {
    Write-Step '익스텐션 빌드'
    Push-Location $ExtDir
    try {
        if (-not (Test-Path (Join-Path $ExtDir 'node_modules'))) {
            & $npm ci
            if ($LASTEXITCODE -ne 0) { Fail 'npm ci 실패' }
        }
        $env:VITE_API_BASE_URL = $ApiBaseUrl
        & $npm run build
        if ($LASTEXITCODE -ne 0) { Fail 'npm run build 실패' }
    } finally {
        Remove-Item Env:\VITE_API_BASE_URL -ErrorAction SilentlyContinue
        Pop-Location
    }

    # 빌드된 dist/manifest.json 의 host_permissions 에 서버 origin 을 추가한다.
    # (localhost 기본값 외 원격 서버로 fetch 하려면 반드시 필요)
    $manifestPath = Join-Path $ExtBuildDir 'manifest.json'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $apiUri = [Uri]$ApiBaseUrl
    $apiOrigin = '{0}://{1}{2}/*' -f $apiUri.Scheme, $apiUri.Host, `
        ($(if ($apiUri.IsDefaultPort) { '' } else { ":$($apiUri.Port)" }))
    $hosts = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $manifest.host_permissions) { [void]$hosts.Add($h) }
    if (-not $hosts.Contains($apiOrigin)) { [void]$hosts.Add($apiOrigin) }
    $manifest.host_permissions = $hosts
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $manifestPath -Encoding utf8
    Write-Host "익스텐션 manifest 패치 (host_permissions += $apiOrigin)"
}
if (-not (Test-Path (Join-Path $ExtBuildDir 'manifest.json'))) {
    Fail "익스텐션 빌드 산출물을 찾지 못했습니다: $ExtBuildDir\manifest.json"
}

# ── 4) Inno Setup 컴파일 ─────────────────────────────────────────────────────
Write-Step 'Inno Setup 컴파일'
& $iscc `
    "/DAppVersion=$FullVersion" `
    "/DReleaseDir=$ReleaseDir" `
    "/DExtDir=$ExtBuildDir" `
    "/DOutputDir=$DistDir" `
    "$IssPath"
if ($LASTEXITCODE -ne 0) { Fail 'ISCC 컴파일 실패' }

$setup = Get-ChildItem $DistDir -Filter 'ProberSetup-*.exe' | Sort-Object LastWriteTime | Select-Object -Last 1

# ── 5) (선택) GitHub Releases 업로드 ─────────────────────────────────────────
if ($PublishRelease) {
    Write-Step "GitHub Releases 업로드 ($ReleaseTag)"
    $gh = Resolve-Tool 'GitHub CLI (gh)' @('gh') 'https://cli.github.com 에서 설치 후 gh auth login 하세요.'
    # /download/win 이 항상 같은 URL 을 가리키도록 애셋 파일명을 ProberSetup.exe 로 고정.
    # (gh 의 file#label 문법은 "표시 라벨"만 바꾸고 다운로드에 쓰이는 애셋 이름=파일명은
    #  그대로다. 따라서 실제 파일을 ProberSetup.exe 로 복사해서 올린다.)
    $stableExe = Join-Path $DistDir 'ProberSetup.exe'
    Copy-Item $setup.FullName $stableExe -Force
    $notes = "Prober 설치기 ($FullVersion). 서버: $ApiBaseUrl"
    & $gh release view $ReleaseTag *> $null
    if ($LASTEXITCODE -eq 0) {
        & $gh release upload $ReleaseTag $stableExe --clobber
    } else {
        & $gh release create $ReleaseTag $stableExe --title "Prober 설치기 (latest)" --notes $notes
    }
    if ($LASTEXITCODE -ne 0) { Fail 'gh release 업로드 실패' }
    Write-Host "업로드 완료 → 다운로드 페이지의 /download/win 이 이 애셋을 가리킵니다."
}

Write-Step '완료'
Write-Host "설치 프로그램: $($setup.FullName)" -ForegroundColor Green
Write-Host "서버 URL     : $ApiBaseUrl"
if ($PublishRelease) { Write-Host "다운로드 페이지: $ApiBaseUrl/download" }
