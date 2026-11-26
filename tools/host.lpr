program host;
{ Minimal CLAP host harness for Windows: loads clap_skeleton.clap, embeds its GUI
  into a window, and feeds a 440 Hz test tone so the VU/knobs animate.
  Build: fpc -Px86_64 -O2 host.lpr   (needs clap.pas in the same dir) }
{$mode Delphi}{$H+}
uses
  Classes, SysUtils, Windows, Math, clap;

var
  g_plugin: PClapPlugin;
  g_frames: Integer = 256;
  g_in, g_out: array[0..1] of c_float;  // stereo
  g_inBuf, g_outBuf: clap_audio_buffer_t;

{ ---- host callbacks ---- }
function host_get_ext(host: pointer; id: PAnsiChar): pointer; cdecl; begin Result := nil; end;
procedure host_restart(host: pointer); cdecl; begin end;
procedure host_process(host: pointer); cdecl; begin end;
procedure host_callback(host: pointer); cdecl;
begin if g_plugin <> nil then g_plugin^.on_main_thread(g_plugin); end;

procedure ProcessBlock; forward;

function WndProc(hwnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  case msg of
    WM_TIMER: begin ProcessBlock; Result := 0; end;
    WM_DESTROY: begin PostQuitMessage(0); Result := 0; end;
  else Result := DefWindowProcA(hwnd, msg, wParam, lParam); end;
end;

procedure FillHost(var h: clap_host_t);
begin
  FillChar(h, SizeOf(h), 0);
  h.name := PAnsiChar('Harness');
  h.vendor := PAnsiChar('test');
  h.version_str := PAnsiChar('1.0');
  h.version.major := 1; h.version.minor := 0; h.version.revision := 0;
  h.get_extension := @host_get_ext;
  h.request_restart := @host_restart;
  h.request_process := @host_process;
  h.request_callback := @host_callback;
end;

procedure ProcessBlock;
var p: clap_process_t; i, ch: Integer;
begin
  if g_plugin = nil then Exit;
  FillChar(p, SizeOf(p), 0);
  p.frames_count := g_frames;
  p.audio_inputs_count := 1;
  p.audio_outputs_count := 1;
  p.audio_inputs := @g_inBuf;
  p.audio_outputs := @g_outBuf;
  g_inBuf.channel_count := 1; g_inBuf.data32 := @g_in;
  g_outBuf.channel_count := 1; g_outBuf.data32 := @g_out;
  for i := 0 to g_frames - 1 do
    g_in[i] := 0.2 * Sin(2.0 * Pi * 440.0 * i / 44100.0);
  g_plugin^.process(g_plugin, @p);
end;

var
  inst: HINST;
  wc: WNDCLASSEX;
  hwindow: HWND;
  message: MSG;
  hLib: HMODULE;
  entry: PClapPluginEntry;
  factory: PClapPluginFactory;
  plugin: PClapPlugin;
  gui: PClapPluginGui;
  g_host: clap_host_t;
  wnd: clap_window_t;
  w: c_uint32;
  h: c_uint32;
begin
  inst := GetModuleHandle(nil);
  hLib := LoadLibrary(PChar(ExtractFilePath(ParamStr(0)) + 'clap_skeleton.clap'));
  if hLib = 0 then begin WriteLn('cannot load clap_skeleton.clap'); Exit; end;
  entry := PClapPluginEntry(GetProcAddress(hLib, PAnsiChar('clap_entry')));
  if entry = nil then begin WriteLn('no clap_entry'); Exit; end;
  entry^.init(nil);
  factory := entry^.get_factory(PAnsiChar('clap.plugin-factory'));
  if factory = nil then begin WriteLn('no factory'); Exit; end;

  FillHost(g_host);
  plugin := factory^.create_plugin(factory, @g_host, PAnsiChar('com.example.chameleonconsole'));
  if plugin = nil then begin WriteLn('create_plugin failed'); Exit; end;
  g_plugin := plugin;
  plugin^.init(plugin);

  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc); wc.style := CS_HREDRAW or CS_VREDRAW;
  wc.lpfnWndProc := @WndProc;
  wc.hInstance := inst; wc.lpszClassName := PAnsiChar('ChameleonHost');
  RegisterClassEx(wc);
  hwindow := CreateWindowExA(0, PAnsiChar('ChameleonHost'), PAnsiChar('ChameleonConsole Host'),
    WS_OVERLAPPEDWINDOW, 100, 100, 400, 700, 0, 0, inst, nil);

  gui := plugin^.get_extension(plugin, PAnsiChar('clap.gui'));
  if gui <> nil then
  begin
    gui^.create(plugin, PAnsiChar('win32'), False);
    gui^.get_size(plugin, @w, @h);
    wnd.api := PAnsiChar('win32'); wnd.ptr := Pointer(hwindow);
    gui^.set_parent(plugin, @wnd);
    gui^.show(plugin);
  end;

  SetTimer(hwindow, 1, 50, nil);
  ShowWindow(hwindow, SW_SHOW);
  while GetMessage(@message, 0, 0, 0) do
  begin
    TranslateMessage(@message);
    DispatchMessage(@message);
  end;

  if gui <> nil then gui^.destroy(plugin);
  plugin^.destroy(plugin);
  entry^.deinit;
end.