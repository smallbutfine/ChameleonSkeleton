unit guiwin;
{ Win32 embedded plugin window for the CLAP GUI extension.
  Creates a child HWND, embeds it into the host HWND, paints a background +
  a gain knob, and updates the gain on vertical drag.
  On non-Windows targets these become no-op stubs so the source stays portable. }
{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}
interface

type
  TGuiWin = record
    hwnd: pointer;   // HWND as pointer (nil = not created)
    gain: ^Double;   // pointer to the plugin's gain value
    pending: ^Boolean; // set True on edit; plugin emits the param event
    host: pointer;   // clap_host_t* (for request_callback)
    request_cb: procedure(host: pointer); cdecl;
    dragging: Boolean;
    startY: Integer;
    startGain: Double;
    bgBmp: pointer;   // HBITMAP background (nil = not loaded)
    knobBmp: pointer; // HBITMAP knob sprite
    loaded: Boolean;  // artwork load attempted
    disp: pointer;    // X11 Display* (Linux)
    win: UInt64;      // X11 Window (Linux)
    gc: pointer;      // X11 GC (Linux)
    gui_w: LongWord;  // GUI client width
    gui_h: LongWord;  // GUI client height
  end;
  PGuiWin = ^TGuiWin;

function GuiCreate(var gw: TGuiWin; width, height: LongWord): Boolean;
procedure GuiDestroy(var gw: TGuiWin);
procedure GuiSetParent(var gw: TGuiWin; parent: pointer);
procedure GuiShow(var gw: TGuiWin; showIt: Boolean);
procedure GuiPump(var gw: TGuiWin);

implementation

{$IFDEF MSWINDOWS}
uses Windows, SysUtils, hostcb, pngload;

const
  GWLP_USERDATA = -21;

type
  TBlendFunction = record
    BlendOp: Byte;
    BlendFlags: Byte;
    SourceConstantAlpha: Byte;
    AlphaFormat: Byte;
  end;

function AlphaBlend(hdcDest: HDC; x0, y0, w0, h0: Integer;
  hdcSrc: HDC; x1, y1, w1, h1: Integer; blend: TBlendFunction): BOOL;
  stdcall; external 'msimg32.dll' name 'AlphaBlend';

var
  g_classRegistered: Boolean = False;
  g_className: PAnsiChar = 'ChameleonSkeletonGui';

function ClampGain(v: Double): Double;
begin
  if v < 0 then Exit(0);
  if v > 1 then Exit(1);
  Result := v;
end;

procedure PaintClient(hwnd: HWND; gw: PGuiWin);
var
  ps: PAINTSTRUCT;
  dc, memdc: HDC;
  rc: RECT;
  bg, knob: HBRUSH;
  oldBrush, oldBmp: HGDIOBJ;
  cx, cy, r, kw, kh: Integer;
  s: ShortString;
  ang: Double;
  ix, iy: Integer;
  bm: BITMAP;
  blend: TBlendFunction;
