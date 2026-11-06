; TirsoDrive Windows installer (Inno Setup). Built automatically by .github/workflows/windows.yml
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F3B2C1E-9A7D-4E51-B8C2-71D0A9E5C4F2}
AppName=TirsoDrive
AppVersion={#AppVersion}
AppPublisher=Tirso
DefaultDirName={localappdata}\Programs\TirsoDrive
DefaultGroupName=TirsoDrive
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=TirsoDrive-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\TirsoDrive.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\TirsoDrive"; Filename: "{app}\TirsoDrive.exe"
Name: "{autodesktop}\TirsoDrive"; Filename: "{app}\TirsoDrive.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TirsoDrive.exe"; Description: "{cm:LaunchProgram,TirsoDrive}"; Flags: nowait postinstall skipifsilent
