// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapterPG;

{ PostgreSQL adapter, built on ZeosLib (libpq).

  Like the MySQL adapter it holds two connections, FConn for the user's
  statements (worker thread) and FMeta for the Explorer (main thread).

  PostgreSQL differs from MySQL in ways the rest of Pagona sees through
  TpgnAdapter:
    - a session sees one database; the Explorer opens one session per
      database (NewSession), and a tab reconnects to change database;
    - tables and code live in schemas, which play the part MySQL's
      databases play: every "ADatabase" (container) argument below is a
      schema of this session's database;
    - functions can share a name, so they are named with their argument
      types: "calc_hours(integer, character varying)";
    - DDL is transactional, so saves can be all-or-nothing.

  Catalog values are written into the SQL as quoted literals (never
  built from unchecked text), which keeps the queries independent of how
  the driver handles parameters. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ZConnection,
  pgnTypes, pgnAdapter, pgnSqlSplit, pgnZeos;

type
  TpgnPostgresAdapter = class(TpgnAdapter)
  private
    FConn: TZConnection;
    FMeta: TZConnection;
    FBackendPid: Int64;
    FVersion: string;
    FSchema: string;
    FAutoCommit: Boolean;
    procedure Configure(AConn: TZConnection);
    function MetaResult(const ASQL: string): TpgnResultSet;
    function MetaStrings(const ASQL: string): TpgnStringArray;
    function MetaValue(const ASQL: string): string;
    procedure MetaExec(const ASQL: string);
    function L(const AText: string): string;
    function RelLiteral(const ASchema, AName: string): string;
    function ProcOid(const ASchema, AName: string): string;
    function TriggerTable(const ASchema, ATrigger: string): string;
    procedure ReadSessionState;
    function UserSchemaFilter(const AColumn: string): string;
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
    function ResolveObject(const AName, ADefault: string; out ARef: TpgnObjectRef;
      out AVia: string): Boolean; override;
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
    function NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs; const AReturns: string): string; override;
    function NewTriggerSQL(const ADatabase, ATable: string): string; override;
    function ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs): string; override;
    function GrantRights(const AObjectWord: string): TpgnStringArray; override;
    function GranteeHint: string; override;
    function GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
      AWithGrantOption: Boolean): string; override;

    function ListSessions: TpgnResultSet; override;
    function ListLocks: TpgnResultSet; override;
    function SessionStatement(const ASession: string): string; override;
    function CancelSession(const ASession: string): string; override;
    function KillSession(const ASession: string): string; override;

    function RoleOid(const AAccount: TpgnAccount): string;
    function HasRoles: Boolean; override;
    function ListAccounts(ASystem: Boolean): TpgnAccounts; override;
    function AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs; override;
    function AlterAccountSQL(const AAccount: TpgnAccount;
      const AOld, ANew: TpgnAccountAttrs): TpgnStringArray; override;
    function CreateAccountSQL(const AAccount: TpgnAccount; const APassword: string): TpgnStringArray; override;
    function PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string; override;
    function AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet; override;
    function AccountMembers(const AAccount: TpgnAccount): TpgnResultSet; override;
    function GrantRoleSQL(const ARole, AMember: TpgnAccount; AAdmin: Boolean): TpgnStringArray; override;
    function RevokeRoleSQL(const ARole, AMember: TpgnAccount): string; override;
    function AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet; override;
    function RevokePrivilegeSQL(const AAccount: TpgnAccount;
      const AObject, AType, APrivilege: string): string; override;
    function GrantPrivilegeSQL(const AAccount: TpgnAccount;
      const AObject, AType, APrivilege: string; AGrantOption: Boolean): string; override;
    function AccountDDL(const AAccount: TpgnAccount): string; override;
    function AccountOwns(const AAccount: TpgnAccount): TpgnResultSet; override;
    function CanReassignOwned: Boolean; override;
    function DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
      ADropOwned: Boolean): TpgnStringArray; override;
    procedure RunAdmin(const ASQL: string); override;
    function ObjectAccess(const AKind, AContainer, AName: string;
      AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet; override;
    function PublicAccess(const AKind, AContainer, AName: string): string; override;
    function RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string; override;
    function AccessSource(const AKind, AContainer, AName: string): string;
    function MissingRight(const AAction: string): string; override;
    function GrantTargets: TpgnStringArray; override;
    function GrantTargetCaption(const AKind: string): string; override;
    function GrantContainerCaption(const AKind: string): string; override;
    function GrantContainers(const AKind: string): TpgnStringArray; override;
    function GrantNeedsObject(const AKind: string): Boolean; override;
    function GrantObjects(const AKind, AContainer: string): TpgnStringArray; override;
    function GrantObjectText(const AKind, AContainer, AName: string): string; override;
    function GrantPrivileges(const AKind: string): TpgnStringArray; override;

    function Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet; override;
    procedure CancelCurrent; override;

    function QuoteIdent(const AName: string): string; override;
    procedure UseDatabase(const ADatabase: string); override;
    procedure SetAutoCommit(AValue: Boolean); override;
    function AutoCommit: Boolean; override;
    procedure Commit; override;
    procedure Rollback; override;
  end;

{ "calc_hours(integer, text)" -> "calc_hours"; a plain name stays as it is. }
function RoutineBaseName(const AName: string): string;

{ "calc_hours(integer, text)" -> "integer, text"; '' when there is no list. }
function RoutineArgTypes(const AName: string): string;

implementation

const
  { Words PostgreSQL won't take as a bare name. Not the full list: names
    outside it that clash still work quoted by hand. }
  ReservedWords: array[0..63] of string = (
    'all', 'analyse', 'analyze', 'and', 'any', 'array', 'as', 'asc', 'asymmetric', 'both',
    'case', 'cast', 'check', 'collate', 'column', 'constraint', 'create', 'current_catalog',
    'current_date', 'current_role', 'current_time', 'current_timestamp', 'current_user',
    'default', 'deferrable', 'desc', 'distinct', 'do', 'else', 'end', 'except', 'false',
    'fetch', 'for', 'foreign', 'from', 'grant', 'group', 'having', 'in', 'initially',
    'intersect', 'into', 'lateral', 'leading', 'limit', 'localtime', 'localtimestamp', 'not',
    'null', 'offset', 'on', 'only', 'or', 'order', 'placing', 'primary', 'references',
    'returning', 'select', 'session_user', 'some', 'symmetric', 'table');
  MoreReserved: array[0..11] of string = (
    'then', 'to', 'trailing', 'true', 'union', 'unique', 'user', 'using', 'variadic',
    'when', 'where', 'window');

function RoutineBaseName(const AName: string): string;
var
  P: Integer;
begin
  P := Pos('(', AName);
  if P > 0 then
  begin
    Result := Copy(AName, 1, P - 1);
  end
  else
  begin
    Result := AName;
  end;
end;

function RoutineArgTypes(const AName: string): string;
var
  P: Integer;
begin
  Result := '';
  P := Pos('(', AName);
  if (P > 0) and (AName[Length(AName)] = ')') then
  begin
    Result := Copy(AName, P + 1, Length(AName) - P - 1);
  end;
end;

{ Always in double quotes (for names handed to to_regclass and friends). }
function QuoteAlways(const AName: string): string;
begin
  Result := '"' + StringReplace(AName, '"', '""', [rfReplaceAll]) + '"';
end;

constructor TpgnPostgresAdapter.Create(const AInfo: TpgnConnectionInfo; const APassword: string);
begin
  inherited Create(AInfo, APassword);
  if FInfo.DefaultDatabase = '' then
  begin
    FInfo.DefaultDatabase := 'postgres';   // every server has it
  end;
  FCurrentDatabase := FInfo.DefaultDatabase;
  FConn := TZConnection.Create(nil);
  FMeta := TZConnection.Create(nil);
  FAutoCommit := True;
end;

destructor TpgnPostgresAdapter.Destroy;
begin
  Disconnect;
  FreeAndNil(FMeta);
  FreeAndNil(FConn);
  inherited Destroy;
end;

procedure TpgnPostgresAdapter.Configure(AConn: TZConnection);
begin
  AConn.Protocol := 'postgresql';
  AConn.HostName := FInfo.Host;
  AConn.Port := FInfo.Port;
  AConn.User := FInfo.User;
  AConn.Password := FPassword;
  AConn.Database := FCurrentDatabase;
  AConn.LoginPrompt := False;
  AConn.AutoCommit := True;   // transactions are plain SQL, see SetAutoCommit
  if FInfo.ClientLibrary <> '' then
  begin
    AConn.LibraryLocation := FInfo.ClientLibrary;
  end;
  AConn.Properties.Values['codepage'] := 'UTF8';
  // TLS: "require" encrypts; with a CA file the server's certificate and
  // name are checked too. Without TLS, libpq still uses it if offered.
  if FInfo.UseTLS then
  begin
    if FInfo.TLSCAFile <> '' then
    begin
      AConn.Properties.Values['sslmode'] := 'verify-full';
      AConn.Properties.Values['sslrootcert'] := FInfo.TLSCAFile;
    end
    else
    begin
      AConn.Properties.Values['sslmode'] := 'require';
    end;
  end
  else
  begin
    AConn.Properties.Values['sslmode'] := 'prefer';
  end;
end;

procedure TpgnPostgresAdapter.ReadSessionState;
var
  R: TpgnResultSet;
begin
  R := RunStatement(FConn, 'SELECT pg_backend_pid(), current_setting(''server_version''), ' +
    'current_database(), current_schema()', 0);
  try
    if R.RowCount > 0 then
    begin
      FBackendPid := StrToInt64Def(R.Rows[0].Values[0], 0);
      FVersion := R.Rows[0].Values[1];
      if Pos(' ', FVersion) > 0 then
      begin
        FVersion := Copy(FVersion, 1, Pos(' ', FVersion) - 1);   // "16.4 (Debian ...)"
      end;
      FCurrentDatabase := R.Rows[0].Values[2];
      FSchema := R.Rows[0].Values[3];
    end;
  finally
    R.Free;
  end;
end;

procedure TpgnPostgresAdapter.Connect;
begin
  Configure(FConn);
  try
    FConn.Connect;
  except
    on E: Exception do
    begin
      if Pos('does not support SSL', E.Message) > 0 then
      begin
        raise Exception.Create('This server doesn''t offer TLS (it has no certificate set up), ' +
          'so a TLS connection isn''t possible. Turn off "Use TLS" for this connection, or ask ' +
          'the server''s administrator to turn on SSL. (' + Trim(E.Message) + ')');
      end;
      raise;
    end;
  end;
  Configure(FMeta);
  FMeta.Connect;
  // literals below are written the standard way: '' for a quote, \ as is
  MetaExec('SET standard_conforming_strings = on');
  ReadSessionState;
  if not FAutoCommit then
  begin
    FConn.ExecuteDirect('BEGIN');
  end;
end;

procedure TpgnPostgresAdapter.Disconnect;
begin
  if (FConn <> nil) and FConn.Connected then
  begin
    FConn.Disconnect;
  end;
  if (FMeta <> nil) and FMeta.Connected then
  begin
    FMeta.Disconnect;
  end;
  FBackendPid := 0;
end;

function TpgnPostgresAdapter.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.Connected;
end;

{ ------------------------------------------------------------- helpers }

function TpgnPostgresAdapter.MetaResult(const ASQL: string): TpgnResultSet;
begin
  Result := RunStatement(FMeta, ASQL, 0);
end;

function TpgnPostgresAdapter.MetaStrings(const ASQL: string): TpgnStringArray;
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

function TpgnPostgresAdapter.MetaValue(const ASQL: string): string;
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

procedure TpgnPostgresAdapter.MetaExec(const ASQL: string);
begin
  RunStatement(FMeta, ASQL, 0).Free;
end;

function TpgnPostgresAdapter.L(const AText: string): string;
begin
  Result := QuoteLiteral(AText);
end;

{ A table, view or sequence as an oid expression. }
function TpgnPostgresAdapter.RelLiteral(const ASchema, AName: string): string;
begin
  Result := 'to_regclass(' + L(QuoteAlways(ASchema) + '.' + QuoteAlways(AName)) + ')';
end;

{ A function or procedure as an oid expression: by "name(types)", or by a
  plain name when only one routine has it. }
function TpgnPostgresAdapter.ProcOid(const ASchema, AName: string): string;
begin
  if Pos('(', AName) > 0 then
  begin
    Result := 'to_regprocedure(' + L(QuoteAlways(ASchema) + '.' + QuoteAlways(RoutineBaseName(AName)) +
      '(' + RoutineArgTypes(AName) + ')') + ')';
  end
  else
  begin
    Result := '(SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
      'WHERE n.nspname = ' + L(ASchema) + ' AND p.proname = ' + L(AName) + ' LIMIT 1)';
  end;
end;

{ The table a trigger belongs to. Trigger names are only unique per table,
  so two tables with the same trigger name can't be told apart here. }
function TpgnPostgresAdapter.TriggerTable(const ASchema, ATrigger: string): string;
var
  Tables: TpgnStringArray;
begin
  Tables := MetaStrings('SELECT c.relname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ' + L(ASchema) +
    ' AND t.tgname = ' + L(ATrigger) + ' AND NOT t.tgisinternal');
  if Length(Tables) = 0 then
  begin
    raise Exception.Create('There is no trigger named ' + ATrigger + ' in ' + ASchema + '.');
  end;
  if Length(Tables) > 1 then
  begin
    raise Exception.Create('More than one table in ' + ASchema + ' has a trigger named ' + ATrigger +
      '; open it from the table instead.');
  end;
  Result := Tables[0];
end;

function TpgnPostgresAdapter.UserSchemaFilter(const AColumn: string): string;
begin
  Result := AColumn + ' NOT LIKE ''pg\_%'' AND ' + AColumn + ' <> ''information_schema''';
end;

function TpgnPostgresAdapter.QuoteIdent(const AName: string): string;
var
  I: Integer;
  Bare: Boolean;
  Lower: string;
begin
  // bare when PostgreSQL would read it back unchanged
  Bare := (AName <> '') and (AName[1] in ['a'..'z', '_']);
  for I := 1 to Length(AName) do
  begin
    if not (AName[I] in ['a'..'z', '0'..'9', '_', '$']) then
    begin
      Bare := False;
    end;
  end;
  if Bare then
  begin
    Lower := AName;
    for I := 0 to High(ReservedWords) do
    begin
      if ReservedWords[I] = Lower then
      begin
        Bare := False;
      end;
    end;
    for I := 0 to High(MoreReserved) do
    begin
      if MoreReserved[I] = Lower then
      begin
        Bare := False;
      end;
    end;
  end;
  if Bare then
  begin
    Result := AName;
  end
  else
  begin
    Result := QuoteAlways(AName);
  end;
end;

{ ------------------------------------------------------- engine shape }

function TpgnPostgresAdapter.Dialect: TpgnDialect;
begin
  Result := sdPostgreSQL;
end;

function TpgnPostgresAdapter.HasSchemas: Boolean;
begin
  Result := True;
end;

function TpgnPostgresAdapter.SessionPerDatabase: Boolean;
begin
  Result := True;
end;

function TpgnPostgresAdapter.TableFolders: Boolean;
begin
  Result := True;
end;

function TpgnPostgresAdapter.OwnSessionId: string;
begin
  if FBackendPid = 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := IntToStr(FBackendPid);
  end;
end;

function TpgnPostgresAdapter.ServerVersion: string;
begin
  Result := FVersion;
end;

function TpgnPostgresAdapter.ListDatabases: TpgnStringArray;
begin
  Result := MetaStrings('SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ' +
    'ORDER BY datname');
end;

function TpgnPostgresAdapter.ListSchemas(ASystem: Boolean): TpgnStringArray;
begin
  if ASystem then
  begin
    Result := MetaStrings('SELECT nspname FROM pg_namespace ' +
      'WHERE nspname IN (''pg_catalog'', ''information_schema'') ORDER BY nspname');
  end
  else
  begin
    Result := MetaStrings('SELECT nspname FROM pg_namespace WHERE ' + UserSchemaFilter('nspname') +
      ' ORDER BY nspname');
  end;
end;

function TpgnPostgresAdapter.CurrentSchema: string;
begin
  Result := FSchema;
end;

{ Unqualified names are looked up in the schema, then in public (where
  extensions usually put their functions). }
procedure TpgnPostgresAdapter.UseSchema(const ASchema: string);
begin
  if (ASchema = '') or (ASchema = 'public') then
  begin
    FConn.ExecuteDirect('SET search_path TO public');
  end
  else
  begin
    FConn.ExecuteDirect('SET search_path TO ' + QuoteIdent(ASchema) + ', public');
  end;
  FSchema := ASchema;
end;

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

{ The folders pgAdmin shows, from PostgreSQL's own catalog. Developer mode
  keeps the everyday ones; DBA mode shows the rest. Tables, Views,
  Materialized Views, Functions, Procedures and Trigger Functions are the
  Explorer's own folders and aren't listed here. }
{ AMore = False: the folders shown at that level; True: the rarely used
  ones, which the Explorer keeps together in a "More" folder. }
function TpgnPostgresAdapter.ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray;
begin
  Result := nil;
  case ALevel of
    flServer:
      begin
        if not AMore then
        begin
          Result := Strings(['Login/Group Roles', 'Tablespaces']);
        end;
      end;
    flDatabase:
      begin
        if AMore then
        begin
          Result := Strings(['Casts', 'Event Triggers', 'Foreign Data Wrappers', 'Languages',
            'Publications', 'Subscriptions']);
        end
        else
        begin
          Result := Strings(['Extensions']);
        end;
      end;
    flSchema:
      begin
        if AMore then
        begin
          Result := Strings(['Aggregates', 'Collations', 'Foreign Tables', 'FTS Configurations',
            'FTS Dictionaries', 'FTS Parsers', 'FTS Templates', 'Operators']);
        end
        else
        begin
          Result := Strings(['Sequences', 'Domains', 'Types']);
        end;
      end;
  end;
end;

function TpgnPostgresAdapter.ListFolder(const AContainer, AFolder: string): TpgnStringArray;
var
  Ns: string;
begin
  Result := nil;
  Ns := '(SELECT oid FROM pg_namespace WHERE nspname = ' + L(AContainer) + ')';
  if AFolder = 'Sequences' then
  begin
    Result := MetaStrings('SELECT relname FROM pg_class WHERE relkind = ''S'' AND relnamespace = ' +
      Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Foreign Tables' then
  begin
    Result := MetaStrings('SELECT relname FROM pg_class WHERE relkind = ''f'' AND relnamespace = ' +
      Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Trigger Functions' then
  begin
    Result := MetaStrings('SELECT proname || ''('' || oidvectortypes(proargtypes) || '')'' ' +
      'FROM pg_proc WHERE prokind = ''f'' AND prorettype = ''trigger''::regtype ' +
      'AND pronamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Aggregates' then
  begin
    Result := MetaStrings('SELECT proname || ''('' || oidvectortypes(proargtypes) || '')'' ' +
      'FROM pg_proc WHERE prokind = ''a'' AND pronamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Types' then
  begin
    // not table row types, not array types, not domains
    Result := MetaStrings('SELECT t.typname FROM pg_type t WHERE t.typnamespace = ' + Ns +
      ' AND t.typtype IN (''b'', ''c'', ''e'', ''r'', ''m'') ' +
      'AND (t.typrelid = 0 OR (SELECT c.relkind FROM pg_class c WHERE c.oid = t.typrelid) = ''c'') ' +
      'AND NOT (t.typelem <> 0 AND t.typlen = -1) ORDER BY 1');
  end
  else if AFolder = 'Domains' then
  begin
    Result := MetaStrings('SELECT typname FROM pg_type WHERE typtype = ''d'' AND typnamespace = ' +
      Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Operators' then
  begin
    Result := MetaStrings('SELECT oprname || '' ('' || ' +
      'CASE WHEN oprleft = 0 THEN ''NONE'' ELSE format_type(oprleft, NULL) END || '', '' || ' +
      'CASE WHEN oprright = 0 THEN ''NONE'' ELSE format_type(oprright, NULL) END || '')'' ' +
      'FROM pg_operator WHERE oprnamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'Collations' then
  begin
    Result := MetaStrings('SELECT collname FROM pg_collation WHERE collnamespace = ' + Ns +
      ' ORDER BY 1');
  end
  else if AFolder = 'FTS Configurations' then
  begin
    Result := MetaStrings('SELECT cfgname FROM pg_ts_config WHERE cfgnamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'FTS Dictionaries' then
  begin
    Result := MetaStrings('SELECT dictname FROM pg_ts_dict WHERE dictnamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'FTS Parsers' then
  begin
    Result := MetaStrings('SELECT prsname FROM pg_ts_parser WHERE prsnamespace = ' + Ns + ' ORDER BY 1');
  end
  else if AFolder = 'FTS Templates' then
  begin
    Result := MetaStrings('SELECT tmplname FROM pg_ts_template WHERE tmplnamespace = ' + Ns +
      ' ORDER BY 1');
  end
  else if AFolder = 'Casts' then
  begin
    // the ones someone added; PostgreSQL's own number in the hundreds
    Result := MetaStrings('SELECT format_type(castsource, NULL) || '' AS '' || ' +
      'format_type(casttarget, NULL) FROM pg_cast WHERE oid >= 16384 ORDER BY 1');
  end
  else if AFolder = 'Event Triggers' then
  begin
    Result := MetaStrings('SELECT evtname FROM pg_event_trigger ORDER BY 1');
  end
  else if AFolder = 'Extensions' then
  begin
    Result := MetaStrings('SELECT extname FROM pg_extension ORDER BY 1');
  end
  else if AFolder = 'Foreign Data Wrappers' then
  begin
    Result := MetaStrings('SELECT fdwname FROM pg_foreign_data_wrapper ORDER BY 1');
  end
  else if AFolder = 'Languages' then
  begin
    Result := MetaStrings('SELECT lanname FROM pg_language ORDER BY 1');
  end
  else if AFolder = 'Publications' then
  begin
    Result := MetaStrings('SELECT pubname FROM pg_publication ORDER BY 1');
  end
  else if AFolder = 'Subscriptions' then
  begin
    Result := MetaStrings('SELECT subname FROM pg_subscription ' +
      'WHERE subdbid = (SELECT oid FROM pg_database WHERE datname = current_database()) ORDER BY 1');
  end
  else if AFolder = 'Login/Group Roles' then
  begin
    Result := MetaStrings('SELECT rolname FROM pg_roles WHERE rolname NOT LIKE ''pg\_%'' ORDER BY 1');
  end
  else if AFolder = 'Tablespaces' then
  begin
    Result := MetaStrings('SELECT spcname FROM pg_tablespace ORDER BY 1');
  end;
end;

function TpgnPostgresAdapter.FolderItemSQL(const AContainer, AFolder, AName: string): string;
begin
  Result := '';
  if AFolder = 'Sequences' then
  begin
    Result := MetaValue('SELECT ''CREATE SEQUENCE '' || ' + L(QuoteIdent(AContainer) + '.' +
      QuoteIdent(AName)) + ' || E''\n  AS '' || data_type::text || E''\n  START WITH '' || ' +
      'start_value || E''\n  INCREMENT BY '' || increment_by || E''\n  MINVALUE '' || min_value || ' +
      'E''\n  MAXVALUE '' || max_value || E''\n  CACHE '' || cache_size || ' +
      'CASE WHEN cycle THEN E''\n  CYCLE'' ELSE '''' END || E'';\n\n-- last value used: '' || ' +
      'coalesce(last_value::text, ''none yet'') FROM pg_sequences WHERE schemaname = ' + L(AContainer) +
      ' AND sequencename = ' + L(AName));
  end
  else if AFolder = 'Domains' then
  begin
    Result := MetaValue('SELECT ''CREATE DOMAIN '' || ' + L(QuoteIdent(AContainer) + '.' +
      QuoteIdent(AName)) + ' || '' AS '' || format_type(t.typbasetype, t.typtypmod) || ' +
      'coalesce('' '' || (SELECT string_agg(pg_get_constraintdef(c.oid), '' '') FROM pg_constraint c ' +
      'WHERE c.contypid = t.oid), '''') || '';'' FROM pg_type t WHERE t.typname = ' + L(AName) +
      ' AND t.typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = ' + L(AContainer) + ')');
  end
  else if AFolder = 'Types' then
  begin
    Result := MetaValue('SELECT ''CREATE TYPE '' || ' + L(QuoteIdent(AContainer) + '.' +
      QuoteIdent(AName)) + ' || '' AS ENUM ('' || string_agg(quote_literal(e.enumlabel), '', '' ' +
      'ORDER BY e.enumsortorder) || '');'' FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid ' +
      'WHERE t.typname = ' + L(AName) + ' AND t.typnamespace = ' +
      '(SELECT oid FROM pg_namespace WHERE nspname = ' + L(AContainer) + ')');
  end
  else if AFolder = 'Extensions' then
  begin
    Result := MetaValue('SELECT ''CREATE EXTENSION '' || quote_ident(e.extname) || '' SCHEMA '' || ' +
      'quote_ident(n.nspname) || '' VERSION '' || quote_literal(e.extversion) || '';'' ' +
      'FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = ' + L(AName));
  end
  else if AFolder = 'Login/Group Roles' then
  begin
    Result := MetaValue('SELECT ''-- '' || rolname || E''\n-- can log in: '' || ' +
      'CASE WHEN rolcanlogin THEN ''yes'' ELSE ''no'' END || E''\n-- superuser: '' || ' +
      'CASE WHEN rolsuper THEN ''yes'' ELSE ''no'' END || E''\n-- create databases: '' || ' +
      'CASE WHEN rolcreatedb THEN ''yes'' ELSE ''no'' END || E''\n-- create roles: '' || ' +
      'CASE WHEN rolcreaterole THEN ''yes'' ELSE ''no'' END || E''\n-- member of: '' || ' +
      'coalesce((SELECT string_agg(g.rolname, '', '' ORDER BY g.rolname) FROM pg_auth_members m ' +
      'JOIN pg_roles g ON g.oid = m.roleid WHERE m.member = r.oid), ''nothing'') ' +
      'FROM pg_roles r WHERE rolname = ' + L(AName));
  end;
end;

{ ------------------------------------------------------- tables, views }

function TpgnPostgresAdapter.ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray;
var
  Kinds: string;
begin
  case AKind of
    okView:
      begin
        Kinds := '''v''';
      end;
    okMatView:
      begin
        Kinds := '''m''';
      end;
  else
    begin
      Kinds := '''r'', ''p''';
    end;
  end;
  Result := MetaStrings('SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE n.nspname = ' + L(ADatabase) + ' AND c.relkind IN (' + Kinds + ') ' +
    'AND NOT c.relispartition ORDER BY c.relname');
end;

function TpgnPostgresAdapter.DescribeTable(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT a.attname AS "Column", format_type(a.atttypid, a.atttypmod) AS "Type", ' +
    'CASE WHEN a.attnotnull THEN ''NO'' ELSE ''YES'' END AS "Nullable", ' +
    'CASE WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = a.attrelid ' +
    'AND k.contype = ''p'' AND a.attnum = ANY (k.conkey)) THEN ''PRI'' ELSE '''' END AS "Key", ' +
    'pg_get_expr(d.adbin, d.adrelid) AS "Default", ' +
    'col_description(a.attrelid, a.attnum) AS "Comment" ' +
    'FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum ' +
    'WHERE a.attrelid = ' + RelLiteral(ADatabase, ATable) + ' AND a.attnum > 0 ' +
    'AND NOT a.attisdropped ORDER BY a.attnum');
end;

function TpgnPostgresAdapter.DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT i.relname AS "Index", CASE WHEN x.indisprimary THEN ''yes'' ELSE '''' END AS "Primary", ' +
    'CASE WHEN x.indisunique THEN ''yes'' ELSE ''no'' END AS "Unique", ' +
    'pg_get_indexdef(x.indexrelid) AS "Definition" ' +
    'FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid ' +
    'WHERE x.indrelid = ' + RelLiteral(ADatabase, ATable) + ' ORDER BY x.indisprimary DESC, i.relname');
end;

{ PostgreSQL has no SHOW CREATE TABLE: the statement is put together from
  the catalog (columns, constraints, other indexes). }
function TpgnPostgresAdapter.GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string;
var
  Rel, Kind, Head: string;
  Cols, Cons, Idx: TpgnStringArray;
  I: Integer;
begin
  Rel := RelLiteral(ADatabase, AObject);
  Head := QuoteIdent(ADatabase) + '.' + QuoteIdent(AObject);
  Kind := MetaValue('SELECT relkind FROM pg_class WHERE oid = ' + Rel);
  if Kind = '' then
  begin
    raise Exception.Create(ADatabase + '.' + AObject + ' was not found.');
  end;
  if (Kind = 'v') or (Kind = 'm') then
  begin
    if Kind = 'm' then
    begin
      Result := 'CREATE MATERIALIZED VIEW ' + Head + ' AS' + LineEnding;
    end
    else
    begin
      Result := 'CREATE OR REPLACE VIEW ' + Head + ' AS' + LineEnding;
    end;
    Result := Result + TrimRight(MetaValue('SELECT pg_get_viewdef(' + Rel + ', true)'));
    if (Result <> '') and (Result[Length(Result)] = ';') then
    begin
      Delete(Result, Length(Result), 1);
    end;
    Exit;
  end;

  Cols := MetaStrings('SELECT quote_ident(a.attname) || '' '' || format_type(a.atttypid, a.atttypmod) || ' +
    'CASE WHEN a.attnotnull THEN '' NOT NULL'' ELSE '''' END || ' +
    'coalesce('' DEFAULT '' || pg_get_expr(d.adbin, d.adrelid), '''') ' +
    'FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum ' +
    'WHERE a.attrelid = ' + Rel + ' AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum');
  Cons := MetaStrings('SELECT ''CONSTRAINT '' || quote_ident(conname) || '' '' || ' +
    'pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = ' + Rel +
    ' ORDER BY contype = ''p'' DESC, conname');
  Idx := MetaStrings('SELECT pg_get_indexdef(x.indexrelid) FROM pg_index x ' +
    'WHERE x.indrelid = ' + Rel + ' AND NOT EXISTS (SELECT 1 FROM pg_constraint k ' +
    'WHERE k.conindid = x.indexrelid) ORDER BY 1');
  Result := 'CREATE TABLE ' + Head + ' (';
  for I := 0 to High(Cols) do
  begin
    Result := Result + LineEnding + '  ' + Cols[I];
    if (I < High(Cols)) or (Length(Cons) > 0) then
    begin
      Result := Result + ',';
    end;
  end;
  for I := 0 to High(Cons) do
  begin
    Result := Result + LineEnding + '  ' + Cons[I];
    if I < High(Cons) then
    begin
      Result := Result + ',';
    end;
  end;
  Result := Result + LineEnding + ')';
  for I := 0 to High(Idx) do
  begin
    Result := Result + ';' + LineEnding + Idx[I];
  end;
end;

function TpgnPostgresAdapter.ListObjectNames(const ADatabase: string): TpgnStringArray;
begin
  // every schema of the database: names are colored wherever they're used
  Result := MetaStrings('SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE c.relkind IN (''r'', ''p'', ''v'', ''m'', ''f'') AND ' + UserSchemaFilter('n.nspname') +
    ' UNION SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
    'WHERE ' + UserSchemaFilter('n.nspname'));
end;

{ An unquoted PostgreSQL name is lower case; a quoted one is kept. }
function PgName(const S: string): string;
begin
  if (Length(Trim(S)) >= 2) and (Trim(S)[1] = '"') then
  begin
    Result := Unquoted(S);
  end
  else
  begin
    Result := LowerCase(Unquoted(S));
  end;
end;

{ As PostgreSQL finds a name: the schema written, else the tab's schema,
  then the search_path; tables and views before functions. }
function TpgnPostgresAdapter.ResolveObject(const AName, ADefault: string; out ARef: TpgnObjectRef;
  out AVia: string): Boolean;
var
  Qual, N, Where, Rank: string;
  P: Integer;
  R: TpgnResultSet;
begin
  Result := False;
  AVia := '';
  ARef.Database := FCurrentDatabase;
  ARef.Schema := '';
  ARef.Name := '';
  ARef.Kind := '';
  P := LastDelimiter('.', AName);
  if P > 0 then
  begin
    Qual := PgName(Copy(AName, 1, P - 1));
    N := PgName(Copy(AName, P + 1, MaxInt));
  end
  else
  begin
    Qual := '';
    N := PgName(AName);
  end;
  if N = '' then
  begin
    Exit;
  end;
  if Qual <> '' then
  begin
    Where := 'n.nspname = ' + L(Qual);
  end
  else
  begin
    Where := '(n.nspname = ' + L(ADefault) + ' OR n.nspname = ANY (current_schemas(false)))';
  end;
  Rank := ', CASE WHEN n.nspname = ' + L(ADefault) + ' THEN 0 ELSE 1 END, ' +
    'COALESCE(array_position(current_schemas(false), n.nspname), 999)';
  R := MetaResult(
    'SELECT n.nspname, c.relname, CASE c.relkind WHEN ''v'' THEN ''View'' ' +
    'WHEN ''m'' THEN ''Materialized View'' ELSE ''Table'' END, 1' + Rank + ' ' +
    'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE c.relkind IN (''r'', ''p'', ''v'', ''m'') AND c.relname = ' + L(N) + ' AND ' + Where +
    ' UNION ALL ' +
    'SELECT n.nspname, p.proname || ''('' || oidvectortypes(p.proargtypes) || '')'', ' +
    'CASE WHEN p.prokind = ''p'' THEN ''Procedure'' ' +
    'WHEN p.prorettype = ''trigger''::regtype THEN ''Trigger Function'' ELSE ''Function'' END, 2' + Rank + ' ' +
    'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
    'WHERE p.prokind IN (''f'', ''p'') AND p.proname = ' + L(N) + ' AND ' + Where +
    ' ORDER BY 4, 5, 6');
  if (R.RowCount = 0) and (Qual = '') then
  begin
    // not on the search_path: any schema the login can see
    R.Free;
    Where := UserSchemaFilter('n.nspname');
    R := MetaResult(
      'SELECT n.nspname, c.relname, CASE c.relkind WHEN ''v'' THEN ''View'' ' +
      'WHEN ''m'' THEN ''Materialized View'' ELSE ''Table'' END, 1 ' +
      'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE c.relkind IN (''r'', ''p'', ''v'', ''m'') AND c.relname = ' + L(N) + ' AND ' + Where +
      ' UNION ALL ' +
      'SELECT n.nspname, p.proname || ''('' || oidvectortypes(p.proargtypes) || '')'', ' +
      'CASE WHEN p.prokind = ''p'' THEN ''Procedure'' ' +
      'WHEN p.prorettype = ''trigger''::regtype THEN ''Trigger Function'' ELSE ''Function'' END, 2 ' +
      'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
      'WHERE p.prokind IN (''f'', ''p'') AND p.proname = ' + L(N) + ' AND ' + Where +
      ' ORDER BY 4, 1');
  end;
  try
    if R.RowCount > 0 then
    begin
      ARef.Schema := R.Rows[0].Values[0];
      ARef.Name := R.Rows[0].Values[1];
      ARef.Kind := R.Rows[0].Values[2];
      Result := True;
    end;
  finally
    R.Free;
  end;
end;

function TpgnPostgresAdapter.DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT con.conname AS "Constraint", CASE con.contype WHEN ''p'' THEN ''Primary key'' ' +
    'WHEN ''u'' THEN ''Unique'' WHEN ''f'' THEN ''Foreign key'' WHEN ''c'' THEN ''Check'' ' +
    'WHEN ''x'' THEN ''Exclusion'' END AS "Type", pg_get_constraintdef(con.oid) AS "Definition" ' +
    'FROM pg_constraint con JOIN pg_class t ON t.oid = con.conrelid ' +
    'JOIN pg_namespace n ON n.oid = t.relnamespace ' +
    'WHERE n.nspname = ' + L(ADatabase) + ' AND t.relname = ' + L(ATable) +
    ' AND con.contype IN (''p'', ''u'', ''f'', ''c'', ''x'') ' +
    'ORDER BY position(con.contype IN ''pufcx''), 1');
end;

{ Views built on it and tables whose foreign keys point at it. }
function TpgnPostgresAdapter.DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT DISTINCT dn.nspname AS "Schema", dc.relname AS "Name", ' +
    'CASE dc.relkind WHEN ''m'' THEN ''Materialized View'' ELSE ''View'' END AS "Type" ' +
    'FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid ' +
    'JOIN pg_class dc ON dc.oid = rw.ev_class JOIN pg_namespace dn ON dn.oid = dc.relnamespace ' +
    'JOIN pg_class t ON t.oid = d.refobjid JOIN pg_namespace tn ON tn.oid = t.relnamespace ' +
    'WHERE tn.nspname = ' + L(ADatabase) + ' AND t.relname = ' + L(AName) + ' AND dc.oid <> t.oid ' +
    'UNION SELECT n2.nspname, c2.relname, ''Table (foreign key)'' FROM pg_constraint con ' +
    'JOIN pg_class c2 ON c2.oid = con.conrelid JOIN pg_namespace n2 ON n2.oid = c2.relnamespace ' +
    'JOIN pg_class t ON t.oid = con.confrelid JOIN pg_namespace tn ON tn.oid = t.relnamespace ' +
    'WHERE con.contype = ''f'' AND tn.nspname = ' + L(ADatabase) + ' AND t.relname = ' + L(AName) +
    ' ORDER BY 3, 1, 2');
end;

function TpgnPostgresAdapter.SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs;
var
  R: TpgnResultSet;
  Pattern: string;
  I: Integer;
begin
  Result := nil;
  Pattern := '%' + StringReplace(StringReplace(StringReplace(AText, '\', '\\', [rfReplaceAll]),
    '%', '\%', [rfReplaceAll]), '_', '\_', [rfReplaceAll]) + '%';
  R := MetaResult(
    'SELECT n.nspname, c.relname, CASE c.relkind WHEN ''v'' THEN ''View'' ' +
    'WHEN ''m'' THEN ''Materialized View'' ELSE ''Table'' END ' +
    'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE c.relkind IN (''r'', ''p'', ''v'', ''m'') AND NOT c.relispartition ' +
    'AND c.relname ILIKE ' + L(Pattern) + ' AND ' + UserSchemaFilter('n.nspname') +
    ' UNION ALL ' +
    'SELECT n.nspname, p.proname || ''('' || oidvectortypes(p.proargtypes) || '')'', ' +
    'CASE WHEN p.prokind = ''p'' THEN ''Procedure'' ' +
    'WHEN p.prorettype = ''trigger''::regtype THEN ''Trigger Function'' ELSE ''Function'' END ' +
    'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
    'WHERE p.prokind IN (''f'', ''p'') AND p.proname ILIKE ' + L(Pattern) +
    ' AND ' + UserSchemaFilter('n.nspname') +
    ' ORDER BY 2, 1 LIMIT ' + IntToStr(AMax));
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

{ ------------------------------------------- functions, procedures, triggers }

function TpgnPostgresAdapter.ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray;
var
  Ns: string;
begin
  Ns := '(SELECT oid FROM pg_namespace WHERE nspname = ' + L(ADatabase) + ')';
  case AKind of
    rkProcedure:
      begin
        Result := MetaStrings('SELECT proname || ''('' || oidvectortypes(proargtypes) || '')'' ' +
          'FROM pg_proc WHERE prokind = ''p'' AND pronamespace = ' + Ns + ' ORDER BY 1');
      end;
    rkFunction:
      begin
        // trigger functions have a folder of their own
        Result := MetaStrings('SELECT proname || ''('' || oidvectortypes(proargtypes) || '')'' ' +
          'FROM pg_proc WHERE prokind = ''f'' AND prorettype NOT IN (''trigger''::regtype, ' +
          '''event_trigger''::regtype) AND pronamespace = ' + Ns + ' ORDER BY 1');
      end;
  else
    begin
      Result := MetaStrings('SELECT DISTINCT t.tgname FROM pg_trigger t ' +
        'JOIN pg_class c ON c.oid = t.tgrelid WHERE c.relnamespace = ' + Ns +
        ' AND NOT t.tgisinternal ORDER BY 1');
    end;
  end;
end;

function TpgnPostgresAdapter.GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
var
  Table: string;
begin
  if AKind = rkTrigger then
  begin
    Table := TriggerTable(ADatabase, AName);
    Result := MetaValue('SELECT pg_get_triggerdef(t.oid, true) FROM pg_trigger t ' +
      'WHERE t.tgrelid = ' + RelLiteral(ADatabase, Table) + ' AND t.tgname = ' + L(AName));
  end
  else
  begin
    Result := TrimRight(MetaValue('SELECT pg_get_functiondef(' + ProcOid(ADatabase, AName) + ')'));
  end;
end;

function TpgnPostgresAdapter.RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean;
begin
  if AKind = rkTrigger then
  begin
    Result := Length(MetaStrings('SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ' + L(ADatabase) +
      ' AND t.tgname = ' + L(AName))) > 0;
  end
  else
  begin
    Result := MetaValue('SELECT CASE WHEN ' + ProcOid(ADatabase, AName) +
      ' IS NOT NULL THEN 1 ELSE 0 END') = '1';
  end;
end;

{ Mode, Parameter, Type: a function's result first, as a RETURNS row;
  TABLE rows are the columns a set-returning function hands back. }
function TpgnPostgresAdapter.DescribeParameters(const ADatabase, AName: string): TpgnResultSet;
var
  Oid: string;
begin
  Oid := ProcOid(ADatabase, AName);
  Result := MetaResult(
    'SELECT "Mode", "Parameter", "Type" FROM (' +
    'SELECT 0 AS ord, ''RETURNS'' AS "Mode", '''' AS "Parameter", ' +
    'pg_get_function_result(p.oid) AS "Type" FROM pg_proc p WHERE p.oid = ' + Oid +
    ' AND p.prokind = ''f'' ' +
    'UNION ALL ' +
    'SELECT a.ord, CASE a.m WHEN ''i'' THEN ''IN'' WHEN ''o'' THEN ''OUT'' WHEN ''b'' THEN ''INOUT'' ' +
    'WHEN ''v'' THEN ''VARIADIC'' WHEN ''t'' THEN ''TABLE'' ELSE ''IN'' END, coalesce(a.n, ''''), ' +
    'format_type(a.t, NULL) FROM pg_proc p, ' +
    'unnest(coalesce(p.proallargtypes, p.proargtypes::oid[]), ' +
    'coalesce(p.proargmodes, array_fill(''i''::"char", ARRAY[cardinality(p.proargtypes::oid[])])), ' +
    'coalesce(p.proargnames, ''{}''::text[])) WITH ORDINALITY AS a(t, m, n, ord) ' +
    'WHERE p.oid = ' + Oid + ' AND a.t IS NOT NULL' +
    ') x ORDER BY ord');
end;

function TpgnPostgresAdapter.DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT t.tgname AS "Trigger", ' +
    'CASE WHEN t.tgtype & 2 = 2 THEN ''BEFORE'' WHEN t.tgtype & 64 = 64 THEN ''INSTEAD OF'' ' +
    'ELSE ''AFTER'' END AS "Timing", ' +
    'concat_ws('' OR '', CASE WHEN t.tgtype & 4 = 4 THEN ''INSERT'' END, ' +
    'CASE WHEN t.tgtype & 16 = 16 THEN ''UPDATE'' END, CASE WHEN t.tgtype & 8 = 8 THEN ''DELETE'' END, ' +
    'CASE WHEN t.tgtype & 32 = 32 THEN ''TRUNCATE'' END) AS "Event", ' +
    'p.proname AS "Function", CASE t.tgenabled WHEN ''D'' THEN ''no'' ELSE ''yes'' END AS "Enabled" ' +
    'FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid ' +
    'WHERE t.tgrelid = ' + RelLiteral(ADatabase, ATable) + ' AND NOT t.tgisinternal ORDER BY 1');
end;

function TpgnPostgresAdapter.DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet;
var
  Src: string;
begin
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    Src := 'FROM pg_proc o, aclexplode(coalesce(o.proacl, acldefault(''f'', o.proowner))) a ' +
      'WHERE o.oid = ' + ProcOid(ADatabase, AName);
  end
  else
  begin
    Src := 'FROM pg_class o, aclexplode(coalesce(o.relacl, acldefault(''r'', o.relowner))) a ' +
      'WHERE o.oid = ' + RelLiteral(ADatabase, AName);
  end;
  Result := MetaResult(
    'SELECT CASE WHEN a.grantee = 0 THEN ''PUBLIC'' ELSE pg_get_userbyid(a.grantee) END AS "Grantee", ' +
    'string_agg(a.privilege_type || CASE WHEN a.is_grantable THEN '' (can grant)'' ELSE '''' END, ' +
    ''', '' ORDER BY a.privilege_type) AS "Privileges", ' +
    'pg_get_userbyid(a.grantor) AS "Granted by" ' + Src + ' GROUP BY 1, 3 ORDER BY 1');
end;

{ Functions and procedures: CREATE OR REPLACE, which PostgreSQL does in one
  step, keeping the grants; if it fails nothing has changed. Triggers:
  drop and create inside one transaction, so a failure leaves the old one.
  Returns the name the routine now has, with its argument types. }
function TpgnPostgresAdapter.SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
  const ASQL: string; ALog: TStrings): string;
var
  St, Len, I, J: Integer;
  NewName, Kw, Word, SQL, Raw, OldTable: string;
  Before, After: TpgnStringArray;
  Found: Boolean;

  function SignaturesNamed(const AName: string): TpgnStringArray;
  begin
    Result := MetaStrings('SELECT proname || ''('' || oidvectortypes(proargtypes) || '')'' ' +
      'FROM pg_proc WHERE proname = ' + L(AName) + ' AND pronamespace = ' +
      '(SELECT oid FROM pg_namespace WHERE nspname = ' + L(ADatabase) + ') ORDER BY 1');
  end;

begin
  Result := '';
  Word := RoutineWord[AKind];
  if not FindCreateName(ASQL, St, Len, NewName, Kw) then
  begin
    raise Exception.Create('The editor should hold one CREATE ' + Word + ' statement.');
  end;
  if Kw <> Word then
  begin
    raise Exception.Create('The text creates a ' + LowerCase(Kw) + ', but this tab is a ' +
      LowerCase(Word) + '. Nothing was changed.');
  end;
  // a name written without quotes is stored in lower case
  Raw := Copy(ASQL, St, Len);
  if Pos('"', Raw) = 0 then
  begin
    NewName := LowerCase(NewName);
  end;

  // unqualified names in the statement land in this schema
  MetaExec('SET search_path TO ' + QuoteIdent(ADatabase) + ', public');
  try
    if AKind = rkTrigger then
    begin
      MetaExec('BEGIN');
      try
        if AOldName <> '' then
        begin
          OldTable := TriggerTable(ADatabase, AOldName);
          MetaExec('DROP TRIGGER ' + QuoteIdent(AOldName) + ' ON ' + QuoteIdent(ADatabase) + '.' +
            QuoteIdent(OldTable));
        end;
        MetaExec(ASQL);
        MetaExec('COMMIT');
      except
        on E: Exception do
        begin
          try
            MetaExec('ROLLBACK');
          except
            on E2: Exception do
            begin
              // the session is reset when it is next used
            end;
          end;
          raise Exception.Create('Nothing was changed: ' + E.Message);
        end;
      end;
      if AOldName = '' then
      begin
        ALog.Add('Created trigger ' + ADatabase + '.' + NewName);
      end
      else
      begin
        ALog.Add('Saved trigger ' + ADatabase + '.' + NewName + ' (replaced in one transaction)');
      end;
      Result := NewName;
      Exit;
    end;

    // functions and procedures: make sure it replaces rather than fails
    SQL := ASQL;
    if not SameText(Copy(TrimLeft(UpperCase(SQL)), 1, 17), 'CREATE OR REPLACE') then
    begin
      I := Pos('CREATE', UpperCase(SQL));
      SQL := Copy(SQL, 1, I + 5) + ' OR REPLACE' + Copy(SQL, I + 6, MaxInt);
    end;
    Before := SignaturesNamed(NewName);
    try
      MetaExec(SQL);
    except
      on E: Exception do
      begin
        if Pos('cannot change return type', E.Message) > 0 then
        begin
          raise Exception.Create('Nothing was changed: PostgreSQL can''t change a function''s ' +
            'return type in place. Drop it first (right-click > Drop), then Save; its grants ' +
            'will need to be given again. (' + E.Message + ')');
        end;
        if Pos('cannot change name of input parameter', E.Message) > 0 then
        begin
          raise Exception.Create('Nothing was changed: PostgreSQL can''t rename a parameter in ' +
            'place. Drop it first (right-click > Drop), then Save. (' + E.Message + ')');
        end;
        raise Exception.Create('Nothing was changed: ' + E.Message);
      end;
    end;
    After := SignaturesNamed(NewName);

    // which one was saved: a new signature if one appeared, else the old one
    for I := 0 to High(After) do
    begin
      Found := False;
      for J := 0 to High(Before) do
      begin
        if After[I] = Before[J] then
        begin
          Found := True;
        end;
      end;
      if not Found then
      begin
        Result := After[I];
      end;
    end;
    if Result = '' then
    begin
      for I := 0 to High(After) do
      begin
        if After[I] = AOldName then
        begin
          Result := AOldName;
        end;
      end;
    end;
    if (Result = '') and (Length(After) > 0) then
    begin
      Result := After[0];
    end;

    if AOldName = '' then
    begin
      ALog.Add('Created ' + LowerCase(Word) + ' ' + ADatabase + '.' + Result);
    end
    else
    begin
      ALog.Add('Saved ' + LowerCase(Word) + ' ' + ADatabase + '.' + Result + ' (grants kept)');
      if Result <> AOldName then
      begin
        ALog.Add('WARNING: the name or parameter types changed, so this is a new ' + LowerCase(Word) +
          '. ' + AOldName + ' is still there; drop it if it''s no longer needed.');
      end;
    end;
  finally
    MetaExec('RESET search_path');
  end;
end;

{ --------------------------------------------- SQL for the forms and menus }

function TpgnPostgresAdapter.RoutineTarget(const ADatabase, AName: string;
  AKind: TpgnRoutineKind): string;
begin
  Result := QuoteIdent(ADatabase) + '.' + QuoteIdent(RoutineBaseName(AName));
end;

function TpgnPostgresAdapter.DropRoutineSQL(const ADatabase, AName: string;
  AKind: TpgnRoutineKind): string;
begin
  if AKind = rkTrigger then
  begin
    Result := 'DROP TRIGGER ' + QuoteIdent(AName) + ' ON ' + QuoteIdent(ADatabase) + '.' +
      QuoteIdent(TriggerTable(ADatabase, AName));
  end
  else
  begin
    Result := 'DROP ' + RoutineWord[AKind] + ' ' + RoutineTarget(ADatabase, AName, AKind) + '(' +
      RoutineArgTypes(AName) + ')';
  end;
end;

{ PostgreSQL has no DESCRIBE: the columns from information_schema. }
function TpgnPostgresAdapter.DescribeSQL(const ADatabase, ATable: string): string;
begin
  Result := 'SELECT column_name AS "Column", ' +
    'CASE WHEN character_maximum_length IS NOT NULL ' +
    'THEN data_type || ''('' || character_maximum_length || '')'' ' +
    'WHEN data_type = ''numeric'' AND numeric_precision IS NOT NULL ' +
    'THEN ''numeric('' || numeric_precision || '','' || numeric_scale || '')'' ' +
    'ELSE data_type END AS "Type", is_nullable AS "Nullable", column_default AS "Default" ' +
    'FROM information_schema.columns WHERE table_schema = ' + L(ADatabase) +
    ' AND table_name = ' + L(ATable) + ' ORDER BY ordinal_position';
end;

function PgParamList(const AParams: TpgnParamDefs; AWithMode: Boolean): string;
var
  I: Integer;
  Line: string;
begin
  Result := '';
  for I := 0 to High(AParams) do
  begin
    Line := AParams[I].Name + ' ' + AParams[I].DataType;
    if AWithMode and (AParams[I].Mode <> '') and (AParams[I].Mode <> 'IN') then
    begin
      Line := AParams[I].Mode + ' ' + Line;
    end;
    if I > 0 then
    begin
      Result := Result + ',' + LineEnding + '  ';
    end;
    Result := Result + Line;
  end;
  if Length(AParams) > 1 then
  begin
    Result := LineEnding + '  ' + Result + LineEnding;
  end;
end;

function TpgnPostgresAdapter.NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs; const AReturns: string): string;
begin
  if AKind = rkProcedure then
  begin
    Result := 'CREATE OR REPLACE PROCEDURE ' + QuoteIdent(AName) + '(' + PgParamList(AParams, True) +
      ')' + LineEnding + 'LANGUAGE plpgsql' + LineEnding + 'AS $$' + LineEnding + 'BEGIN' +
      LineEnding + '  -- your code here' + LineEnding + 'END;' + LineEnding + '$$';
  end
  else
  begin
    Result := 'CREATE OR REPLACE FUNCTION ' + QuoteIdent(AName) + '(' + PgParamList(AParams, False) +
      ')' + LineEnding + 'RETURNS ' + AReturns + LineEnding + 'LANGUAGE plpgsql' + LineEnding +
      'AS $$' + LineEnding + 'BEGIN' + LineEnding + '  -- your code here' + LineEnding +
      '  RETURN NULL;' + LineEnding + 'END;' + LineEnding + '$$';
  end;
end;

function TpgnPostgresAdapter.NewTriggerSQL(const ADatabase, ATable: string): string;
var
  Fn: string;
begin
  Fn := QuoteIdent(ADatabase) + '.' + QuoteIdent(ATable + '_before_insert');
  Result :=
    '-- A PostgreSQL trigger runs a trigger function. Save the function first' + LineEnding +
    '-- (it is in its own tab: Trigger Functions > New), or point this' + LineEnding +
    '-- trigger at one that already exists.' + LineEnding +
    'CREATE TRIGGER ' + QuoteIdent(ATable + '_before_insert') + LineEnding +
    'BEFORE INSERT ON ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(ATable) + LineEnding +
    '-- timing: BEFORE, AFTER or INSTEAD OF;  event: INSERT, UPDATE, DELETE or TRUNCATE' + LineEnding +
    'FOR EACH ROW' + LineEnding +
    'EXECUTE FUNCTION ' + Fn + '()';
end;

{ Functions are read with SELECT * FROM, which also shows every column of
  a set-returning one. Procedures are CALLed; OUT parameters are passed as
  NULL and come back as a row. }
function TpgnPostgresAdapter.ExecuteRoutineSQL(const ADatabase, AName: string;
  AKind: TpgnRoutineKind; const AParams: TpgnParamDefs): string;
var
  I: Integer;
  Args, Mode: string;
begin
  Args := '';
  for I := 0 to High(AParams) do
  begin
    Mode := UpperCase(AParams[I].Mode);
    if Mode = 'TABLE' then
    begin
      Continue;
    end;
    if (Mode = 'OUT') and (AKind = rkFunction) then
    begin
      Continue;   // a function's OUT parameters are its result columns
    end;
    if Args <> '' then
    begin
      Args := Args + ', ';
    end;
    if Mode = 'OUT' then
    begin
      Args := Args + 'NULL';
    end
    else
    begin
      Args := Args + AParams[I].Value;
    end;
  end;
  if AKind = rkFunction then
  begin
    Result := 'SELECT * FROM ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args + ');';
  end
  else
  begin
    Result := 'CALL ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args + ');';
  end;
end;

function TpgnPostgresAdapter.GrantRights(const AObjectWord: string): TpgnStringArray;
begin
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    Result := Strings(['EXECUTE']);
  end
  else
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']);
  end;
end;

function TpgnPostgresAdapter.GranteeHint: string;
begin
  Result := 'To (a role, e.g. reports, or PUBLIC for everyone)';
end;

function TpgnPostgresAdapter.GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
  AWithGrantOption: Boolean): string;
var
  Who, OnWhat: string;
begin
  Who := Trim(AGrantee);
  if not SameText(Who, 'PUBLIC') then
  begin
    Who := QuoteIdent(Who);
  end
  else
  begin
    Who := 'PUBLIC';
  end;
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    OnWhat := AObjectWord + ' ' + RoutineTarget(ADatabase, AName, rkFunction) + '(' +
      RoutineArgTypes(AName) + ')';
  end
  else
  begin
    OnWhat := 'TABLE ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(AName);
  end;
  Result := 'GRANT ' + ARights + ' ON ' + OnWhat + ' TO ' + Who;
  if AWithGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
  Result := Result + ';';
end;

{ ------------------------------------------------------------------- DBA }

function TpgnPostgresAdapter.ListSessions: TpgnResultSet;
begin
  // active first, longest running first; this tab's two sessions marked
  Result := MetaResult(
    'SELECT a.pid AS "Session", a.usename AS "User", ' +
    'coalesce(a.client_hostname, host(a.client_addr), ' +
    'CASE WHEN a.backend_type IS NULL THEN ''(hidden)'' ELSE ''local'' END) AS "Machine", ' +
    'a.application_name AS "Program", a.datname AS "Database", ' +
    'CASE WHEN a.wait_event_type = ''Lock'' THEN ''waiting for a lock'' ' +
    'ELSE coalesce(a.state, '''') END AS "State", ' +
    'to_char(now() - coalesce(a.query_start, a.backend_start), ''HH24:MI:SS'') AS "Time", ' +
    'left(regexp_replace(coalesce(a.query, ''''), ''\s+'', '' '', ''g''), 200) AS "Statement", ' +
    'CASE WHEN a.pid IN (pg_backend_pid(), ' + IntToStr(FBackendPid) + ') THEN ''this tab'' ' +
    'ELSE '''' END AS "Note" ' +
    // other users' rows hide backend_type from a login without
    // pg_read_all_stats, so a hidden one counts as a client
    'FROM pg_stat_activity a WHERE coalesce(a.backend_type, ''client backend'') = ''client backend'' ' +
    'AND a.usename IS NOT NULL ' +
    'ORDER BY a.state = ''idle'', a.query_start NULLS LAST');
end;

function TpgnPostgresAdapter.ListLocks: TpgnResultSet;
var
  WaitStart: string;
begin
  // pg_locks.waitstart (PostgreSQL 14 on) is the real start of the wait,
  // and is shown even when the login can't see other users' query times
  if StrToIntDef(MetaValue('SELECT current_setting(''server_version_num'')'), 0) >= 140000 then
  begin
    WaitStart := 'coalesce((SELECT min(l.waitstart) FROM pg_locks l WHERE l.pid = w.pid AND NOT l.granted), w.query_start)';
  end
  else
  begin
    WaitStart := 'w.query_start';
  end;
  Result := MetaResult(
    'SELECT w.pid AS "Waiting", w.usename AS "Waiting user", ' +
    'to_char(now() - ' + WaitStart + ', ''HH24:MI:SS'') AS "Waiting for", ' +
    'b.pid AS "Blocked by", b.usename AS "Blocker user", b.state AS "Blocker state", ' +
    'to_char(now() - coalesce(b.state_change, b.query_start), ''HH24:MI:SS'') AS "Blocker time", ' +
    'CASE WHEN cardinality(pg_blocking_pids(b.pid)) = 0 THEN ''yes'' ELSE '''' END AS "Head of chain", ' +
    // a row lock wait is on the blocker's transaction id, not the table:
    // the table then is one the waiter wants a tuple of, or one both hold
    // a row-changing lock on
    '(SELECT string_agg(DISTINCT l.relation::regclass::text, '', '') FROM pg_locks l ' +
    'WHERE l.pid = w.pid AND l.relation IN (SELECT oid FROM pg_class WHERE relkind IN (''r'', ''p'', ''m'')) ' +
    'AND (NOT l.granted OR l.locktype = ''tuple'' OR ' +
    '(l.mode <> ''AccessShareLock'' AND EXISTS (SELECT 1 FROM pg_locks lb WHERE lb.pid = b.pid ' +
    'AND lb.relation = l.relation AND lb.mode <> ''AccessShareLock'')))) AS "Object", ' +
    'left(regexp_replace(coalesce(w.query, ''''), ''\s+'', '' '', ''g''), 200) AS "Waiting statement", ' +
    'left(regexp_replace(coalesce(b.query, ''''), ''\s+'', '' '', ''g''), 200) AS "Blocker statement" ' +
    'FROM pg_stat_activity w CROSS JOIN LATERAL unnest(pg_blocking_pids(w.pid)) AS bp(pid) ' +
    'JOIN pg_stat_activity b ON b.pid = bp.pid ' +
    'ORDER BY 3 DESC NULLS LAST');
end;

function TpgnPostgresAdapter.SessionStatement(const ASession: string): string;
begin
  Result := MetaValue('SELECT query FROM pg_stat_activity WHERE pid = ' + SessionNumber(ASession));
end;

function TpgnPostgresAdapter.CancelSession(const ASession: string): string;
begin
  Result := 'SELECT pg_cancel_backend(' + SessionNumber(ASession) + ')';
  if MetaValue(Result) <> 't' then
  begin
    // false: it ended already, or the login may not cancel it
    if MetaValue('SELECT count(*) FROM pg_stat_activity WHERE pid = ' + SessionNumber(ASession)) = '0' then
    begin
      raise Exception.Create('Session ' + ASession + ' has already ended.');
    end;
  end;
end;

function TpgnPostgresAdapter.KillSession(const ASession: string): string;
begin
  Result := 'SELECT pg_terminate_backend(' + SessionNumber(ASession) + ')';
  MetaValue(Result);
end;

{ ------------------------------------------------------ users and roles }

function TpgnPostgresAdapter.HasRoles: Boolean;
begin
  Result := True;
end;

function TpgnPostgresAdapter.RoleOid(const AAccount: TpgnAccount): string;
begin
  Result := '(SELECT oid FROM pg_roles WHERE rolname = ' + L(AAccount.Name) + ')';
end;

function TpgnPostgresAdapter.ListAccounts(ASystem: Boolean): TpgnAccounts;
var
  R: TpgnResultSet;
  I: Integer;
  Where: string;
begin
  Result := nil;
  Where := '';
  if not ASystem then
  begin
    Where := 'WHERE rolname !~ ''^pg_'' ';
  end;
  R := MetaResult('SELECT rolname, CASE WHEN rolcanlogin THEN ''0'' ELSE ''1'' END, ' +
    'CASE WHEN rolname ~ ''^pg_'' THEN ''1'' ELSE ''0'' END FROM pg_roles ' + Where + 'ORDER BY rolname');
  try
    SetLength(Result, R.RowCount);
    for I := 0 to R.RowCount - 1 do
    begin
      Result[I] := Default(TpgnAccount);
      Result[I].Name := R.Rows[I].Values[0];
      Result[I].IsRole := R.Rows[I].Values[1] = '1';
      Result[I].IsSystem := R.Rows[I].Values[2] = '1';
    end;
  finally
    R.Free;
  end;
end;

const
  PgRoleFlags: array[0..6] of record
    Key, Caption, Column, YesWord, NoWord, Hint: string;
  end = (
    (Key: 'login'; Caption: 'Can log in'; Column: 'rolcanlogin'; YesWord: 'LOGIN'; NoWord: 'NOLOGIN';
     Hint: 'A role that can log in is a user'),
    (Key: 'super'; Caption: 'Superuser'; Column: 'rolsuper'; YesWord: 'SUPERUSER'; NoWord: 'NOSUPERUSER';
     Hint: 'Passes every permission check'),
    (Key: 'createdb'; Caption: 'Create databases'; Column: 'rolcreatedb'; YesWord: 'CREATEDB'; NoWord: 'NOCREATEDB';
     Hint: ''),
    (Key: 'createrole'; Caption: 'Create roles'; Column: 'rolcreaterole'; YesWord: 'CREATEROLE';
     NoWord: 'NOCREATEROLE'; Hint: 'Can create, change and drop other roles'),
    (Key: 'inherit'; Caption: 'Inherits its roles'' rights'; Column: 'rolinherit'; YesWord: 'INHERIT';
     NoWord: 'NOINHERIT'; Hint: 'Off: the rights of its roles apply only after SET ROLE'),
    (Key: 'replication'; Caption: 'Replication'; Column: 'rolreplication'; YesWord: 'REPLICATION';
     NoWord: 'NOREPLICATION'; Hint: 'Can start streaming replication and backups'),
    (Key: 'bypassrls'; Caption: 'Bypass row-level security'; Column: 'rolbypassrls'; YesWord: 'BYPASSRLS';
     NoWord: 'NOBYPASSRLS'; Hint: ''));

function TpgnPostgresAdapter.AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs;
var
  R: TpgnResultSet;
  Cols: string;
  I: Integer;
begin
  Result := nil;
  Cols := '';
  for I := 0 to High(PgRoleFlags) do
  begin
    Cols := Cols + 'CASE WHEN ' + PgRoleFlags[I].Column + ' THEN ''1'' ELSE ''0'' END, ';
  end;
  R := MetaResult('SELECT ' + Cols + 'rolconnlimit::text, ' +
    'CASE WHEN rolvaliduntil IS NULL OR rolvaliduntil = ''infinity'' THEN '''' ' +
    'ELSE to_char(rolvaliduntil, ''YYYY-MM-DD HH24:MI'') END ' +
    'FROM pg_roles WHERE rolname = ' + L(AAccount.Name));
  try
    if R.RowCount = 0 then
    begin
      raise Exception.Create('Role ' + AAccount.Name + ' no longer exists.');
    end;
    SetLength(Result, Length(PgRoleFlags) + 2);
    for I := 0 to High(PgRoleFlags) do
    begin
      Result[I] := Default(TpgnAccountAttr);
      Result[I].Key := PgRoleFlags[I].Key;
      Result[I].Caption := PgRoleFlags[I].Caption;
      Result[I].Hint := PgRoleFlags[I].Hint;
      Result[I].Kind := akBool;
      Result[I].Value := R.Rows[0].Values[I];
    end;
    I := Length(PgRoleFlags);
    Result[I] := Default(TpgnAccountAttr);
    Result[I].Key := 'connlimit';
    Result[I].Caption := 'Connection limit';
    Result[I].Hint := '-1 or empty: no limit';
    Result[I].Kind := akInt;
    Result[I].Value := R.Rows[0].Values[I];
    if Result[I].Value = '-1' then
    begin
      Result[I].Value := '';
    end;
    Result[I + 1] := Default(TpgnAccountAttr);
    Result[I + 1].Key := 'validuntil';
    Result[I + 1].Caption := 'Password valid until';
    Result[I + 1].Hint := 'yyyy-mm-dd or yyyy-mm-dd hh:mm; empty: always';
    Result[I + 1].Kind := akText;
    Result[I + 1].Value := R.Rows[0].Values[I + 1];
  finally
    R.Free;
  end;
end;

function TpgnPostgresAdapter.AlterAccountSQL(const AAccount: TpgnAccount;
  const AOld, ANew: TpgnAccountAttrs): TpgnStringArray;
var
  I, J, N: Integer;
  Words: string;
begin
  Result := nil;
  Words := '';
  for I := 0 to High(ANew) do
  begin
    if (I > High(AOld)) or (AOld[I].Value = ANew[I].Value) then
    begin
      Continue;
    end;
    if ANew[I].Key = 'connlimit' then
    begin
      if Trim(ANew[I].Value) = '' then
      begin
        Words := Words + ' CONNECTION LIMIT -1';
      end
      else if TryStrToInt(Trim(ANew[I].Value), N) then
      begin
        Words := Words + ' CONNECTION LIMIT ' + IntToStr(N);
      end
      else
      begin
        raise Exception.Create('Connection limit must be a whole number.');
      end;
    end
    else if ANew[I].Key = 'validuntil' then
    begin
      if Trim(ANew[I].Value) = '' then
      begin
        Words := Words + ' VALID UNTIL ''infinity''';
      end
      else
      begin
        Words := Words + ' VALID UNTIL ' + L(Trim(ANew[I].Value));
      end;
    end
    else
    begin
      for J := 0 to High(PgRoleFlags) do
      begin
        if PgRoleFlags[J].Key = ANew[I].Key then
        begin
          if ANew[I].Value = '1' then
          begin
            Words := Words + ' ' + PgRoleFlags[J].YesWord;
          end
          else
          begin
            Words := Words + ' ' + PgRoleFlags[J].NoWord;
          end;
        end;
      end;
    end;
  end;
  if Words <> '' then
  begin
    SetLength(Result, 1);
    Result[0] := 'ALTER ROLE ' + QuoteIdent(AAccount.Name) + Words;
  end;
end;

function TpgnPostgresAdapter.CreateAccountSQL(const AAccount: TpgnAccount;
  const APassword: string): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  if AAccount.IsRole then
  begin
    Result[0] := 'CREATE ROLE ' + QuoteIdent(AAccount.Name) + ' NOLOGIN';
  end
  else if APassword <> '' then
  begin
    Result[0] := 'CREATE ROLE ' + QuoteIdent(AAccount.Name) + ' LOGIN PASSWORD ' + L(APassword);
  end
  else
  begin
    Result[0] := 'CREATE ROLE ' + QuoteIdent(AAccount.Name) + ' LOGIN';
  end;
end;

function TpgnPostgresAdapter.PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string;
begin
  Result := 'ALTER ROLE ' + QuoteIdent(AAccount.Name) + ' PASSWORD ' + L(APassword);
end;

function TpgnPostgresAdapter.AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT r.rolname AS "Role", ' +
    'CASE WHEN m.admin_option THEN ''yes'' ELSE '''' END AS "Can pass on", ' +
    'pg_get_userbyid(m.grantor) AS "Granted by" ' +
    'FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.roleid ' +
    'WHERE m.member = ' + RoleOid(AAccount) + ' ORDER BY 1');
end;

function TpgnPostgresAdapter.AccountMembers(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT u.rolname AS "Member", ' +
    'CASE WHEN m.admin_option THEN ''yes'' ELSE '''' END AS "Can pass on", ' +
    'pg_get_userbyid(m.grantor) AS "Granted by" ' +
    'FROM pg_auth_members m JOIN pg_roles u ON u.oid = m.member ' +
    'WHERE m.roleid = ' + RoleOid(AAccount) + ' ORDER BY 1');
end;

function TpgnPostgresAdapter.GrantRoleSQL(const ARole, AMember: TpgnAccount;
  AAdmin: Boolean): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := 'GRANT ' + QuoteIdent(ARole.Name) + ' TO ' + QuoteIdent(AMember.Name);
  if AAdmin then
  begin
    Result[0] := Result[0] + ' WITH ADMIN OPTION';
  end;
end;

function TpgnPostgresAdapter.RevokeRoleSQL(const ARole, AMember: TpgnAccount): string;
begin
  Result := 'REVOKE ' + QuoteIdent(ARole.Name) + ' FROM ' + QuoteIdent(AMember.Name);
end;

function TpgnPostgresAdapter.AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet;
const
  Tail = 'a.privilege_type AS "Privilege", ' +
    'CASE WHEN a.is_grantable THEN ''yes'' ELSE '''' END AS "Can grant", ' +
    'pg_get_userbyid(a.grantor) AS "Granted by" ';
  NotSystem = ' AND n.nspname NOT IN (''pg_catalog'', ''information_schema'') AND n.nspname !~ ''^pg_toast''';
var
  R: string;
begin
  R := RoleOid(AAccount);
  Result := MetaResult('SELECT * FROM (' +
    'SELECT quote_ident(n.nspname) || ''.'' || quote_ident(c.relname) AS "Object", ' +
    'CASE c.relkind WHEN ''v'' THEN ''view'' WHEN ''m'' THEN ''materialized view'' ' +
    'WHEN ''S'' THEN ''sequence'' WHEN ''f'' THEN ''foreign table'' ELSE ''table'' END AS "Type", ' + Tail +
    'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, aclexplode(c.relacl) a ' +
    'WHERE a.grantee = ' + R + NotSystem +
    ' UNION ALL SELECT quote_ident(n.nspname) || ''.'' || quote_ident(p.proname) || ''('' || ' +
    'oidvectortypes(p.proargtypes) || '')'', ' +
    'CASE p.prokind WHEN ''p'' THEN ''procedure'' ELSE ''function'' END, ' + Tail +
    'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace, aclexplode(p.proacl) a ' +
    'WHERE a.grantee = ' + R + NotSystem +
    ' UNION ALL SELECT quote_ident(n.nspname), ''schema'', ' + Tail +
    'FROM pg_namespace n, aclexplode(n.nspacl) a WHERE a.grantee = ' + R +
    ' UNION ALL SELECT quote_ident(d.datname), ''database'', ' + Tail +
    'FROM pg_database d, aclexplode(d.datacl) a WHERE a.grantee = ' + R +
    ') x ORDER BY 2, 1, 3');
end;

function PgObjectWord(const AType: string): string;
begin
  if (AType = 'table') or (AType = 'view') or (AType = 'materialized view') or (AType = 'foreign table') then
  begin
    Result := 'TABLE';
  end
  else
  begin
    Result := UpperCase(AType);   // SEQUENCE, FUNCTION, PROCEDURE, SCHEMA, DATABASE
  end;
end;

function TpgnPostgresAdapter.RevokePrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string): string;
begin
  Result := 'REVOKE ' + APrivilege + ' ON ' + PgObjectWord(AType) + ' ' + AObject + ' FROM ' +
    QuoteIdent(AAccount.Name);
end;

function TpgnPostgresAdapter.GrantPrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string; AGrantOption: Boolean): string;
begin
  Result := 'GRANT ' + APrivilege + ' ON ' + PgObjectWord(AType) + ' ' + AObject + ' TO ' +
    QuoteIdent(AAccount.Name);
  if AGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
end;

function TpgnPostgresAdapter.AccountDDL(const AAccount: TpgnAccount): string;
var
  A: TpgnAccountAttrs;
  R: TpgnResultSet;
  I, J, P: Integer;
  S, Who, Setting: string;
begin
  Who := QuoteIdent(AAccount.Name);
  A := AccountAttrs(AAccount);
  S := 'CREATE ROLE ' + Who + ' WITH';
  for I := 0 to High(A) do
  begin
    for J := 0 to High(PgRoleFlags) do
    begin
      if PgRoleFlags[J].Key = A[I].Key then
      begin
        if A[I].Value = '1' then
        begin
          S := S + ' ' + PgRoleFlags[J].YesWord;
        end
        else
        begin
          S := S + ' ' + PgRoleFlags[J].NoWord;
        end;
      end;
    end;
    if (A[I].Key = 'connlimit') and (A[I].Value <> '') then
    begin
      S := S + ' CONNECTION LIMIT ' + A[I].Value;
    end;
    if (A[I].Key = 'validuntil') and (A[I].Value <> '') then
    begin
      S := S + ' VALID UNTIL ' + L(A[I].Value);
    end;
  end;
  Result := '-- ' + AAccount.Name + ' (the password is not included)' + LineEnding + S + ';' + LineEnding;

  // settings made with ALTER ROLE ... SET
  R := MetaResult('SELECT coalesce(d.datname, ''''), c FROM pg_db_role_setting s ' +
    'LEFT JOIN pg_database d ON d.oid = s.setdatabase, unnest(s.setconfig) c ' +
    'WHERE s.setrole = ' + RoleOid(AAccount) + ' ORDER BY 1, 2');
  try
    for I := 0 to R.RowCount - 1 do
    begin
      Setting := R.Rows[I].Values[1];
      P := Pos('=', Setting);
      S := 'ALTER ROLE ' + Who;
      if R.Rows[I].Values[0] <> '' then
      begin
        S := S + ' IN DATABASE ' + QuoteIdent(R.Rows[I].Values[0]);
      end;
      Result := Result + S + ' SET ' + Copy(Setting, 1, P - 1) + ' = ' +
        L(Copy(Setting, P + 1, MaxInt)) + ';' + LineEnding;
    end;
  finally
    R.Free;
  end;

  R := AccountMemberOf(AAccount);
  try
    if R.RowCount > 0 then
    begin
      Result := Result + LineEnding;
    end;
    for I := 0 to R.RowCount - 1 do
    begin
      Result := Result + GrantRoleSQL(AccountFromText(R.Rows[I].Values[0]), AAccount,
        R.Rows[I].Values[1] = 'yes')[0] + ';' + LineEnding;
    end;
  finally
    R.Free;
  end;

  R := AccountPrivileges(AAccount);
  try
    if R.RowCount > 0 then
    begin
      Result := Result + LineEnding + '-- object grants in database ' + FInfo.DefaultDatabase + LineEnding;
    end;
    for I := 0 to R.RowCount - 1 do
    begin
      Result := Result + GrantPrivilegeSQL(AAccount, R.Rows[I].Values[0], R.Rows[I].Values[1],
        R.Rows[I].Values[2], R.Rows[I].Values[3] = 'yes') + ';' + LineEnding;
    end;
  finally
    R.Free;
  end;
end;

function TpgnPostgresAdapter.AccountOwns(const AAccount: TpgnAccount): TpgnResultSet;
var
  R: string;
begin
  R := RoleOid(AAccount);
  Result := MetaResult('SELECT * FROM (' +
    'SELECT quote_ident(n.nspname) || ''.'' || quote_ident(c.relname) AS "Object", ' +
    'CASE c.relkind WHEN ''v'' THEN ''view'' WHEN ''m'' THEN ''materialized view'' ' +
    'WHEN ''S'' THEN ''sequence'' WHEN ''f'' THEN ''foreign table'' ELSE ''table'' END AS "Type", ' +
    'current_database()::text AS "Where" ' +
    'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE c.relowner = ' + R + ' AND c.relkind IN (''r'', ''p'', ''v'', ''m'', ''S'', ''f'') ' +
    'UNION ALL SELECT quote_ident(n.nspname) || ''.'' || quote_ident(p.proname) || ''('' || ' +
    'oidvectortypes(p.proargtypes) || '')'', ' +
    'CASE p.prokind WHEN ''p'' THEN ''procedure'' WHEN ''a'' THEN ''aggregate'' ELSE ''function'' END, ' +
    'current_database()::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
    'WHERE p.proowner = ' + R +
    ' UNION ALL SELECT quote_ident(nspname), ''schema'', current_database()::text ' +
    'FROM pg_namespace WHERE nspowner = ' + R +
    ' UNION ALL SELECT quote_ident(n.nspname) || ''.'' || quote_ident(t.typname), ' +
    'CASE t.typtype WHEN ''d'' THEN ''domain'' WHEN ''e'' THEN ''enum type'' ELSE ''type'' END, ' +
    'current_database()::text FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace ' +
    'WHERE t.typowner = ' + R + ' AND t.typtype IN (''d'', ''e'', ''r'', ''m'') ' +
    'UNION ALL SELECT quote_ident(datname), ''database'', ''(the server)'' FROM pg_database ' +
    'WHERE datdba = ' + R +
    ' UNION ALL SELECT quote_ident(spcname), ''tablespace'', ''(the server)'' FROM pg_tablespace ' +
    'WHERE spcowner = ' + R +
    ') x ORDER BY 3, 2, 1');
end;

function TpgnPostgresAdapter.CanReassignOwned: Boolean;
begin
  Result := True;
end;

{ In one transaction, so a DROP ROLE that fails leaves nothing half done. }
function TpgnPostgresAdapter.DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
  ADropOwned: Boolean): TpgnStringArray;
var
  N: Integer;
begin
  Result := nil;
  SetLength(Result, 5);
  N := 0;
  Result[N] := 'BEGIN';
  Inc(N);
  if AReassignTo <> '' then
  begin
    Result[N] := 'REASSIGN OWNED BY ' + QuoteIdent(AAccount.Name) + ' TO ' + QuoteIdent(AReassignTo);
    Inc(N);
  end;
  if ADropOwned then
  begin
    Result[N] := 'DROP OWNED BY ' + QuoteIdent(AAccount.Name);
    Inc(N);
  end;
  Result[N] := 'DROP ROLE ' + QuoteIdent(AAccount.Name);
  Inc(N);
  Result[N] := 'COMMIT';
  Inc(N);
  SetLength(Result, N);
end;

function TpgnPostgresAdapter.MissingRight(const AAction: string): string;
begin
  Result := '';
  try
    if AAction = 'kill' then
    begin
      if MetaValue('SELECT rolsuper OR pg_has_role(current_user, ''pg_signal_backend'', ''MEMBER'') ' +
        'FROM pg_roles WHERE rolname = current_user') = 'f' then
      begin
        Result := 'Needs superuser or membership in pg_signal_backend (your own sessions are fine)';
      end;
    end
    else if AAction = 'accounts' then
    begin
      if MetaValue('SELECT rolsuper OR rolcreaterole FROM pg_roles WHERE rolname = current_user') = 'f' then
      begin
        Result := 'Needs the CREATEROLE attribute (or superuser) to change accounts';
      end;
    end;
  except
    on E: Exception do
    begin
      Result := '';   // can't tell: the server decides
    end;
  end;
end;

procedure TpgnPostgresAdapter.RunAdmin(const ASQL: string);
begin
  MetaExec(ASQL);
end;


{ 'A B C' -> ['A', 'B', 'C'], with '_' standing for a space in a name. }
function WordList(const AWords: string): TpgnStringArray;
var
  I: Integer;
begin
  Result := AWords.Split([' ']);
  for I := 0 to High(Result) do
  begin
    Result[I] := StringReplace(Result[I], '_', ' ', [rfReplaceAll]);
  end;
end;

function TpgnPostgresAdapter.GrantTargets: TpgnStringArray;
begin
  Result := WordList('table all_tables schema sequence function procedure database');
end;

function TpgnPostgresAdapter.GrantTargetCaption(const AKind: string): string;
begin
  if AKind = 'table' then
  begin
    Result := 'A table or view';
  end
  else if AKind = 'all tables' then
  begin
    Result := 'All tables in a schema (as they are now)';
  end
  else if AKind = 'schema' then
  begin
    Result := 'A schema';
  end
  else if AKind = 'sequence' then
  begin
    Result := 'A sequence';
  end
  else if AKind = 'function' then
  begin
    Result := 'A function';
  end
  else if AKind = 'procedure' then
  begin
    Result := 'A procedure';
  end
  else
  begin
    Result := 'A database';
  end;
end;

function TpgnPostgresAdapter.GrantContainerCaption(const AKind: string): string;
begin
  if AKind = 'database' then
  begin
    Result := 'Database';
  end
  else
  begin
    Result := 'Schema';
  end;
end;

function TpgnPostgresAdapter.GrantContainers(const AKind: string): TpgnStringArray;
begin
  if AKind = 'database' then
  begin
    Result := ListDatabases;
  end
  else
  begin
    Result := ListSchemas(False);
  end;
end;

function TpgnPostgresAdapter.GrantNeedsObject(const AKind: string): Boolean;
begin
  Result := (AKind = 'table') or (AKind = 'sequence') or (AKind = 'function') or (AKind = 'procedure');
end;

function TpgnPostgresAdapter.GrantObjects(const AKind, AContainer: string): TpgnStringArray;
var
  N: string;
begin
  N := 'n.nspname = ' + L(AContainer);
  if AKind = 'table' then
  begin
    Result := MetaStrings('SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE ' + N + ' AND c.relkind IN (''r'', ''p'', ''v'', ''m'', ''f'') ORDER BY 1');
  end
  else if AKind = 'sequence' then
  begin
    Result := MetaStrings('SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE ' + N + ' AND c.relkind = ''S'' ORDER BY 1');
  end
  else if (AKind = 'function') or (AKind = 'procedure') then
  begin
    if AKind = 'function' then
    begin
      N := N + ' AND p.prokind = ''f''';
    end
    else
    begin
      N := N + ' AND p.prokind = ''p''';
    end;
    Result := MetaStrings('SELECT p.proname || ''('' || oidvectortypes(p.proargtypes) || '')'' ' +
      'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE ' + N + ' ORDER BY 1');
  end
  else
  begin
    Result := nil;
  end;
end;

{ In the form the Privileges tab shows; "all tables" becomes
  "IN SCHEMA s" after the words ALL TABLES. }
function TpgnPostgresAdapter.GrantObjectText(const AKind, AContainer, AName: string): string;
var
  P: Integer;
begin
  if AKind = 'all tables' then
  begin
    Result := 'IN SCHEMA ' + QuoteIdent(AContainer);
  end
  else if (AKind = 'schema') or (AKind = 'database') then
  begin
    Result := QuoteIdent(AContainer);
  end
  else if (AKind = 'function') or (AKind = 'procedure') then
  begin
    P := Pos('(', AName);
    Result := QuoteIdent(AContainer) + '.' + QuoteIdent(Copy(AName, 1, P - 1)) + Copy(AName, P, MaxInt);
  end
  else
  begin
    Result := QuoteIdent(AContainer) + '.' + QuoteIdent(AName);
  end;
end;

function TpgnPostgresAdapter.GrantPrivileges(const AKind: string): TpgnStringArray;
begin
  if (AKind = 'table') or (AKind = 'all tables') then
  begin
    Result := WordList('SELECT INSERT UPDATE DELETE TRUNCATE REFERENCES TRIGGER');
  end
  else if AKind = 'schema' then
  begin
    Result := WordList('USAGE CREATE');
  end
  else if AKind = 'sequence' then
  begin
    Result := WordList('USAGE SELECT UPDATE');
  end
  else if AKind = 'database' then
  begin
    Result := WordList('CONNECT CREATE TEMPORARY');
  end
  else
  begin
    Result := WordList('EXECUTE');
  end;
end;


{ ------------------------------------------------------ who can do what }

{ The object's ACL, owner and ACL type (for acldefault) as one row "obj". }
function TpgnPostgresAdapter.AccessSource(const AKind, AContainer, AName: string): string;
var
  Obj: string;
begin
  Obj := L(GrantObjectText(AKind, AContainer, AName));
  if AKind = 'schema' then
  begin
    Result := 'SELECT nspacl AS acl, nspowner AS owner, ''n''::"char" AS t FROM pg_namespace ' +
      'WHERE nspname = ' + L(AContainer);
  end
  else if AKind = 'database' then
  begin
    Result := 'SELECT datacl AS acl, datdba AS owner, ''d''::"char" AS t FROM pg_database ' +
      'WHERE datname = ' + L(AContainer);
  end
  else if (AKind = 'function') or (AKind = 'procedure') then
  begin
    Result := 'SELECT proacl AS acl, proowner AS owner, ''f''::"char" AS t FROM pg_proc ' +
      'WHERE oid = to_regprocedure(' + Obj + ')';
  end
  else if AKind = 'sequence' then
  begin
    Result := 'SELECT relacl AS acl, relowner AS owner, ''s''::"char" AS t FROM pg_class ' +
      'WHERE oid = to_regclass(' + Obj + ')';
  end
  else
  begin
    Result := 'SELECT relacl AS acl, relowner AS owner, ''r''::"char" AS t FROM pg_class ' +
      'WHERE oid = to_regclass(' + Obj + ')';
  end;
end;

{ The ACL as it is, or the built-in default when nobody has granted
  anything yet (which is where PUBLIC's EXECUTE on functions comes from). }
function TpgnPostgresAdapter.ObjectAccess(const AKind, AContainer, AName: string;
  AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet;
const
  KindCol = 'CASE WHEN r.rolcanlogin THEN ''user'' ELSE ''role'' END';
var
  SQL, Sys: string;
begin
  Sys := '';
  if not ASystem then
  begin
    Sys := ' AND r.rolname !~ ''^pg_''';
  end;
  SQL := 'WITH RECURSIVE obj AS (' + AccessSource(AKind, AContainer, AName) + '), ' +
    'g AS (SELECT a.grantee, a.privilege_type, a.is_grantable FROM obj, ' +
    'aclexplode(coalesce(obj.acl, acldefault(obj.t, obj.owner))) a), ' +
    'm(member, via) AS (SELECT am.member, am.roleid FROM pg_auth_members am ' +
    'WHERE am.roleid IN (SELECT grantee FROM g WHERE grantee <> 0) ' +
    'UNION SELECT am.member, m.via FROM pg_auth_members am JOIN m ON am.roleid = m.member) ' +
    'SELECT * FROM (' +
    'SELECT r.rolname AS "Who", ' + KindCol + ' AS "Kind", g.privilege_type AS "Can do", ' +
    '''direct'' AS "How", CASE WHEN g.is_grantable THEN ''yes'' ELSE '''' END AS "Can grant" ' +
    'FROM g JOIN pg_roles r ON r.oid = g.grantee, obj WHERE g.grantee <> 0 AND g.grantee <> obj.owner' + Sys;
  if AThroughRoles then
  begin
    SQL := SQL + ' UNION SELECT r.rolname, ' + KindCol + ', g.privilege_type, ' +
      '''through role '' || v.rolname, CASE WHEN g.is_grantable THEN ''yes'' ELSE '''' END ' +
      'FROM m JOIN g ON g.grantee = m.via JOIN pg_roles r ON r.oid = m.member ' +
      'JOIN pg_roles v ON v.oid = m.via, obj WHERE true' + Sys;
    if not AOwners then
    begin
      SQL := SQL + ' AND m.via <> obj.owner';
    end;
  end;
  if AOwners then
  begin
    // the owner's rights are built in: one row, not one per privilege
    SQL := SQL + ' UNION SELECT r.rolname, ' + KindCol + ', ''everything'', ''owner'', ''yes'' ' +
      'FROM obj JOIN pg_roles r ON r.oid = obj.owner' +
      ' UNION SELECT r.rolname, ' + KindCol + ', ''everything'', ''superuser'', ''yes'' ' +
      'FROM pg_roles r WHERE r.rolsuper' + Sys;
  end;
  SQL := SQL + ') x ORDER BY 1, 3, 4';
  Result := MetaResult(SQL);
end;

function TpgnPostgresAdapter.PublicAccess(const AKind, AContainer, AName: string): string;
begin
  Result := MetaValue('WITH obj AS (' + AccessSource(AKind, AContainer, AName) + ') ' +
    'SELECT coalesce(string_agg(a.privilege_type, '', '' ORDER BY a.privilege_type), '''') ' +
    'FROM obj, aclexplode(coalesce(obj.acl, acldefault(obj.t, obj.owner))) a WHERE a.grantee = 0');
end;

function TpgnPostgresAdapter.RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string;
begin
  Result := 'REVOKE ' + APrivileges + ' ON ' + PgObjectWord(AKind) + ' ' +
    GrantObjectText(AKind, AContainer, AName) + ' FROM PUBLIC';
end;

{ ------------------------------------------------------------ the session }

function TpgnPostgresAdapter.Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
var
  R: TpgnResultSet;
begin
  Result := RunStatement(FConn, TrimStatement(ASQL), ARowLimit);
  // SET search_path typed in the editor: keep the Schema picker honest
  if (FirstKeyword(ASQL) = 'SET') and (Pos('SEARCH_PATH', UpperCase(ASQL)) > 0) then
  begin
    try
      R := RunStatement(FConn, 'SELECT current_schema()', 0);
      try
        if R.RowCount > 0 then
        begin
          FSchema := R.Rows[0].Values[0];
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

procedure TpgnPostgresAdapter.CancelCurrent;
begin
  if FBackendPid = 0 then
  begin
    Exit;
  end;
  MetaExec('SELECT pg_cancel_backend(' + IntToStr(FBackendPid) + ')');
end;

{ A session can't change database: this one closes and opens on the new
  database (any open transaction is rolled back by the server). }
procedure TpgnPostgresAdapter.UseDatabase(const ADatabase: string);
var
  Old, Msg: string;
begin
  if SameText(ADatabase, FCurrentDatabase) and IsConnected then
  begin
    Exit;
  end;
  Old := FCurrentDatabase;
  Disconnect;
  FCurrentDatabase := ADatabase;
  Msg := '';
  try
    Connect;
  except
    on E: Exception do
    begin
      Msg := E.Message;
    end;
  end;
  if Msg <> '' then
  begin
    // back where it was, so the tab keeps working
    FCurrentDatabase := Old;
    try
      Connect;
    except
      on E: Exception do
      begin
        // the first error is the one to report
      end;
    end;
    raise Exception.Create('Could not open ' + ADatabase + ': ' + Msg);
  end;
end;

{ Transactions as plain SQL: with auto-commit off a transaction is always
  open (BEGIN after every COMMIT or ROLLBACK), as in Toad and SSMS. }
procedure TpgnPostgresAdapter.SetAutoCommit(AValue: Boolean);
begin
  if AValue = FAutoCommit then
  begin
    Exit;
  end;
  if AValue then
  begin
    FConn.ExecuteDirect('COMMIT');
  end
  else
  begin
    FConn.ExecuteDirect('BEGIN');
  end;
  FAutoCommit := AValue;
end;

function TpgnPostgresAdapter.AutoCommit: Boolean;
begin
  Result := FAutoCommit;
end;

procedure TpgnPostgresAdapter.Commit;
begin
  FConn.ExecuteDirect('COMMIT');
  if not FAutoCommit then
  begin
    FConn.ExecuteDirect('BEGIN');
  end;
end;

procedure TpgnPostgresAdapter.Rollback;
begin
  FConn.ExecuteDirect('ROLLBACK');
  if not FAutoCommit then
  begin
    FConn.ExecuteDirect('BEGIN');
  end;
end;

end.