begin
  if not gw^.loaded then
  begin
    gw^.loaded := True;
    gw^.bgBmp := pointer(LoadPngToHBitmap(PAnsiChar('background.png')));
    gw^.knobBmp := pointer(LoadPngToHBitmap(PAnsiChar('knob.png')));
  end;

  dc := BeginPaint(hwnd, @ps);
  try
    GetClientRect(hwnd, @rc);
    cx := (rc.right - rc.left) div 2;
    cy := (rc.bottom - rc.top) div 2;

    { background: PNG if present, else dark fill }
    if gw^.bgBmp <> nil then
    begin
      memdc := CreateCompatibleDC(dc);
      oldBmp := SelectObject(memdc, HBITMAP(gw^.bgBmp));
      BitBlt(dc, 0, 0, rc.right, rc.bottom, memdc, 0, 0, SRCCOPY);
      SelectObject(memdc, oldBmp);
      DeleteDC(memdc);
    end
    else
    begin
      bg := CreateSolidBrush(RGB(40, 40, 40));
      FillRect(dc, rc, bg);
      DeleteObject(bg);
    end;

    { knob: PNG sprite (alpha) centered, else generated knob }
    if gw^.knobBmp <> nil then
    begin
      GetObject(HBITMAP(gw^.knobBmp), SizeOf(BITMAP), @bm);
      kw := bm.bmWidth;
      kh := bm.bmHeight;
      memdc := CreateCompatibleDC(dc);
      oldBmp := SelectObject(memdc, HBITMAP(gw^.knobBmp));
      blend.BlendOp := 0;
      blend.BlendFlags := 0;
      blend.SourceConstantAlpha := 255;
      blend.AlphaFormat := 1; { AC_SRC_ALPHA }
      AlphaBlend(dc, cx - kw div 2, cy - kh div 2, kw, kh,
        memdc, 0, 0, kw, kh, blend);
      SelectObject(memdc, oldBmp);
      DeleteDC(memdc);
    end
    else
    begin
      r := 80;
      knob := CreateSolidBrush(RGB(90, 90, 90));
      oldBrush := SelectObject(dc, knob);
      Ellipse(dc, cx - r, cy - r, cx + r, cy + r);
      SelectObject(dc, oldBrush);
      DeleteObject(knob);
    end;

    { gain indicator + value text (always drawn on top) }
    if gw^.gain <> nil then
    begin
      ang := (-135.0 + 270.0 * ClampGain(gw^.gain^)) * Pi / 180.0;
      ix := cx + Round(60.0 * Sin(ang));
      iy := cy - Round(60.0 * Cos(ang));
      MoveToEx(dc, cx, cy, nil);
      LineTo(dc, ix, iy);
      Str(ClampGain(gw^.gain^):0:2, s);
      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, RGB(230, 230, 230));
      TextOut(dc, cx - 20, cy + 100, PAnsiChar(@s[1]), Length(s));
    end;
  finally
    EndPaint(hwnd, @ps);
  end;
end;

{ Call the host's request_callback (kept out of the stdcall window proc: FPC
  will not call a cdecl procedure-variable from a stdcall routine on win64).
  The actual call is in hostcb (FPC mode) to avoid a Delphi-mode FPC bug. }
procedure DoRequestCallback(gw: PGuiWin);
begin
  if gw = nil then Exit;
  CallRequest(gw^.request_cb, gw^.host);
end;

