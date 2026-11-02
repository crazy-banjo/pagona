// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnTheme;

{ Colors. Two kinds:

    Editor themes   how SQL is colored: Plume (the default) and Classic
                    (the original look: bold and italic only, no color).
    Interface       the window's own colors: surfaces, lines, the accent,
                    and the environment colors (PROD / TEST / DEV).

  Color is never the only signal: editor styles keep bold and italic, and
  every environment color comes with the environment's name in words. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynHighlighterSQL, SynEditHighlighter, pgnTypes;

const
  ThemePlume   = 'Plume';
  ThemeClassic = 'Classic';
  ThemeNames: array[0..1] of string = (ThemePlume, ThemeClassic);

  // interface colors (see docs/design.md); the frame's colors are the
  // look's (variables below)
  clPgnWork      = clWhite;             // #FFFFFF  editor, grid
  clPgnGridFixed = TColor($00FAF8F7);   // #F7F8FA  grid titles and row numbers (same in every look)
  clPgnGridLines = TColor($00B4A8A0);   // #A0A8B4  lines between grid cells
  clPgnGridHead  = TColor($0094887F);   // #7F8894  line under grid titles
  clPgnAccent    = TColor($009E4E1D);   // #1D4E9E  Pagona blue
  clPgnSelection = TColor($00F7E7DC);   // #DCE7F7  tree, grid selection
  clPgnText      = TColor($003F3024);   // #24303F  toolbar text
  clPgnMuted     = TColor($0080746B);   // #6B7480  captions, disabled
  clPgnHover     = TColor($00F6EEE9);   // #E9EEF6  button under the mouse
  clPgnDanger    = TColor($002A2AB0);   // #B02A2A
  clPgnCaution   = TColor($000B73A8);   // #A8730B
  clPgnSafe      = TColor($00306B2E);   // #2E6B30
  clPgnShade     = TColor($00FCF6F2);   // #F2F6FC  statement that will run

  // looks: the frame around the work, one per layout
  LookMatchLayout = 'Match layout';
  LookPlume       = 'Plume';
  LookAmphibian   = 'Amphibian';
  LookSeattle     = 'Seattle';
  LookNames: array[0..2] of string = (LookPlume, LookAmphibian, LookSeattle);

var
  // the frame, set by ApplyLook (Plume's until then)
  clPgnSurface: TColor = TColor($00FAF8F7);     // panels
  clPgnLines: TColor = TColor($00E1DBD7);       // borders
  clPgnBar: TColor = TColor($00FAF8F7);         // toolbars
  clPgnHeader: TColor = TColor($00FAF8F7);      // panel headers, title strips
  clPgnHeaderText: TColor = TColor($003F3024);
  clPgnStatus: TColor = TColor($00FAF8F7);      // the status bar
  clPgnStatusText: TColor = TColor($003F3024);
  clPgnStatusLines: TColor = TColor($00E1DBD7);
  clPgnMenu: TColor = clNone;                   // the menu bar (Windows); clNone = the system's

{ Sets the frame's colors for a look (Plume, Amphibian or Seattle). }
procedure ApplyLook(const ALook: string);

{ The look in use for a look setting and a layout. }
function EffectiveLook(const ALookSetting, ALayout: string): string;

type
  { The look of one environment: band background, its border and the text. }
  TpgnEnvLook = record
    Back: TColor;
    Border: TColor;
    Text: TColor;
  end;

function EnvironmentLook(AEnv: TpgnEnvironment): TpgnEnvLook;

{ Colors (or uncolors) a SQL highlighter. Unknown names fall back to Plume. }
procedure ApplyEditorTheme(AHighlighter: TSynSQLSyn; const ATheme: string);

{ Asks Windows for smoothed (ClearType) text in this font, whatever the
  system's own smoothing setting. Other widget sets ignore it. }
procedure SmoothFont(AFont: TFont);

function NormalizeThemeName(const AValue: string): string;

implementation

function Hex(const AValue: string): TColor;
var
  V: LongInt;
begin
  V := StrToInt('$' + AValue);
  Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

procedure ApplyLook(const ALook: string);
begin
  if SameText(ALook, LookAmphibian) then
  begin
    // Toad's slightly older Windows: warm grays, crisper lines
    clPgnSurface := Hex('ECE9E2');
    clPgnLines := Hex('ADA9A0');
    clPgnBar := Hex('E4E1DA');
    clPgnHeader := Hex('D6DEE8');
    clPgnHeaderText := Hex('1B2C44');
    clPgnStatus := Hex('E4E1DA');
    clPgnStatusText := Hex('000000');
    clPgnStatusLines := Hex('ADA9A0');
    clPgnMenu := Hex('F0F0F0');
  end
  else if SameText(ALook, LookSeattle) then
  begin
    // SSMS 22's light blue, dark status bar
    clPgnSurface := Hex('EEF3F9');
    clPgnLines := Hex('A9BCD3');
    clPgnBar := Hex('D9E4F1');
    clPgnHeader := Hex('D9E4F1');
    clPgnHeaderText := Hex('0F1D2E');
    clPgnStatus := Hex('3C4654');
    clPgnStatusText := Hex('FFFFFF');
    clPgnStatusLines := Hex('5D6878');
    clPgnMenu := Hex('C9D8EA');
  end
  else
  begin
    clPgnSurface := Hex('F7F8FA');
    clPgnLines := Hex('D7DBE1');
    clPgnBar := Hex('F7F8FA');
    clPgnHeader := Hex('F7F8FA');
    clPgnHeaderText := Hex('24303F');
    clPgnStatus := Hex('F7F8FA');
    clPgnStatusText := Hex('24303F');
    clPgnStatusLines := Hex('D7DBE1');
    clPgnMenu := clNone;
  end;
end;

function EffectiveLook(const ALookSetting, ALayout: string): string;
var
  I: Integer;
begin
  for I := 0 to High(LookNames) do
  begin
    if SameText(ALookSetting, LookNames[I]) then
    begin
      Result := LookNames[I];
      Exit;
    end;
  end;
  // Match layout
  if SameText(ALayout, LookAmphibian) then
  begin
    Result := LookAmphibian;
  end
  else if SameText(ALayout, LookSeattle) then
  begin
    Result := LookSeattle;
  end
  else
  begin
    Result := LookPlume;
  end;
end;

procedure SmoothFont(AFont: TFont);
begin
  AFont.Quality := fqCleartypeNatural;
end;

function EnvironmentLook(AEnv: TpgnEnvironment): TpgnEnvLook;
begin
  case AEnv of
    enProduction:
      begin
        Result.Back := TColor($00E3E3FB);     // #FBE3E3
        Result.Border := clPgnDanger;
        Result.Text := TColor($001C1C8A);     // #8A1C1C
      end;
    enTest:
      begin
        Result.Back := TColor($00D6F2FF);     // #FFF2D6
        Result.Border := clPgnCaution;
        Result.Text := TColor($0000527A);     // #7A5200
      end;
    enDevelopment:
      begin
        Result.Back := TColor($00E3F0E2);     // #E2F0E3
        Result.Border := clPgnSafe;
        Result.Text := TColor($00214D1F);     // #1F4D21
      end;
  else
    begin
      Result.Back := TColor($00F3F0EE);       // #EEF0F3
      Result.Border := clPgnLines;
      Result.Text := clPgnText;
    end;
  end;
end;

procedure SetAttr(A: TSynHighlighterAttributes; AColor: TColor; AStyle: TFontStyles);
begin
  A.Foreground := AColor;
  A.Background := clNone;
  A.Style := AStyle;
end;

procedure ApplyClassic(H: TSynSQLSyn);
begin
  // the highlighter's own defaults: no color, keywords bold, comments italic
  SetAttr(H.CommentAttri, clNone, [fsItalic]);
  SetAttr(H.DataTypeAttri, clNone, [fsBold]);
  SetAttr(H.DefaultPackageAttri, clNone, [fsBold]);
  SetAttr(H.ExceptionAttri, clNone, [fsItalic]);
  SetAttr(H.FunctionAttri, clNone, [fsBold]);
  SetAttr(H.IdentifierAttri, clNone, []);
  SetAttr(H.KeyAttri, clNone, [fsBold]);
  SetAttr(H.NumberAttri, clNone, []);
  SetAttr(H.PLSQLAttri, clNone, [fsBold]);
  SetAttr(H.SQLPlusAttri, clNone, [fsBold]);
  SetAttr(H.StringAttri, clNone, []);
  SetAttr(H.SymbolAttri, clNone, []);
  SetAttr(H.TableNameAttri, clNone, []);
  SetAttr(H.VariableAttri, clNone, []);
end;

procedure ApplyPlume(H: TSynSQLSyn);
const
  Keyword  = TColor($009E4E1D);   // #1D4E9E blue
  Comment  = TColor($00306B2E);   // #2E6B30 green
  Str      = TColor($000F42A3);   // #A3420F rust
  Number   = TColor($00A33F6E);   // #6E3FA3 purple
  Func     = TColor($0000527A);   // #7A5200 brown
  DataType = TColor($007A6500);   // #00657A teal
  Obj      = TColor($005C1F9B);   // #9B1F5C plum
  Variable = TColor($0000645C);   // #5C6400 olive
  Plain    = TColor($001A1A1A);   // #1A1A1A
  Symbol   = TColor($004A4A4A);   // #4A4A4A
begin
  SetAttr(H.KeyAttri, Keyword, [fsBold]);
  SetAttr(H.PLSQLAttri, Keyword, [fsBold]);
  SetAttr(H.SQLPlusAttri, Keyword, [fsBold]);
  SetAttr(H.DefaultPackageAttri, Keyword, [fsBold]);
  SetAttr(H.ExceptionAttri, Keyword, [fsBold]);
  SetAttr(H.CommentAttri, Comment, [fsItalic]);
  SetAttr(H.StringAttri, Str, []);
  SetAttr(H.NumberAttri, Number, []);
  SetAttr(H.FunctionAttri, Func, []);
  SetAttr(H.DataTypeAttri, DataType, []);
  SetAttr(H.TableNameAttri, Obj, []);
  SetAttr(H.VariableAttri, Variable, [fsBold]);
  SetAttr(H.IdentifierAttri, Plain, []);
  SetAttr(H.SymbolAttri, Symbol, []);
end;

procedure ApplyEditorTheme(AHighlighter: TSynSQLSyn; const ATheme: string);
begin
  if AHighlighter = nil then
  begin
    Exit;
  end;
  if SameText(ATheme, ThemeClassic) then
  begin
    ApplyClassic(AHighlighter);
  end
  else
  begin
    ApplyPlume(AHighlighter);
  end;
end;

function NormalizeThemeName(const AValue: string): string;
var
  I: Integer;
begin
  Result := ThemePlume;
  for I := 0 to High(ThemeNames) do
  begin
    if SameText(AValue, ThemeNames[I]) then
    begin
      Result := ThemeNames[I];
    end;
  end;
end;

end.
