// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapterMSSQL;

{ SQL Server adapter, through ODBC (pgnOdbc): Microsoft's ODBC Driver 18
  or 17 for SQL Server, falling back to the "SQL Server" driver built into
  Windows, or FreeTDS on Linux.

  Written without an SQL Server to try it on; the SQL follows the
  documented catalog views (sys.*). First runs are expected to need small
  fixes.

  How SQL Server maps onto Pagona:
    - databases hold schemas (dbo, ...) that hold the objects, so the
      Explorer shows Databases, then a database's Schemas, as PostgreSQL;
      each database the Explorer opens gets a session of its own;
    - a tab switches database with USE, keeping its session;
    - scripts are cut into batches at GO lines, as SSMS does; each batch
      goes to the server whole;
    - PRINT and "(n rows affected)" come back as messages, as in SSMS;
    - auto-commit off is SQL Server's implicit transactions; savepoints are
      SAVE TRANSACTION; DDL waits for Commit too;
    - names are written [schema].[name];
    - Save of a procedure, function or trigger is CREATE OR ALTER (SQL
      Server 2016 SP1 on), so grants stay. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, pgnTypes, pgnAdapter, pgnSqlSplit, pgnOdbc;

type
  TpgnMSSQLAdapter = class(TpgnAdapter)
  private
    FConn: TpgnOdbcConnection;
    FMeta: TpgnOdbcConnection;
    FDriver: string;            // the ODBC driver that connected
    FVersion: string;           // "17.0 RTM"
    FFullVersion: string;       // "17.0.1000.7"
    FSpid: string;
    FSchema: string;            // SCHEMA_NAME(): the login's default schema
    FAutoCommit: Boolean;
    function ConnString(const ADriver, ADatabase: string): string;
    procedure OpenWith(AConn: TpgnOdbcConnection; const ADatabase: string);
    function MetaResult(const ASQL: string): TpgnResultSet;
    function MetaStrings(const ASQL: string): TpgnStringArray;
    function MetaValue(const ASQL: string): string;
    procedure MetaExec(const ASQL: string);
    function TryValue(const ASQL: string): string;
    function L(const AText: string): string;
    function Q2(const ASchema, AName: string): string;
    function ObjId(const ASchema, AName: string): string;
  public
    constructor Create(const AInfo: TpgnConnectionInfo; const APassword: string); override;
    destructor Destroy; override;

    procedure Connect; override;
    procedure Disconnect; override;
    function IsConnected: Boolean; override;

    function ListDatabases: TpgnStringArray; override;
    function ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray; override;
    function DescribeTable(const ADatabase, ATable: string): TpgnResultSet; override;
    function GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string; override;
    function ListObjectNames(const ADatabase: string): TpgnStringArray; override;
    function SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs; override;
    function DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet; override;
    function DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet; override;
    function DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet; override;
    function ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray; override;
    function GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; override;
    function RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean; override;
    function DescribeParameters(const ADatabase, AName: string): TpgnResultSet; override;
    function DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet; override;
    function DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet; override;
    function SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
      const ASQL: string; ALog: TStrings): string; override;
    function ServerVersion: string; override;
    function OwnSessionId: string; override;

    function Dialect: TpgnDialect; override;
    function HasSchemas: Boolean; override;
    function SessionPerDatabase: Boolean; override;
    function ListSchemas(ASystem: Boolean): TpgnStringArray; override;
    function CurrentSchema: string; override;
    procedure UseSchema(const ASchema: string); override;
    function ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray; override;
    function ListFolder(const AContainer, AFolder: string): TpgnStringArray; override;
    function FolderItemSQL(const AContainer, AFolder, AName: string): string; override;
    function TableFolders: Boolean; override;

    function RoutineTarget(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; override;
    function DropRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; override;
    function DescribeSQL(const ADatabase, ATable: string): string; override;
    function SelectTopSQL(const AQualifiedName: string; ARows: Integer): string; override;
    function NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs; const AReturns: string): string; override;
    function NewTriggerSQL(const ADatabase, ATable: string): string; override;
    function ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs): string; override;
    function GrantRights(const AObjectWord: string): TpgnStringArray; override;
    function GranteeHint: string; override;
    function GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
      AWithGrantOption: Boolean): string; override;

    function Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet; override;
    procedure CancelCurrent; override;

    function QuoteIdent(const AName: string): string; override;
    procedure UseDatabase(const ADatabase: string); override;
    procedure SetAutoCommit(AValue: Boolean); override;
    function AutoCommit: Boolean; override;
    procedure Commit; override;
    procedure Rollback; override;

    { "17.0.1000.7", for Object Explorer's server line. }
    property FullVersion: string read FFullVersion;
  end;

implementation

function Strings(const AItems: array of string): TpgnStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for I := 0 to High(AItems) do
  begin
    Result[I] := AItems[I];
  end;
end;

{ SHOWPLAN_ALL gives one result set per statement: the statement's own row,
  then a row per operator. They become one grid, with the columns SSMS's
  plan tooltips show, in its words. Frees ASets. }
function PlanGrid(ASets: TpgnResultSet): TpgnResultSet;
const
  Wanted: array[0..8] of string = ('StmtText', 'PhysicalOp', 'LogicalOp', 'EstimateRows',
    'EstimateExecutions', 'EstimateIO', 'EstimateCPU', 'TotalSubtreeCost', 'Warnings');
  Titles: array[0..8] of string = ('Operation', 'Physical Operation', 'Logical Operation',
    'Estimated Number of Rows', 'Estimated Number of Executions', 'Estimated I/O Cost',
    'Estimated CPU Cost', 'Estimated Subtree Cost', 'Warnings');
var
  S: TpgnResultSet;
  Map: array[0..8] of Integer;
  I, J, N: Integer;
begin
  Result := TpgnResultSet.Create;
  Result.ReturnsRows := True;
  SetLength(Result.Columns, Length(Titles));
  for I := 0 to High(Titles) do
  begin
    Result.Columns[I] := Titles[I];
  end;
  N := 0;
  S := ASets;
  while S <> nil do
  begin
    for I := 0 to High(Wanted) do
    begin
      Map[I] := -1;
      for J := 0 to High(S.Columns) do
      begin
        if SameText(S.Columns[J], Wanted[I]) then
        begin
          Map[I] := J;
        end;
      end;
    end;
    for J := 0 to S.RowCount - 1 do
    begin
      SetLength(Result.Rows, N + 1);
      SetLength(Result.Rows[N].Values, Length(Titles));
      SetLength(Result.Rows[N].Nulls, Length(Titles));
      for I := 0 to High(Titles) do
      begin
        if Map[I] >= 0 then
        begin
          Result.Rows[N].Values[I] := S.Rows[J].Values[Map[I]];
          Result.Rows[N].Nulls[I] := S.Rows[J].Nulls[Map[I]];
        end
        else
        begin
          Result.Rows[N].Values[I] := '';
          Result.Rows[N].Nulls[I] := True;
        end;
      end;
      Inc(N);
    end;
    S := S.Next;
  end;
  ASets.Free;   // and the ones after it
end;

// A value in a connection string, in braces when it has ; or a brace in it.
function ConnValue(const AValue: string): string;
begin
  if (Pos(';', AValue) > 0) or (Pos('{', AValue) > 0) or (Pos('}', AValue) > 0) or
    (Pos(' ', AValue) > 0) then
  begin
    Result := '{' + StringReplace(AValue, '}', '}}', [rfReplaceAll]) + '}';
  end
  else
  begin
    Result := AValue;
  end;
end;

{ ------------------------------------------------------------ connecting }

constructor TpgnMSSQLAdapter.Create(const AInfo: TpgnConnectionInfo; const APassword: string);
begin
  inherited Create(AInfo, APassword);
  FConn := TpgnOdbcConnection.Create;
  FMeta := TpgnOdbcConnection.Create;
  FAutoCommit := True;
end;

destructor TpgnMSSQLAdapter.Destroy;
begin
  Disconnect;
  FreeAndNil(FMeta);
  FreeAndNil(FConn);
  inherited Destroy;
end;

function TpgnMSSQLAdapter.ConnString(const ADriver, ADatabase: string): string;
var
  Server, Enc: string;
  FreeTDS, Legacy: Boolean;
begin
  FreeTDS := Pos('FREETDS', UpperCase(ADriver)) > 0;
  Legacy := SameText(ADriver, 'SQL Server');
  Server := Trim(FInfo.Host);
  if Server = '' then
  begin
    Server := '(local)';
  end;
  Result := 'Driver={' + ADriver + '};';
  if FreeTDS then
  begin
    Result := Result + 'Server=' + ConnValue(Server) + ';';
    if (FInfo.Port > 0) and (Pos('\', Server) = 0) then
    begin
      Result := Result + 'Port=' + IntToStr(FInfo.Port) + ';';
    end;
    Result := Result + 'TDS_Version=7.4;ClientCharset=UTF-8;';
  end
  else
  begin
    // HOST\INSTANCE and HOST,PORT are written as SSMS takes them
    if (FInfo.Port > 0) and (FInfo.Port <> 1433) and (Pos('\', Server) = 0) and (Pos(',', Server) = 0) then
    begin
      Server := Server + ',' + IntToStr(FInfo.Port);
    end;
    Result := Result + 'Server=' + ConnValue(Server) + ';';
  end;
  if ADatabase <> '' then
  begin
    Result := Result + 'Database=' + ConnValue(ADatabase) + ';';
  end;
  if FInfo.WindowsAuth and not FreeTDS then
  begin
    Result := Result + 'Trusted_Connection=yes;';
  end
  else
  begin
    Result := Result + 'UID=' + ConnValue(FInfo.User) + ';PWD=' + ConnValue(FPassword) + ';';
  end;
  // Encrypt: Mandatory / Optional / Strict, as SSMS 22 offers them
  if SameText(FInfo.Encrypt, 'Optional') then
  begin
    Enc := 'no';
  end
  else if SameText(FInfo.Encrypt, 'Strict') and not Legacy and not FreeTDS then
  begin
    Enc := 'strict';
  end
  else
  begin
    Enc := 'yes';
  end;
  if FreeTDS then
  begin
    if Enc = 'no' then
    begin
      Result := Result + 'Encryption=off;';
    end
    else
    begin
      Result := Result + 'Encryption=require;';
    end;
  end
  else
  begin
    Result := Result + 'Encrypt=' + Enc + ';';
    if FInfo.TrustServerCert then
    begin
      Result := Result + 'TrustServerCertificate=yes;';
    end
    else
    begin
      Result := Result + 'TrustServerCertificate=no;';
    end;
    Result := Result + 'APP=Pagona;';
  end;
end;

{ The driver named in the connection (its client library field), or the
  first one installed: Microsoft's 18, 17, then Windows' own or FreeTDS. }
procedure TpgnMSSQLAdapter.OpenWith(AConn: TpgnOdbcConnection; const ADatabase: string);
var
  Drivers: TpgnStringArray;
  I: Integer;
  Tried: string;
begin
  if FDriver <> '' then
  begin
    AConn.Connect(ConnString(FDriver, ADatabase));
    Exit;
  end;
  if Trim(FInfo.ClientLibrary) <> '' then
  begin
    Drivers := Strings([Trim(FInfo.ClientLibrary)]);
  end
  else
  begin
    {$IFDEF WINDOWS}
    Drivers := Strings(['ODBC Driver 18 for SQL Server', 'ODBC Driver 17 for SQL Server', 'SQL Server']);
    {$ELSE}
    Drivers := Strings(['ODBC Driver 18 for SQL Server', 'ODBC Driver 17 for SQL Server', 'FreeTDS']);
    {$ENDIF}
  end;
  Tried := '';
  for I := 0 to High(Drivers) do
  begin
    try
      AConn.Connect(ConnString(Drivers[I], ADatabase));
      FDriver := Drivers[I];
      Exit;
    except
      on E: EpgnOdbcError do
      begin
        // IM002: no such driver here; anything else is the server's answer
        if (E.SqlState <> 'IM002') or (I = High(Drivers)) then
        begin
          if E.SqlState = 'IM002' then
          begin
            raise Exception.Create('No SQL Server ODBC driver was found (tried ' + Tried + Drivers[I] +
              '). Install Microsoft''s "ODBC Driver 18 for SQL Server", or name an installed driver ' +
              'as the client library in Edit Connection.');
          end;
          if (Pos('certificate', LowerCase(E.Message)) > 0) and not FInfo.TrustServerCert then
          begin
            raise Exception.Create(E.Message + LineEnding + LineEnding + 'The server''s certificate isn''t ' +
              'trusted by this computer. For a server you know (your own test server, say), tick "Trust ' +
              'server certificate" in Edit Connection, as in SSMS''s Connect dialog.');
          end;
          raise;
        end;
        Tried := Tried + Drivers[I] + ', ';
      end;
    end;
  end;
end;

procedure TpgnMSSQLAdapter.Connect;
var
  R: TpgnResultSet;
  Parts: TStringArray;
begin
  OpenWith(FConn, FInfo.DefaultDatabase);
  OpenWith(FMeta, FInfo.DefaultDatabase);
  R := FConn.Run('SELECT DB_NAME(), @@SPID, SCHEMA_NAME(), ' +
    'CAST(SERVERPROPERTY(''ProductVersion'') AS nvarchar(64)), ' +
    'CAST(SERVERPROPERTY(''ProductLevel'') AS nvarchar(64)), SUSER_SNAME()', 0);
  try
    if R.RowCount > 0 then
    begin
      FCurrentDatabase := R.Rows[0].Values[0];
      FSpid := R.Rows[0].Values[1];
      FSchema := R.Rows[0].Values[2];
      FFullVersion := R.Rows[0].Values[3];
      // "17.0.1000.7" + "RTM" -> "17.0 RTM", as SSMS's status bar
      Parts := FFullVersion.Split(['.']);
      if Length(Parts) >= 2 then
      begin
        FVersion := Parts[0] + '.' + Parts[1];
      end
      else
      begin
        FVersion := FFullVersion;
      end;
      FVersion := Trim(FVersion + ' ' + R.Rows[0].Values[4]);
      if FInfo.WindowsAuth then
      begin
        FInfo.User := R.Rows[0].Values[5];   // homeone\randyw, as SSMS shows it
      end;
    end;
  finally
    R.Free;
  end;
  if not FAutoCommit then
  begin
    FConn.Run('SET IMPLICIT_TRANSACTIONS ON', 0).Free;
  end;
end;

procedure TpgnMSSQLAdapter.Disconnect;
begin
  if FConn <> nil then
  begin
    FConn.Disconnect;
  end;
  if FMeta <> nil then
  begin
    FMeta.Disconnect;
  end;
end;

function TpgnMSSQLAdapter.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.Connected;
end;

{ ------------------------------------------------------------- helpers }

function TpgnMSSQLAdapter.MetaResult(const ASQL: string): TpgnResultSet;
begin
  Result := FMeta.Run(ASQL, 0);
end;

function TpgnMSSQLAdapter.MetaStrings(const ASQL: string): TpgnStringArray;
var
  R: TpgnResultSet;
  I: Integer;
begin
  Result := nil;
  R := MetaResult(ASQL);
  try
    SetLength(Result, R.RowCount);
    for I := 0 to R.RowCount - 1 do
    begin
      Result[I] := R.Rows[I].Values[0];
    end;
  finally
    R.Free;
  end;
end;

function TpgnMSSQLAdapter.MetaValue(const ASQL: string): string;
var
  R: TpgnResultSet;
begin
  Result := '';
  R := MetaResult(ASQL);
  try
    if (R.RowCount > 0) and (R.ColumnCount > 0) then
    begin
      Result := R.Rows[0].Values[0];
    end;
  finally
    R.Free;
  end;
end;

procedure TpgnMSSQLAdapter.MetaExec(const ASQL: string);
begin
  FMeta.Run(ASQL, 0).Free;
end;

function TpgnMSSQLAdapter.TryValue(const ASQL: string): string;
begin
  try
    Result := MetaValue(ASQL);
  except
    on E: Exception do
    begin
      Result := '';
    end;
  end;
end;

{ N'...' so names in any language survive. }
function TpgnMSSQLAdapter.L(const AText: string): string;
begin
  Result := 'N' + QuoteLiteral(AText);
end;

function TpgnMSSQLAdapter.Q2(const ASchema, AName: string): string;
begin
  Result := QuoteIdent(ASchema) + '.' + QuoteIdent(AName);
end;

function TpgnMSSQLAdapter.ObjId(const ASchema, AName: string): string;
begin
  Result := 'OBJECT_ID(' + L(Q2(ASchema, AName)) + ')';
end;

function TpgnMSSQLAdapter.QuoteIdent(const AName: string): string;
begin
  Result := '[' + StringReplace(AName, ']', ']]', [rfReplaceAll]) + ']';
end;

{ ------------------------------------------------------- engine shape }

function TpgnMSSQLAdapter.Dialect: TpgnDialect;
begin
  Result := sdTSQL;
end;

function TpgnMSSQLAdapter.HasSchemas: Boolean;
begin
  Result := True;
end;

function TpgnMSSQLAdapter.SessionPerDatabase: Boolean;
begin
  Result := True;
end;

function TpgnMSSQLAdapter.TableFolders: Boolean;
begin
  Result := True;
end;

function TpgnMSSQLAdapter.ServerVersion: string;
begin
  Result := FVersion;
end;

function TpgnMSSQLAdapter.OwnSessionId: string;
begin
  Result := FSpid;
end;

function TpgnMSSQLAdapter.ListDatabases: TpgnStringArray;
begin
  // the user's databases first, then master, model, msdb, tempdb
  Result := MetaStrings('SELECT name FROM sys.databases WHERE HAS_DBACCESS(name) = 1 ' +
    'ORDER BY CASE WHEN database_id <= 4 THEN 1 ELSE 0 END, name');
end;

procedure TpgnMSSQLAdapter.UseDatabase(const ADatabase: string);
begin
  if ADatabase = '' then
  begin
    Exit;
  end;
  FConn.Run('USE ' + QuoteIdent(ADatabase), 0).Free;
  FMeta.Run('USE ' + QuoteIdent(ADatabase), 0).Free;
  FCurrentDatabase := ADatabase;
  FSchema := TryValue('SELECT SCHEMA_NAME()');
end;

function TpgnMSSQLAdapter.ListSchemas(ASystem: Boolean): TpgnStringArray;
begin
  if ASystem then
  begin
    Result := Strings(['sys', 'INFORMATION_SCHEMA']);
  end
  else
  begin
    // not the fixed role schemas (db_owner, ...: ids from 16384) or guest
    Result := MetaStrings('SELECT name FROM sys.schemas WHERE schema_id < 16384 ' +
      'AND name NOT IN (''sys'', ''INFORMATION_SCHEMA'', ''guest'') ORDER BY name');
  end;
end;

function TpgnMSSQLAdapter.CurrentSchema: string;
begin
  Result := FSchema;
  if Result = '' then
  begin
    Result := 'dbo';
  end;
end;

{ SQL Server has no "current schema" to set: unqualified names use the
  login's default schema (usually dbo). The picker is hidden for it. }
procedure TpgnMSSQLAdapter.UseSchema(const ASchema: string);
begin
  // nothing to do on the server
end;

{ ------------------------------------------------------- Explorer folders }

function TpgnMSSQLAdapter.ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray;
begin
  Result := nil;
  if AMore then
  begin
    Exit;
  end;
  case ALevel of
    flServer:
      begin
        Result := Strings(['Logins', 'Server Roles', 'Linked Servers', 'SQL Server Agent Jobs']);
      end;
    flDatabase:
      begin
        Result := Strings(['Users', 'Database Roles']);
      end;
    flSchema:
      begin
        Result := Strings(['Sequences', 'Synonyms', 'User-Defined Types']);
      end;
  end;
end;

function TpgnMSSQLAdapter.ListFolder(const AContainer, AFolder: string): TpgnStringArray;
var
  S: string;
begin
  Result := nil;
  S := 'SCHEMA_ID(' + L(AContainer) + ')';
  if AFolder = 'Sequences' then
  begin
    Result := MetaStrings('SELECT name FROM sys.sequences WHERE schema_id = ' + S + ' ORDER BY name');
  end
  else if AFolder = 'Synonyms' then
  begin
    Result := MetaStrings('SELECT name FROM sys.synonyms WHERE schema_id = ' + S + ' ORDER BY name');
  end
  else if AFolder = 'User-Defined Types' then
  begin
    Result := MetaStrings('SELECT name FROM sys.types WHERE is_user_defined = 1 AND schema_id = ' + S +
      ' ORDER BY name');
  end
  else if AFolder = 'Users' then
  begin
    Result := MetaStrings('SELECT name FROM sys.database_principals WHERE type IN (''S'', ''U'', ''G'', ' +
      '''E'', ''X'') AND principal_id > 4 ORDER BY name');
  end
  else if AFolder = 'Database Roles' then
  begin
    Result := MetaStrings('SELECT name FROM sys.database_principals WHERE type = ''R'' ORDER BY ' +
      'is_fixed_role, name');
  end
  else if AFolder = 'Logins' then
  begin
    Result := MetaStrings('SELECT name FROM sys.server_principals WHERE type IN (''S'', ''U'', ''G'', ' +
      '''E'', ''X'') AND name NOT LIKE ''##%'' ORDER BY name');
  end
  else if AFolder = 'Server Roles' then
  begin
    Result := MetaStrings('SELECT name FROM sys.server_principals WHERE type = ''R'' ORDER BY name');
  end
  else if AFolder = 'Linked Servers' then
  begin
    Result := MetaStrings('SELECT name FROM sys.servers WHERE is_linked = 1 ORDER BY name');
  end
  else if AFolder = 'SQL Server Agent Jobs' then
  begin
    try
      Result := MetaStrings('SELECT name FROM msdb.dbo.sysjobs ORDER BY name');
    except
      on E: Exception do
      begin
        Result := nil;   // Express has no Agent; other logins may not read msdb
      end;
    end;
  end;
end;

function TpgnMSSQLAdapter.FolderItemSQL(const AContainer, AFolder, AName: string): string;
begin
  Result := '';
  if AFolder = 'Sequences' then
  begin
    Result := MetaValue('SELECT ''CREATE SEQUENCE ' + StringReplace(Q2(AContainer, AName), '''', '''''',
      [rfReplaceAll]) + ''' + CHAR(10) + ''  AS '' + TYPE_NAME(s.user_type_id) + CHAR(10) + ' +
      '''  START WITH '' + CAST(s.start_value AS nvarchar(40)) + CHAR(10) + ' +
      '''  INCREMENT BY '' + CAST(s.increment AS nvarchar(40)) + CHAR(10) + ' +
      '''  MINVALUE '' + CAST(s.minimum_value AS nvarchar(40)) + CHAR(10) + ' +
      '''  MAXVALUE '' + CAST(s.maximum_value AS nvarchar(40)) + ' +
      'CASE WHEN s.is_cycling = 1 THEN CHAR(10) + ''  CYCLE'' ELSE '''' END + '';'' + CHAR(10) + ' +
      '''-- current value: '' + ISNULL(CAST(s.current_value AS nvarchar(40)), ''none'') ' +
      'FROM sys.sequences s WHERE s.object_id = ' + ObjId(AContainer, AName));
  end
  else if AFolder = 'Synonyms' then
  begin
    Result := MetaValue('SELECT ''CREATE SYNONYM ' + StringReplace(Q2(AContainer, AName), '''', '''''',
      [rfReplaceAll]) + ' FOR '' + base_object_name + '';'' FROM sys.synonyms WHERE object_id = ' +
      ObjId(AContainer, AName));
  end
  else if AFolder = 'User-Defined Types' then
  begin
    Result := MetaValue('SELECT ''CREATE TYPE ' + StringReplace(Q2(AContainer, AName), '''', '''''',
      [rfReplaceAll]) + ' FROM '' + TYPE_NAME(t.system_type_id) + ' +
      'CASE WHEN TYPE_NAME(t.system_type_id) IN (''varchar'', ''char'', ''varbinary'', ''binary'') ' +
      'THEN ''('' + CASE WHEN t.max_length = -1 THEN ''max'' ELSE CAST(t.max_length AS nvarchar(10)) END + '')'' ' +
      'WHEN TYPE_NAME(t.system_type_id) IN (''nvarchar'', ''nchar'') ' +
      'THEN ''('' + CASE WHEN t.max_length = -1 THEN ''max'' ELSE CAST(t.max_length / 2 AS nvarchar(10)) END + '')'' ' +
      'WHEN TYPE_NAME(t.system_type_id) IN (''decimal'', ''numeric'') ' +
      'THEN ''('' + CAST(t.precision AS nvarchar(10)) + '', '' + CAST(t.scale AS nvarchar(10)) + '')'' ' +
      'ELSE '''' END + CASE WHEN t.is_nullable = 0 THEN '' NOT NULL'' ELSE '''' END + '';'' ' +
      'FROM sys.types t WHERE t.is_user_defined = 1 AND t.schema_id = SCHEMA_ID(' + L(AContainer) +
      ') AND t.name = ' + L(AName));
  end
  else if AFolder = 'SQL Server Agent Jobs' then
  begin
    Result := TryValue('SELECT ''-- '' + j.name + CHAR(10) + ''-- enabled: '' + ' +
      'CASE WHEN j.enabled = 1 THEN ''yes'' ELSE ''no'' END + CHAR(10) + ''-- description: '' + ' +
      'ISNULL(j.description, '''') + CHAR(10) + ''-- steps:'' + CHAR(10) + ' +
      'ISNULL((SELECT ''--   '' + CAST(s.step_id AS nvarchar(10)) + ''. '' + s.step_name + '' ('' + ' +
      's.subsystem + '')'' + CHAR(10) FROM msdb.dbo.sysjobsteps s WHERE s.job_id = j.job_id ' +
      'ORDER BY s.step_id FOR XML PATH(''''), TYPE).value(''.'', ''nvarchar(max)''), '''') ' +
      'FROM msdb.dbo.sysjobs j WHERE j.name = ' + L(AName));
  end
  else if AFolder = 'Linked Servers' then
  begin
    Result := TryValue('SELECT ''-- linked server '' + name + CHAR(10) + ''-- product: '' + ' +
      'ISNULL(product, '''') + CHAR(10) + ''-- provider: '' + ISNULL(provider, '''') + CHAR(10) + ' +
      '''-- data source: '' + ISNULL(data_source, '''') FROM sys.servers WHERE name = ' + L(AName));
  end
  else if (AFolder = 'Logins') or (AFolder = 'Users') or (AFolder = 'Server Roles') or
    (AFolder = 'Database Roles') then
  begin
    Result := '-- ' + AName + ': the DBA screens for SQL Server come with the DBA work.';
  end;
end;

{ ------------------------------------------------------- tables, views }

function TpgnMSSQLAdapter.ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray;
var
  S: string;
begin
  S := 'SCHEMA_ID(' + L(ADatabase) + ')';
  case AKind of
    okView:
      begin
        Result := MetaStrings('SELECT name FROM sys.views WHERE schema_id = ' + S +
          ' AND is_ms_shipped = 0 ORDER BY name');
      end;
    okMatView:
      begin
        // indexed views: a view with a clustered index
        Result := MetaStrings('SELECT v.name FROM sys.views v WHERE v.schema_id = ' + S +
          ' AND EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = v.object_id AND i.index_id = 1) ' +
          'ORDER BY v.name');
      end;
  else
    begin
      Result := MetaStrings('SELECT name FROM sys.tables WHERE schema_id = ' + S +
        ' AND is_ms_shipped = 0 ORDER BY name');
    end;
  end;
end;

const
  TypeExpr =
    'TYPE_NAME(c.user_type_id) + CASE ' +
    'WHEN TYPE_NAME(c.user_type_id) IN (''varchar'', ''char'', ''varbinary'', ''binary'') ' +
    'THEN ''('' + CASE WHEN c.max_length = -1 THEN ''max'' ELSE CAST(c.max_length AS nvarchar(10)) END + '')'' ' +
    'WHEN TYPE_NAME(c.user_type_id) IN (''nvarchar'', ''nchar'') ' +
    'THEN ''('' + CASE WHEN c.max_length = -1 THEN ''max'' ELSE CAST(c.max_length / 2 AS nvarchar(10)) END + '')'' ' +
    'WHEN TYPE_NAME(c.user_type_id) IN (''decimal'', ''numeric'') ' +
    'THEN ''('' + CAST(c.precision AS nvarchar(10)) + '', '' + CAST(c.scale AS nvarchar(10)) + '')'' ' +
    'WHEN TYPE_NAME(c.user_type_id) IN (''datetime2'', ''time'', ''datetimeoffset'') ' +
    'THEN ''('' + CAST(c.scale AS nvarchar(10)) + '')'' ELSE '''' END';

function TpgnMSSQLAdapter.DescribeTable(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT c.name AS [Column], ' + TypeExpr + ' AS [Type], ' +
    'CASE WHEN c.is_nullable = 1 THEN ''YES'' ELSE ''NO'' END AS [Nullable], ' +
    'CASE WHEN EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.indexes i ' +
    'ON i.object_id = ic.object_id AND i.index_id = ic.index_id ' +
    'WHERE i.is_primary_key = 1 AND ic.object_id = c.object_id AND ic.column_id = c.column_id) ' +
    'THEN ''PRI'' ELSE '''' END AS [Key], ' +
    'CASE WHEN c.is_identity = 1 THEN ''IDENTITY('' + CAST(ic2.seed_value AS nvarchar(40)) + '', '' + ' +
    'CAST(ic2.increment_value AS nvarchar(40)) + '')'' ELSE d.definition END AS [Default], ' +
    'CAST(ep.value AS nvarchar(4000)) AS [Comment] ' +
    'FROM sys.columns c LEFT JOIN sys.default_constraints d ON d.object_id = c.default_object_id ' +
    'LEFT JOIN sys.identity_columns ic2 ON ic2.object_id = c.object_id AND ic2.column_id = c.column_id ' +
    'LEFT JOIN sys.extended_properties ep ON ep.major_id = c.object_id AND ep.minor_id = c.column_id ' +
    'AND ep.class = 1 AND ep.name = ''MS_Description'' ' +
    'WHERE c.object_id = ' + ObjId(ADatabase, ATable) + ' ORDER BY c.column_id');
end;

function TpgnMSSQLAdapter.DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT i.name AS [Index], CASE WHEN i.is_primary_key = 1 THEN ''yes'' ELSE '''' END AS [Primary], ' +
    'CASE WHEN i.is_unique = 1 THEN ''yes'' ELSE ''no'' END AS [Unique], ' +
    'LOWER(i.type_desc) + '': '' + STUFF((SELECT '', '' + c.name + ' +
    'CASE WHEN ic.is_descending_key = 1 THEN '' DESC'' ELSE '''' END ' +
    'FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id ' +
    'WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ' +
    'ORDER BY ic.key_ordinal FOR XML PATH(''''), TYPE).value(''.'', ''nvarchar(max)''), 1, 2, '''') ' +
    'AS [Definition] FROM sys.indexes i WHERE i.object_id = ' + ObjId(ADatabase, ATable) +
    ' AND i.index_id > 0 ORDER BY i.is_primary_key DESC, i.name');
end;

{ Views: their definition as stored. Tables: put together from the catalog
  (columns, defaults, identity, primary key). }
function TpgnMSSQLAdapter.GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string;
var
  Cols, Pk: TpgnStringArray;
  PkName: string;
  I: Integer;
begin
  if AKind in [okView, okMatView] then
  begin
    Result := TrimRight(MetaValue('SELECT OBJECT_DEFINITION(' + ObjId(ADatabase, AObject) + ')'));
    if Result = '' then
    begin
      raise Exception.Create('The definition of ' + ADatabase + '.' + AObject + ' can''t be read ' +
        '(it is encrypted, or this login lacks VIEW DEFINITION).');
    end;
    Exit;
  end;
  Cols := MetaStrings('SELECT ''['' + REPLACE(c.name, '']'', '']]'') + ''] '' + ' + TypeExpr + ' + ' +
    'CASE WHEN c.is_identity = 1 THEN '' IDENTITY('' + CAST(ic.seed_value AS nvarchar(40)) + '', '' + ' +
    'CAST(ic.increment_value AS nvarchar(40)) + '')'' ELSE '''' END + ' +
    'CASE WHEN c.is_nullable = 1 THEN '' NULL'' ELSE '' NOT NULL'' END + ' +
    'ISNULL('' DEFAULT '' + d.definition, '''') FROM sys.columns c ' +
    'LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id ' +
    'LEFT JOIN sys.default_constraints d ON d.object_id = c.default_object_id ' +
    'WHERE c.object_id = ' + ObjId(ADatabase, AObject) + ' ORDER BY c.column_id');
  if Length(Cols) = 0 then
  begin
    raise Exception.Create(ADatabase + '.' + AObject + ' was not found.');
  end;
  PkName := TryValue('SELECT name FROM sys.indexes WHERE is_primary_key = 1 AND object_id = ' +
    ObjId(ADatabase, AObject));
  Pk := MetaStrings('SELECT ''['' + REPLACE(c.name, '']'', '']]'') + '']'' FROM sys.indexes i ' +
    'JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id ' +
    'JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id ' +
    'WHERE i.is_primary_key = 1 AND i.object_id = ' + ObjId(ADatabase, AObject) + ' ORDER BY ic.key_ordinal');
  Result := 'CREATE TABLE ' + Q2(ADatabase, AObject) + ' (';
  for I := 0 to High(Cols) do
  begin
    Result := Result + LineEnding + '  ' + Cols[I];
    if (I < High(Cols)) or (Length(Pk) > 0) then
    begin
      Result := Result + ',';
    end;
  end;
  if Length(Pk) > 0 then
  begin
    Result := Result + LineEnding + '  CONSTRAINT ' + QuoteIdent(PkName) + ' PRIMARY KEY (';
    for I := 0 to High(Pk) do
    begin
      if I > 0 then
      begin
        Result := Result + ', ';
      end;
      Result := Result + Pk[I];
    end;
    Result := Result + ')';
  end;
  Result := Result + LineEnding + ');';
end;

function TpgnMSSQLAdapter.ListObjectNames(const ADatabase: string): TpgnStringArray;
begin
  Result := MetaStrings('SELECT name FROM sys.objects WHERE schema_id = SCHEMA_ID(' + L(ADatabase) +
    ') AND type IN (''U'', ''V'', ''P'', ''FN'', ''IF'', ''TF'', ''SN'', ''SO'')');
end;

{ Takes a result's last column away (a column only there to sort by). }
procedure DropLastColumn(R: TpgnResultSet);
var
  I, N: Integer;
begin
  N := Length(R.Columns) - 1;
  SetLength(R.Columns, N);
  for I := 0 to R.RowCount - 1 do
  begin
    SetLength(R.Rows[I].Values, N);
    SetLength(R.Rows[I].Nulls, N);
  end;
end;

function TpgnMSSQLAdapter.DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet;
var
  Obj: string;
begin
  Obj := 'OBJECT_ID(' + L(QuoteIdent(ADatabase) + '.' + QuoteIdent(ATable)) + ')';
  Result := MetaResult(
    'SELECT k.name AS [Constraint], CASE k.type WHEN ''PK'' THEN ''Primary key'' ELSE ''Unique'' END AS [Type], ' +
    'STUFF((SELECT '', '' + c.name FROM sys.index_columns ic JOIN sys.columns c ' +
    'ON c.object_id = ic.object_id AND c.column_id = ic.column_id ' +
    'WHERE ic.object_id = k.parent_object_id AND ic.index_id = k.unique_index_id ' +
    'ORDER BY ic.key_ordinal FOR XML PATH('''')), 1, 2, '''') AS [Columns], ' +
    'CAST(NULL AS nvarchar(max)) AS [Details], CASE k.type WHEN ''PK'' THEN 1 ELSE 2 END AS ord ' +
    'FROM sys.key_constraints k WHERE k.parent_object_id = ' + Obj +
    ' UNION ALL SELECT f.name, ''Foreign key'', ' +
    'STUFF((SELECT '', '' + COL_NAME(fc.parent_object_id, fc.parent_column_id) FROM sys.foreign_key_columns fc ' +
    'WHERE fc.constraint_object_id = f.object_id ORDER BY fc.constraint_column_id FOR XML PATH('''')), 1, 2, ''''), ' +
    'OBJECT_SCHEMA_NAME(f.referenced_object_id) + ''.'' + OBJECT_NAME(f.referenced_object_id), 3 ' +
    'FROM sys.foreign_keys f WHERE f.parent_object_id = ' + Obj +
    ' UNION ALL SELECT cc.name, ''Check'', COL_NAME(cc.parent_object_id, NULLIF(cc.parent_column_id, 0)), ' +
    'cc.definition, 4 FROM sys.check_constraints cc WHERE cc.parent_object_id = ' + Obj +
    ' UNION ALL SELECT dc.name, ''Default'', COL_NAME(dc.parent_object_id, dc.parent_column_id), ' +
    'dc.definition, 5 FROM sys.default_constraints dc WHERE dc.parent_object_id = ' + Obj +
    ' ORDER BY ord, 1');
  // the sort column isn't for showing
  if (Result <> nil) and (Length(Result.Columns) = 5) then
  begin
    DropLastColumn(Result);
  end;
end;

function TpgnMSSQLAdapter.DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet;
var
  Obj: string;
begin
  Obj := 'OBJECT_ID(' + L(QuoteIdent(ADatabase) + '.' + QuoteIdent(AName)) + ')';
  Result := MetaResult(
    'SELECT DISTINCT OBJECT_SCHEMA_NAME(d.referencing_id) AS [Schema], OBJECT_NAME(d.referencing_id) AS [Name], ' +
    'CASE o.type WHEN ''V'' THEN ''View'' WHEN ''P'' THEN ''Procedure'' WHEN ''TR'' THEN ''Trigger'' ' +
    'WHEN ''FN'' THEN ''Function'' WHEN ''IF'' THEN ''Function'' WHEN ''TF'' THEN ''Function'' ' +
    'ELSE o.type_desc END AS [Type] ' +
    'FROM sys.sql_expression_dependencies d JOIN sys.objects o ON o.object_id = d.referencing_id ' +
    'WHERE d.referenced_id = ' + Obj +
    ' UNION SELECT OBJECT_SCHEMA_NAME(f.parent_object_id), OBJECT_NAME(f.parent_object_id), ''Table (foreign key)'' ' +
    'FROM sys.foreign_keys f WHERE f.referenced_object_id = ' + Obj + ' AND f.parent_object_id <> ' + Obj +
    ' ORDER BY 3, 1, 2');
end;

function TpgnMSSQLAdapter.SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs;
var
  R: TpgnResultSet;
  I: Integer;
  Pattern: string;
begin
  Result := nil;
  Pattern := '%' + StringReplace(StringReplace(StringReplace(AText, '[', '[[]', [rfReplaceAll]),
    '%', '[%]', [rfReplaceAll]), '_', '[_]', [rfReplaceAll]) + '%';
  R := MetaResult('SELECT TOP (' + IntToStr(AMax) + ') SCHEMA_NAME(schema_id), name, ' +
    'CASE type WHEN ''U'' THEN ''Table'' WHEN ''V'' THEN ''View'' WHEN ''P'' THEN ''Procedure'' ' +
    'ELSE ''Function'' END FROM sys.objects WHERE type IN (''U'', ''V'', ''P'', ''FN'', ''IF'', ''TF'') ' +
    'AND is_ms_shipped = 0 AND name LIKE ' + L(Pattern) + ' ORDER BY name');
  try
    SetLength(Result, R.RowCount);
    for I := 0 to R.RowCount - 1 do
    begin
      Result[I].Database := FCurrentDatabase;
      Result[I].Schema := R.Rows[I].Values[0];
      Result[I].Name := R.Rows[I].Values[1];
      Result[I].Kind := R.Rows[I].Values[2];
    end;
  finally
    R.Free;
  end;
end;

{ ------------------------------------------- procedures, functions, triggers }

function TypeList(AKind: TpgnRoutineKind): string;
begin
  case AKind of
    rkProcedure:
      begin
        Result := '(''P'', ''PC'')';
      end;
    rkFunction:
      begin
        Result := '(''FN'', ''IF'', ''TF'', ''FS'', ''FT'')';
      end;
  else
    begin
      Result := '(''TR'')';
    end;
  end;
end;

function TpgnMSSQLAdapter.ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray;
begin
  // a trigger is in its table's schema
  Result := MetaStrings('SELECT name FROM sys.objects WHERE schema_id = SCHEMA_ID(' + L(ADatabase) +
    ') AND type IN ' + TypeList(AKind) + ' AND is_ms_shipped = 0 ORDER BY name');
end;

function TpgnMSSQLAdapter.GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := TrimRight(MetaValue('SELECT OBJECT_DEFINITION(' + ObjId(ADatabase, AName) + ')'));
end;

function TpgnMSSQLAdapter.RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean;
begin
  Result := MetaValue('SELECT COUNT(*) FROM sys.objects WHERE object_id = ' + ObjId(ADatabase, AName) +
    ' AND type IN ' + TypeList(AKind)) <> '0';
end;

function TpgnMSSQLAdapter.DescribeParameters(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT CASE WHEN p.parameter_id = 0 THEN ''RETURNS'' WHEN p.is_output = 1 THEN ''OUT'' ' +
    'ELSE ''IN'' END AS [Mode], CASE WHEN p.parameter_id = 0 THEN '' '' ELSE p.name END AS [Parameter], ' +
    'TYPE_NAME(p.user_type_id) + CASE ' +
    'WHEN TYPE_NAME(p.user_type_id) IN (''varchar'', ''char'', ''varbinary'', ''binary'') ' +
    'THEN ''('' + CASE WHEN p.max_length = -1 THEN ''max'' ELSE CAST(p.max_length AS nvarchar(10)) END + '')'' ' +
    'WHEN TYPE_NAME(p.user_type_id) IN (''nvarchar'', ''nchar'') ' +
    'THEN ''('' + CASE WHEN p.max_length = -1 THEN ''max'' ELSE CAST(p.max_length / 2 AS nvarchar(10)) END + '')'' ' +
    'WHEN TYPE_NAME(p.user_type_id) IN (''decimal'', ''numeric'') ' +
    'THEN ''('' + CAST(p.precision AS nvarchar(10)) + '', '' + CAST(p.scale AS nvarchar(10)) + '')'' ' +
    'ELSE '''' END AS [Type] FROM sys.parameters p WHERE p.object_id = ' + ObjId(ADatabase, AName) +
    ' ORDER BY p.parameter_id');
end;

function TpgnMSSQLAdapter.DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT t.name AS [Trigger], CASE WHEN t.is_instead_of_trigger = 1 THEN ''INSTEAD OF'' ' +
    'ELSE ''AFTER'' END AS [Timing], STUFF((SELECT '', '' + e.type_desc FROM sys.trigger_events e ' +
    'WHERE e.object_id = t.object_id FOR XML PATH(''''), TYPE).value(''.'', ''nvarchar(max)''), 1, 2, '''') ' +
    'AS [Event], CASE WHEN t.is_disabled = 1 THEN ''no'' ELSE ''yes'' END AS [Enabled] ' +
    'FROM sys.triggers t WHERE t.parent_id = ' + ObjId(ADatabase, ATable) + ' ORDER BY t.name');
end;

function TpgnMSSQLAdapter.DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT pr.name AS [Grantee], STUFF((SELECT '', '' + p2.permission_name + ' +
    'CASE p2.state WHEN ''W'' THEN '' (can grant)'' WHEN ''D'' THEN '' (DENIED)'' ELSE '''' END ' +
    'FROM sys.database_permissions p2 WHERE p2.major_id = p.major_id AND p2.grantee_principal_id = ' +
    'p.grantee_principal_id AND p2.class = 1 ORDER BY p2.permission_name FOR XML PATH(''''), TYPE)' +
    '.value(''.'', ''nvarchar(max)''), 1, 2, '''') AS [Privileges], g.name AS [Granted by] ' +
    'FROM sys.database_permissions p JOIN sys.database_principals pr ON pr.principal_id = ' +
    'p.grantee_principal_id JOIN sys.database_principals g ON g.principal_id = p.grantor_principal_id ' +
    'WHERE p.class = 1 AND p.major_id = ' + ObjId(ADatabase, AName) +
    ' GROUP BY p.major_id, p.grantee_principal_id, pr.name, g.name ORDER BY pr.name');
end;

{ "CREATE PROCEDURE x" -> "CREATE OR ALTER PROCEDURE [schema].x": saving
  keeps the object (and its grants); an unqualified name lands in the
  schema the tab is for. }
function TpgnMSSQLAdapter.SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
  const ASQL: string; ALog: TStrings): string;
var
  St, Len, P, Q: Integer;
  NewName, Kw, Written, SQL, U: string;
begin
  Result := '';
  if not FindCreateName(ASQL, St, Len, NewName, Kw) then
  begin
    raise Exception.Create('The editor should hold one CREATE ' + RoutineWord[AKind] + ' statement.');
  end;
  if Kw <> RoutineWord[AKind] then
  begin
    raise Exception.Create('The text creates a ' + LowerCase(Kw) + ', but this tab is a ' +
      LowerCase(RoutineWord[AKind]) + '. Nothing was changed.');
  end;
  SQL := ASQL;
  Written := Copy(SQL, St, Len);
  if Pos('.', Written) = 0 then
  begin
    // the schema in front of the name
    Delete(SQL, St, Len);
    Insert(QuoteIdent(ADatabase) + '.' + Written, SQL, St);
  end;
  // CREATE [OR ALTER] -> CREATE OR ALTER
  U := UpperCase(SQL);
  P := Pos('CREATE', U);
  if (P > 0) and (P < St) then
  begin
    Q := P + 6;
    while (Q <= Length(U)) and (U[Q] in [' ', #9, #10, #13]) do
    begin
      Inc(Q);
    end;
    if Copy(U, Q, 2) <> 'OR' then
    begin
      Insert(' OR ALTER', SQL, P + 6);
    end;
  end;
  SQL := TrimRight(SQL);
  while (SQL <> '') and (SQL[Length(SQL)] = ';') do
  begin
    SQL := TrimRight(Copy(SQL, 1, Length(SQL) - 1));
  end;
  try
    MetaExec(SQL);
  except
    on E: Exception do
    begin
      raise Exception.Create('Nothing was changed: ' + E.Message);
    end;
  end;
  Result := NewName;
  if AOldName = '' then
  begin
    ALog.Add('Created ' + LowerCase(Kw) + ' ' + ADatabase + '.' + NewName);
  end
  else
  begin
    ALog.Add('Saved ' + LowerCase(Kw) + ' ' + ADatabase + '.' + NewName + ' (grants kept)');
    if not SameText(NewName, AOldName) then
    begin
      ALog.Add('WARNING: the name changed, so this is a new ' + LowerCase(Kw) + '. ' + AOldName +
        ' is still there; drop it if it''s no longer needed.');
    end;
  end;
end;

{ --------------------------------------------- SQL for the forms and menus }

function TpgnMSSQLAdapter.RoutineTarget(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := Q2(ADatabase, AName);
end;

function TpgnMSSQLAdapter.DropRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := 'DROP ' + RoutineWord[AKind] + ' ' + Q2(ADatabase, AName);
end;

{ sp_help: the columns, and the indexes, constraints and identity after
  them (Seattle stacks the result sets, as SSMS). }
function TpgnMSSQLAdapter.DescribeSQL(const ADatabase, ATable: string): string;
begin
  Result := 'EXEC sp_help ' + L(Q2(ADatabase, ATable));
end;

function TpgnMSSQLAdapter.SelectTopSQL(const AQualifiedName: string; ARows: Integer): string;
begin
  Result := 'SELECT TOP (' + IntToStr(ARows) + ') * FROM ' + AQualifiedName;
end;

function ParamName(const AName: string): string;
begin
  Result := Trim(AName);
  if (Result <> '') and (Result[1] <> '@') then
  begin
    Result := '@' + Result;
  end;
end;

function TpgnMSSQLAdapter.NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs; const AReturns: string): string;
var
  I: Integer;
  Params, Mode: string;
begin
  Params := '';
  for I := 0 to High(AParams) do
  begin
    Mode := UpperCase(AParams[I].Mode);
    if I > 0 then
    begin
      Params := Params + ',';
    end;
    Params := Params + LineEnding + '  ' + ParamName(AParams[I].Name) + ' ' + AParams[I].DataType;
    if (Mode = 'OUT') or (Mode = 'INOUT') then
    begin
      Params := Params + ' OUTPUT';
    end;
  end;
  if AKind = rkProcedure then
  begin
    Result := 'CREATE OR ALTER PROCEDURE ' + QuoteIdent(AName) + Params + LineEnding + 'AS' + LineEnding +
      'BEGIN' + LineEnding + '  SET NOCOUNT ON;' + LineEnding + '  -- your code here' + LineEnding + 'END';
  end
  else
  begin
    if Params <> '' then
    begin
      Params := ' (' + Params + LineEnding + ')';
    end
    else
    begin
      Params := ' ()';
    end;
    Result := 'CREATE OR ALTER FUNCTION ' + QuoteIdent(AName) + Params + LineEnding + 'RETURNS ' + AReturns +
      LineEnding + 'AS' + LineEnding + 'BEGIN' + LineEnding + '  -- your code here' + LineEnding +
      '  RETURN NULL;' + LineEnding + 'END';
  end;
end;

function TpgnMSSQLAdapter.NewTriggerSQL(const ADatabase, ATable: string): string;
begin
  Result := 'CREATE OR ALTER TRIGGER ' + Q2(ADatabase, 'trg_' + ATable) + LineEnding +
    'ON ' + Q2(ADatabase, ATable) + LineEnding +
    'AFTER INSERT, UPDATE' + LineEnding +
    '-- timing: AFTER or INSTEAD OF;  events: INSERT, UPDATE, DELETE' + LineEnding +
    'AS' + LineEnding + 'BEGIN' + LineEnding + '  SET NOCOUNT ON;' + LineEnding +
    '  -- the changed rows are in the inserted and deleted tables' + LineEnding + 'END';
end;

{ A procedure runs with EXEC; OUTPUT parameters are declared, passed and
  shown after it. A scalar function is SELECTed; a table-valued one is
  SELECTed FROM. }
function TpgnMSSQLAdapter.ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs): string;
var
  I: Integer;
  Args, Decl, Shows, Mode, V, Value: string;
  Scalar: Boolean;
begin
  Args := '';
  Decl := '';
  Shows := '';
  Scalar := False;
  for I := 0 to High(AParams) do
  begin
    Mode := UpperCase(AParams[I].Mode);
    if Mode = 'RETURNS' then
    begin
      Scalar := True;
      Continue;
    end;
    if AParams[I].IsNull then
    begin
      Value := 'NULL';
    end
    else
    begin
      Value := AParams[I].Value;
    end;
    if Args <> '' then
    begin
      Args := Args + ', ';
    end;
    if AKind = rkFunction then
    begin
      Args := Args + Value;
    end
    else if (Mode = 'OUT') or (Mode = 'INOUT') then
    begin
      V := '@out_' + Copy(ParamName(AParams[I].Name), 2, 100);
      Decl := Decl + 'DECLARE ' + V + ' ' + AParams[I].DataType;
      if (Mode = 'INOUT') and (Value <> '') then
      begin
        Decl := Decl + ' = ' + Value;
      end;
      Decl := Decl + ';' + LineEnding;
      Args := Args + ParamName(AParams[I].Name) + ' = ' + V + ' OUTPUT';
      if Shows <> '' then
      begin
        Shows := Shows + ', ';
      end;
      Shows := Shows + V + ' AS ' + QuoteIdent(ParamName(AParams[I].Name));
    end
    else
    begin
      Args := Args + ParamName(AParams[I].Name) + ' = ' + Value;
    end;
  end;
  if AKind = rkFunction then
  begin
    if Scalar then
    begin
      Result := 'SELECT ' + Q2(ADatabase, AName) + '(' + Args + ') AS [result];';
    end
    else
    begin
      Result := 'SELECT * FROM ' + Q2(ADatabase, AName) + '(' + Args + ');';
    end;
    Exit;
  end;
  Result := Decl + 'EXEC ' + Q2(ADatabase, AName);
  if Args <> '' then
  begin
    Result := Result + ' ' + Args;
  end;
  Result := Result + ';';
  if Shows <> '' then
  begin
    Result := Result + LineEnding + 'SELECT ' + Shows + ';';
  end;
end;

function TpgnMSSQLAdapter.GrantRights(const AObjectWord: string): TpgnStringArray;
begin
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    Result := Strings(['EXECUTE', 'VIEW DEFINITION', 'ALTER', 'CONTROL']);
  end
  else if AObjectWord = 'VIEW' then
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'VIEW DEFINITION']);
  end
  else
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'REFERENCES', 'ALTER', 'VIEW DEFINITION',
      'CONTROL']);
  end;
end;

function TpgnMSSQLAdapter.GranteeHint: string;
begin
  Result := 'To (a database user or role, e.g. reports_reader, or public for everyone)';
end;

function TpgnMSSQLAdapter.GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
  AWithGrantOption: Boolean): string;
var
  Who: string;
begin
  Who := Trim(AGrantee);
  if SameText(Who, 'public') then
  begin
    Who := 'public';
  end
  else
  begin
    Who := QuoteIdent(Who);
  end;
  Result := 'GRANT ' + ARights + ' ON ' + Q2(ADatabase, AName) + ' TO ' + Who;
  if AWithGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
  Result := Result + ';';
end;

{ ----------------------------------------------------------- running }

{ Pagona's own savepoint statements in SQL Server's words, the Explain
  button's "EXPLAIN ...", then the batch as written. }
function TpgnMSSQLAdapter.Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
var
  S, U, Name: string;
  R: TpgnResultSet;
begin
  S := Trim(ASQL);
  U := UpperCase(S);
  if Copy(U, 1, 10) = 'SAVEPOINT ' then
  begin
    Name := Trim(Copy(S, 11, MaxInt));
    // SAVE TRANSACTION needs one open; implicit transactions open it on
    // the first change, which comes after this
    Result := FConn.Run('IF @@TRANCOUNT = 0 BEGIN TRANSACTION; SAVE TRANSACTION ' + Name, 0);
    Result.Messages := nil;
    Exit;
  end;
  if Copy(U, 1, 22) = 'ROLLBACK TO SAVEPOINT ' then
  begin
    Name := Trim(Copy(S, 23, MaxInt));
    Result := FConn.Run('ROLLBACK TRANSACTION ' + Name, 0);
    Result.Messages := nil;
    Exit;
  end;
  if (FirstKeyword(S) = 'EXPLAIN') then
  begin
    // the estimated plan, without running the statement
    FConn.Run('SET SHOWPLAN_ALL ON', 0).Free;
    try
      try
        R := FConn.Run(Trim(Copy(S, 8, MaxInt)), 0);
      except
        on E: EpgnOdbcError do
        begin
          if E.NativeError = 262 then
          begin
            E.Message := E.Message + LineEnding + LineEnding +
              'This login needs SHOWPLAN permission in the database to see plans. ' +
              'A DBA can give it with: GRANT SHOWPLAN TO <user>';
          end;
          raise;
        end;
      end;
    finally
      FConn.Run('SET SHOWPLAN_ALL OFF', 0).Free;
    end;
    Result := PlanGrid(R);
    Exit;
  end;
  Result := FConn.Run(S, ARowLimit);
  // a USE in the batch changes the tab's database
  if Pos('USE', U) > 0 then
  begin
    try
      R := FConn.Run('SELECT DB_NAME(), SCHEMA_NAME()', 0);
      try
        if R.RowCount > 0 then
        begin
          FCurrentDatabase := R.Rows[0].Values[0];
          FSchema := R.Rows[0].Values[1];
        end;
      finally
        R.Free;
      end;
    except
      on E: Exception do
      begin
        // the picker just stays as it was
      end;
    end;
  end;
end;

procedure TpgnMSSQLAdapter.CancelCurrent;
begin
  FConn.Cancel;
end;

procedure TpgnMSSQLAdapter.SetAutoCommit(AValue: Boolean);
begin
  if AValue = FAutoCommit then
  begin
    Exit;
  end;
  if FConn.Connected then
  begin
    if AValue then
    begin
      FConn.Run('IF @@TRANCOUNT > 0 COMMIT TRANSACTION; SET IMPLICIT_TRANSACTIONS OFF', 0).Free;
    end
    else
    begin
      FConn.Run('SET IMPLICIT_TRANSACTIONS ON', 0).Free;
    end;
  end;
  FAutoCommit := AValue;
end;

function TpgnMSSQLAdapter.AutoCommit: Boolean;
begin
  Result := FAutoCommit;
end;

procedure TpgnMSSQLAdapter.Commit;
begin
  FConn.Run('IF @@TRANCOUNT > 0 COMMIT TRANSACTION', 0).Free;
end;

procedure TpgnMSSQLAdapter.Rollback;
begin
  FConn.Run('IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION', 0).Free;
end;

end.