function MainWndProc(hwnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  gw: PGuiWin;
  lp: Integer;
  y: Integer;
  ng: Double;
begin
  gw := PGuiWin(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
  case msg of
    WM_PAINT:
      begin
        if gw <> nil then PaintClient(hwnd, gw);
        Result := 0;
      end;
    WM_LBUTTONDOWN:
      begin
        if gw <> nil then
        begin
          lp := Integer(lParam);
          y := SmallInt((lp shr 16) and $FFFF);
          gw^.dragging := True;
          gw^.startY := y;
          if gw^.gain <> nil then gw^.startGain := gw^.gain^;
        end;
        Result := 0;
      end;
    WM_MOUSEMOVE:
      begin
        if (gw <> nil) and gw^.dragging and (gw^.gain <> nil) then
        begin
          lp := Integer(lParam);
          y := SmallInt((lp shr 16) and $FFFF);
          ng := ClampGain(gw^.startGain + (gw^.startY - y) / 200.0);
          gw^.gain^ := ng;
          if gw^.pending <> nil then gw^.pending^ := True;
          DoRequestCallback(gw);
          InvalidateRect(hwnd, nil, True);
        end;
        Result := 0;
      end;
    WM_LBUTTONUP:
      begin
        if gw <> nil then gw^.dragging := False;
        Result := 0;
      end;
  else
    Result := DefWindowProcA(hwnd, msg, wParam, lParam);
  end;
end;

function GuiCreate(var gw: TGuiWin; width, height: LongWord): Boolean;
var
  wc: WNDCLASSEXA;
  inst: HINST;
  title: ShortString;
begin
  Result := False;
  inst := GetModuleHandle(nil);
  if not g_classRegistered then
  begin
    FillChar(wc, SizeOf(wc), 0);
    wc.cbSize := SizeOf(wc);
    wc.style := CS_HREDRAW or CS_VREDRAW;
    wc.lpfnWndProc := @MainWndProc;
    wc.hInstance := inst;
    wc.hCursor := LoadCursorA(0, IDC_ARROW);
    wc.lpszClassName := g_className;
    if RegisterClassExA(wc) = 0 then
    begin
      if GetLastError <> ERROR_CLASS_ALREADY_EXISTS then Exit;
    end;
    g_classRegistered := True;
  end;

  title := 'Chameleon Skeleton';
  gw.hwnd := pointer(CreateWindowExA(0, g_className, PAnsiChar(@title[1]),
    WS_CHILD or WS_CLIPSIBLINGS,
    0, 0, Integer(width), Integer(height),
    0, 0, inst, nil));
  if gw.hwnd = nil then Exit;

  SetWindowLongPtrA(HWND(gw.hwnd), GWLP_USERDATA, LONG_PTR(@gw));
  Result := True;
end;

procedure GuiDestroy(var gw: TGuiWin);
begin
  if gw.hwnd <> nil then
  begin
    DestroyWindow(HWND(gw.hwnd));
    gw.hwnd := nil;
  end;
end;

procedure GuiSetParent(var gw: TGuiWin; parent: pointer);
begin
  if (gw.hwnd <> nil) and (parent <> nil) then
    SetParent(HWND(gw.hwnd), HWND(parent));
end;

procedure GuiShow(var gw: TGuiWin; showIt: Boolean);
begin
  if gw.hwnd <> nil then
  begin
    if showIt then
      ShowWindow(HWND(gw.hwnd), SW_SHOW)
    else
      ShowWindow(HWND(gw.hwnd), SW_HIDE);
  end;
end;

procedure GuiPump(var gw: TGuiWin); begin end;

{$ELSE}
{$IFDEF LINUX}
{ X11 embedded window (Linux). The host embeds our window via XReparentWindow;
  GuiPump must be called (e.g. from on_main_thread) to process X events. }
uses xlib, x, sysutils, hostcb;

function ClampGain(v: Double): Double;
begin
  if v < 0 then Exit(0);
  if v > 1 then Exit(1);
  Result := v;
end;

procedure DoRequestCallback(gw: PGuiWin);
begin
  if gw = nil then Exit;
  CallRequest(gw^.request_cb, gw^.host);
end;

procedure Redraw(gw: PGuiWin);
var
  dpy: PDisplay;
  w: TWindow;
  g: TGC;
  font: PXFontStruct;
  s: ShortString;
  cx, cy, r, ix, iy: Integer;
  ang: Double;
begin
  if (gw = nil) or (gw^.disp = nil) then Exit;
  dpy := PDisplay(gw^.disp);
  w := TWindow(gw^.win);
  g := TGC(gw^.gc);
  XSetForeground(dpy, g, $282828);
  XFillRectangle(dpy, w, g, 0, 0, 800, 600);
  cx := 400; cy := 300; r := 80;
  XSetForeground(dpy, g, $5A5A5A);
  XFillArc(dpy, w, g, cx - r, cy - r, 2 * r, 2 * r, 0, 360 * 64);
  if gw^.gain <> nil then
  begin
    ang := (-135.0 + 270.0 * ClampGain(gw^.gain^)) * Pi / 180.0;
    ix := cx + Round(60.0 * Sin(ang));
    iy := cy - Round(60.0 * Cos(ang));
    XSetForeground(dpy, g, $E6E6E6);
    XDrawLine(dpy, w, g, cx, cy, ix, iy);
    Str(ClampGain(gw^.gain^):0:2, s);
    font := XLoadQueryFont(dpy, PAnsiChar('fixed'));
    if font <> nil then
    begin
      XSetFont(dpy, g, font^.fid);
      XDrawString(dpy, w, g, cx - 20, cy + 100, PAnsiChar(@s[1]), Length(s));
    end;
  end;
  XFlush(dpy);
end;

function GuiCreate(var gw: TGuiWin; width, height: LongWord): Boolean;
var
  dpy: PDisplay;
begin
  Result := False;
  dpy := XOpenDisplay(nil);
  if dpy = nil then Exit;
  gw.disp := dpy;
  gw.win := UInt64(XCreateSimpleWindow(dpy, XDefaultRootWindow(dpy), 0, 0, width, height, 0, 0, 0));
  gw.gc := XCreateGC(dpy, TWindow(gw.win), 0, nil);
  XSelectInput(dpy, TWindow(gw.win), ExposureMask or ButtonPressMask or ButtonReleaseMask or PointerMotionMask);
  gw.loaded := True; { no PNG on X11 yet; generated knob }
  Result := True;
end;

procedure GuiDestroy(var gw: TGuiWin);
begin
  if gw.disp <> nil then
  begin
    if gw.win <> 0 then XDestroyWindow(PDisplay(gw.disp), TWindow(gw.win));
    XCloseDisplay(PDisplay(gw.disp));
    gw.disp := nil; gw.win := 0; gw.gc := nil;
  end;
end;

procedure GuiSetParent(var gw: TGuiWin; parent: pointer);
begin
  if (gw.disp <> nil) and (parent <> nil) then
    XReparentWindow(PDisplay(gw.disp), TWindow(gw.win), TWindow(UInt64(parent)), 0, 0);
end;

procedure GuiShow(var gw: TGuiWin; showIt: Boolean);
begin
  if gw.disp <> nil then
  begin
    if showIt then XMapWindow(PDisplay(gw.disp), TWindow(gw.win))
    else XUnmapWindow(PDisplay(gw.disp), TWindow(gw.win));
    XFlush(PDisplay(gw.disp));
  end;
end;

procedure GuiPump(var gw: TGuiWin);
var
  ev: TXEvent;
begin
  if gw.disp = nil then Exit;
  while XPending(PDisplay(gw.disp)) > 0 do
  begin
    XNextEvent(PDisplay(gw.disp), @ev);
    case ev._type of
      Expose: Redraw(@gw);
      ButtonPress:
        begin
          gw.dragging := True;
          gw.startY := ev.xbutton.y;
          if gw.gain <> nil then gw.startGain := gw.gain^;
        end;
      ButtonRelease: gw.dragging := False;
      MotionNotify:
        if gw.dragging and (gw.gain <> nil) then
        begin
          gw.gain^ := ClampGain(gw.startGain + (gw.startY - ev.xmotion.y) / 200.0);
          if gw.pending <> nil then gw.pending^ := True;
          DoRequestCallback(@gw);
          Redraw(@gw);
        end;
    end;
  end;
end;

{$ELSE}
{$IFDEF DARWIN}
{ macOS Cocoa GUI - BEST EFFORT, UNVERIFIED (no Cocoa SDK on this build host).
  Creates a custom NSView subclass via the Objective-C runtime and embeds it
  into the host NSView. Draws with CoreGraphics. Build & test on a Mac. }
uses sysutils, hostcb;

type
  CGFloat = Double;
  CGPoint = record x, y: CGFloat; end;
  CGSize = record width, height: CGFloat; end;
  CGRect = record origin: CGPoint; size: CGSize; end;
  id = Pointer;
  SEL = Pointer;

const
  OBJC_ASSOCIATION_ASSIGN = 0;

function objc_getClass(name: MarshaledAString): id; cdecl; external 'libobjc.A.dylib';
function sel_registerName(name: MarshaledAString): SEL; cdecl; external 'libobjc.A.dylib';
function objc_msgSend(receiver: id; op: SEL): id; cdecl; varargs; external 'libobjc.A.dylib';
function objc_allocateClassPair(superclass: id; name: MarshaledAString; extraBytes: LongWord): id; cdecl; external 'libobjc.A.dylib';
function class_addMethod(cls: id; name: SEL; imp: Pointer; types: MarshaledAString): Byte; cdecl; external 'libobjc.A.dylib';
procedure objc_registerClassPair(cls: id); cdecl; external 'libobjc.A.dylib';
function objc_setAssociatedObject(object_: id; key: Pointer; value: id; policy: LongWord): id; cdecl; external 'libobjc.A.dylib';
function objc_getAssociatedObject(object_: id; key: Pointer): id; cdecl; external 'libobjc.A.dylib';

procedure CGContextSetRGBFillColor(ctx: Pointer; r, g, b, a: CGFloat); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextSetRGBFillColor';
procedure CGContextFillRect(ctx: Pointer; rect: CGRect); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextFillRect';
procedure CGContextFillEllipseInRect(ctx: Pointer; rect: CGRect); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextFillEllipseInRect';
procedure CGContextSetLineWidth(ctx: Pointer; w: CGFloat); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextSetLineWidth';
procedure CGContextMoveToPoint(ctx: Pointer; x, y: CGFloat); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextMoveToPoint';
procedure CGContextAddLineToPoint(ctx: Pointer; x, y: CGFloat); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextAddLineToPoint';
procedure CGContextStrokePath(ctx: Pointer); cdecl; external '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices' name 'CGContextStrokePath';

var
  g_viewClass: id;
  g_key: Pointer;
  g_assocKey: Byte;
  g_selAlloc, g_selInitWithFrame, g_selAddSubview, g_selSetHidden,
  g_selRemoveFromSuperview, g_selRelease, g_selCurrentContext,
  g_selGraphicsContext, g_selSetNeedsDisplay, g_selDrawRect,
  g_selMouseDown, g_selMouseDragged, g_selMouseUp: SEL;

function CGRectMake(x, y, w, h: CGFloat): CGRect;
begin
  Result.origin.x := x; Result.origin.y := y;
  Result.size.width := w; Result.size.height := h;
end;

function ClampGain(v: Double): Double;
begin
  if v < 0 then Exit(0);
  if v > 1 then Exit(1);
  Result := v;
end;

procedure DoRequestCallback(gw: PGuiWin);
begin
  if gw = nil then Exit;
  CallRequest(gw^.request_cb, gw^.host);
end;

procedure chameleon_drawRect(self: id; _cmd: SEL; dirty: CGRect); cdecl;
var
  g: PGuiWin;
  ctx: id;
  cx, cy, r, ix, iy, ang: Double;
begin
  g := PGuiWin(objc_getAssociatedObject(self, g_key));
  if g = nil then Exit;
  ctx := objc_msgSend(objc_msgSend(objc_getClass('NSGraphicsContext'), g_selCurrentContext), g_selGraphicsContext);
  CGContextSetRGBFillColor(ctx, 0.16, 0.16, 0.16, 1);
  CGContextFillRect(ctx, CGRectMake(0, 0, 800, 600));
  cx := 400; cy := 300; r := 80;
  CGContextSetRGBFillColor(ctx, 0.35, 0.35, 0.35, 1);
  CGContextFillEllipseInRect(ctx, CGRectMake(cx - r, cy - r, 2 * r, 2 * r));
  if g^.gain <> nil then
  begin
    ang := (-135.0 + 270.0 * ClampGain(g^.gain^)) * Pi / 180.0;
    ix := cx + 60.0 * Sin(ang);
    iy := cy - 60.0 * Cos(ang);
    CGContextSetRGBFillColor(ctx, 0.9, 0.9, 0.9, 1);
    CGContextSetLineWidth(ctx, 2);
    CGContextMoveToPoint(ctx, cx, cy);
    CGContextAddLineToPoint(ctx, ix, iy);
    CGContextStrokePath(ctx);
  end;
end;

procedure chameleon_mouseDown(self: id; _cmd: SEL; ev: id); cdecl;
var g: PGuiWin;
begin
  g := PGuiWin(objc_getAssociatedObject(self, g_key));
  if g = nil then Exit;
  g^.dragging := True;
  if g^.gain <> nil then g^.startGain := g^.gain^;
end;

procedure chameleon_mouseDragged(self: id; _cmd: SEL; ev: id); cdecl;
var g: PGuiWin;
begin
  g := PGuiWin(objc_getAssociatedObject(self, g_key));
  if (g = nil) or (not g^.dragging) or (g^.gain = nil) then Exit;
  g^.gain^ := ClampGain(g^.gain^ + 0.01);
  if g^.pending <> nil then g^.pending^ := True;
  DoRequestCallback(g);
  objc_msgSend(self, g_selSetNeedsDisplay, Byte(1));
end;

procedure chameleon_mouseUp(self: id; _cmd: SEL; ev: id); cdecl;
var g: PGuiWin;
begin
  g := PGuiWin(objc_getAssociatedObject(self, g_key));
  if g <> nil then g^.dragging := False;
end;

procedure RegisterViewClass;
var sup: id;
begin
  if g_viewClass <> nil then Exit;
  g_selAlloc := sel_registerName('alloc');
  g_selInitWithFrame := sel_registerName('initWithFrame:');
  g_selAddSubview := sel_registerName('addSubview:');
  g_selSetHidden := sel_registerName('setHidden:');
  g_selRemoveFromSuperview := sel_registerName('removeFromSuperview');
  g_selRelease := sel_registerName('release');
  g_selCurrentContext := sel_registerName('currentContext');
  g_selGraphicsContext := sel_registerName('graphicsContext');
  g_selSetNeedsDisplay := sel_registerName('setNeedsDisplay:');
  g_selDrawRect := sel_registerName('drawRect:');
  g_selMouseDown := sel_registerName('mouseDown:');
  g_selMouseDragged := sel_registerName('mouseDragged:');
  g_selMouseUp := sel_registerName('mouseUp:');
  g_key := @g_assocKey;
  sup := objc_getClass('NSView');
  g_viewClass := objc_allocateClassPair(sup, 'ChameleonView', 0);
  class_addMethod(g_viewClass, g_selDrawRect, @chameleon_drawRect, 'v@:{CGRect={CGPoint=dd}{CGSize=dd}}');
  class_addMethod(g_viewClass, g_selMouseDown, @chameleon_mouseDown, 'v@:@');
  class_addMethod(g_viewClass, g_selMouseDragged, @chameleon_mouseDragged, 'v@:@');
  class_addMethod(g_viewClass, g_selMouseUp, @chameleon_mouseUp, 'v@:@');
  objc_registerClassPair(g_viewClass);
end;

function GuiCreate(var gw: TGuiWin; width, height: LongWord): Boolean;
var view: id;
begin
  Result := False;
  RegisterViewClass;
  view := objc_msgSend(g_viewClass, g_selAlloc);
  view := objc_msgSend(view, g_selInitWithFrame, CGRectMake(0, 0, width, height));
  if view = nil then Exit;
  objc_setAssociatedObject(view, g_key, Pointer(@gw), OBJC_ASSOCIATION_ASSIGN);
  gw.hwnd := view;
  Result := True;
end;

procedure GuiDestroy(var gw: TGuiWin);
begin
  if gw.hwnd <> nil then
  begin
    objc_msgSend(gw.hwnd, g_selRemoveFromSuperview);
    objc_msgSend(gw.hwnd, g_selRelease);
    gw.hwnd := nil;
  end;
end;

procedure GuiSetParent(var gw: TGuiWin; parent: pointer);
begin
  if (gw.hwnd <> nil) and (parent <> nil) then
    objc_msgSend(parent, g_selAddSubview, gw.hwnd);
end;

procedure GuiShow(var gw: TGuiWin; showIt: Boolean);
begin
  if gw.hwnd <> nil then
    objc_msgSend(gw.hwnd, g_selSetHidden, Byte(not showIt));
end;

procedure GuiPump(var gw: TGuiWin); begin end;

{$ELSE}
{ Other platforms: no-op stubs. }
function GuiCreate(var gw: TGuiWin; width, height: LongWord): Boolean;
begin
  gw.hwnd := nil;
  Result := False;
end;
procedure GuiDestroy(var gw: TGuiWin); begin gw.hwnd := nil; end;
procedure GuiSetParent(var gw: TGuiWin; parent: pointer); begin end;
procedure GuiShow(var gw: TGuiWin; showIt: Boolean); begin end;
procedure GuiPump(var gw: TGuiWin); begin end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

end.