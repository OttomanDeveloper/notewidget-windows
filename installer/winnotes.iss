; Inno Setup script for WinNotes.
;
; Version and output directory are supplied on the command line by
; tool/release/package.ps1, so nothing here is hardcoded and the script cannot
; go stale against pubspec.yaml:
;
;   ISCC /DAppVersion=1.1.0 /O<output-dir> installer\winnotes.iss
;
; The staged application tree is produced by the same script, so this only has to
; describe where the files are and what the Windows shell should be told.

#ifndef AppVersion
  #error AppVersion is not defined. Build via tool/release/package.ps1.
#endif

#define AppName "WinNotes"
#define AppPublisher "WinNotes"
#define AppExeName "win_notes.exe"
#define AppMutex "Local\\WinNotes.SingleInstance"

[Setup]
AppId={{6E3B0C7A-6C2E-4E1B-9E2E-0D2F7A5B1C40}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
; Per-user install into the person's own profile, with no elevation. The app
; keeps its data in %APPDATA% and its autostart entry under HKCU, and its whole
; promise is that it needs no administrator rights - so the installer must not
; ask for any. Inno defaults to PrivilegesRequired=admin, which would put a UAC
; prompt in front of an app that has no reason to need one.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputBaseFilename=WinNotes-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Windows 10 and 11. Flutter's Windows embedder requires 1809 or newer.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
; The app has no installer of its own and no registry keys, so an interrupted
; install cannot leave anything behind that a retry would trip over.
Uninstallable=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Bring the widget back after every restart"; GroupDescription: "Startup:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; The staged tree laid out by package.ps1.
Source: "..\dist\WinNotes-{#AppVersion}\WinNotes\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; The same per-user Run key the app writes from its own Settings screen. Put
; here with the install path already resolved, because the app reads it on
; startup and an entry pointing at the wrong folder would show a widget that
; cannot open.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
    ValueType: string; ValueName: "WinNotes"; \
    ValueData: """{app}\{#AppExeName}"""; \
    Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Logs written next to the executable. Notes are NOT deleted: they live in
; %APPDATA%\WinNotes and belong to the person, not to the installation.
Type: files; Name: "{app}\*.log"