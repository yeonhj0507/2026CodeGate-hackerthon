; ============================================================================
; Prober 설치 프로그램 (Inno Setup 6) — 데스크톱 앱 전용
;
; deploy/build.ps1 이 아래 심볼을 /D 로 주입해 컴파일한다:
;   AppVersion  : 표시 버전 (예: 0.1.0+1309f13)
;   ReleaseDir  : Flutter 릴리스 산출 폴더 (prober_local.exe 포함)
;   OutputDir   : 설치기 .exe 를 떨굴 폴더 (deploy/dist)
;
; ⚠️ Chrome 익스텐션은 이 설치기에 포함하지 않는다(별도 배포).
; 직접 열지 말고 build.ps1 을 통해 빌드할 것(심볼 미정의 시 컴파일 실패).
; ============================================================================

#ifndef AppVersion
  #error "build.ps1 을 통해 컴파일하세요 (AppVersion 미정의)."
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
ArchitecturesInstallIn64BitMode=x64
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

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
