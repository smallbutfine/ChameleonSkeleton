unit clapplugin;
{ Skeleton CLAP audio-effect plugin.
  - one parameter "Gain" (clap.params) applied to the audio (clap.process)
  - GUI extension stub (clap.gui) so a host can embed a window
  Replace the DSP in plugin_process and the GUI stubs with your own. }
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface
uses clap, clapentry;

implementation
uses SysUtils, guiwin, hostcb;

const
  PARAM_GAIN = 0;

type
  PPluginData = ^TPluginData;
  TPluginData = record
    host: PClapHost;
    sample_rate: c_double;
    max_frames: c_uint32;
    gain: c_double;
    pending_param: Boolean;
    last_sent_gain: c_double;
    gw: TGuiWin;
  end;

  TChan32 = array[0..1023] of PSingle;
  PChan32 = ^TChan32;
  TChan64 = array[0..1023] of PDouble;
  PChan64 = ^TChan64;
  TSampleF = array[0..1048575] of c_float;
  PSampleF = ^TSampleF;
  TSampleD = array[0..1048575] of c_double;
  PSampleD = ^TSampleD;
  TAudioBufArray = array[0..1023] of clap_audio_buffer_t;
  PAudioBufArray = ^TAudioBufArray;

var
  g_descriptor: clap_plugin_descriptor_t;
  g_features: array[0..1] of PAnsiChar;
  g_factory: clap_plugin_factory_t;
  g_params: clap_plugin_params_t;
  g_gui: clap_plugin_gui_t;
  g_state: clap_plugin_state_t;

procedure setStr(dst: PAnsiChar; src: PAnsiChar); cdecl;
begin
  if (dst = nil) or (src = nil) then Exit;
  StrCopy(dst, src);
end;

{ ---- forward ---- }
function plugin_init(plugin: pointer): clap_bool; cdecl; forward;
procedure plugin_destroy(plugin: pointer); cdecl; forward;
function plugin_activate(plugin: pointer; sample_rate: c_double;
  min_frames_count: c_uint32; max_frames_count: c_uint32): clap_bool; cdecl; forward;
procedure plugin_deactivate(plugin: pointer); cdecl; forward;
function plugin_start_processing(plugin: pointer): clap_bool; cdecl; forward;
procedure plugin_stop_processing(plugin: pointer); cdecl; forward;
procedure plugin_reset(plugin: pointer); cdecl; forward;
function plugin_process(plugin: pointer; proc: PClapProcess): c_int32; cdecl; forward;
function plugin_get_extension(plugin: pointer; id: PAnsiChar): pointer; cdecl; forward;
procedure plugin_on_main_thread(plugin: pointer); cdecl; forward;

{ ---- entry ---- }
function entry_init(plugin_path: PAnsiChar): clap_bool; cdecl;
begin
  Result := True;
end;

procedure entry_deinit; cdecl;
begin
end;

function entry_get_factory(factory_id: PAnsiChar): pointer; cdecl;
begin
  if (factory_id <> nil) and (StrComp(factory_id, CLAP_PLUGIN_FACTORY_ID) = 0) then
    Exit(@g_factory);
  Result := nil;
end;

{ ---- factory ---- }
function factory_get_count(factory: pointer): c_uint32; cdecl;
begin
  Result := 1;
end;

function factory_get_descriptor(factory: pointer; index: c_uint32): PClapPluginDescriptor; cdecl;
begin
  if index = 0 then Exit(@g_descriptor);
  Result := nil;
end;

function factory_create_plugin(factory: pointer; host: PClapHost; plugin_id: PAnsiChar): PClapPlugin; cdecl;
var
  p: PClapPlugin;
  pd: PPluginData;
begin
  if (plugin_id = nil) or (g_descriptor.id = nil) or
     (StrComp(plugin_id, g_descriptor.id) <> 0) then
    Exit(nil);
  New(pd);
  pd^.host := host;
  pd^.sample_rate := 0;
  pd^.max_frames := 0;
  pd^.gain := 0.5;
  pd^.pending_param := False;
  pd^.last_sent_gain := 0.5;
  pd^.gw.hwnd := nil;
  pd^.gw.gain := nil;
  pd^.gw.host := nil;
  pd^.gw.request_cb := nil;
  pd^.gw.dragging := False;
  pd^.gw.bgBmp := nil;
  pd^.gw.knobBmp := nil;
  pd^.gw.loaded := False;
  pd^.gw.gui_w := 800;
  pd^.gw.gui_h := 600;
  New(p);
  FillChar(p^, SizeOf(clap_plugin_t), 0);
  p^.desc := @g_descriptor;
  p^.plugin_data := pd;
  p^.init := @plugin_init;
  p^.destroy := @plugin_destroy;
  p^.activate := @plugin_activate;
  p^.deactivate := @plugin_deactivate;
  p^.start_processing := @plugin_start_processing;
  p^.stop_processing := @plugin_stop_processing;
  p^.reset := @plugin_reset;
  p^.process := @plugin_process;
  p^.get_extension := @plugin_get_extension;
  p^.on_main_thread := @plugin_on_main_thread;
  Result := p;
