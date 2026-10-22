; DukeBoxarr Windows installer (Inno Setup 6).
; Build with tool\build_installer.ps1, which passes /DAppVersion from pubspec.yaml.
;
; Installs per user (no admin prompt) into %LOCALAPPDATA%\Programs\DukeBoxarr.
; Running a newer installer upgrades in place: the AppId below must never
; change, or Windows will treat it as a different app.
; Settings, library cache and album numbers live in %APPDATA%\ca.dukebox and
; are left alone by updates and uninstalls.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "DukeBoxarr"
#define AppExe "dukeboxarr.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B8B195E8-ECE9-4B4A-BC58-0ECE7E194801}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Cd084
AppPublisherURL=https://github.com/Cd084/DukeBoxarr
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=DukeBoxarr-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Close a running DukeBoxarr before updating its files.
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Remove the previous version's Flutter assets so stale files don't linger.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
