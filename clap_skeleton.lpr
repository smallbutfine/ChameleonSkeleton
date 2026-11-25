library clap_skeleton;
{ CLAP plugin library. The host resolves the exported symbol "clap_entry".
  clapentry.pas declares it "cvar" (unmangled); this clause exports it into the
  dynamic symbol table on Windows, Linux and macOS. }
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
uses
  SysUtils,
  clap,
  clapentry,
  clapplugin;

exports
  clap_entry;

begin
end.