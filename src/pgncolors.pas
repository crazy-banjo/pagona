// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnColors;

{ Connection colors: the preset list offered in the connection dialog,
  and a helper to pick readable text on a colored background. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

type
  TpgnColorPreset = record
    Name: string;
    Color: TColor;   // -1 = no color
  end;

const
  NoConnectionColor = -1;

function ColorPresetCount: Integer;
function ColorPreset(AIndex: Integer): TpgnColorPreset;
function ColorPresetIndex(AColor: TColor): Integer;
function ContrastTextColor(ABackground: TColor): TColor;

implementation

function ColorPresetCount: Integer;
begin
  Result := 8;
end;

function ColorPreset(AIndex: Integer): TpgnColorPreset;
begin
  case AIndex of
    1:
      begin
        Result.Name := 'Red';
        Result.Color := RGBToColor(200, 40, 40);
      end;
    2:
      begin
        Result.Name := 'Orange';
        Result.Color := RGBToColor(230, 130, 20);
      end;
    3:
      begin
        Result.Name := 'Yellow';
        Result.Color := RGBToColor(225, 195, 35);
      end;
    4:
      begin
        Result.Name := 'Green';
        Result.Color := RGBToColor(40, 150, 60);
      end;
    5:
      begin
        Result.Name := 'Blue';
        Result.Color := RGBToColor(40, 100, 200);
      end;
    6:
      begin
        Result.Name := 'Purple';
        Result.Color := RGBToColor(130, 60, 170);
      end;
    7:
      begin
        Result.Name := 'Gray';
        Result.Color := RGBToColor(110, 110, 110);
      end;
  else
    begin
      Result.Name := 'None';
      Result.Color := NoConnectionColor;
    end;
  end;
end;

{ Index of the preset with this color, or -1 if it isn't a preset. }
function ColorPresetIndex(AColor: TColor): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to ColorPresetCount - 1 do
  begin
    if ColorPreset(I).Color = AColor then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function ContrastTextColor(ABackground: TColor): TColor;
var
  C: TColor;
  Luma: Double;
begin
  C := ColorToRGB(ABackground);
  Luma := 0.299 * Red(C) + 0.587 * Green(C) + 0.114 * Blue(C);
  if Luma > 150 then
  begin
    Result := clBlack;
  end
  else
  begin
    Result := clWhite;
  end;
end;

end.
