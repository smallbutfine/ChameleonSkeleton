unit pngload;
{ Decode a PNG file into a 32-bit top-down HBITMAP (BGRA) using fcl-image. }
{$mode Delphi}{$H+}
interface
uses Windows;

function LoadPngToHBitmap(const path: PAnsiChar): HBITMAP;

implementation
uses fpimage, fpreadpng, classes, sysutils;

function LoadPngToHBitmap(const path: PAnsiChar): HBITMAP;
var
  fs: TFileStream;
  rdr: TFPReaderPNG;
  img: TFPMemoryImage;
  bi: BITMAPINFO;
  bits: pointer;
  hbm: HBITMAP;
  dc: HDC;
  x, y, w, h: Integer;
  c: TFPColor;
  p: PByte;
begin
  Result := 0;
  if (path = nil) or (path^ = #0) or (not FileExists(path)) then Exit;

  fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  try
    rdr := TFPReaderPNG.Create;
    try
      img := TFPMemoryImage.Create(0, 0);
      try
        rdr.ImageRead(fs, img);
        w := img.Width;
        h := img.Height;
        if (w <= 0) or (h <= 0) then Exit;

        dc := GetDC(0);
        try
          FillChar(bi, SizeOf(bi), 0);
          bi.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
          bi.bmiHeader.biWidth := w;
          bi.bmiHeader.biHeight := -h; { top-down }
          bi.bmiHeader.biPlanes := 1;
          bi.bmiHeader.biBitCount := 32;
          bi.bmiHeader.biCompression := BI_RGB;
          hbm := CreateDIBSection(dc, bi, DIB_RGB_COLORS, bits, 0, 0);
          if hbm <> 0 then
          begin
            p := PByte(bits);
            for y := 0 to h - 1 do
              for x := 0 to w - 1 do
              begin
                c := img.Colors[x, y];
                p^ := c.blue shr 8;       // B
                (p + 1)^ := c.green shr 8; // G
                (p + 2)^ := c.red shr 8;   // R
                (p + 3)^ := c.alpha shr 8; // A
                p := p + 4;
              end;
            Result := hbm;
          end;
        finally
          ReleaseDC(0, dc);
        end;
      finally
        img.Free;
      end;
    finally
      rdr.Free;
    end;
  finally
    fs.Free;
  end;
end;

end.