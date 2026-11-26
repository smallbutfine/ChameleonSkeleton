# CLAP Skeleton (Lazarus / Free Pascal DLL)

Minimal, compilable **CLAP** audio-effect plugin written in Pascal. It is a
passthrough (silence-in → silence-out / input copied to output) with the full
CLAP entry → factory → plugin wiring in place, ready for you to drop your DSP
into `plugin_process`.

ABI translated from the official headers (free-audio/clap, CLAP 1.2.x).

## Files
- `clap.pas` — CLAP ABI types (core + params + events + gui + state).
- `clapplugin.pas` — entry, factory, plugin, params, state, gui wiring, gain DSP.
- `guiwin.pas` — embedded plugin window: Win32 (GDI), Linux/X11, macOS stub.
- `pngload.pas` — PNG → HBITMAP decoder (fcl-image, Win32).
- `hostcb.pas` — FPC-mode helper to call cdecl proc-vars (Delphi-mode FPC bug).
- `clap_skeleton.lpr` — the `library` that exports `clap_entry`.
- `clap_skeleton.dll` — built x64 DLL (exports `clap_entry`).

## Build
From this directory, with Free Pascal:

```
# 64-bit (modern DAWs)
"C:\fpcupdeluxe\fpc\bin\i386-win32\fpc.exe" -Px86_64 -O2 clap_skeleton.lpr

# 32-bit
"C:\fpcupdeluxe\fpc\bin\i386-win32\fpc.exe" -O2 clap_skeleton.lpr
```

Or with Lazarus: create a `Library` project, add `clap.pas` + `clapplugin.pas`,
set the library name to `clap_skeleton`, and build.

The output is `clap_skeleton.dll`. The host resolves the exported symbol
`clap_entry` (a `clap_plugin_entry_t` **variable**, not a function).

## Install / test
Copy the DLL into a CLAP search path, e.g. on Windows:
- `%LOCALAPPDATA%\Programs\Common\CLAP\`
- `%COMMONPROGRAMFILES%\CLAP\`

or set `CLAP_PATH` to its folder. Then rescan plugins in a CLAP-capable host
(Bitwig, Reaper, Studio One, FL Studio). It appears as
**“Chameleon Skeleton”** (id `com.example.chameleonskeleton`).

## What's implemented
- **clap.params**: one automatable `Gain` parameter (0..1, default 0.5),
  with `count/get_info/get_value/value_to_text/text_to_value/flush`.
  Incoming `CLAP_EVENT_PARAM_VALUE` events are applied in `process()` and
  `flush()`, and the gain is multiplied into the audio. When the GUI knob
  changes the gain it calls `host->request_callback`; `on_main_thread` then
  requests a process cycle, during which `process()` emits
  `PARAM_GESTURE_BEGIN` / `PARAM_VALUE` / `PARAM_GESTURE_END` to `out_events`
  so the DAW value tracks the knob.
- **clap.gui**: real **Win32** embedded window (`guiwin.pas`): creates a child
  HWND, embeds it into the host HWND via `set_parent`, paints a background +
  a gain knob (GDI), and updates the gain on vertical drag. If `background.png`
  and `knob.png` are present (loaded from the working directory via `pngload.pas`)
  they are alpha-blended in; otherwise a generated knob is drawn. The knob
  updates the gain and the host is notified (see params below).

## Linux build (native, recommended)
The Windows cross-linker can't link a Linux `.so` on this host (the fpcupdeluxe
Linux sysroot lacks `ld-linux`, and `ppcross -k--sysroot` isn't applied). Build
natively on Linux/WSL instead (needs `fpc`):
```
./build_linux.sh      # -> clap_skeleton.clap
```
The code is platform-independent and already compiles via the cross, so native
`fpc` produces the same `.so` with `clap_entry` exported.

## Wrappers (more formats)
`build_all.bat` has a `:wrap` stage that uses
[clap-wrapper](https://github.com/free-audio/clap-wrapper) to turn the CLAP into
a **VST3**. It auto-uses a `deps/` checkout if present, otherwise it skips
cleanly. To build the Windows VST3 it needs (already cloned into `deps/` here):
- `deps/clap-wrapper`, `deps/clap` (CLAP SDK), `deps/vst3sdk` (VST3 SDK **3.7.x** —
  3.8.x fails on GCC with an ambiguous `iid`), and `cmake` + Ninja + a C++ compiler.

The Windows VST3 is produced as `dist/win64/clap_skeleton.vst3` and copied to
`Deploy/`. Notes:
- Wrappers are **platform-native**: this builds the **Windows VST3**. Build the
  **macOS AU/VST3** and **Linux VST3** with the same clap-wrapper command on
  those OSes (CMake can't cross-build them from Windows).
- **AUv2** is optional: add `-DCLAP_WRAPPER_BUILD_AUV2=ON` + an `AudioUnitSDK`.
- **AAX** is intentionally not supported. **LV2** is not a clap-wrapper target.

## Platform status
- **Windows (win64):** builds via `build_all.bat`, `clap_entry` exported (`.clap` = the DLL). Compile-verified.
- **Linux (x64):** builds via `build_all.bat`, `clap_entry` in the ELF `.dynsym`
  (`.clap` = the `.so`). Compile-verified (loads as a CLAP host).
- **macOS (intel/arm64):** builds into `.clap` bundles, `_clap_entry` exported.
  The **Cocoa GUI is best-effort and UNVERIFIED at runtime** — build/test on a Mac.

Build all four with `CI=true ./build_all.bat` (add `NO_VERSION_BUMP=1` to keep the
version). `linux-arm` (32-bit) is intentionally not built (the image is 64-bit).
- **clap.state**: `save`/`load` persist the gain **and the GUI size** as a
  24-byte record (`'C','H','S','1'` magic + version 2 + gain double + width +
  height), so sessions/presets recall the knob and window size.
  `plugin_get_extension` returns `@g_state` for `"clap.state"`.

## Where to put your DSP
- `plugin_process` in `clapplugin.pas` — read `proc^.audio_inputs`, write
  `proc^.audio_outputs`, `proc^.frames_count` frames. Replace the passthrough
  copy with your DSP call.
- `plugin_activate` — you get `sample_rate`, `min/max_frames_count`; prepare
  your DSP here.
- `plugin_get_extension` — return `@g_params`, `@g_gui`, `@g_state`, … once you
  implement those extensions (params for knobs, gui for the bitmap editor,
  state for save/restore).

## Notes
- `clap_entry` is exported as a **variable** via the `exports` clause. If a
  particular host/toolchain cannot see it, add a `.def` file exporting
  `clap_entry` and link with `-kDEF:clap.def`.
- The ABI structs must stay in the exact field order of the C headers; only the
  subset needed for a basic effect is declared here.