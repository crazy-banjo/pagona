// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnSettings;

{ Application settings, stored as JSON in the per-user config folder:
    Windows: %LOCALAPPDATA%\Pagona\settings.json
    Linux:   ~/.config/Pagona/settings.json }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, pgnKeymap, pgnTheme;

type
  TpgnSettings = class
  public
    Keymap: string;                 // a keymap name, or "Match layout"
    Layout: string;                 // Plume, Amphibian or Seattle
    RowLimit: Integer;              // 0 = no limit
    ConfirmDestructive: Boolean;    // ask before DELETE, TRUNCATE, DROP
    WarnDdlCommit: Boolean;         // Oracle, MySQL: ask before DDL commits pending changes
    Theme: string;                  // editor colors: Plume or Classic
    Look: string;                   // the frame's colors: Match layout, Plume, Amphibian or Seattle
    LogEveryStatement: Boolean;     // long scripts too (otherwise only problems + summary)
    AutoCommitNewTabs: Boolean;     // a tab starts with auto-commit on (default off, as Toad)
    AutoCommitSeattle: Boolean;     // Seattle's own: on by default, as SSMS
    DBAMode: Boolean;               // the Explorer shows a DBA's folders too
    { Toolbar buttons per layout, as "Layout=id,id,|,id" (| = separator).
      A layout with no entry uses its default buttons. }
    Toolbars: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function FileName: string;
  end;

function PagonaConfigDir: string;
function ReadTextFile(const AFileName: string): string;
procedure WriteTextFile(const AFileName, AText: string);

implementation

function PagonaConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

function ReadTextFile(const AFileName: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(AFileName);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure WriteTextFile(const AFileName, AText: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  L := TStringList.Create;
  try
    L.Text := AText;
    L.SaveToFile(AFileName);
  finally
    L.Free;
  end;
end;

constructor TpgnSettings.Create;
begin
  inherited Create;
  Keymap := KeymapMatchLayout;
  Layout := LayoutPlume;
  RowLimit := 1000;
  ConfirmDestructive := True;
  WarnDdlCommit := True;
  Theme := ThemePlume;
  LogEveryStatement := False;
  AutoCommitNewTabs := False;
  AutoCommitSeattle := True;
  Look := 'Match layout';
  DBAMode := False;
  Toolbars := TStringList.Create;
end;

destructor TpgnSettings.Destroy;
begin
  Toolbars.Free;
  inherited Destroy;
end;

function TpgnSettings.FileName: string;
begin
  Result := PagonaConfigDir + 'settings.json';
end;

procedure TpgnSettings.Load;
var
  Data: TJSONData;
  O, T: TJSONObject;
  I: Integer;
begin
  if not FileExists(FileName) then
  begin
    Exit;
  end;
  try
    Data := GetJSON(ReadTextFile(FileName));
    try
      if Data is TJSONObject then
      begin
        O := TJSONObject(Data);
        Keymap := NormalizeKeymapSetting(O.Get('keymap', Keymap));
        Layout := O.Get('layout', Layout);
        RowLimit := O.Get('rowLimit', RowLimit);
        ConfirmDestructive := O.Get('confirmDestructive', ConfirmDestructive);
        WarnDdlCommit := O.Get('warnDdlCommit', WarnDdlCommit);
        Theme := NormalizeThemeName(O.Get('theme', Theme));
        LogEveryStatement := O.Get('logEveryStatement', LogEveryStatement);
        AutoCommitNewTabs := O.Get('autoCommitNewTabs', AutoCommitNewTabs);
        AutoCommitSeattle := O.Get('autoCommitSeattle', AutoCommitSeattle);
        Look := O.Get('look', Look);
        DBAMode := O.Get('dbaMode', DBAMode);
        Toolbars.Clear;
        if O.Find('toolbars') is TJSONObject then
        begin
          T := TJSONObject(O.Find('toolbars'));
          for I := 0 to T.Count - 1 do
          begin
            Toolbars.Values[T.Names[I]] := T.Items[I].AsString;
          end;
        end;
      end;
    finally
      Data.Free;
    end;
  except
    on E: Exception do
    begin
      // A damaged settings file should never stop Pagona from starting.
    end;
  end;
end;

procedure TpgnSettings.Save;
var
  O, T: TJSONObject;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    O.Add('keymap', Keymap);
    O.Add('layout', Layout);
    O.Add('rowLimit', RowLimit);
    O.Add('confirmDestructive', ConfirmDestructive);
    O.Add('warnDdlCommit', WarnDdlCommit);
    O.Add('theme', Theme);
    O.Add('logEveryStatement', LogEveryStatement);
    O.Add('autoCommitNewTabs', AutoCommitNewTabs);
    O.Add('autoCommitSeattle', AutoCommitSeattle);
    O.Add('look', Look);
    O.Add('dbaMode', DBAMode);
    T := TJSONObject.Create;
    for I := 0 to Toolbars.Count - 1 do
    begin
      T.Add(Toolbars.Names[I], Toolbars.ValueFromIndex[I]);
    end;
    O.Add('toolbars', T);
    WriteTextFile(FileName, O.FormatJSON);
  finally
    O.Free;
  end;
end;

end.
