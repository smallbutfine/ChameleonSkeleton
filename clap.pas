unit clap;
{ Minimal CLAP (CLever Audio Plugin) ABI translation for Free Pascal / Lazarus.
  Generated from the official headers (free-audio/clap, CLAP 1.2.x).
  Subset: core + params + events + gui, enough for an audio-effect with a knob. }
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface

const
  CLAP_PLUGIN_FACTORY_ID = 'clap.plugin-factory';
  CLAP_EXT_PARAMS = 'clap.params';
  CLAP_EXT_GUI = 'clap.gui';
  CLAP_EXT_STATE = 'clap.state';

  CLAP_VERSION_MAJOR = 1;
  CLAP_VERSION_MINOR = 2;
  CLAP_VERSION_REVISION = 10;

  // clap_process_status
  CLAP_PROCESS_ERROR = 0;
  CLAP_PROCESS_CONTINUE = 1;
  CLAP_PROCESS_CONTINUE_IF_NOT_QUIET = 2;
  CLAP_PROCESS_TAIL = 3;
  CLAP_PROCESS_SLEEP = 4;

  // event types (core space)
  CLAP_EVENT_PARAM_VALUE = 5;
  CLAP_EVENT_PARAM_GESTURE_BEGIN = 7;
  CLAP_EVENT_PARAM_GESTURE_END = 8;

  // param flags
  CLAP_PARAM_IS_STEPPED = 1 shl 0;
  CLAP_PARAM_IS_AUTOMATABLE = 1 shl 5;

  // string sizes
  CLAP_NAME_SIZE = 256;
  CLAP_PATH_SIZE = 1024;

  // window api
  CLAP_WINDOW_API_WIN32 = 'win32';
  CLAP_WINDOW_API_COCOA = 'cocoa';
  CLAP_WINDOW_API_X11 = 'x11';

