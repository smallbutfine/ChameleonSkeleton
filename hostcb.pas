unit hostcb;
{ FPC-mode helper: calling a cdecl procedure-variable from Delphi mode is
  broken in FPC on win64 ("Wrong number of parameters"), so the actual calls
  live here in FPC mode. }
{$mode fpc}{$H+}
interface
uses clap;

type
  TRequestCb = procedure(host: pointer); cdecl;
  TTryPush = function(list: pointer; event: PClapEventHeader): clap_bool; cdecl;

procedure CallRequest(cb: TRequestCb; host: pointer);
procedure CallTryPush(tp: TTryPush; list: pointer; event: PClapEventHeader);

implementation

procedure CallRequest(cb: TRequestCb; host: pointer);
begin
  if cb <> nil then
    cb(host);
end;

procedure CallTryPush(tp: TTryPush; list: pointer; event: PClapEventHeader);
begin
  if tp <> nil then
    tp(list, event);
end;

end.