end;

{ ---- plugin ---- }
function plugin_init(plugin: pointer): clap_bool; cdecl;
begin
  Result := True;
end;

procedure plugin_destroy(plugin: pointer); cdecl;
var
  p: PClapPlugin;
  pd: PPluginData;
begin
  p := PClapPlugin(plugin);
  if p = nil then Exit;
  pd := PPluginData(p^.plugin_data);
  if pd <> nil then Dispose(pd);
  Dispose(p);
end;

function plugin_activate(plugin: pointer; sample_rate: c_double;
  min_frames_count: c_uint32; max_frames_count: c_uint32): clap_bool; cdecl;
var
  pd: PPluginData;
begin
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  pd^.sample_rate := sample_rate;
  pd^.max_frames := max_frames_count;
  Result := True;
end;

procedure plugin_deactivate(plugin: pointer); cdecl;
begin
end;

function plugin_start_processing(plugin: pointer): clap_bool; cdecl;
begin
  Result := True;
end;

procedure plugin_stop_processing(plugin: pointer); cdecl;
begin
end;

procedure plugin_reset(plugin: pointer); cdecl;
begin
end;

{ Apply incoming parameter events to the plugin state. }
procedure handle_in_events(pd: PPluginData; list: PClapInputEvents);
var
  i: c_uint32;
  ev: PClapEventHeader;
  pv: PClapEventParamValue;
begin
  if (pd = nil) or (list = nil) then Exit;
  for i := 0 to list^.size_fn(list) - 1 do
  begin
    ev := list^.get_fn(list, i);
    if (ev <> nil) and (ev^.evt_type = CLAP_EVENT_PARAM_VALUE) then
    begin
      pv := PClapEventParamValue(ev);
      if pv^.param_id = PARAM_GAIN then
        pd^.gain := pv^.value;
    end;
  end;
end;

{ Push one event through the host output list (if any). }
procedure push_event(out_: PClapOutputEvents; ev: PClapEventHeader);
begin
  if out_ = nil then Exit;
  CallTryPush(out_^.try_push, out_, ev);
end;

{ Emit a parameter change (gesture begin/value/end) to the host. }
procedure emit_param_change(out_: PClapOutputEvents; pd: PPluginData);
var
  gv: clap_event_param_value_t;
  gb, ge: clap_event_param_gesture_t;
begin
  FillChar(gv, SizeOf(gv), 0);
  gv.header.size := SizeOf(gv);
  gv.header.time := 0;
  gv.header.space_id := 0;
  gv.header.evt_type := CLAP_EVENT_PARAM_VALUE;
  gv.header.flags := 0;
  gv.param_id := PARAM_GAIN;
  gv.cookie := nil;
  gv.note_id := -1;
  gv.port_index := -1;
  gv.channel := -1;
  gv.key := -1;
  gv.value := pd^.gain;

  FillChar(gb, SizeOf(gb), 0);
  gb.header.size := SizeOf(gb);
  gb.header.evt_type := CLAP_EVENT_PARAM_GESTURE_BEGIN;
  gb.param_id := PARAM_GAIN;

  FillChar(ge, SizeOf(ge), 0);
  ge.header.size := SizeOf(ge);
  ge.header.evt_type := CLAP_EVENT_PARAM_GESTURE_END;
  ge.param_id := PARAM_GAIN;

  push_event(out_, @gb);
  push_event(out_, @gv);
  push_event(out_, @ge);

  pd^.last_sent_gain := pd^.gain;
  pd^.pending_param := False;
end;

function plugin_process(plugin: pointer; proc: PClapProcess): c_int32; cdecl;
var
  i, ch, s: integer;
  n: integer;
  inb, outb: PClapAudioBuffer;
  src, dst: PSingle;
  src64, dst64: PDouble;
  a32: PChan32;
  a64: PChan64;
  pd: PPluginData;
  g: c_float;
  g64: c_double;
