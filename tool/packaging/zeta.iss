#ifndef ProjectRoot
  #error ProjectRoot must be provided by package_windows.ps1.
#endif
#ifndef BuildDir
  #error BuildDir must be provided by package_windows.ps1.
#endif
#ifndef OutputDir
  #error OutputDir must be provided by package_windows.ps1.
#endif
#ifndef AppVersion
  #error AppVersion must be provided by package_windows.ps1.
#endif
#ifndef ArtifactVersion
  #error ArtifactVersion must be provided by package_windows.ps1.
#endif
#ifndef VersionInfoVersion
  #error VersionInfoVersion must be provided by package_windows.ps1.
#endif

[Setup]
AppId=io.github.linpeilie.zeta
AppName=Zeta
AppVersion={#AppVersion}
AppVerName=Zeta {#AppVersion}
AppPublisher=linpeilie
AppPublisherURL=https://github.com/linpeilie/zeta
AppSupportURL=https://github.com/linpeilie/zeta/issues
DefaultDirName={localappdata}\Programs\Zeta
DefaultGroupName=Zeta
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=zeta-{#ArtifactVersion}-windows-x86_64-setup
SetupIconFile={#ProjectRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\zeta.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
VersionInfoCompany=linpeilie
VersionInfoDescription=Zeta installer
VersionInfoProductName=Zeta
VersionInfoProductTextVersion={#AppVersion}
VersionInfoProductVersion={#VersionInfoVersion}
VersionInfoVersion={#VersionInfoVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Zeta"; Filename: "{app}\zeta.exe"
Name: "{autodesktop}\Zeta"; Filename: "{app}\zeta.exe"; Tasks: desktopicon

; Do not add a postinstall [Run] launch entry. Starting Zeta from Setup.exe
; inherits the installer process environment and races first-run assistant
; detection, which can fail the project session list until the next launch.
