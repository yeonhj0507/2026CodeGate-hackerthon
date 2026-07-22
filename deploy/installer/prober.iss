; ============================================================================
; Prober 설치 프로그램 (Inno Setup 6) — 데스크톱 앱 + Chrome 익스텐션(가이드형 등록)
;
; deploy/build.ps1 이 아래 심볼을 /D 로 주입해 컴파일한다:
;   AppVersion  : 표시 버전 (예: 0.1.0+1309f13)
;   ReleaseDir  : Flutter 릴리스 산출 폴더 (prober_local.exe 포함)
;   ExtDir      : 익스텐션 빌드 산출 폴더 (extension/dist, manifest.json 포함)
;   OutputDir   : 설치기 .exe 를 떨굴 폴더 (deploy/dist)
;
; 익스텐션은 {app}\extension 에 풀리고, 설치 마지막에 "크롬 등록 가이드"가 뜬다
; (chrome://extensions → 개발자 모드 → 압축해제된 확장 로드 → {app}\extension).
; 직접 열지 말고 build.ps1 을 통해 빌드할 것(심볼 미정의 시 컴파일 실패).
; ============================================================================

#ifndef AppVersion
  #error "build.ps1 을 통해 컴파일하세요 (AppVersion 미정의)."
#endif
#ifndef ExtDir
  #error "ExtDir 미정의 — build.ps1 로 컴파일하세요."
#endif

#define AppName "Prober"
#define AppExe "prober_local.exe"
#define AppPublisher "Prober Team"

[Setup]
AppId={{402CCB6A-9F7D-43C9-AA9A-372361F6EBB1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=ProberSetup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Program Files 쓰기에 관리자 권한을 쓴다(사용자 폴더 설치를 원하면 lowest 로).
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#SourcePath}..\..\local_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Flutter 앱 일체 (exe + dll + data)
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
; Chrome 익스텐션(압축해제 로드용 원본). {app}\extension 을 사용자가 "로드"한다.
Source: "{#ExtDir}\*"; DestDir: "{app}\extension"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; 완료 화면 체크박스(모두 기본 체크). 확장 등록을 돕는 두 가지를 열어 준다.
Filename: "{code:GetChromePath}"; Parameters: "chrome://extensions"; \
  Description: "Chrome 확장 페이지 열기 (chrome://extensions)"; \
  Flags: nowait postinstall skipifsilent shellexec; Check: ChromeInstalled
Filename: "{win}\explorer.exe"; Parameters: """{app}\extension"""; \
  Description: "등록할 확장 폴더 열기"; \
  Flags: nowait postinstall skipifsilent
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\extension"

; ============================================================================
[Code]
function GetChromePath(Param: string): string;
begin
  Result := ExpandConstant('{pf}\Google\Chrome\Application\chrome.exe');
  if not FileExists(Result) then
    Result := ExpandConstant('{pf32}\Google\Chrome\Application\chrome.exe');
end;

function ChromeInstalled(): Boolean;
begin
  Result := FileExists(GetChromePath(''));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    MsgBox(
      '데스크톱 앱 설치가 끝났습니다.' + #13#10 +
      '이제 Chrome 확장만 등록하면 모든 설치가 완료됩니다.' + #13#10#13#10 +
      '1. chrome://extensions 를 엽니다  (다음 화면의 체크로 자동으로 열려요)' + #13#10 +
      '2. 오른쪽 위 "개발자 모드" 를 켭니다' + #13#10 +
      '3. "압축해제된 확장 프로그램 로드" 를 클릭합니다' + #13#10 +
      '4. 이 폴더를 선택합니다:' + #13#10 +
      '      ' + ExpandConstant('{app}\extension') + #13#10#13#10 +
      '등록되면 브라우저 오른쪽 위에 프로버(Prober) 아이콘이 나타나고,' + #13#10 +
      '기사를 열면 확장이 동작합니다.',
      mbInformation, MB_OK);
end;
