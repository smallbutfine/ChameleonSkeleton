[Setup]
AppId={{D3A4B5C6-1E2F-4A3B-9C8D-0F1A2B3C4D5E}
AppName=ChameleonSkeleton
AppVersion={#MyAppVersion}
DefaultDirName={code:GetCLAPDir}
OutputBaseFilename=ChameleonSkeleton_Setup_{#MyAppVersion}
OutputDir=..
PrivilegesRequired=none
PrivilegesRequiredOverridesAllowed=dialog
DisableDirPage=no
DisableProgramGroupPage=yes
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Types]
Name: "full"; Description: "Full (CLAP + VST3)"
Name: "clap"; Description: "CLAP only"
Name: "vst3"; Description: "VST3 only"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "clap"; Description: "CLAP plugin (with artwork)"; Types: full clap custom
Name: "vst3"; Description: "VST3 plugin"; Types: full vst3 custom

[Files]
Source: "..\clap_skeleton.clap"; DestDir: "{code:GetCLAPDir}"; Components: clap; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\Assets\*"; DestDir: "{code:GetCLAPDir}\Assets"; Components: clap; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\clap_skeleton.vst3"; DestDir: "{code:GetVST3Dir}"; Components: vst3; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\Assets\*"; DestDir: "{code:GetVST3Dir}\Assets"; Components: vst3; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Code]
{ Uninstall any previous version (same AppId) before installing. }
function InitializeSetup(): Boolean;
var
  RegKey: String;
  UninstallPath: String;
  ResultCode: Integer;
begin
  Result := True;
  RegKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + ExpandConstant('{#SetupSetting("AppId")}') + '_is1';
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, RegKey, 'UninstallString', UninstallPath) then
    RegQueryStringValue(HKEY_CURRENT_USER, RegKey, 'UninstallString', UninstallPath);
  if UninstallPath <> '' then
  begin
    UninstallPath := RemoveQuotes(UninstallPath);
    Exec(UninstallPath, '/SILENT /NORESTART /SUPPRESSMSGBOXES', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
  end;
end;

{ Per-user (no admin) or system-wide (admin), chosen via the standard
  all-users / just-me dialog. commonpf64 is C:\Program Files (64-bit);
  append the literal Common Files. }
function GetCLAPDir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonpf64}') + '\Common Files\CLAP\ChameleonSkeleton'
  else
    Result := ExpandConstant('{localappdata}') + '\Programs\Common\CLAP\ChameleonSkeleton';
end;

function GetVST3Dir(Param: String): String;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{commonpf64}') + '\Common Files\VST3'
  else
    Result := ExpandConstant('{localappdata}') + '\Programs\Common\VST3';
end;