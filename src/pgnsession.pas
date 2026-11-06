// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnSession;

{ The tabs open when Pagona last closed, so they can open again (Options:
  "Reopen last session's tabs"). Kept in session.json next to the settings.

  A tab with a file comes back as the file (as it is on disk). A tab with
  no file comes back with its text. Which connection and database it was
  on is noted so the tab can say so; it comes back not connected (the
  password is asked for when you connect, as always: passwords are never
  written down). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, pgnSettings;

type
  TpgnSessionTab = record
    Title: string;
    FileName: string;    // '' for a tab that was never saved
    Text: string;        // a tab with no file: its SQL
    ConnName: string;    // the saved connection it was on ('' = none)
    ConnId: string;
    Database: string;
    Line: Integer;       // where the cursor was
  end;
  TpgnSessionTabs = array of TpgnSessionTab;

function SessionFileName: string;
procedure SaveSession(const ATabs: TpgnSessionTabs; AActive: Integer);
function LoadSession(out ATabs: TpgnSessionTabs; out AActive: Integer): Boolean;
procedure ForgetSession;

implementation

function SessionFileName: string;
begin
  Result := PagonaConfigDir + 'session.json';
end;

procedure SaveSession(const ATabs: TpgnSessionTabs; AActive: Integer);
var
  O, T: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    A := TJSONArray.Create;
    for I := 0 to High(ATabs) do
    begin
      T := TJSONObject.Create;
      T.Add('title', ATabs[I].Title);
      T.Add('file', ATabs[I].FileName);
      T.Add('text', ATabs[I].Text);
      T.Add('connection', ATabs[I].ConnName);
      T.Add('connectionId', ATabs[I].ConnId);
      T.Add('database', ATabs[I].Database);
      T.Add('line', ATabs[I].Line);
      A.Add(T);
    end;
    O.Add('tabs', A);
    O.Add('active', AActive);
    ForceDirectories(PagonaConfigDir);
    WriteTextFile(SessionFileName, O.FormatJSON);
  finally
    O.Free;
  end;
end;

function LoadSession(out ATabs: TpgnSessionTabs; out AActive: Integer): Boolean;
var
  Data: TJSONData;
  O, T: TJSONObject;
  A: TJSONArray;
  I, N: Integer;
begin
  Result := False;
  ATabs := nil;
  AActive := 0;
  if not FileExists(SessionFileName) then
  begin
    Exit;
  end;
  try
    Data := GetJSON(ReadTextFile(SessionFileName));
    try
      if not (Data is TJSONObject) then
      begin
        Exit;
      end;
      O := TJSONObject(Data);
      AActive := O.Get('active', 0);
      if not (O.Find('tabs') is TJSONArray) then
      begin
        Exit;
      end;
      A := TJSONArray(O.Find('tabs'));
      for I := 0 to A.Count - 1 do
      begin
        if not (A.Items[I] is TJSONObject) then
        begin
          Continue;
        end;
        T := TJSONObject(A.Items[I]);
        N := Length(ATabs);
        SetLength(ATabs, N + 1);
        ATabs[N].Title := T.Get('title', '');
        ATabs[N].FileName := T.Get('file', '');
        ATabs[N].Text := T.Get('text', '');
        ATabs[N].ConnName := T.Get('connection', '');
        ATabs[N].ConnId := T.Get('connectionId', '');
        ATabs[N].Database := T.Get('database', '');
        ATabs[N].Line := T.Get('line', 1);
      end;
      Result := Length(ATabs) > 0;
    finally
      Data.Free;
    end;
  except
    on E: Exception do
    begin
      // a damaged session file means starting with an empty tab, nothing worse
      ATabs := nil;
      Result := False;
    end;
  end;
end;

procedure ForgetSession;
begin
  if FileExists(SessionFileName) then
  begin
    DeleteFile(SessionFileName);
  end;
end;

end.