begin
  if proc = nil then Exit(CLAP_PROCESS_ERROR);
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  handle_in_events(pd, proc^.in_events);
  if pd^.pending_param and (proc^.out_events <> nil) then
    emit_param_change(proc^.out_events, pd);
  g := pd^.gain;
  g64 := pd^.gain;
  n := proc^.frames_count;

  for i := 0 to proc^.audio_outputs_count - 1 do
  begin
    outb := @PAudioBufArray(proc^.audio_outputs)^[i];
    if outb^.channel_count = 0 then Continue;

    if i < proc^.audio_inputs_count then
      inb := @PAudioBufArray(proc^.audio_inputs)^[i]
    else
      inb := nil;

    if outb^.data32 <> nil then
    begin
      a32 := PChan32(outb^.data32);
      for ch := 0 to outb^.channel_count - 1 do
      begin
        dst := a32^[ch];
        if (inb <> nil) and (inb^.data32 <> nil) then
        begin
          src := PChan32(inb^.data32)^[ch];
          for s := 0 to n - 1 do PSampleF(dst)[s] := PSampleF(src)[s] * g;
        end
        else
          for s := 0 to n - 1 do PSampleF(dst)[s] := 0;
      end;
    end;

    if outb^.data64 <> nil then
    begin
      a64 := PChan64(outb^.data64);
      for ch := 0 to outb^.channel_count - 1 do
      begin
        dst64 := a64^[ch];
        if (inb <> nil) and (inb^.data64 <> nil) then
        begin
          src64 := PChan64(inb^.data64)^[ch];
          for s := 0 to n - 1 do PSampleD(dst64)[s] := PSampleD(src64)[s] * g64;
        end
        else
          for s := 0 to n - 1 do PSampleD(dst64)[s] := 0;
      end;
    end;
  end;

  Result := CLAP_PROCESS_CONTINUE;
end;

{ ---- params extension ---- }
function params_count(plugin: pointer): c_uint32; cdecl;
begin
  Result := 1;
end;

function params_get_info(plugin: pointer; param_index: c_uint32; info: PClapParamInfo): clap_bool; cdecl;
begin
  if (info = nil) or (param_index <> 0) then Exit(False);
  info^.id := PARAM_GAIN;
  info^.flags := CLAP_PARAM_IS_AUTOMATABLE;
  info^.cookie := nil;
  setStr(@info^.name, 'Gain');
  setStr(@info^.module, '');
  info^.min_value := 0;
  info^.max_value := 1;
  info^.default_value := 0.5;
  Result := True;
end;

function params_get_value(plugin: pointer; param_id: clap_id; out_value: PDouble): clap_bool; cdecl;
begin
  if (out_value = nil) or (param_id <> PARAM_GAIN) then Exit(False);
  out_value^ := PPluginData(PClapPlugin(plugin)^.plugin_data)^.gain;
  Result := True;
end;

function params_value_to_text(plugin: pointer; param_id: clap_id; value: c_double;
  out_buffer: PAnsiChar; out_buffer_capacity: c_uint32): clap_bool; cdecl;
var
  s: ShortString;
begin
  if (out_buffer = nil) or (param_id <> PARAM_GAIN) or (out_buffer_capacity = 0) then Exit(False);
  Str(value:0:2, s);
  StrLCopy(out_buffer, PAnsiChar(@s[1]), out_buffer_capacity - 1);
  Result := True;
end;

function params_text_to_value(plugin: pointer; param_id: clap_id; param_value_text: PAnsiChar;
  out_value: PDouble): clap_bool; cdecl;
begin
  if (out_value = nil) or (param_id <> PARAM_GAIN) then Exit(False);
  out_value^ := StrToFloatDef(param_value_text, 0.5);
  Result := True;
end;

procedure params_flush(plugin: pointer; in_: PClapInputEvents; out_: PClapOutputEvents); cdecl;
begin
  handle_in_events(PPluginData(PClapPlugin(plugin)^.plugin_data), in_);
end;

{ ---- gui extension (stub) ---- }
function gui_is_api_supported(plugin: pointer; api: PAnsiChar; is_floating: clap_bool): clap_bool; cdecl;
begin
  if (api <> nil) and
     ((StrComp(api, CLAP_WINDOW_API_WIN32) = 0) or
      (StrComp(api, CLAP_WINDOW_API_COCOA) = 0) or
      (StrComp(api, CLAP_WINDOW_API_X11) = 0)) then
    Exit(True);
  Result := False;
