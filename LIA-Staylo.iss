; ================================
; Inno Setup script for LIA-Staylo
; ================================

#define MyAppName      "LIA-Staylo"
#define MyAppVersion   "1.0.0"
#define MyAppPublisher "La Saga de Ángelo"
#define SrcDist        "D:\LIA-Staylo_dist\LIA-Staylo"

; Si incluiste el redistribuible VC++ en Prereqs, descomenta:
; #define VcRedist "{#SrcDist}\Prereqs\vc_redist.x64.exe"

[Setup]
AppId={{0E7E6A3E-7C7C-4727-9E4A-9A0F8F6A1B11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={pf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableDirPage=no
OutputDir={#SrcDist}\Output
OutputBaseFilename=LIA-Staylo-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\app\LIA-Staylo.exe
ChangesEnvironment=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; App (Flutter)
Source: "{#SrcDist}\app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion

; Reglas: cópialas DENTRO del dist junto al exe congelado (y opcionalmente también en backend\rules)
Source: "{#SrcDist}\backend\rules\*"; DestDir: "{app}\backend\dist\lia-backend\rules"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#SrcDist}\backend\rules\*"; DestDir: "{app}\backend\rules"; Flags: recursesubdirs createallsubdirs ignoreversion

; LanguageTool completo
Source: "{#SrcDist}\LanguageTool\*"; DestDir: "{app}\LanguageTool"; Flags: recursesubdirs createallsubdirs ignoreversion

; Scripts
Source: "{#SrcDist}\scripts\run_stack.ps1";  DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#SrcDist}\scripts\stop_stack.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#SrcDist}\scripts\start_lt.ps1";  DestDir: "{app}\scripts"; Flags: ignoreversion

#ifdef VcRedist
Source: {#VcRedist}; DestDir: "{app}\Prereqs"; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\{#MyAppName}";               Filename: "{app}\app\LIA-Staylo.exe"; WorkingDir: "{app}\app"
Name: "{autodesktop}\{#MyAppName}";         Filename: "{app}\app\LIA-Staylo.exe"; Tasks: desktopicon
Name: "{group}\Iniciar servicios (oculto)"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File ""{app}\scripts\run_stack.ps1"""; WorkingDir: "{app}"
Name: "{group}\Detener servicios";          Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\scripts\stop_stack.ps1"""; WorkingDir: "{app}"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: unchecked

[Run]
#ifdef VcRedist
Filename: "{app}\Prereqs\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Flags: runhidden waituntilterminated; StatusMsg: "Instalando componentes de Microsoft..."
#endif
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File ""{app}\scripts\run_stack.ps1"""; WorkingDir: "{app}"; Flags: postinstall nowait shellexec skipifsilent; Description: "Iniciar servicios (recomendado)"

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\scripts\stop_stack.ps1"""; Flags: runhidden