type
  { C fixed-width types (defined locally to avoid unit/mode differences). }
  c_byte = Byte;
  c_uint16 = Word;
  c_int16 = SmallInt;
  c_uint32 = LongWord;
  c_int32 = LongInt;
  c_uint64 = UInt64;
  c_int64 = Int64;
  c_float = Single;
  c_double = Double;

  clap_id = c_uint32;
  clap_bool = Boolean; // C99 _Bool (1 byte)
  PClapBool = ^clap_bool;

  PSingle = ^c_float;
  PDouble = ^c_double;
  PPAnsiChar = ^PAnsiChar;
  PClapSize = ^c_uint32;

  clap_version_t = record
    major: c_uint32;
    minor: c_uint32;
    revision: c_uint32;
  end;

  clap_audio_buffer_t = record
    data32: pointer;      // float **
    data64: pointer;      // double **
    channel_count: c_uint32;
    latency: c_uint32;
    constant_mask: c_uint64;
  end;
  PClapAudioBuffer = ^clap_audio_buffer_t;

  // ---- events ----
  clap_event_header_t = record
    size: c_uint32;
    time: c_uint32;
    space_id: c_uint16;
    evt_type: c_uint16;
    flags: c_uint32;
  end;
  PClapEventHeader = ^clap_event_header_t;

  clap_event_param_value_t = record
    header: clap_event_header_t;
    param_id: clap_id;
    cookie: pointer;
    note_id: c_int32;
    port_index: c_int16;
    channel: c_int16;
    key: c_int16;
    value: c_double;
  end;
  PClapEventParamValue = ^clap_event_param_value_t;

  clap_event_param_gesture_t = record
    header: clap_event_header_t;
    param_id: clap_id;
  end;
  PClapEventParamGesture = ^clap_event_param_gesture_t;

  clap_input_events_t = record
    ctx: pointer;
    size_fn: function(list: pointer): c_uint32; cdecl;
    get_fn: function(list: pointer; index: c_uint32): PClapEventHeader; cdecl;
  end;
  PClapInputEvents = ^clap_input_events_t;

  clap_output_events_t = record
    ctx: pointer;
    try_push: function(list: pointer; event: PClapEventHeader): clap_bool; cdecl;
  end;
  PClapOutputEvents = ^clap_output_events_t;

  // opaque transport (unused by the skeleton)
  clap_event_transport_t = record
    _opaque: array[0..63] of c_byte;
  end;
  PClapEventTransport = ^clap_event_transport_t;

  clap_process_t = record
    steady_time: c_int64;
    frames_count: c_uint32;
    transport: PClapEventTransport;
    audio_inputs: PClapAudioBuffer;
    audio_outputs: PClapAudioBuffer;
    audio_inputs_count: c_uint32;
    audio_outputs_count: c_uint32;
    in_events: PClapInputEvents;
    out_events: PClapOutputEvents;
  end;
  PClapProcess = ^clap_process_t;

  // ---- params ----
  clap_param_info_t = record
    id: clap_id;
    flags: c_uint32;
    cookie: pointer;
    name: array[0..CLAP_NAME_SIZE - 1] of AnsiChar;
    module: array[0..CLAP_PATH_SIZE - 1] of AnsiChar;
    min_value: c_double;
    max_value: c_double;
    default_value: c_double;
  end;
  PClapParamInfo = ^clap_param_info_t;

  clap_plugin_params_t = record
    count: function(plugin: pointer): c_uint32; cdecl;
    get_info: function(plugin: pointer; param_index: c_uint32; param_info: PClapParamInfo): clap_bool; cdecl;
    get_value: function(plugin: pointer; param_id: clap_id; out_value: PDouble): clap_bool; cdecl;
    value_to_text: function(plugin: pointer; param_id: clap_id; value: c_double;
      out_buffer: PAnsiChar; out_buffer_capacity: c_uint32): clap_bool; cdecl;
    text_to_value: function(plugin: pointer; param_id: clap_id; param_value_text: PAnsiChar;
      out_value: PDouble): clap_bool; cdecl;
    flush: procedure(plugin: pointer; in_: PClapInputEvents; out_: PClapOutputEvents); cdecl;
  end;
  PClapPluginParams = ^clap_plugin_params_t;

  // ---- gui ----
  clap_window_t = record
    api: PAnsiChar;
    ptr: pointer; // union of win32/cocoa/x11/... (all pointer sized)
  end;
  PClapWindow = ^clap_window_t;

  clap_gui_resize_hints_t = record
    can_resize_horizontally: clap_bool;
    can_resize_vertically: clap_bool;
    preserve_aspect_ratio: clap_bool;
    aspect_ratio_width: c_uint32;
    aspect_ratio_height: c_uint32;
  end;
  PClapGuiResizeHints = ^clap_gui_resize_hints_t;

  clap_plugin_gui_t = record
    is_api_supported: function(plugin: pointer; api: PAnsiChar; is_floating: clap_bool): clap_bool; cdecl;
    get_preferred_api: function(plugin: pointer; api: PPAnsiChar; is_floating: PClapBool): clap_bool; cdecl;
    create: function(plugin: pointer; api: PAnsiChar; is_floating: clap_bool): clap_bool; cdecl;
    destroy: procedure(plugin: pointer); cdecl;
    set_scale: function(plugin: pointer; scale: c_double): clap_bool; cdecl;
    get_size: function(plugin: pointer; width: PClapSize; height: PClapSize): clap_bool; cdecl;
    can_resize: function(plugin: pointer): clap_bool; cdecl;
    get_resize_hints: function(plugin: pointer; hints: PClapGuiResizeHints): clap_bool; cdecl;
    adjust_size: function(plugin: pointer; width: PClapSize; height: PClapSize): clap_bool; cdecl;
    set_size: function(plugin: pointer; width: c_uint32; height: c_uint32): clap_bool; cdecl;
    set_parent: function(plugin: pointer; window: PClapWindow): clap_bool; cdecl;
    set_transient: function(plugin: pointer; window: PClapWindow): clap_bool; cdecl;
    suggest_title: procedure(plugin: pointer; title: PAnsiChar); cdecl;
    show: function(plugin: pointer): clap_bool; cdecl;
    hide: function(plugin: pointer): clap_bool; cdecl;
  end;
  PClapPluginGui = ^clap_plugin_gui_t;

  // ---- descriptor / host / plugin / factory / entry ----
  // ---- state / streams ----
  clap_istream_t = record
    ctx: pointer;
    read_fn: function(stream: pointer; buffer: pointer; size: c_uint64): c_int64; cdecl;
  end;
  PClapIStream = ^clap_istream_t;

  clap_ostream_t = record
    ctx: pointer;
    write_fn: function(stream: pointer; buffer: pointer; size: c_uint64): c_int64; cdecl;
  end;
  PClapOStream = ^clap_ostream_t;

  clap_plugin_state_t = record
    save: function(plugin: pointer; stream: PClapOStream): clap_bool; cdecl;
    load: function(plugin: pointer; stream: PClapIStream): clap_bool; cdecl;
  end;
  PClapPluginState = ^clap_plugin_state_t;

  clap_plugin_descriptor_t = record
    version: clap_version_t;
    id: PAnsiChar;
    name: PAnsiChar;
    vendor: PAnsiChar;
    url: PAnsiChar;
    manual_url: PAnsiChar;
    support_url: PAnsiChar;
    version_str: PAnsiChar;
    description: PAnsiChar;
    features: PPAnsiChar;
  end;
  PClapPluginDescriptor = ^clap_plugin_descriptor_t;

  clap_host_t = record
    version: clap_version_t;
    host_data: pointer;
    name: PAnsiChar;
    vendor: PAnsiChar;
    url: PAnsiChar;
    version_str: PAnsiChar;
    get_extension: function(host: pointer; extension_id: PAnsiChar): pointer; cdecl;
    request_restart: procedure(host: pointer); cdecl;
    request_process: procedure(host: pointer); cdecl;
    request_callback: procedure(host: pointer); cdecl;
  end;
  PClapHost = ^clap_host_t;

  clap_plugin_t = record
    desc: PClapPluginDescriptor;
    plugin_data: pointer;
    init: function(plugin: pointer): clap_bool; cdecl;
    destroy: procedure(plugin: pointer); cdecl;
    activate: function(plugin: pointer; sample_rate: c_double;
      min_frames_count: c_uint32; max_frames_count: c_uint32): clap_bool; cdecl;
    deactivate: procedure(plugin: pointer); cdecl;
    start_processing: function(plugin: pointer): clap_bool; cdecl;
    stop_processing: procedure(plugin: pointer); cdecl;
    reset: procedure(plugin: pointer); cdecl;
    process: function(plugin: pointer; proc: PClapProcess): c_int32; cdecl;
    get_extension: function(plugin: pointer; id: PAnsiChar): pointer; cdecl;
    on_main_thread: procedure(plugin: pointer); cdecl;
  end;
  PClapPlugin = ^clap_plugin_t;

  clap_plugin_factory_t = record
    get_plugin_count: function(factory: pointer): c_uint32; cdecl;
    get_plugin_descriptor: function(factory: pointer; index: c_uint32): PClapPluginDescriptor; cdecl;
    create_plugin: function(factory: pointer; host: PClapHost; plugin_id: PAnsiChar): PClapPlugin; cdecl;
  end;
  PClapPluginFactory = ^clap_plugin_factory_t;

  clap_plugin_entry_t = record
    version: clap_version_t;
    init: function(plugin_path: PAnsiChar): clap_bool; cdecl;
    deinit: procedure; cdecl;
    get_factory: function(factory_id: PAnsiChar): pointer; cdecl;
  end;
  PClapPluginEntry = ^clap_plugin_entry_t;

implementation
end.