end;

function gui_get_preferred_api(plugin: pointer; api: PPAnsiChar; is_floating: PClapBool): clap_bool; cdecl;
begin
  if api <> nil then api^ := PAnsiChar(CLAP_WINDOW_API_WIN32);
  if is_floating <> nil then is_floating^ := False;
  Result := True;
end;

function gui_create(plugin: pointer; api: PAnsiChar; is_floating: clap_bool): clap_bool; cdecl;
var
  pd: PPluginData;
begin
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  pd^.gw.gain := @pd^.gain;
  pd^.gw.pending := @pd^.pending_param;
  pd^.gw.host := pd^.host;
  if pd^.host <> nil then
    pd^.gw.request_cb := pd^.host^.request_callback
  else
    pd^.gw.request_cb := nil;
  Result := GuiCreate(pd^.gw, pd^.gw.gui_w, pd^.gw.gui_h);
end;

procedure gui_destroy(plugin: pointer); cdecl;
begin
  GuiDestroy(PPluginData(PClapPlugin(plugin)^.plugin_data)^.gw);
end;

function gui_set_scale(plugin: pointer; scale: c_double): clap_bool; cdecl;
begin
  Result := True;
end;

function gui_get_size(plugin: pointer; width: PClapSize; height: PClapSize): clap_bool; cdecl;
var
  pd: PPluginData;
begin
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  if width <> nil then width^ := pd^.gw.gui_w;
  if height <> nil then height^ := pd^.gw.gui_h;
  Result := True;
end;

function gui_can_resize(plugin: pointer): clap_bool; cdecl;
begin
  Result := False;
end;

function gui_get_resize_hints(plugin: pointer; hints: PClapGuiResizeHints): clap_bool; cdecl;
begin
  if hints <> nil then FillChar(hints^, SizeOf(clap_gui_resize_hints_t), 0);
  Result := False;
end;

function gui_adjust_size(plugin: pointer; width: PClapSize; height: PClapSize): clap_bool; cdecl;
begin
  Result := True;
end;

function gui_set_size(plugin: pointer; width: c_uint32; height: c_uint32): clap_bool; cdecl;
var
  pd: PPluginData;
begin
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  pd^.gw.gui_w := width;
  pd^.gw.gui_h := height;
  Result := True;
end;

function gui_set_parent(plugin: pointer; window: PClapWindow): clap_bool; cdecl;
begin
  if window <> nil then
    GuiSetParent(PPluginData(PClapPlugin(plugin)^.plugin_data)^.gw, window^.ptr);
  Result := True;
end;

function gui_set_transient(plugin: pointer; window: PClapWindow): clap_bool; cdecl;
begin
  Result := True;
end;

procedure gui_suggest_title(plugin: pointer; title: PAnsiChar); cdecl;
begin
end;

function gui_show(plugin: pointer): clap_bool; cdecl;
begin
  GuiShow(PPluginData(PClapPlugin(plugin)^.plugin_data)^.gw, True);
  Result := True;
end;

function gui_hide(plugin: pointer): clap_bool; cdecl;
begin
  GuiShow(PPluginData(PClapPlugin(plugin)^.plugin_data)^.gw, False);
  Result := True;
end;

{ ---- state extension (save/load the gain) ---- }
function state_save(plugin: pointer; stream: PClapOStream): clap_bool; cdecl;
var
  pd: PPluginData;
  buf: array[0..23] of c_byte;
  total: c_int64;
  w: c_int64;
begin
  if stream = nil then Exit(False);
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  buf[0] := 67; buf[1] := 72; buf[2] := 83; buf[3] := 49; // 'C','H','S','1'
  buf[4] := 2; buf[5] := 0; buf[6] := 0; buf[7] := 0;       // version 2
  Move(pd^.gain, buf[8], 8);
  Move(pd^.gw.gui_w, buf[16], 4);
  Move(pd^.gw.gui_h, buf[20], 4);
  total := 0;
  while total < 24 do
  begin
    w := stream^.write_fn(stream, @buf[total], 24 - total);
    if w <= 0 then Exit(False);
    total := total + w;
  end;
  Result := True;
end;

function state_load(plugin: pointer; stream: PClapIStream): clap_bool; cdecl;
var
  pd: PPluginData;
  buf: array[0..23] of c_byte;
  total: c_int64;
  r: c_int64;
  g: c_double;
  gw, gh: LongWord;
