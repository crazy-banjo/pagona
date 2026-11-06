// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnTypes;

{ Shared types used across Pagona: connection profiles and query results. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TpgnStringArray = array of string;
  TpgnBoolArray = array of Boolean;

  TpgnEngine = (feMySQL, feMariaDB, fePostgreSQL, feOracle, feSQLServer);

  { Shown as text on tabs, the connection band, the window title and the
    confirmations, so it never depends on color. }
  TpgnEnvironment = (enNone, enProduction, enTest, enDevelopment);

  TpgnObjectKind = (okTable, okView, okMatView);

  { How an engine writes SQL: quoting, comments, statement ends. }
  TpgnDialect = (sdMySQL, sdPostgreSQL, sdOracle, sdTSQL);

  { Code objects kept in the database. }
  TpgnRoutineKind = (rkProcedure, rkFunction, rkTrigger);

  { An object found by a search: where it lives and what it is
    ("Table", "View", "Procedure", "Function"). Schema is '' on engines
    without schemas (MySQL), where the database holds the objects. }
  TpgnObjectRef = record
    Database: string;
    Schema: string;
    Name: string;
    Kind: string;
  end;
  TpgnObjectRefs = array of TpgnObjectRef;

  { One parameter of a procedure or function: for the New form (Mode,
    Name, DataType) and the Execute form (also Value / IsNull). }
  TpgnParamDef = record
    Mode: string;       // IN, OUT, INOUT ('' for function parameters)
    Name: string;
    DataType: string;
    Value: string;
    IsNull: Boolean;
  end;
  TpgnParamDefs = array of TpgnParamDef;

  { An account on the server: a user or a role. MySQL names it user@host;
    PostgreSQL has roles only (a role that can log in is a user). }
  TpgnAccount = record
    Name: string;
    Host: string;        // MySQL; '' elsewhere
    IsRole: Boolean;     // cannot log in / made as a role
    IsSystem: Boolean;   // the server's own (mysql.sys, pg_*)
  end;

  TpgnAccounts = array of TpgnAccount;

  { One setting on an account's General page. The adapter says what there
    is, so each engine shows its own (Oracle later: profile, tablespaces).
    Value: '1'/'0' for akBool; '' means "not set" for the others. }
  TpgnAttrKind = (akBool, akInt, akText, akChoice);

  TpgnAccountAttr = record
    Key: string;
    Caption: string;
    Hint: string;
    Kind: TpgnAttrKind;
    Value: string;
    Choices: TpgnStringArray;   // akChoice
    ReadOnly: Boolean;
  end;

  TpgnAccountAttrs = array of TpgnAccountAttr;

  { A saved connection profile. The password is never part of this record:
    it is asked for at connect time and only kept in memory by the adapter. }
  { A stored function or procedure, as the data dictionary describes it
    (never its source). }
  TpgnRoutineInfo = record
    Found: Boolean;
    Owner: string;          // the schema
    PackageName: string;    // '' for a standalone function or procedure
    Name: string;
    Kind: string;           // FUNCTION or PROCEDURE
    ReturnType: string;     // '' for a procedure
    Params: string;         // "P_PIDM IN NUMBER, P_CODE IN VARCHAR2"
    Overloads: Integer;     // versions with the same name (a package can have several)
    Status: string;         // VALID / INVALID
    LastChanged: string;    // YYYY-MM-DD HH24:MI
    Reads: string;          // tables and views it reads, comma separated
    Note: string;           // what this login couldn't see
  end;

  TpgnConnectionInfo = record
    Id: string;
    Name: string;
    Engine: TpgnEngine;
    Host: string;
    Port: Integer;
    User: string;
    DefaultDatabase: string;
    ClientLibrary: string;   // optional path to libmariadb / libmysql
    UseTLS: Boolean;
    TLSCAFile: string;       // optional CA certificate file
    TnsAlias: string;        // Oracle: an alias from tnsnames.ora (else host/port/service)
    TnsFile: string;         // Oracle: tnsnames.ora or its folder ('' = the usual places)
    Color: Integer;          // TColor value; -1 = no color
    Environment: TpgnEnvironment;
    // SQL Server
    WindowsAuth: Boolean;    // Windows Authentication (no password asked)
    Encrypt: string;         // Mandatory (default), Optional or Strict, as SSMS
    TrustServerCert: Boolean;
  end;

  TpgnResultRow = record
    Values: TpgnStringArray;
    Nulls: TpgnBoolArray;
  end;

  TpgnResultRows = array of TpgnResultRow;

  { The outcome of one statement. ReturnsRows is False for INSERT/UPDATE/DDL,
    in which case RowsAffected is meaningful and Columns/Rows are empty. }
  TpgnResultSet = class
  public
    Columns: TpgnStringArray;
    Rows: TpgnResultRows;
    ReturnsRows: Boolean;
    HasMoreRows: Boolean;
    RowsAffected: Int64;
    { A statement can return several result sets (a CALL often does): the
      first is this object, the rest follow through Next. Owned. }
    Next: TpgnResultSet;
    { What the server said while running it (SQL Server's PRINT and row
      counts); shown in Messages. }
    Messages: TpgnStringArray;
    { The statement (or SQL Server batch) that returned it, and which of
      that statement's result sets it is: Save Results As can run it again
      for all rows. Set by the query thread. }
    SourceSQL: string;
    SourceIndex: Integer;
    destructor Destroy; override;
    function RowCount: Integer;
    function ColumnCount: Integer;
    { this result set and every one after it }
    function ChainLength: Integer;
  end;

const
  { The release number: also in pagona.lpi (Version Info) and the tag a
    release is built from (v0.2.0). }
  PagonaVersion = '0.2.5';
  PagonaCopyright = 'Copyright (C) 2026 Randy Morrow';
  PagonaSourceURL = 'https://github.com/crazy-banjo/pagona';

const
  EngineNames: array[TpgnEngine] of string = ('mysql', 'mariadb', 'postgresql', 'oracle', 'sqlserver');
  EngineCaptions: array[TpgnEngine] of string = ('MySQL', 'MariaDB', 'PostgreSQL', 'Oracle', 'SQL Server');

  EnvironmentNames: array[TpgnEnvironment] of string = ('none', 'production', 'test', 'development');
  EnvironmentCaptions: array[TpgnEnvironment] of string = ('None', 'Production', 'Test', 'Development');
  EnvironmentShort: array[TpgnEnvironment] of string = ('', 'PROD', 'TEST', 'DEV');
  RoutineWord: array[TpgnRoutineKind] of string = ('PROCEDURE', 'FUNCTION', 'TRIGGER');
  RoutineCaption: array[TpgnRoutineKind] of string = ('Procedure', 'Function', 'Trigger');
  EnvironmentLong: array[TpgnEnvironment] of string = ('', 'PRODUCTION', 'TEST', 'DEVELOPMENT');

function EngineFromName(const AName: string): TpgnEngine;
function EnvironmentFromName(const AName: string): TpgnEnvironment;

{ "PROD · MySQL · finaid-db" (environment left out when none). }
function ConnectionLabel(const AInfo: TpgnConnectionInfo): string;

{ "PRODUCTION finaid-db" for confirmations and the band. }
function ConnectionLongLabel(const AInfo: TpgnConnectionInfo): string;

function EngineDefaultPort(AEngine: TpgnEngine): Integer;
function NewConnectionInfo: TpgnConnectionInfo;

implementation

destructor TpgnResultSet.Destroy;
begin
  FreeAndNil(Next);
  inherited Destroy;
end;

function TpgnResultSet.ChainLength: Integer;
var
  R: TpgnResultSet;
begin
  Result := 0;
  R := Self;
  while R <> nil do
  begin
    Inc(Result);
    R := R.Next;
  end;
end;

function TpgnResultSet.RowCount: Integer;
begin
  Result := Length(Rows);
end;

function TpgnResultSet.ColumnCount: Integer;
begin
  Result := Length(Columns);
end;

function EngineFromName(const AName: string): TpgnEngine;
var
  E: TpgnEngine;
begin
  Result := feMySQL;
  for E := Low(TpgnEngine) to High(TpgnEngine) do
  begin
    if SameText(EngineNames[E], AName) then
    begin
      Result := E;
      Exit;
    end;
  end;
end;

function EnvironmentFromName(const AName: string): TpgnEnvironment;
var
  E: TpgnEnvironment;
begin
  Result := enNone;
  for E := Low(TpgnEnvironment) to High(TpgnEnvironment) do
  begin
    if SameText(EnvironmentNames[E], AName) then
    begin
      Result := E;
      Exit;
    end;
  end;
end;

function ConnectionLabel(const AInfo: TpgnConnectionInfo): string;
begin
  Result := EngineCaptions[AInfo.Engine] + ' ' + #$C2#$B7 + ' ' + AInfo.Name;
  if AInfo.Environment <> enNone then
  begin
    Result := EnvironmentShort[AInfo.Environment] + ' ' + #$C2#$B7 + ' ' + Result;
  end;
end;

function ConnectionLongLabel(const AInfo: TpgnConnectionInfo): string;
begin
  Result := AInfo.Name;
  if AInfo.Environment <> enNone then
  begin
    Result := EnvironmentLong[AInfo.Environment] + ' ' + Result;
  end;
end;

function EngineDefaultPort(AEngine: TpgnEngine): Integer;
begin
  case AEngine of
    feMySQL, feMariaDB:
      begin
        Result := 3306;
      end;
    fePostgreSQL:
      begin
        Result := 5432;
      end;
    feOracle:
      begin
        Result := 1521;
      end;
    feSQLServer:
      begin
        Result := 1433;
      end;
  else
    begin
      Result := 0;
    end;
  end;
end;

function NewConnectionInfo: TpgnConnectionInfo;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result.Id := GUIDToString(G);
  Result.Name := '';
  Result.Engine := feMySQL;
  Result.Host := '';
  Result.Port := EngineDefaultPort(feMySQL);
  Result.User := '';
  Result.DefaultDatabase := '';
  Result.ClientLibrary := '';
  Result.UseTLS := True;   // cloud databases: TLS on by default
  Result.TLSCAFile := '';
  Result.TnsAlias := '';
  Result.TnsFile := '';
  Result.Color := -1;
  Result.Environment := enNone;
  Result.WindowsAuth := False;
  Result.Encrypt := 'Mandatory';
  Result.TrustServerCert := False;
end;

end.
