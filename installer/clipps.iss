; Inno Setup script for Clipps. Build: ISCC installer\clipps.iss
; Expects a fresh `flutter build windows` (Release) in build\windows\x64\runner\Release.

#define AppName "Clipps"
#define AppVersion "3.0.0"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6F7C2B1E-8C4A-4E59-9C1B-3D2A6E4F9A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Clipps
; Per-user install: no admin prompt, matches the per-user startup entry.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\clipps.exe
OutputDir=..\build\installer
OutputBaseFilename=Clipps-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Clipps keeps running in the tray; close it so files can be replaced.
CloseApplications=force
RestartApplications=no

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ runtime, app-local, for PCs without the redistributable.
Source: "{sys}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion external
Source: "{sys}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion external
Source: "{sys}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion external

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\clipps.exe"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\clipps.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Registry]
; The app rewrites this on every launch; declared here so uninstall removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Clipps"; ValueData: """{app}\clipps.exe"" --hidden"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\clipps.exe"; Description: "Launch Clipps"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop the tray instance before its files are removed.
Filename: "{sys}\taskkill.exe"; Parameters: "/IM clipps.exe /F"; Flags: runhidden; RunOnceId: "StopClipps"