begin
  if stream = nil then Exit(False);
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  total := 0;
  while total < 24 do
  begin
    r := stream^.read_fn(stream, @buf[total], 24 - total);
    if r <= 0 then Exit(False);
    total := total + r;
  end;
  if not ((buf[0] = 67) and (buf[1] = 72) and (buf[2] = 83) and (buf[3] = 49) and (buf[4] = 2)) then
    Exit(False);
  Move(buf[8], g, 8);
  Move(buf[16], gw, 4);
  Move(buf[20], gh, 4);
  pd^.gain := g;
  if (gw > 0) and (gh > 0) then
  begin
    pd^.gw.gui_w := gw;
    pd^.gw.gui_h := gh;
  end;
  Result := True;
end;

{ ---- extension dispatch ---- }
function plugin_get_extension(plugin: pointer; id: PAnsiChar): pointer; cdecl;
begin
  if (id <> nil) and (StrComp(id, CLAP_EXT_PARAMS) = 0) then Exit(@g_params);
  if (id <> nil) and (StrComp(id, CLAP_EXT_GUI) = 0) then Exit(@g_gui);
  if (id <> nil) and (StrComp(id, CLAP_EXT_STATE) = 0) then Exit(@g_state);
  Result := nil;
end;

procedure plugin_on_main_thread(plugin: pointer); cdecl;
var
  pd: PPluginData;
begin
  pd := PPluginData(PClapPlugin(plugin)^.plugin_data);
  GuiPump(pd^.gw); { process pending X11 events (no-op on other platforms) }
  { The GUI set pending_param and called request_callback; ask the host to
    run a process/flush cycle so we can emit the parameter event. }
  if pd^.pending_param and (pd^.host <> nil) then
    pd^.host^.request_process(pd^.host);
end;

{ ---- module setup ---- }
initialization
  clap_entry.version.major := CLAP_VERSION_MAJOR;
  clap_entry.version.minor := CLAP_VERSION_MINOR;
  clap_entry.version.revision := CLAP_VERSION_REVISION;
  clap_entry.init := @entry_init;
  clap_entry.deinit := @entry_deinit;
  clap_entry.get_factory := @entry_get_factory;

  g_features[0] := PAnsiChar('audio-effect');
  g_features[1] := nil;

  g_descriptor.version.major := CLAP_VERSION_MAJOR;
  g_descriptor.version.minor := CLAP_VERSION_MINOR;
  g_descriptor.version.revision := CLAP_VERSION_REVISION;
  g_descriptor.id := PAnsiChar('com.example.chameleonskeleton');
  g_descriptor.name := PAnsiChar('Chameleon Skeleton');
  g_descriptor.vendor := PAnsiChar('Example');
  g_descriptor.url := PAnsiChar('https://example.com');
  g_descriptor.manual_url := nil;
  g_descriptor.support_url := nil;
  g_descriptor.version_str := PAnsiChar('0.1.0');
  g_descriptor.description := PAnsiChar('CLAP audio-effect skeleton with a Gain parameter.');
  g_descriptor.features := @g_features;

  g_factory.get_plugin_count := @factory_get_count;
  g_factory.get_plugin_descriptor := @factory_get_descriptor;
  g_factory.create_plugin := @factory_create_plugin;

  g_params.count := @params_count;
  g_params.get_info := @params_get_info;
  g_params.get_value := @params_get_value;
  g_params.value_to_text := @params_value_to_text;
  g_params.text_to_value := @params_text_to_value;
  g_params.flush := @params_flush;

  g_gui.is_api_supported := @gui_is_api_supported;
  g_gui.get_preferred_api := @gui_get_preferred_api;
  g_gui.create := @gui_create;
  g_gui.destroy := @gui_destroy;
  g_gui.set_scale := @gui_set_scale;
  g_gui.get_size := @gui_get_size;
  g_gui.can_resize := @gui_can_resize;
  g_gui.get_resize_hints := @gui_get_resize_hints;
  g_gui.adjust_size := @gui_adjust_size;
  g_gui.set_size := @gui_set_size;
  g_gui.set_parent := @gui_set_parent;
  g_gui.set_transient := @gui_set_transient;
  g_gui.suggest_title := @gui_suggest_title;
  g_gui.show := @gui_show;
  g_gui.hide := @gui_hide;

  g_state.save := @state_save;
  g_state.load := @state_load;
end.