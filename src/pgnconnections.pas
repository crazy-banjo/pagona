// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnConnections;

{ The user's saved connection list (connections.json in the config folder).
  Passwords are never written here. A profile file with no passwords is also
  what a team can pass around to share a standard set of connections. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, pgnTypes, pgnSettings;

type
  TpgnConnectionStore = class
  public
    Items: array of TpgnConnectionInfo;
    function Count: Integer;
    function IndexOfId(const AId: string): Integer;
    procedure Add(const AInfo: TpgnConnectionInfo);
    procedure Delete(AIndex: Integer);
    procedure Load;
    procedure Save;
    function FileName: string;
  end;

implementation

function TpgnConnectionStore.Count: Integer;
begin
  Result := Length(Items);
end;

function TpgnConnectionStore.IndexOfId(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Items) do
  begin
    if Items[I].Id = AId then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TpgnConnectionStore.Add(const AInfo: TpgnConnectionInfo);
begin
  SetLength(Items, Length(Items) + 1);
  Items[High(Items)] := AInfo;
end;

procedure TpgnConnectionStore.Delete(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(Items)) then
  begin
    Exit;
  end;
  for I := AIndex to High(Items) - 1 do
  begin
    Items[I] := Items[I + 1];
  end;
  SetLength(Items, Length(Items) - 1);
end;

function TpgnConnectionStore.FileName: string;
begin
  Result := PagonaConfigDir + 'connections.json';
end;

procedure TpgnConnectionStore.Load;
var
  Data, ListData: TJSONData;
  Arr: TJSONArray;
  O: TJSONObject;
  Info: TpgnConnectionInfo;
  I: Integer;
begin
  Items := nil;
  if not FileExists(FileName) then
  begin
    Exit;
  end;
  try
    Data := GetJSON(ReadTextFile(FileName));
    try
      if Data is TJSONObject then
      begin
        ListData := TJSONObject(Data).Find('connections');
        if (ListData <> nil) and (ListData.JSONType = jtArray) then
        begin
          Arr := TJSONArray(ListData);
          for I := 0 to Arr.Count - 1 do
          begin
            if Arr.Items[I].JSONType = jtObject then
            begin
              O := TJSONObject(Arr.Items[I]);
              Info := NewConnectionInfo;
              Info.Id := O.Get('id', Info.Id);
              Info.Name := O.Get('name', '');
              Info.Engine := EngineFromName(O.Get('engine', 'mysql'));
              Info.Host := O.Get('host', '');
              Info.Port := O.Get('port', EngineDefaultPort(Info.Engine));
              Info.User := O.Get('user', '');
              Info.DefaultDatabase := O.Get('database', '');
              Info.ClientLibrary := O.Get('clientLibrary', '');
              Info.UseTLS := O.Get('useTLS', True);
              Info.TLSCAFile := O.Get('tlsCAFile', '');
              Info.TnsAlias := O.Get('tnsAlias', '');
              Info.TnsFile := O.Get('tnsFile', '');
              Info.Color := O.Get('color', -1);
              Info.Environment := EnvironmentFromName(O.Get('environment', 'none'));
              Info.WindowsAuth := O.Get('windowsAuth', False);
              Info.Encrypt := O.Get('encrypt', 'Mandatory');
              Info.TrustServerCert := O.Get('trustServerCert', False);
              Add(Info);
            end;
          end;
        end;
      end;
    finally
      Data.Free;
    end;
  except
    on E: Exception do
    begin
      // Keep whatever loaded; a bad file shouldn't block startup.
    end;
  end;
end;

procedure TpgnConnectionStore.Save;
var
  Root, O: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    Root.Add('connections', Arr);
    for I := 0 to High(Items) do
    begin
      O := TJSONObject.Create;
      O.Add('id', Items[I].Id);
      O.Add('name', Items[I].Name);
      O.Add('engine', EngineNames[Items[I].Engine]);
      O.Add('host', Items[I].Host);
      O.Add('port', Items[I].Port);
      O.Add('user', Items[I].User);
      O.Add('database', Items[I].DefaultDatabase);
      O.Add('clientLibrary', Items[I].ClientLibrary);
      O.Add('useTLS', Items[I].UseTLS);
      O.Add('tlsCAFile', Items[I].TLSCAFile);
      O.Add('tnsAlias', Items[I].TnsAlias);
      O.Add('tnsFile', Items[I].TnsFile);
      O.Add('color', Items[I].Color);
      O.Add('environment', EnvironmentNames[Items[I].Environment]);
      if Items[I].Engine = feSQLServer then
      begin
        O.Add('windowsAuth', Items[I].WindowsAuth);
        O.Add('encrypt', Items[I].Encrypt);
        O.Add('trustServerCert', Items[I].TrustServerCert);
      end;
      Arr.Add(O);
    end;
    WriteTextFile(FileName, Root.FormatJSON);
  finally
    Root.Free;
  end;
end;

end.
