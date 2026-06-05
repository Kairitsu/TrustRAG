[Setup]
AppId={{B2F8A9E1-7C3D-4F5A-9E1B-2D4F6A8C0E3F}
AppName=TrustRAG
AppVersion=0.2.8
AppVerName=TrustRAG 0.2.8
AppPublisher=TrustRAG Team
AppSupportURL=https://github.com/ximi-ai/TrustRAG/issues
AppUpdatesURL=https://github.com/ximi-ai/TrustRAG/releases
DefaultDirName={autopf}\TrustRAG
DefaultGroupName=TrustRAG
OutputDir=..\
OutputBaseFilename=TrustRAG-Setup-Windows-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\TrustRAG.exe
UninstallDisplayName=TrustRAG 0.2.8
UninstallFilesDir={app}\uninstall
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
  DirsToDelete: String;
  DirPath: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DirsToDelete := '';

    DirPath := ExpandConstant('{localappdata}\trustrag\TrustRAG');
    if DirExists(DirPath) then
      DirsToDelete := DirsToDelete + '  ' + DirPath + #13#10;

    DirPath := ExpandConstant('{localappdata}\trustrag');
    if DirExists(DirPath) then
      DirsToDelete := DirsToDelete + '  ' + DirPath + #13#10;

    DirPath := ExpandConstant('{userappdata}\com.trustrag');
    if DirExists(DirPath) then
      DirsToDelete := DirsToDelete + '  ' + DirPath + #13#10;

    DirPath := ExpandConstant('{localappdata}\TrustRAG');
    if DirExists(DirPath) then
      DirsToDelete := DirsToDelete + '  ' + DirPath + #13#10;

    DirPath := ExpandConstant('{userappdata}\TrustRAG');
    if DirExists(DirPath) then
      DirsToDelete := DirsToDelete + '  ' + DirPath + #13#10;

    if DirsToDelete = '' then
      Exit;

    MsgResult := MsgBox(
      'Do you want to delete all TrustRAG local data?' + #13#10 + #13#10 +
      'This includes:' + #13#10 +
      '  - Local databases (trustrag.db)' + #13#10 +
      '  - Model configurations and API keys' + #13#10 +
      '  - Account data and login tokens' + #13#10 +
      '  - Document caches and indexes' + #13#10 + #13#10 +
      'Directories that will be deleted:' + #13#10 +
      DirsToDelete + #13#10 +
      'Choose "No" if you plan to reinstall or upgrade TrustRAG later.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2);

    if MsgResult = IDYES then
    begin
      DirPath := ExpandConstant('{localappdata}\trustrag\TrustRAG');
      if DirExists(DirPath) then DelTree(DirPath, True, True, True);

      DirPath := ExpandConstant('{localappdata}\trustrag');
      if DirExists(DirPath) then DelTree(DirPath, True, True, True);

      DirPath := ExpandConstant('{userappdata}\com.trustrag');
      if DirExists(DirPath) then DelTree(DirPath, True, True, True);

      DirPath := ExpandConstant('{localappdata}\TrustRAG');
      if DirExists(DirPath) then DelTree(DirPath, True, True, True);

      DirPath := ExpandConstant('{userappdata}\TrustRAG');
      if DirExists(DirPath) then DelTree(DirPath, True, True, True);
    end;
  end;
end;
