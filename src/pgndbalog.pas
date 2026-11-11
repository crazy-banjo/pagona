// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnDbaLog;

{ The Pagona DBA log: one line for every DBA action Pagona carries out
  (killing a session, and later grants, setting changes, maintenance),
  saying when, where, as whom, and the exact statement. It's a plain text
  file in the settings folder, so it can be read, searched or archived
  with anything. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, pgnTypes;

procedure DbaLog(const AInfo: TpgnConnectionInfo; const AWhat, ASQL: string);

function DbaLogFileName: string;

implementation

uses
  pgnSettings;

function DbaLogFileName: string;
begin
  Result := PagonaConfigDir + 'dba-log.txt';
end;

{ 2026-10-22 01:30:12 | PRODUCTION reports-db | randy@db.example.edu |
  Kill session 1234 (asmith, psql) | SELECT pg_terminate_backend(1234) }
procedure DbaLog(const AInfo: TpgnConnectionInfo; const AWhat, ASQL: string);
var
  F: TextFile;
  Line: string;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' | ' + ConnectionLongLabel(AInfo) + ' | ' +
    AInfo.User + '@' + AInfo.Host + ' | ' + AWhat + ' | ' +
    StringReplace(StringReplace(ASQL, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  try
    ForceDirectories(PagonaConfigDir);
    AssignFile(F, DbaLogFileName);
    if FileExists(DbaLogFileName) then
    begin
      Append(F);
    end
    else
    begin
      Rewrite(F);
    end;
    try
      WriteLn(F, Line);
    finally
      CloseFile(F);
    end;
  except
    on E: Exception do
    begin
      // the action happened either way; a log that can't be written
      // mustn't stop it
    end;
  end;
end;

end.
