// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnMenuColor;

{ The menu bar's background in the look's color. Windows only: there the
  menu bar is drawn by Windows and takes a brush for its background. Other
  widget sets draw it from the desktop theme, so this does nothing there. }

{$mode objfpc}{$H+}

interface

uses
  Graphics;

{ AMenuHandle: the main menu's handle; AFormHandle: its window's.
  AColor = clNone gives the system's own color back. }
procedure ColorMenuBar(AMenuHandle, AFormHandle: PtrUInt; AColor: TColor);

implementation

{$IFDEF WINDOWS}
uses
  Windows;

type
  TPgnMenuInfo = record
    cbSize: DWORD;
    fMask: DWORD;
    dwStyle: DWORD;
    cyMax: UINT;
    hbrBack: HBRUSH;
    dwContextHelpID: DWORD;
    dwMenuData: PtrUInt;
  end;

const
  PgnMimBackground = $00000002;

function PgnSetMenuInfo(AMenu: HMENU; AInfo: Pointer): BOOL; stdcall;
  external 'user32.dll' name 'SetMenuInfo';

var
  LastBrush: HBRUSH = 0;

procedure ColorMenuBar(AMenuHandle, AFormHandle: PtrUInt; AColor: TColor);
var
  MI: TPgnMenuInfo;
  Brush: HBRUSH;
begin
  if AMenuHandle = 0 then
  begin
    Exit;
  end;
  if AColor = clNone then
  begin
    Brush := 0;
  end
  else
  begin
    Brush := CreateSolidBrush(ColorToRGB(AColor));
  end;
  FillChar(MI, SizeOf(MI), 0);
  MI.cbSize := SizeOf(MI);
  MI.fMask := PgnMimBackground;
  MI.hbrBack := Brush;
  PgnSetMenuInfo(HMENU(AMenuHandle), @MI);
  if AFormHandle <> 0 then
  begin
    DrawMenuBar(HWND(AFormHandle));
  end;
  if LastBrush <> 0 then
  begin
    DeleteObject(LastBrush);
  end;
  LastBrush := Brush;
end;
{$ELSE}
procedure ColorMenuBar(AMenuHandle, AFormHandle: PtrUInt; AColor: TColor);
begin
  // the desktop theme draws the menu bar here
end;
{$ENDIF}

end.
