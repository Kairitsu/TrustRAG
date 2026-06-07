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
Source: "..\..\..\scripts\windows\trustrag_paths.ps1"; DestDir: "{app}\scripts\windows"; Flags: ignoreversion
Source: "..\..\..\scripts\windows\uninstall_cleanup.ps1"; DestDir: "{app}\scripts\windows"; Flags: ignoreversion
Source: "..\..\..\scripts\windows\check_trustrag_residue.ps1"; DestDir: "{app}\scripts\windows"; Flags: ignoreversion

[Icons]
Name: "{group}\TrustRAG"; Filename: "{app}\TrustRAG.exe"
Name: "{group}\{cm:UninstallProgram,TrustRAG}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TrustRAG"; Filename: "{app}\TrustRAG.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TrustRAG.exe"; Description: "{cm:LaunchProgram,TrustRAG}"; Flags: nowait postinstall skipifsilent

[Code]
var
  UninstallChoicePage: TInputOptionWizardPage;
  DeleteAllLocalData: Boolean;
  CleanupTempDir: String;
  CleanupFailedMsg: String;
  ProcessStopFailed: Boolean;

procedure CopyCleanupScriptsToTemp;
var
  AppDir, Src, Dst: String;
begin
  CleanupTempDir := ExpandConstant('{tmp}\trustrag-uninstall');
  if not DirExists(CleanupTempDir) then
    ForceDirectories(CleanupTempDir);

  AppDir := ExpandConstant('{app}\scripts\windows');

  Src := AppDir + '\trustrag_paths.ps1';
  Dst := CleanupTempDir + '\trustrag_paths.ps1';
  if FileExists(Src) then
    FileCopy(Src, Dst, False);

  Src := AppDir + '\uninstall_cleanup.ps1';
  Dst := CleanupTempDir + '\uninstall_cleanup.ps1';
  if FileExists(Src) then
    FileCopy(Src, Dst, False);
end;

function RunPowerShell(const ScriptArgs: String; var ResultCode: Integer): Boolean;
begin
  Result := Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass ' + ScriptArgs,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function StopTrustRagProcesses: Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
begin
  ScriptPath := '"' + CleanupTempDir + '\uninstall_cleanup.ps1" -StopProcessesOnly';
  if not RunPowerShell('-File ' + ScriptPath, ResultCode) then
  begin
    Result := False;
    Exit;
  end;
  Result := (ResultCode = 0);
end;

function DeleteTrustRagLocalData(const InstallDir: String): Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
begin
  ScriptPath := '"' + CleanupTempDir + '\uninstall_cleanup.ps1" -DeleteLocalData';
  if InstallDir <> '' then
    ScriptPath := ScriptPath + ' -InstallDir "' + InstallDir + '"';
  if not RunPowerShell('-File ' + ScriptPath, ResultCode) then
  begin
    Result := False;
    Exit;
  end;
  Result := (ResultCode = 0);
end;

function InitializeUninstall(): Boolean;
begin
  DeleteAllLocalData := False;
  ProcessStopFailed := False;
  CleanupFailedMsg := '';
  CleanupTempDir := '';

  UninstallChoicePage := CreateInputOptionPage(
    wpWelcome,
    '本地数据',
    '选择是否在卸载时保留 TrustRAG 本地数据',
    '建议选择「仅卸载应用程序」以保留资料库和配置，便于以后重装继续使用。' + #13#10 + #13#10 +
    '若选择「删除全部本地数据」，将彻底清除本机所有 TrustRAG 相关文件（不可恢复）。',
    True, False);
  UninstallChoicePage.Add('仅卸载应用程序（保留本地数据）');
  UninstallChoicePage.Add('卸载应用程序并删除全部本地数据');
  UninstallChoicePage.SelectedValueIndex := 0;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  MsgResult: Integer;
  InstallDir: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    DeleteAllLocalData := (UninstallChoicePage.SelectedValueIndex = 1);
    InstallDir := ExpandConstant('{app}');

    if DeleteAllLocalData then
    begin
      MsgResult := MsgBox(
        '确认删除全部本地数据？' + #13#10 + #13#10 +
        '此操作不可恢复，将删除：' + #13#10 +
        '  · 本地资料库与上传文件' + #13#10 +
        '  · 聊天记录' + #13#10 +
        '  · 模型配置' + #13#10 +
        '  · API Key / Token / Session' + #13#10 +
        '  · 本地账号和工作区信息' + #13#10 +
        '  · 缓存和日志' + #13#10 + #13#10 +
        '确定要继续吗？',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2);

      if MsgResult <> IDYES then
        DeleteAllLocalData := False;
    end;

    CopyCleanupScriptsToTemp;

    if DeleteAllLocalData then
    begin
      if not StopTrustRagProcesses then
      begin
        ProcessStopFailed := True;
        MsgBox(
          '无法停止 TrustRAG 相关进程（TrustRAG.exe / trustrag-backend.exe）。' + #13#10 + #13#10 +
          '为避免数据库文件损坏，本次将只卸载应用程序，不会删除本地数据。' + #13#10 +
          '请手动关闭相关进程后，可重新运行卸载并选择删除数据，' + #13#10 +
          '或在应用设置中使用「清除本机全部数据」。',
          mbError, MB_OK);
        DeleteAllLocalData := False;
      end;
    end;
  end;

  if CurUninstallStep = usPostUninstall then
  begin
    if DeleteAllLocalData and not ProcessStopFailed then
    begin
      InstallDir := ExpandConstant('{app}');
      if not DeleteTrustRagLocalData(InstallDir) then
      begin
        CleanupFailedMsg :=
          '应用程序已卸载，但部分本地数据未能完全删除。' + #13#10 + #13#10 +
          '请运行以下命令检查残留：' + #13#10 +
          '  powershell -NoProfile -ExecutionPolicy Bypass -File ' + #13#10 +
          '    "%USERPROFILE%\check_trustrag_residue.ps1"' + #13#10 + #13#10 +
          '（若安装目录仍存在脚本，也可运行安装目录下的 scripts\windows\check_trustrag_residue.ps1）';
      end;
    end;

    if CleanupFailedMsg <> '' then
      MsgBox(CleanupFailedMsg, mbError, MB_OK);
  end;
end;