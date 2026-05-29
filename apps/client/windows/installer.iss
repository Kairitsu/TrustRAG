[Setup]
AppName=TrustRAG
AppVersion=0.1.1
AppPublisher=TrustRAG Team
DefaultDirName={autopf}\TrustRAG
DefaultGroupName=TrustRAG
OutputDir=..\
OutputBaseFilename=TrustRAG-Setup-Windows-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\TrustRAG.exe
UninstallDisplayName=Uninstall TrustRAG
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\TrustRAG"; Filename: "{app}\TrustRAG.exe"
Name: "{group}\{cm:UninstallProgram,TrustRAG}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TrustRAG"; Filename: "{app}\TrustRAG.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TrustRAG.exe"; Description: "{cm:LaunchProgram,TrustRAG}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  MsgResult: Integer;
  LocalAppDataDir: String;
  RoamingAppDataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    LocalAppDataDir := ExpandConstant('{localappdata}\TrustRAG');
    RoamingAppDataDir := ExpandConstant('{userappdata}\TrustRAG');

    MsgResult := MsgBox(
      'Do you want to delete all TrustRAG local data?' + #13#10 + #13#10 +
      'This includes:' + #13#10 +
      '  - Local databases (trustrag.db)' + #13#10 +
      '  - Model configurations and API keys' + #13#10 +
      '  - Account data and login tokens' + #13#10 +
      '  - Document caches and indexes' + #13#10 + #13#10 +
      'Directories that will be deleted:' + #13#10 +
      '  ' + LocalAppDataDir + #13#10 +
      '  ' + RoamingAppDataDir + #13#10 + #13#10 +
      'Choose "No" if you plan to reinstall or upgrade TrustRAG later.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2);

    if MsgResult = IDYES then
    begin
      if DirExists(LocalAppDataDir) then
        DelTree(LocalAppDataDir, True, True, True);
      if DirExists(RoamingAppDataDir) then
        DelTree(RoamingAppDataDir, True, True, True);
    end;
  end;
end;
