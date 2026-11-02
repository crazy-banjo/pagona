// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapterOracle;

{ Oracle adapter, built on ZeosLib and the Oracle client (Instant Client's
  oci.dll / libclntsh.so).

  Written without an Oracle server to try it on: the SQL follows Oracle's
  documented data dictionary (ALL_* views for what any login may see,
  DBA_* and V$ views for the DBA screens, falling back where a login
  can't read them). First runs are expected to need small fixes.

  How Oracle maps onto Pagona:
    - one database per connection; schemas (users) hold the objects, so
      the Explorer shows the database, then its schemas, like PostgreSQL;
    - names are stored in upper case; QuoteIdent leaves plain upper-case
      names bare and quotes anything else;
    - a session is connected by TNS alias (tnsnames.ora, as Toad does) or
      by host, port and service name (Easy Connect);
    - PL/SQL blocks are sent whole, ending in "END;"; other statements
      without their ';' (Oracle refuses it);
    - DBMS_OUTPUT is switched on for every session and read after each
      statement; what was printed comes back as an extra result set
      named "DBMS Output";
    - CREATE OR REPLACE of code always replaces, even when it doesn't
      compile (the object is then INVALID): Save says so, with the lines
      from ALL_ERRORS. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ZConnection, ZDbcIntfs,
  pgnTypes, pgnAdapter, pgnSqlSplit, pgnZeos, pgnTns;

type
  TpgnOracleAdapter = class(TpgnAdapter)
  private
    FConn: TZConnection;
    FMeta: TZConnection;
    FVersion: string;
    FDbName: string;
    FSchema: string;
    FSid: string;
    FSerial: string;
    FAutoCommit: Boolean;
    FDbmsOutput: Boolean;        // read DBMS_OUTPUT after each statement
    FMetadataReady: Boolean;     // DBMS_METADATA transform params set
    procedure Configure(AConn: TZConnection);
    function ConnectString: string;
    function MetaResult(const ASQL: string): TpgnResultSet;
    function MetaStrings(const ASQL: string): TpgnStringArray;
    function MetaValue(const ASQL: string): string;
    procedure MetaExec(const ASQL: string);
    function TryValue(const ASQL: string): string;
    function L(const AText: string): string;
    function Q2(const ASchema, AName: string): string;
    function MetadataDDL(const AType, ASchema, AName: string): string;
    function SourceText(const ASchema, AName, AType: string): string;
    function CompileErrors(AConn: TZConnection; const ASchema, AName, AType: string): string;
    function ReadDbmsOutput: TpgnResultSet;
    function SessionId(const ASession: string): string;
    function HasPriv(const APrivilege: string): Boolean;
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
    function ObjectScript(const ADatabase, AName, AKind: string): string; override;
    function SelectTopSQL(const AQualifiedName: string; ARows: Integer): string; override;
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
    function DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
      ADropOwned: Boolean): TpgnStringArray; override;
    function DropOwnedChoice: Boolean; override;
    procedure RunAdmin(const ASQL: string); override;
    function MissingRight(const AAction: string): string; override;

    function GrantTargets: TpgnStringArray; override;
    function GrantTargetCaption(const AKind: string): string; override;
    function GrantContainerCaption(const AKind: string): string; override;
    function GrantContainers(const AKind: string): TpgnStringArray; override;
    function GrantNeedsObject(const AKind: string): Boolean; override;
    function GrantObjects(const AKind, AContainer: string): TpgnStringArray; override;
    function GrantObjectText(const AKind, AContainer, AName: string): string; override;
    function GrantPrivileges(const AKind: string): TpgnStringArray; override;
    function ObjectAccess(const AKind, AContainer, AName: string;
      AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet; override;
    function PublicAccess(const AKind, AContainer, AName: string): string; override;
    function RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string; override;

    function Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet; override;
    procedure CancelCurrent; override;

    function QuoteIdent(const AName: string): string; override;
    procedure UseDatabase(const ADatabase: string); override;
    procedure SetAutoCommit(AValue: Boolean); override;
    function AutoCommit: Boolean; override;
    procedure Commit; override;
    procedure Rollback; override;
  end;

{ True when ASQL is a PL/SQL block or creates PL/SQL code (it must then
  keep its final ';'). }
function IsPlSqlBlock(const ASQL: string): Boolean;

implementation

{$IFDEF WINDOWS}
uses
  Windows;
{$ELSE}
function setenv(const AName, AValue: PChar; AOverwrite: Integer): Integer; cdecl; external 'c' name 'setenv';
{$ENDIF}

const
  NotSystemUser = '(SELECT username FROM all_users WHERE oracle_maintained = ''N'')';
  ReservedWords: array[0..39] of string = (
    'ACCESS', 'ADD', 'ALL', 'ALTER', 'AND', 'ANY', 'AS', 'ASC', 'AUDIT', 'BETWEEN', 'BY', 'CHAR',
    'CHECK', 'CLUSTER', 'COLUMN', 'COMMENT', 'COMPRESS', 'CONNECT', 'CREATE', 'CURRENT', 'DATE',
    'DECIMAL', 'DEFAULT', 'DELETE', 'DESC', 'DISTINCT', 'DROP', 'ELSE', 'EXCLUSIVE', 'EXISTS',
    'FILE', 'FLOAT', 'FOR', 'FROM', 'GRANT', 'GROUP', 'HAVING', 'IDENTIFIED', 'IMMEDIATE', 'IN');
  MoreReserved: array[0..48] of string = (
    'INCREMENT', 'INDEX', 'INITIAL', 'INSERT', 'INTEGER', 'INTERSECT', 'INTO', 'IS', 'LEVEL', 'LIKE',
    'LOCK', 'LONG', 'MAXEXTENTS', 'MINUS', 'MODE', 'MODIFY', 'NOAUDIT', 'NOCOMPRESS', 'NOT',
    'NOWAIT', 'NULL', 'NUMBER', 'OF', 'OFFLINE', 'ON', 'ONLINE', 'OPTION', 'OR', 'ORDER', 'PRIOR',
    'PUBLIC', 'RAW', 'RENAME', 'RESOURCE', 'REVOKE', 'ROW', 'ROWID', 'ROWNUM', 'ROWS', 'SELECT',
    'SESSION', 'SET', 'SHARE', 'SIZE', 'START', 'TABLE', 'TO', 'UPDATE', 'USER');

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

function IsPlSqlBlock(const ASQL: string): Boolean;
var
  K, U: string;
  P: Integer;
begin
  K := FirstKeyword(ASQL);
  if (K = 'DECLARE') or (K = 'BEGIN') then
  begin
    Result := True;
    Exit;
  end;
  Result := False;
  if K <> 'CREATE' then
  begin
    Exit;
  end;
  U := UpperCase(ASQL);
  P := Pos('CREATE', U);
  U := ' ' + StringReplace(StringReplace(Copy(U, P, 200), #10, ' ', [rfReplaceAll]), #13, ' ', [rfReplaceAll]) + ' ';
  Result := (Pos(' PROCEDURE ', U) > 0) or (Pos(' FUNCTION ', U) > 0) or (Pos(' PACKAGE ', U) > 0) or
    (Pos(' TRIGGER ', U) > 0) or (Pos(' TYPE ', U) > 0) or (Pos(' LIBRARY ', U) > 0);
  // CREATE TABLE ... (a column called type) isn't code: the kind is the
  // first word after CREATE [OR REPLACE] [EDITIONABLE]
  if Result then
  begin
    U := Trim(Copy(U, Pos('CREATE', U) + 6, MaxInt));
    if Copy(U, 1, 3) = 'OR ' then
    begin
      U := Trim(Copy(U, 4, MaxInt));
    end;
    if Copy(U, 1, 8) = 'REPLACE ' then
    begin
      U := Trim(Copy(U, 9, MaxInt));
    end;
    if Copy(U, 1, 12) = 'EDITIONABLE ' then
    begin
      U := Trim(Copy(U, 13, MaxInt));
    end;
    if Copy(U, 1, 15) = 'NONEDITIONABLE ' then
    begin
      U := Trim(Copy(U, 16, MaxInt));
    end;
    Result := (Copy(U, 1, 10) = 'PROCEDURE ') or (Copy(U, 1, 9) = 'FUNCTION ') or
      (Copy(U, 1, 8) = 'PACKAGE ') or (Copy(U, 1, 8) = 'TRIGGER ') or (Copy(U, 1, 5) = 'TYPE ') or
      (Copy(U, 1, 8) = 'LIBRARY ');
  end;
end;

{ What goes to the server: no trailing '/' line; PL/SQL keeps (or gets) its
  final ';', anything else loses it. }
function OracleStatement(const ASQL: string): string;
begin
  Result := Trim(ASQL);
  while (Result <> '') and (Result[Length(Result)] = '/') do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
  if IsPlSqlBlock(Result) then
  begin
    if (Result <> '') and (Result[Length(Result)] <> ';') then
    begin
      Result := Result + ';';
    end;
  end
  else
  begin
    Result := TrimStatement(Result);
  end;
end;

{ ------------------------------------------------------------ connecting }

constructor TpgnOracleAdapter.Create(const AInfo: TpgnConnectionInfo; const APassword: string);
begin
  inherited Create(AInfo, APassword);
  FConn := TZConnection.Create(nil);
  FMeta := TZConnection.Create(nil);
  FAutoCommit := True;
  FDbmsOutput := True;
end;

destructor TpgnOracleAdapter.Destroy;
begin
  Disconnect;
  FreeAndNil(FMeta);
  FreeAndNil(FConn);
  inherited Destroy;
end;

{ A TNS alias as Toad uses, or Easy Connect: //host:port/service. }
function TpgnOracleAdapter.ConnectString: string;
begin
  if FInfo.TnsAlias <> '' then
  begin
    Result := FInfo.TnsAlias;
  end
  else
  begin
    if FInfo.Host = '' then
    begin
      raise Exception.Create('Give either a TNS alias, or a host and service name, for this connection.');
    end;
    Result := '//' + FInfo.Host;
    if FInfo.Port > 0 then
    begin
      Result := Result + ':' + IntToStr(FInfo.Port);
    end;
    Result := Result + '/' + FInfo.DefaultDatabase;
  end;
end;

procedure TpgnOracleAdapter.Configure(AConn: TZConnection);
var
  Tns: string;
begin
  // the client finds tnsnames.ora through TNS_ADMIN
  Tns := FindTnsFile(FInfo.TnsFile, FInfo.ClientLibrary);
  if (Tns <> '') and (FInfo.TnsAlias <> '') then
  begin
    {$IFDEF WINDOWS}
    SetEnvironmentVariable('TNS_ADMIN', PChar(TnsFolder(Tns)));
    {$ELSE}
    setenv('TNS_ADMIN', PChar(TnsFolder(Tns)), 1);
    {$ENDIF}
  end;
  AConn.Protocol := 'oracle';
  AConn.HostName := '';
  AConn.Port := 0;
  AConn.Database := ConnectString;
  AConn.User := FInfo.User;
  AConn.Password := FPassword;
  AConn.LoginPrompt := False;
  if FInfo.ClientLibrary <> '' then
  begin
    AConn.LibraryLocation := FInfo.ClientLibrary;
  end;
  AConn.Properties.Values['codepage'] := 'AL32UTF8';
end;

procedure TpgnOracleAdapter.Connect;
var
  R: TpgnResultSet;
begin
  Configure(FConn);
  FConn.AutoCommit := FAutoCommit;
  try
    FConn.Connect;
  except
    on E: Exception do
    begin
      if (Pos('ORA-12154', E.Message) > 0) then
      begin
        raise Exception.Create('The Oracle client doesn''t know the alias "' + FInfo.TnsAlias +
          '". Check the tnsnames.ora it reads (Edit Connection shows which), or TNS_ADMIN. (' +
          Trim(E.Message) + ')');
      end;
      if (Pos('dynamic librar', LowerCase(E.Message)) > 0) or
        ((Pos('oci', LowerCase(E.Message)) > 0) and (Pos('load', LowerCase(E.Message)) > 0)) then
      begin
        raise Exception.Create('Could not load the Oracle client (Instant Client). Install it and put ' +
          'its folder on PATH, or give the path to oci.dll as the client library in Edit Connection. ' +
          '(Toad needs an Oracle client too, so one is likely installed already; Pagona needs a 64-bit one.)' +
          LineEnding + LineEnding + Trim(E.Message));
      end;
      raise;
    end;
  end;
  Configure(FMeta);
  FMeta.AutoCommit := True;
  FMeta.Connect;

  FDbName := TryValue('SELECT SYS_CONTEXT(''USERENV'', ''DB_NAME'') FROM dual');
  FSchema := TryValue('SELECT SYS_CONTEXT(''USERENV'', ''CURRENT_SCHEMA'') FROM dual');
  FCurrentDatabase := FDbName;
  FVersion := TryValue('SELECT version FROM product_component_version ' +
    'WHERE product LIKE ''Oracle%'' AND ROWNUM = 1');
  // this session's id, for "this tab" and Cancel (V$SESSION may be closed)
  R := nil;
  try
    try
      R := RunStatement(FConn, 'SELECT SYS_CONTEXT(''USERENV'', ''SID''), ' +
        '(SELECT serial# FROM v$session WHERE sid = SYS_CONTEXT(''USERENV'', ''SID'')) FROM dual', 0);
      if R.RowCount > 0 then
      begin
        FSid := R.Rows[0].Values[0];
        FSerial := R.Rows[0].Values[1];
      end;
    except
      on E: Exception do
      begin
        FSid := '';
        FSerial := '';
      end;
    end;
  finally
    R.Free;
  end;
  if FDbmsOutput then
  begin
    try
      RunStatement(FConn, 'BEGIN DBMS_OUTPUT.ENABLE(NULL); END;', 0).Free;
    except
      on E: Exception do
      begin
        FDbmsOutput := False;
      end;
    end;
  end;
end;

procedure TpgnOracleAdapter.Disconnect;
begin
  if (FConn <> nil) and FConn.Connected then
  begin
    FConn.Disconnect;
  end;
  if (FMeta <> nil) and FMeta.Connected then
  begin
    FMeta.Disconnect;
  end;
end;

function TpgnOracleAdapter.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.Connected;
end;

{ ------------------------------------------------------------- helpers }

function TpgnOracleAdapter.MetaResult(const ASQL: string): TpgnResultSet;
begin
  Result := RunStatement(FMeta, ASQL, 0);
end;

function TpgnOracleAdapter.MetaStrings(const ASQL: string): TpgnStringArray;
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

function TpgnOracleAdapter.MetaValue(const ASQL: string): string;
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

procedure TpgnOracleAdapter.MetaExec(const ASQL: string);
begin
  RunStatement(FMeta, ASQL, 0).Free;
end;

function TpgnOracleAdapter.TryValue(const ASQL: string): string;
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

function TpgnOracleAdapter.L(const AText: string): string;
begin
  Result := QuoteLiteral(AText);
end;

function TpgnOracleAdapter.Q2(const ASchema, AName: string): string;
begin
  Result := QuoteIdent(ASchema) + '.' + QuoteIdent(AName);
end;

function TpgnOracleAdapter.QuoteIdent(const AName: string): string;
var
  I: Integer;
  Bare: Boolean;
begin
  Bare := (AName <> '') and (AName[1] in ['A'..'Z']);
  for I := 1 to Length(AName) do
  begin
    if not (AName[I] in ['A'..'Z', '0'..'9', '_', '$', '#']) then
    begin
      Bare := False;
    end;
  end;
  if Bare then
  begin
    for I := 0 to High(ReservedWords) do
    begin
      if ReservedWords[I] = AName then
      begin
        Bare := False;
      end;
    end;
    for I := 0 to High(MoreReserved) do
    begin
      if MoreReserved[I] = AName then
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
    Result := '"' + StringReplace(AName, '"', '""', [rfReplaceAll]) + '"';
  end;
end;

{ DBMS_METADATA's DDL, without storage clauses; '' when the login may not
  read it (other schemas need SELECT_CATALOG_ROLE). }
function TpgnOracleAdapter.MetadataDDL(const AType, ASchema, AName: string): string;
begin
  if not FMetadataReady then
  begin
    FMetadataReady := True;
    try
      MetaExec('BEGIN ' +
        'DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''SEGMENT_ATTRIBUTES'', FALSE); ' +
        'DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''STORAGE'', FALSE); ' +
        'DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''PRETTY'', TRUE); ' +
        'DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''SQLTERMINATOR'', FALSE); ' +
        'END;');
    except
      on E: Exception do
      begin
        // the DDL just keeps its storage clauses
      end;
    end;
  end;
  try
    Result := Trim(MetaValue('SELECT DBMS_METADATA.GET_DDL(' + L(AType) + ', ' + L(AName) + ', ' +
      L(ASchema) + ') FROM dual'));
  except
    on E: Exception do
    begin
      Result := '';
    end;
  end;
end;

{ The source of a code object, as stored (ALL_SOURCE, line by line). }
function TpgnOracleAdapter.SourceText(const ASchema, AName, AType: string): string;
var
  Lines: TpgnStringArray;
  I: Integer;
begin
  Result := '';
  Lines := MetaStrings('SELECT text FROM all_source WHERE owner = ' + L(ASchema) + ' AND name = ' +
    L(AName) + ' AND type = ' + L(AType) + ' ORDER BY line');
  for I := 0 to High(Lines) do
  begin
    Result := Result + Lines[I];
    if (Lines[I] = '') or (Lines[I][Length(Lines[I])] <> #10) then
    begin
      Result := Result + LineEnding;
    end;
  end;
  Result := TrimRight(Result);
end;

{ "LINE 12: PLS-00201: identifier 'X' must be declared" per error, as the
  editor's error-line finder reads them; '' when it compiled. }
function TpgnOracleAdapter.CompileErrors(AConn: TZConnection; const ASchema, AName, AType: string): string;
var
  R: TpgnResultSet;
  I: Integer;
begin
  Result := '';
  R := RunStatement(AConn, 'SELECT line, position, text FROM all_errors WHERE owner = ' + L(ASchema) +
    ' AND name = ' + L(AName) + ' AND type = ' + L(AType) + ' ORDER BY sequence', 0);
  try
    for I := 0 to R.RowCount - 1 do
    begin
      Result := Result + 'LINE ' + R.Rows[I].Values[0] + ', column ' + R.Rows[I].Values[1] + ': ' +
        Trim(R.Rows[I].Values[2]) + LineEnding;
    end;
  finally
    R.Free;
  end;
  Result := TrimRight(Result);
end;

{ What the statement printed with DBMS_OUTPUT, one row per line; nil when
  nothing. Read with an inline function (Oracle 12c on), so no bind
  variables are needed. }
function TpgnOracleAdapter.ReadDbmsOutput: TpgnResultSet;
var
  R: TpgnResultSet;
  Lines: TStringList;
  I: Integer;
begin
  Result := nil;
  try
    R := RunStatement(FConn,
      'WITH FUNCTION pgn_output RETURN CLOB IS ' +
      'l VARCHAR2(32767); s INTEGER; r CLOB; ' +
      'BEGIN LOOP DBMS_OUTPUT.GET_LINE(l, s); EXIT WHEN s <> 0; r := r || l || CHR(10); END LOOP; ' +
      'RETURN r; END; ' +
      'SELECT pgn_output() FROM dual', 0);
  except
    on E: Exception do
    begin
      FDbmsOutput := False;   // older server: stop trying
      Exit;
    end;
  end;
  try
    if (R.RowCount = 0) or (R.Rows[0].Values[0] = '') then
    begin
      Exit;
    end;
    Lines := TStringList.Create;
    try
      Lines.Text := R.Rows[0].Values[0];
      Result := TpgnResultSet.Create;
      Result.ReturnsRows := True;
      SetLength(Result.Columns, 1);
      Result.Columns[0] := 'DBMS Output';
      SetLength(Result.Rows, Lines.Count);
      for I := 0 to Lines.Count - 1 do
      begin
        SetLength(Result.Rows[I].Values, 1);
        SetLength(Result.Rows[I].Nulls, 1);
        Result.Rows[I].Values[0] := Lines[I];
      end;
    finally
      Lines.Free;
    end;
  finally
    R.Free;
  end;
end;

{ 'sid,serial#' checked to be two numbers. }
function TpgnOracleAdapter.SessionId(const ASession: string): string;
var
  P: Integer;
  A, B: Int64;
begin
  P := Pos(',', ASession);
  if (P = 0) or not TryStrToInt64(Trim(Copy(ASession, 1, P - 1)), A) or
    not TryStrToInt64(Trim(Copy(ASession, P + 1, MaxInt)), B) then
  begin
    raise Exception.Create('"' + ASession + '" is not an Oracle session (sid,serial#).');
  end;
  Result := IntToStr(A) + ',' + IntToStr(B);
end;

function TpgnOracleAdapter.HasPriv(const APrivilege: string): Boolean;
begin
  Result := TryValue('SELECT COUNT(*) FROM session_privs WHERE privilege = ' + L(APrivilege)) <> '0';
end;

{ ------------------------------------------------------- engine shape }

function TpgnOracleAdapter.Dialect: TpgnDialect;
begin
  Result := sdOracle;
end;

function TpgnOracleAdapter.HasSchemas: Boolean;
begin
  Result := True;
end;

function TpgnOracleAdapter.TableFolders: Boolean;
begin
  Result := True;
end;

function TpgnOracleAdapter.OwnSessionId: string;
begin
  Result := FSid;
end;

function TpgnOracleAdapter.ServerVersion: string;
begin
  Result := FVersion;
end;

function TpgnOracleAdapter.ListDatabases: TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := FDbName;
end;

{ One database per connection: there's nothing to change to. }
procedure TpgnOracleAdapter.UseDatabase(const ADatabase: string);
begin
  FCurrentDatabase := FDbName;
end;

function TpgnOracleAdapter.ListSchemas(ASystem: Boolean): TpgnStringArray;
var
  Flag: string;
begin
  if ASystem then
  begin
    Flag := 'Y';
  end
  else
  begin
    Flag := 'N';
  end;
  try
    Result := MetaStrings('SELECT username FROM all_users WHERE oracle_maintained = ' + L(Flag) +
      ' ORDER BY username');
  except
    on E: Exception do
    begin
      // before 12c there is no ORACLE_MAINTAINED
      if ASystem then
      begin
        Result := Strings(['SYS', 'SYSTEM']);
      end
      else
      begin
        Result := MetaStrings('SELECT username FROM all_users WHERE username NOT IN (''SYS'', ''SYSTEM'', ' +
          '''OUTLN'', ''DBSNMP'', ''XDB'', ''CTXSYS'', ''MDSYS'', ''ORDSYS'', ''WMSYS'', ''APPQOSSYS'', ' +
          '''ANONYMOUS'', ''XS$NULL'', ''OJVMSYS'', ''GSMADMIN_INTERNAL'', ''AUDSYS'', ''DIP'') ' +
          'ORDER BY username');
      end;
    end;
  end;
end;

function TpgnOracleAdapter.CurrentSchema: string;
begin
  Result := FSchema;
end;

procedure TpgnOracleAdapter.UseSchema(const ASchema: string);
begin
  if ASchema = '' then
  begin
    Exit;
  end;
  RunStatement(FConn, 'ALTER SESSION SET CURRENT_SCHEMA = ' + QuoteIdent(ASchema), 0).Free;
  FSchema := ASchema;
end;

{ ------------------------------------------------------- Explorer folders }

function TpgnOracleAdapter.ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray;
begin
  Result := nil;
  case ALevel of
    flServer:
      begin
        if AMore then
        begin
          Result := Strings(['Profiles', 'Directories']);
        end
        else
        begin
          Result := Strings(['Users', 'Roles', 'Tablespaces']);
        end;
      end;
    flSchema:
      begin
        if AMore then
        begin
          Result := Strings(['Database Links', 'Scheduler Jobs', 'Materialized View Logs']);
        end
        else
        begin
          Result := Strings(['Packages', 'Sequences', 'Synonyms', 'Types', 'Invalid Objects']);
        end;
      end;
  end;
end;

function TpgnOracleAdapter.ListFolder(const AContainer, AFolder: string): TpgnStringArray;
var
  O: string;
begin
  Result := nil;
  O := 'owner = ' + L(AContainer);
  if AFolder = 'Packages' then
  begin
    Result := MetaStrings('SELECT object_name FROM all_objects WHERE ' + O +
      ' AND object_type = ''PACKAGE'' ORDER BY 1');
  end
  else if AFolder = 'Sequences' then
  begin
    Result := MetaStrings('SELECT sequence_name FROM all_sequences WHERE sequence_' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Synonyms' then
  begin
    Result := MetaStrings('SELECT synonym_name FROM all_synonyms WHERE ' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Types' then
  begin
    Result := MetaStrings('SELECT type_name FROM all_types WHERE ' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Invalid Objects' then
  begin
    Result := MetaStrings('SELECT object_name || '' ('' || LOWER(object_type) || '')'' FROM all_objects ' +
      'WHERE ' + O + ' AND status = ''INVALID'' ORDER BY 1');
  end
  else if AFolder = 'Database Links' then
  begin
    Result := MetaStrings('SELECT db_link FROM all_db_links WHERE ' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Scheduler Jobs' then
  begin
    Result := MetaStrings('SELECT job_name FROM all_scheduler_jobs WHERE ' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Materialized View Logs' then
  begin
    Result := MetaStrings('SELECT master FROM all_mview_logs WHERE log_' + O + ' ORDER BY 1');
  end
  else if AFolder = 'Users' then
  begin
    Result := ListSchemas(False);
  end
  else if AFolder = 'Roles' then
  begin
    try
      Result := MetaStrings('SELECT role FROM dba_roles WHERE oracle_maintained = ''N'' ORDER BY 1');
    except
      on E: Exception do
      begin
        Result := MetaStrings('SELECT role FROM session_roles ORDER BY 1');
      end;
    end;
  end
  else if AFolder = 'Tablespaces' then
  begin
    try
      Result := MetaStrings('SELECT tablespace_name FROM dba_tablespaces ORDER BY 1');
    except
      on E: Exception do
      begin
        Result := MetaStrings('SELECT tablespace_name FROM user_tablespaces ORDER BY 1');
      end;
    end;
  end
  else if AFolder = 'Profiles' then
  begin
    Result := MetaStrings('SELECT DISTINCT profile FROM dba_profiles ORDER BY 1');
  end
  else if AFolder = 'Directories' then
  begin
    Result := MetaStrings('SELECT directory_name FROM all_directories ORDER BY 1');
  end;
end;

function TpgnOracleAdapter.FolderItemSQL(const AContainer, AFolder, AName: string): string;
var
  Body: string;
begin
  Result := '';
  if AFolder = 'Packages' then
  begin
    // spec and body, each ending in '/', ready to run as a script (F5)
    Result := 'CREATE OR REPLACE ' + SourceText(AContainer, AName, 'PACKAGE');
    Result := Result + LineEnding + '/' + LineEnding;
    Body := SourceText(AContainer, AName, 'PACKAGE BODY');
    if Body <> '' then
    begin
      Result := Result + LineEnding + 'CREATE OR REPLACE ' + Body + LineEnding + '/' + LineEnding;
    end;
  end
  else if AFolder = 'Types' then
  begin
    Result := 'CREATE OR REPLACE ' + SourceText(AContainer, AName, 'TYPE') + LineEnding + '/' + LineEnding;
    Body := SourceText(AContainer, AName, 'TYPE BODY');
    if Body <> '' then
    begin
      Result := Result + LineEnding + 'CREATE OR REPLACE ' + Body + LineEnding + '/' + LineEnding;
    end;
  end
  else if AFolder = 'Sequences' then
  begin
    Result := MetaValue('SELECT ''CREATE SEQUENCE ' + Q2(AContainer, AName) + ''' || CHR(10) || ' +
      '''  START WITH '' || last_number || CHR(10) || ''  INCREMENT BY '' || increment_by || CHR(10) || ' +
      '''  MINVALUE '' || min_value || CHR(10) || ''  MAXVALUE '' || max_value || CHR(10) || ' +
      'CASE WHEN cache_size > 0 THEN ''  CACHE '' || cache_size ELSE ''  NOCACHE'' END || ' +
      'CASE WHEN cycle_flag = ''Y'' THEN CHR(10) || ''  CYCLE'' ELSE '''' END || '';'' ' +
      'FROM all_sequences WHERE sequence_owner = ' + L(AContainer) + ' AND sequence_name = ' + L(AName));
  end
  else if AFolder = 'Synonyms' then
  begin
    Result := MetaValue('SELECT ''CREATE OR REPLACE SYNONYM ' + Q2(AContainer, AName) + ' FOR '' || ' +
      'table_owner || ''.'' || table_name || CASE WHEN db_link IS NOT NULL THEN ''@'' || db_link END || '';'' ' +
      'FROM all_synonyms WHERE owner = ' + L(AContainer) + ' AND synonym_name = ' + L(AName));
  end
  else if AFolder = 'Database Links' then
  begin
    Result := MetaValue('SELECT ''CREATE DATABASE LINK '' || db_link || CHR(10) || ' +
      '''  CONNECT TO '' || username || '' IDENTIFIED BY "****"'' || CHR(10) || ''  USING '''''' || ' +
      'host || '''''';'' FROM all_db_links WHERE owner = ' + L(AContainer) + ' AND db_link = ' + L(AName));
  end
  else if AFolder = 'Scheduler Jobs' then
  begin
    Result := MetaValue('SELECT ''-- '' || job_name || CHR(10) || ''-- enabled: '' || enabled || ' +
      'CHR(10) || ''-- runs: '' || NVL(repeat_interval, ''once'') || CHR(10) || ''-- last run: '' || ' +
      'TO_CHAR(last_start_date, ''YYYY-MM-DD HH24:MI'') || CHR(10) || ''-- next run: '' || ' +
      'TO_CHAR(next_run_date, ''YYYY-MM-DD HH24:MI'') || CHR(10) || ''-- does:'' || CHR(10) || ' +
      'job_action FROM all_scheduler_jobs WHERE owner = ' + L(AContainer) + ' AND job_name = ' + L(AName));
  end
  else if AFolder = 'Directories' then
  begin
    Result := MetaValue('SELECT ''CREATE OR REPLACE DIRECTORY '' || directory_name || '' AS '''''' || ' +
      'directory_path || '''''';'' FROM all_directories WHERE directory_name = ' + L(AName));
  end
  else if AFolder = 'Tablespaces' then
  begin
    Result := TryValue('SELECT ''-- '' || tablespace_name || CHR(10) || ''-- status: '' || status || ' +
      'CHR(10) || ''-- contents: '' || contents || CHR(10) || ''-- size: '' || ' +
      '(SELECT ROUND(SUM(bytes) / 1048576) FROM dba_data_files f WHERE f.tablespace_name = t.tablespace_name) ' +
      '|| '' MB'' FROM dba_tablespaces t WHERE tablespace_name = ' + L(AName));
  end
  else if (AFolder = 'Users') or (AFolder = 'Roles') then
  begin
    Result := '-- DBA > Users and Roles shows ' + AName + ' in full.';
  end;
end;

{ ------------------------------------------------------- tables, views }

function TpgnOracleAdapter.ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray;
begin
  case AKind of
    okView:
      begin
        Result := MetaStrings('SELECT view_name FROM all_views WHERE owner = ' + L(ADatabase) +
          ' ORDER BY 1');
      end;
    okMatView:
      begin
        Result := MetaStrings('SELECT mview_name FROM all_mviews WHERE owner = ' + L(ADatabase) +
          ' ORDER BY 1');
      end;
  else
    begin
      // not the tables behind materialized views, nested tables or the recycle bin
      Result := MetaStrings('SELECT t.table_name FROM all_tables t WHERE t.owner = ' + L(ADatabase) +
        ' AND t.nested = ''NO'' AND t.table_name NOT LIKE ''BIN$%'' AND NOT EXISTS (SELECT 1 ' +
        'FROM all_mviews m WHERE m.owner = t.owner AND m.mview_name = t.table_name) ORDER BY 1');
    end;
  end;
end;

const
  TypeExpr =
    'CASE WHEN c.data_type IN (''VARCHAR2'', ''NVARCHAR2'', ''CHAR'', ''NCHAR'') ' +
    'THEN c.data_type || ''('' || c.char_length || CASE WHEN c.char_used = ''C'' THEN '' CHAR'' END || '')'' ' +
    'WHEN c.data_type = ''RAW'' THEN ''RAW('' || c.data_length || '')'' ' +
    'WHEN c.data_type = ''NUMBER'' AND c.data_precision IS NOT NULL THEN ''NUMBER('' || c.data_precision || ' +
    'CASE WHEN c.data_scale > 0 THEN '','' || c.data_scale END || '')'' ' +
    'WHEN c.data_type = ''NUMBER'' AND c.data_scale = 0 THEN ''INTEGER'' ' +
    'ELSE c.data_type END';

function TpgnOracleAdapter.DescribeTable(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT c.column_name AS "Column", ' + TypeExpr + ' AS "Type", ' +
    'CASE WHEN c.nullable = ''N'' THEN ''NO'' ELSE ''YES'' END AS "Nullable", ' +
    'CASE WHEN EXISTS (SELECT 1 FROM all_constraints k JOIN all_cons_columns kc ' +
    'ON kc.owner = k.owner AND kc.constraint_name = k.constraint_name ' +
    'WHERE k.owner = c.owner AND k.table_name = c.table_name AND k.constraint_type = ''P'' ' +
    'AND kc.column_name = c.column_name) THEN ''PRI'' END AS "Key", ' +
    'c.data_default AS "Default", m.comments AS "Comment" ' +
    'FROM all_tab_columns c LEFT JOIN all_col_comments m ON m.owner = c.owner ' +
    'AND m.table_name = c.table_name AND m.column_name = c.column_name ' +
    'WHERE c.owner = ' + L(ADatabase) + ' AND c.table_name = ' + L(ATable) + ' ORDER BY c.column_id');
end;

function TpgnOracleAdapter.DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT i.index_name AS "Index", ' +
    'CASE WHEN EXISTS (SELECT 1 FROM all_constraints k WHERE k.owner = i.table_owner ' +
    'AND k.index_name = i.index_name AND k.constraint_type = ''P'') THEN ''yes'' END AS "Primary", ' +
    'CASE WHEN i.uniqueness = ''UNIQUE'' THEN ''yes'' ELSE ''no'' END AS "Unique", ' +
    '(SELECT LISTAGG(ic.column_name, '', '') WITHIN GROUP (ORDER BY ic.column_position) ' +
    'FROM all_ind_columns ic WHERE ic.index_owner = i.owner AND ic.index_name = i.index_name) ' +
    'AS "Definition" FROM all_indexes i WHERE i.table_owner = ' + L(ADatabase) +
    ' AND i.table_name = ' + L(ATable) + ' ORDER BY 2 NULLS LAST, 1');
end;

{ DBMS_METADATA when the login may use it on that schema; otherwise put
  together from the dictionary (columns and primary key). }
function TpgnOracleAdapter.GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string;
var
  Cols, Pk: TpgnStringArray;
  I: Integer;
  T: string;
begin
  case AKind of
    okView:
      begin
        T := 'VIEW';
      end;
    okMatView:
      begin
        T := 'MATERIALIZED_VIEW';
      end;
  else
    begin
      T := 'TABLE';
    end;
  end;
  Result := MetadataDDL(T, ADatabase, AObject);
  if Result <> '' then
  begin
    Exit;
  end;
  if AKind = okView then
  begin
    Result := 'CREATE OR REPLACE VIEW ' + Q2(ADatabase, AObject) + ' AS' + LineEnding +
      TrimRight(MetaValue('SELECT text FROM all_views WHERE owner = ' + L(ADatabase) + ' AND view_name = ' +
      L(AObject)));
    Exit;
  end;
  Cols := MetaStrings('SELECT ''"'' || c.column_name || ''" '' || ' + TypeExpr +
    ' || CASE WHEN c.nullable = ''N'' THEN '' NOT NULL'' END FROM all_tab_columns c ' +
    'WHERE c.owner = ' + L(ADatabase) + ' AND c.table_name = ' + L(AObject) + ' ORDER BY c.column_id');
  if Length(Cols) = 0 then
  begin
    raise Exception.Create(ADatabase + '.' + AObject + ' was not found.');
  end;
  Pk := MetaStrings('SELECT ''"'' || kc.column_name || ''"'' FROM all_constraints k JOIN all_cons_columns kc ' +
    'ON kc.owner = k.owner AND kc.constraint_name = k.constraint_name WHERE k.owner = ' + L(ADatabase) +
    ' AND k.table_name = ' + L(AObject) + ' AND k.constraint_type = ''P'' ORDER BY kc.position');
  Result := '-- put together from the data dictionary (DBMS_METADATA wasn''t available)' + LineEnding +
    'CREATE TABLE ' + Q2(ADatabase, AObject) + ' (';
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
    Result := Result + LineEnding + '  PRIMARY KEY (';
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
  Result := Result + LineEnding + ')';
end;

function TpgnOracleAdapter.ListObjectNames(const ADatabase: string): TpgnStringArray;
begin
  Result := MetaStrings('SELECT DISTINCT object_name FROM all_objects WHERE owner = ' + L(ADatabase) +
    ' AND object_type IN (''TABLE'', ''VIEW'', ''PROCEDURE'', ''FUNCTION'', ''PACKAGE'', ''SEQUENCE'', ' +
    '''SYNONYM'', ''MATERIALIZED VIEW'')');
end;

function TpgnOracleAdapter.SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs;
var
  R: TpgnResultSet;
  I: Integer;
  Pattern: string;
begin
  Result := nil;
  Pattern := '%' + UpperCase(StringReplace(StringReplace(StringReplace(AText, '\', '\\', [rfReplaceAll]),
    '%', '\%', [rfReplaceAll]), '_', '\_', [rfReplaceAll])) + '%';
  R := MetaResult('SELECT owner, object_name, ' +
    'CASE object_type WHEN ''TABLE'' THEN ''Table'' WHEN ''VIEW'' THEN ''View'' ' +
    'WHEN ''MATERIALIZED VIEW'' THEN ''Materialized View'' WHEN ''PROCEDURE'' THEN ''Procedure'' ' +
    'ELSE ''Function'' END FROM all_objects ' +
    'WHERE object_type IN (''TABLE'', ''VIEW'', ''MATERIALIZED VIEW'', ''PROCEDURE'', ''FUNCTION'') ' +
    'AND object_name LIKE ' + L(Pattern) + ' ESCAPE ''\'' AND owner IN ' + NotSystemUser +
    ' AND ROWNUM <= ' + IntToStr(AMax) + ' ORDER BY 2, 1');
  try
    SetLength(Result, R.RowCount);
    for I := 0 to R.RowCount - 1 do
    begin
      Result[I].Database := FDbName;
      Result[I].Schema := R.Rows[I].Values[0];
      Result[I].Name := R.Rows[I].Values[1];
      Result[I].Kind := R.Rows[I].Values[2];
    end;
  finally
    R.Free;
  end;
end;

{ ------------------------------------------------- the Describe window }

const
  DescribeTypes = '(''TABLE'', ''VIEW'', ''MATERIALIZED VIEW'', ''PROCEDURE'', ''FUNCTION'', ''PACKAGE'')';

{ Oracle's name for a kind in Pagona's words. }
function OraKindName(const AType: string): string;
begin
  if AType = 'TABLE' then
  begin
    Result := 'Table';
  end
  else if AType = 'VIEW' then
  begin
    Result := 'View';
  end
  else if AType = 'MATERIALIZED VIEW' then
  begin
    Result := 'Materialized View';
  end
  else if AType = 'PROCEDURE' then
  begin
    Result := 'Procedure';
  end
  else if AType = 'FUNCTION' then
  begin
    Result := 'Function';
  end
  else
  begin
    Result := 'Package';
  end;
end;

{ An unquoted Oracle name is upper case; a quoted one is kept as written. }
function OraName(const S: string): string;
begin
  if (Length(Trim(S)) >= 2) and (Trim(S)[1] = '"') then
  begin
    Result := Unquoted(S);
  end
  else
  begin
    Result := UpperCase(Unquoted(S));
  end;
end;

{ As Oracle resolves a name: your schema (or the one written), then your
  private synonyms, then public synonyms, then any schema you can see. }
function TpgnOracleAdapter.ResolveObject(const AName, ADefault: string; out ARef: TpgnObjectRef;
  out AVia: string): Boolean;
var
  Qual, N, Owner, Target, Kind: string;
  R: TpgnResultSet;
  I, P: Integer;
begin
  Result := False;
  AVia := '';
  ARef.Database := FDbName;
  ARef.Schema := '';
  ARef.Name := '';
  ARef.Kind := '';
  P := LastDelimiter('.', AName);
  if P > 0 then
  begin
    Qual := OraName(Copy(AName, 1, P - 1));
    N := OraName(Copy(AName, P + 1, MaxInt));
  end
  else
  begin
    Qual := '';
    N := OraName(AName);
  end;
  if N = '' then
  begin
    Exit;
  end;
  if Qual = '' then
  begin
    Qual := UpperCase(ADefault);
  end;
  // 1 the schema's own object, 2 its private synonym, 3 a public synonym,
  // 4 the object in any schema (a materialized view also shows as a TABLE:
  // the MATERIALIZED VIEW row wins)
  R := MetaResult(
    'SELECT owner, object_name, object_type, 1 AS pri, NULL AS syn FROM all_objects ' +
    'WHERE owner = ' + L(Qual) + ' AND object_name = ' + L(N) + ' AND object_type IN ' + DescribeTypes +
    ' UNION ALL SELECT table_owner, table_name, NULL, 2, synonym_name FROM all_synonyms ' +
    'WHERE owner = ' + L(Qual) + ' AND synonym_name = ' + L(N) +
    ' UNION ALL SELECT table_owner, table_name, NULL, 3, synonym_name FROM all_synonyms ' +
    'WHERE owner = ''PUBLIC'' AND synonym_name = ' + L(N) +
    ' UNION ALL SELECT owner, object_name, object_type, 4, NULL FROM all_objects ' +
    'WHERE object_name = ' + L(N) + ' AND object_type IN ' + DescribeTypes +
    ' ORDER BY 4, 1');
  try
    for I := 0 to R.RowCount - 1 do
    begin
      Owner := R.Rows[I].Values[0];
      Target := R.Rows[I].Values[1];
      Kind := R.Rows[I].Values[2];
      if R.Rows[I].Values[3] = '2' then
      begin
        AVia := 'via synonym ' + Qual + '.' + R.Rows[I].Values[4];
      end
      else if R.Rows[I].Values[3] = '3' then
      begin
        AVia := 'via public synonym ' + R.Rows[I].Values[4];
      end
      else
      begin
        AVia := '';
      end;
      if R.Rows[I].Nulls[2] or (Kind = '') then
      begin
        // a synonym: what it points at
        Kind := MetaValue('SELECT object_type FROM (SELECT object_type FROM all_objects ' +
          'WHERE owner = ' + L(Owner) + ' AND object_name = ' + L(Target) + ' AND object_type IN ' +
          DescribeTypes + ' ORDER BY CASE object_type WHEN ''MATERIALIZED VIEW'' THEN 0 ELSE 1 END) ' +
          'WHERE ROWNUM = 1');
        if Kind = '' then
        begin
          Continue;   // points at something we can't see (or a remote object)
        end;
      end
      else if (Kind = 'TABLE') and (MetaValue('SELECT COUNT(*) FROM all_mviews WHERE owner = ' + L(Owner) +
        ' AND mview_name = ' + L(Target)) <> '0') then
      begin
        Kind := 'MATERIALIZED VIEW';
      end;
      ARef.Schema := Owner;
      ARef.Name := Target;
      ARef.Kind := OraKindName(Kind);
      Result := True;
      Exit;
    end;
  finally
    R.Free;
  end;
end;

function TpgnOracleAdapter.DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet;
begin
  // NOT NULL checks Oracle names itself are left out: Columns shows them
  Result := MetaResult(
    'SELECT c.constraint_name AS "Constraint", ' +
    'DECODE(c.constraint_type, ''P'', ''Primary key'', ''U'', ''Unique'', ''R'', ''Foreign key'', ' +
    '''C'', ''Check'', c.constraint_type) AS "Type", ' +
    'LISTAGG(cc.column_name, '', '') WITHIN GROUP (ORDER BY cc.position) AS "Columns", ' +
    'CASE WHEN c.constraint_type = ''R'' THEN r.owner || ''.'' || r.table_name END AS "References", ' +
    'c.status AS "Status" ' +
    'FROM all_constraints c ' +
    'LEFT JOIN all_cons_columns cc ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name ' +
    'LEFT JOIN all_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name ' +
    'WHERE c.owner = ' + L(ADatabase) + ' AND c.table_name = ' + L(ATable) +
    ' AND c.constraint_type IN (''P'', ''U'', ''R'', ''C'') ' +
    'AND NOT (c.constraint_type = ''C'' AND c.generated = ''GENERATED NAME'') ' +
    'GROUP BY c.constraint_name, c.constraint_type, r.owner, r.table_name, c.status ' +
    'ORDER BY DECODE(c.constraint_type, ''P'', 1, ''U'', 2, ''R'', 3, 4), 1');
end;

function TpgnOracleAdapter.DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT owner AS "Owner", name AS "Name", INITCAP(type) AS "Type" FROM all_dependencies ' +
    'WHERE referenced_owner = ' + L(ADatabase) + ' AND referenced_name = ' + L(AName) +
    ' AND NOT (owner = referenced_owner AND name = referenced_name) ' +
    'UNION SELECT c.owner, c.table_name, ''Table (foreign key)'' FROM all_constraints c ' +
    'JOIN all_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name ' +
    'WHERE c.constraint_type = ''R'' AND r.owner = ' + L(ADatabase) + ' AND r.table_name = ' + L(AName) +
    ' ORDER BY 3, 1, 2');
end;

function TpgnOracleAdapter.ObjectScript(const ADatabase, AName, AKind: string): string;
var
  Body: string;
begin
  Result := '';
  if AKind = 'Package' then
  begin
    Result := SourceText(ADatabase, AName, 'PACKAGE');
    if Result <> '' then
    begin
      Result := 'CREATE OR REPLACE ' + Result + LineEnding + '/';
    end;
    Body := SourceText(ADatabase, AName, 'PACKAGE BODY');
    if Body <> '' then
    begin
      Result := Result + LineEnding + LineEnding + 'CREATE OR REPLACE ' + Body + LineEnding + '/';
    end;
  end;
end;

function TpgnOracleAdapter.SelectTopSQL(const AQualifiedName: string; ARows: Integer): string;
begin
  Result := 'SELECT * FROM ' + AQualifiedName + ' FETCH FIRST ' + IntToStr(ARows) + ' ROWS ONLY';
end;

{ ------------------------------------------- procedures, functions, triggers }

function ObjectType(AKind: TpgnRoutineKind): string;
begin
  Result := RoutineWord[AKind];   // PROCEDURE, FUNCTION, TRIGGER
end;

function TpgnOracleAdapter.ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray;
begin
  Result := MetaStrings('SELECT object_name FROM all_objects WHERE owner = ' + L(ADatabase) +
    ' AND object_type = ' + L(ObjectType(AKind)) + ' ORDER BY 1');
end;

function TpgnOracleAdapter.GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := SourceText(ADatabase, AName, ObjectType(AKind));
  if Result <> '' then
  begin
    Result := 'CREATE OR REPLACE ' + Result;
  end;
end;

function TpgnOracleAdapter.RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean;
begin
  Result := MetaValue('SELECT COUNT(*) FROM all_objects WHERE owner = ' + L(ADatabase) +
    ' AND object_name = ' + L(AName) + ' AND object_type = ' + L(ObjectType(AKind))) <> '0';
end;

function TpgnOracleAdapter.DescribeParameters(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT CASE WHEN a.argument_name IS NULL AND a.position = 0 THEN ''RETURNS'' ' +
    'WHEN a.in_out = ''IN/OUT'' THEN ''INOUT'' ELSE a.in_out END AS "Mode", ' +
    'NVL(a.argument_name, '' '') AS "Parameter", ' +
    'a.data_type || CASE WHEN a.type_name IS NOT NULL THEN '' '' || a.type_owner || ''.'' || a.type_name END ' +
    'AS "Type" FROM all_arguments a WHERE a.owner = ' + L(ADatabase) + ' AND a.object_name = ' + L(AName) +
    ' AND a.package_name IS NULL AND a.data_level = 0 AND (a.argument_name IS NOT NULL OR a.position = 0) ' +
    'AND a.data_type IS NOT NULL ORDER BY a.position');
end;

function TpgnOracleAdapter.DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT trigger_name AS "Trigger", trigger_type AS "Timing", triggering_event AS "Event", ' +
    'CASE WHEN status = ''ENABLED'' THEN ''yes'' ELSE ''no'' END AS "Enabled" FROM all_triggers ' +
    'WHERE table_owner = ' + L(ADatabase) + ' AND table_name = ' + L(ATable) + ' ORDER BY 1');
end;

function TpgnOracleAdapter.DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT grantee AS "Grantee", LISTAGG(privilege || CASE WHEN grantable = ''YES'' THEN '' (can grant)'' END, ' +
    ''', '') WITHIN GROUP (ORDER BY privilege) AS "Privileges", grantor AS "Granted by" ' +
    'FROM all_tab_privs WHERE table_schema = ' + L(ADatabase) + ' AND table_name = ' + L(AName) +
    ' GROUP BY grantee, grantor ORDER BY 1');
end;

{ CREATE OR REPLACE always replaces in Oracle, even code that doesn't
  compile; the object is then INVALID. The errors are read from
  ALL_ERRORS and reported with their lines. }
function TpgnOracleAdapter.SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
  const ASQL: string; ALog: TStrings): string;
var
  St, Len: Integer;
  NewName, Kw, Raw, SQL, Errors: string;
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
  Raw := Copy(ASQL, St, Len);
  if Pos('"', Raw) = 0 then
  begin
    NewName := UpperCase(NewName);
  end;
  SQL := OracleStatement(ASQL);
  // unqualified names in the statement land in this schema
  MetaExec('ALTER SESSION SET CURRENT_SCHEMA = ' + QuoteIdent(ADatabase));
  try
    try
      MetaExec(SQL);
    except
      on E: Exception do
      begin
        // ORA-24344: saved, but with compilation errors
        if Pos('24344', E.Message) = 0 then
        begin
          raise Exception.Create('Nothing was changed: ' + E.Message);
        end;
      end;
    end;
    Errors := CompileErrors(FMeta, ADatabase, NewName, RoutineWord[AKind]);
  finally
    MetaExec('ALTER SESSION SET CURRENT_SCHEMA = ' + QuoteIdent(FInfo.User));
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
  if Errors <> '' then
  begin
    raise Exception.Create('Saved, but it doesn''t compile: ' + ADatabase + '.' + NewName +
      ' is now INVALID.' + LineEnding + Errors);
  end;
end;

{ --------------------------------------------- SQL for the forms and menus }

function TpgnOracleAdapter.RoutineTarget(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := Q2(ADatabase, AName);
end;

function TpgnOracleAdapter.DropRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := 'DROP ' + RoutineWord[AKind] + ' ' + Q2(ADatabase, AName);
end;

function TpgnOracleAdapter.DescribeSQL(const ADatabase, ATable: string): string;
begin
  Result := 'SELECT c.column_name AS "Column", ' + TypeExpr + ' AS "Type", ' +
    'c.nullable AS "Nullable", c.data_default AS "Default" FROM all_tab_columns c ' +
    'WHERE c.owner = ' + L(ADatabase) + ' AND c.table_name = ' + L(ATable) + ' ORDER BY c.column_id';
end;

function OraParamList(const AParams: TpgnParamDefs): string;
var
  I: Integer;
  Mode: string;
begin
  Result := '';
  if Length(AParams) = 0 then
  begin
    Exit;
  end;
  for I := 0 to High(AParams) do
  begin
    Mode := UpperCase(AParams[I].Mode);
    if Mode = 'INOUT' then
    begin
      Mode := 'IN OUT';
    end;
    if Mode = '' then
    begin
      Mode := 'IN';
    end;
    if I > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + LineEnding + '  ' + AParams[I].Name + ' ' + Mode + ' ' + AParams[I].DataType;
  end;
  Result := ' (' + Result + LineEnding + ')';
end;

function TpgnOracleAdapter.NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs; const AReturns: string): string;
begin
  if AKind = rkProcedure then
  begin
    Result := 'CREATE OR REPLACE PROCEDURE ' + QuoteIdent(UpperCase(AName)) + OraParamList(AParams) +
      LineEnding + 'AS' + LineEnding + 'BEGIN' + LineEnding + '  NULL;  -- your code here' + LineEnding +
      'END ' + AName + ';';
  end
  else
  begin
    Result := 'CREATE OR REPLACE FUNCTION ' + QuoteIdent(UpperCase(AName)) + OraParamList(AParams) +
      LineEnding + 'RETURN ' + AReturns + LineEnding + 'AS' + LineEnding + 'BEGIN' + LineEnding +
      '  -- your code here' + LineEnding + '  RETURN NULL;' + LineEnding + 'END ' + AName + ';';
  end;
end;

function TpgnOracleAdapter.NewTriggerSQL(const ADatabase, ATable: string): string;
begin
  Result := 'CREATE OR REPLACE TRIGGER ' + Q2(ADatabase, Copy(ATable, 1, 24) + '_BIU') + LineEnding +
    'BEFORE INSERT OR UPDATE ON ' + Q2(ADatabase, ATable) + LineEnding +
    '-- timing: BEFORE, AFTER or INSTEAD OF;  events: INSERT, UPDATE [OF column], DELETE' + LineEnding +
    'FOR EACH ROW' + LineEnding + 'BEGIN' + LineEnding + '  NULL;  -- :NEW.column := ...;' + LineEnding +
    'END;';
end;

{ A procedure runs in an anonymous block; OUT parameters are declared and
  printed with DBMS_OUTPUT (the DBMS Output results show them). A
  function is SELECTed FROM dual. }
function TpgnOracleAdapter.ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs): string;
var
  I: Integer;
  Args, Decl, Prints, Mode, T, V: string;
begin
  Args := '';
  Decl := '';
  Prints := '';
  for I := 0 to High(AParams) do
  begin
    Mode := UpperCase(AParams[I].Mode);
    if Mode = 'RETURNS' then
    begin
      Continue;
    end;
    if Args <> '' then
    begin
      Args := Args + ', ';
    end;
    if (Mode = 'OUT') or (Mode = 'INOUT') or (Mode = 'IN/OUT') then
    begin
      V := 'v_' + Copy(AParams[I].Name, 1, 26);
      T := UpperCase(AParams[I].DataType);
      if (Pos('CHAR', T) > 0) and (Pos('(', T) = 0) then
      begin
        T := T + '(32767)';
      end;
      Decl := Decl + '  ' + V + ' ' + T;
      if Mode <> 'OUT' then
      begin
        Decl := Decl + ' := ' + AParams[I].Value;
      end;
      Decl := Decl + ';' + LineEnding;
      Prints := Prints + '  DBMS_OUTPUT.PUT_LINE(''' + AParams[I].Name + ' = '' || ' + V + ');' + LineEnding;
      Args := Args + V;
    end
    else
    begin
      Args := Args + AParams[I].Value;
    end;
  end;
  if AKind = rkFunction then
  begin
    Result := 'SELECT ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args + ') AS result FROM dual;';
  end
  else
  begin
    Result := '';
    if Decl <> '' then
    begin
      Result := 'DECLARE' + LineEnding + Decl;
    end;
    Result := Result + 'BEGIN' + LineEnding + '  ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args +
      ');' + LineEnding + Prints + 'END;' + LineEnding + '/';
  end;
end;

function TpgnOracleAdapter.GrantRights(const AObjectWord: string): TpgnStringArray;
begin
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    Result := Strings(['EXECUTE', 'DEBUG']);
  end
  else if AObjectWord = 'VIEW' then
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE']);
  end
  else
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'ALTER', 'INDEX', 'REFERENCES']);
  end;
end;

function TpgnOracleAdapter.GranteeHint: string;
begin
  Result := 'To (a user or role, e.g. BAN_DEFAULT_M, or PUBLIC for everyone)';
end;

function TpgnOracleAdapter.GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
  AWithGrantOption: Boolean): string;
var
  Who: string;
begin
  Who := Trim(AGrantee);
  if SameText(Who, 'PUBLIC') then
  begin
    Who := 'PUBLIC';
  end
  else
  begin
    Who := QuoteIdent(UpperCase(Who));
  end;
  Result := 'GRANT ' + ARights + ' ON ' + Q2(ADatabase, AName) + ' TO ' + Who;
  if AWithGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
  Result := Result + ';';
end;

{ ------------------------------------------------------------------- DBA }

const
  SessionCols =
    's.sid || '','' || s.serial# AS "Session", s.username AS "User", s.machine AS "Machine", ' +
    's.program AS "Program", s.schemaname AS "Database", ' +
    'LOWER(s.status) || CASE WHEN s.blocking_session IS NOT NULL THEN '' / waiting for a lock'' END AS "State", ' +
    'TO_CHAR(TRUNC(s.last_call_et / 3600), ''FM00'') || '':'' || ' +
    'TO_CHAR(TRUNC(MOD(s.last_call_et, 3600) / 60), ''FM00'') || '':'' || ' +
    'TO_CHAR(MOD(s.last_call_et, 60), ''FM00'') AS "Time", ' +
    '(SELECT SUBSTR(q.sql_text, 1, 200) FROM v$sql q WHERE q.sql_id = s.sql_id AND ROWNUM = 1) AS "Statement"';

function TpgnOracleAdapter.ListSessions: TpgnResultSet;
var
  Mine: string;
begin
  Mine := '-1';
  if FSid <> '' then
  begin
    Mine := FSid;
  end;
  try
    Result := MetaResult('SELECT ' + SessionCols + ', ' +
      'CASE WHEN s.sid IN (' + Mine + ', SYS_CONTEXT(''USERENV'', ''SID'')) THEN ''this tab'' END AS "Note" ' +
      'FROM v$session s WHERE s.type = ''USER'' ' +
      'ORDER BY CASE WHEN s.status = ''ACTIVE'' THEN 0 ELSE 1 END, s.last_call_et DESC');
  except
    on E: Exception do
    begin
      raise Exception.Create('Could not read V$SESSION; this needs SELECT on it (or the ' +
        'SELECT_CATALOG_ROLE role). (' + E.Message + ')');
    end;
  end;
end;

function TpgnOracleAdapter.ListLocks: TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT w.sid || '','' || w.serial# AS "Waiting", w.username AS "Waiting user", ' +
    'TO_CHAR(TRUNC(w.seconds_in_wait / 3600), ''FM00'') || '':'' || ' +
    'TO_CHAR(TRUNC(MOD(w.seconds_in_wait, 3600) / 60), ''FM00'') || '':'' || ' +
    'TO_CHAR(MOD(w.seconds_in_wait, 60), ''FM00'') AS "Waiting for", ' +
    'b.sid || '','' || b.serial# AS "Blocked by", b.username AS "Blocker user", LOWER(b.status) AS "Blocker state", ' +
    'TO_CHAR(TRUNC(b.last_call_et / 3600), ''FM00'') || '':'' || ' +
    'TO_CHAR(TRUNC(MOD(b.last_call_et, 3600) / 60), ''FM00'') || '':'' || ' +
    'TO_CHAR(MOD(b.last_call_et, 60), ''FM00'') AS "Blocker time", ' +
    'CASE WHEN b.blocking_session IS NULL THEN ''yes'' END AS "Head of chain", ' +
    '(SELECT o.owner || ''.'' || o.object_name FROM all_objects o WHERE o.object_id = w.row_wait_obj#) AS "Object", ' +
    '(SELECT SUBSTR(q.sql_text, 1, 200) FROM v$sql q WHERE q.sql_id = w.sql_id AND ROWNUM = 1) AS "Waiting statement", ' +
    '(SELECT SUBSTR(q.sql_text, 1, 200) FROM v$sql q WHERE q.sql_id = NVL(b.sql_id, b.prev_sql_id) ' +
    'AND ROWNUM = 1) AS "Blocker statement" ' +
    'FROM v$session w JOIN v$session b ON b.sid = w.blocking_session ' +
    'WHERE w.blocking_session IS NOT NULL ORDER BY w.seconds_in_wait DESC');
end;

function TpgnOracleAdapter.SessionStatement(const ASession: string): string;
var
  Sid: string;
begin
  Sid := SessionId(ASession);
  Result := MetaValue('SELECT q.sql_fulltext FROM v$session s JOIN v$sql q ' +
    'ON q.sql_id = NVL(s.sql_id, s.prev_sql_id) WHERE s.sid = ' + Copy(Sid, 1, Pos(',', Sid) - 1) +
    ' AND ROWNUM = 1');
end;

{ Oracle 18c on; needs ALTER SYSTEM. }
function TpgnOracleAdapter.CancelSession(const ASession: string): string;
begin
  Result := 'ALTER SYSTEM CANCEL SQL ''' + SessionId(ASession) + '''';
  MetaExec(Result);
end;

function TpgnOracleAdapter.KillSession(const ASession: string): string;
begin
  Result := 'ALTER SYSTEM KILL SESSION ''' + SessionId(ASession) + ''' IMMEDIATE';
  MetaExec(Result);
end;

function TpgnOracleAdapter.MissingRight(const AAction: string): string;
begin
  Result := '';
  if (AAction = 'kill') and not HasPriv('ALTER SYSTEM') then
  begin
    Result := 'Needs the ALTER SYSTEM privilege (Oracle asks for it even for your own sessions)';
  end
  else if (AAction = 'accounts') and not HasPriv('ALTER USER') and not HasPriv('CREATE USER') then
  begin
    Result := 'Needs the CREATE USER / ALTER USER privileges to change accounts';
  end;
end;

procedure TpgnOracleAdapter.RunAdmin(const ASQL: string);
begin
  MetaExec(OracleStatement(ASQL));
end;

{ ------------------------------------------------------ users and roles }

function TpgnOracleAdapter.HasRoles: Boolean;
begin
  Result := True;
end;

function TpgnOracleAdapter.ListAccounts(ASystem: Boolean): TpgnAccounts;
var
  R: TpgnResultSet;
  I: Integer;
  W: string;
begin
  Result := nil;
  W := '';
  if not ASystem then
  begin
    W := ' WHERE m = ''N''';
  end;
  try
    R := MetaResult('SELECT n, r, m FROM (SELECT username n, ''0'' r, oracle_maintained m FROM dba_users ' +
      'UNION ALL SELECT role, ''1'', oracle_maintained FROM dba_roles)' + W + ' ORDER BY 1');
  except
    on E: Exception do
    begin
      // no DBA views: the users any login can list
      R := MetaResult('SELECT username, ''0'', oracle_maintained FROM all_users' +
        StringReplace(W, ' m ', ' oracle_maintained ', []) + ' ORDER BY 1');
    end;
  end;
  try
    SetLength(Result, R.RowCount);
    for I := 0 to R.RowCount - 1 do
    begin
      Result[I] := Default(TpgnAccount);
      Result[I].Name := R.Rows[I].Values[0];
      Result[I].IsRole := R.Rows[I].Values[1] = '1';
      Result[I].IsSystem := R.Rows[I].Values[2] = 'Y';
    end;
  finally
    R.Free;
  end;
end;

function OraAttr(const AKey, ACaption, AHint: string; AKind: TpgnAttrKind; const AValue: string): TpgnAccountAttr;
begin
  Result := Default(TpgnAccountAttr);
  Result.Key := AKey;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Kind := AKind;
  Result.Value := AValue;
end;

function TpgnOracleAdapter.AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs;
var
  R: TpgnResultSet;
  Status: string;

  procedure Add(const AAttr: TpgnAccountAttr);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AAttr;
  end;

begin
  Result := nil;
  if AAccount.IsRole then
  begin
    Exit;
  end;
  R := MetaResult('SELECT account_status, profile, default_tablespace, temporary_tablespace, ' +
    'TO_CHAR(expiry_date, ''YYYY-MM-DD'') FROM dba_users WHERE username = ' + L(AAccount.Name));
  try
    if R.RowCount = 0 then
    begin
      raise Exception.Create('User ' + AAccount.Name + ' no longer exists.');
    end;
    Status := UpperCase(R.Rows[0].Values[0]);
    if Pos('LOCKED', Status) > 0 then
    begin
      Add(OraAttr('locked', 'Account locked', 'Status: ' + LowerCase(Status), akBool, '1'));
    end
    else
    begin
      Add(OraAttr('locked', 'Account locked', 'Status: ' + LowerCase(Status), akBool, '0'));
    end;
    if Pos('EXPIRED', Status) > 0 then
    begin
      Add(OraAttr('expired', 'Must change password at next login', 'Cleared when a new password is set',
        akBool, '1'));
      Result[High(Result)].ReadOnly := True;
    end
    else
    begin
      Add(OraAttr('expired', 'Must change password at next login', 'Password expires ' +
        R.Rows[0].Values[4], akBool, '0'));
    end;
    Add(OraAttr('profile', 'Profile', 'Password and resource rules', akChoice, R.Rows[0].Values[1]));
    Result[High(Result)].Choices := ListFolder('', 'Profiles');
    Add(OraAttr('deftbs', 'Default tablespace', '', akChoice, R.Rows[0].Values[2]));
    Result[High(Result)].Choices := MetaStrings('SELECT tablespace_name FROM dba_tablespaces ' +
      'WHERE contents = ''PERMANENT'' ORDER BY 1');
    Add(OraAttr('temptbs', 'Temporary tablespace', '', akChoice, R.Rows[0].Values[3]));
    Result[High(Result)].Choices := MetaStrings('SELECT tablespace_name FROM dba_tablespaces ' +
      'WHERE contents = ''TEMPORARY'' ORDER BY 1');
  finally
    R.Free;
  end;
end;

function TpgnOracleAdapter.AlterAccountSQL(const AAccount: TpgnAccount;
  const AOld, ANew: TpgnAccountAttrs): TpgnStringArray;
var
  I: Integer;
  K, V, A: string;

  procedure Add(const AClause: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'ALTER USER ' + A + ' ' + AClause;
  end;

begin
  Result := nil;
  A := QuoteIdent(AAccount.Name);
  for I := 0 to High(ANew) do
  begin
    if (I > High(AOld)) or (AOld[I].Value = ANew[I].Value) then
    begin
      Continue;
    end;
    K := ANew[I].Key;
    V := Trim(ANew[I].Value);
    if K = 'locked' then
    begin
      if V = '1' then
      begin
        Add('ACCOUNT LOCK');
      end
      else
      begin
        Add('ACCOUNT UNLOCK');
      end;
    end
    else if (K = 'expired') and (V = '1') then
    begin
      Add('PASSWORD EXPIRE');
    end
    else if (K = 'profile') and (V <> '') then
    begin
      Add('PROFILE ' + QuoteIdent(V));
    end
    else if (K = 'deftbs') and (V <> '') then
    begin
      Add('DEFAULT TABLESPACE ' + QuoteIdent(V));
    end
    else if (K = 'temptbs') and (V <> '') then
    begin
      Add('TEMPORARY TABLESPACE ' + QuoteIdent(V));
    end;
  end;
end;

{ Oracle passwords go in double quotes (any characters, case kept). A new
  user also gets CREATE SESSION, without which it can't log in. }
function TpgnOracleAdapter.CreateAccountSQL(const AAccount: TpgnAccount;
  const APassword: string): TpgnStringArray;
begin
  Result := nil;
  if AAccount.IsRole then
  begin
    SetLength(Result, 1);
    Result[0] := 'CREATE ROLE ' + QuoteIdent(UpperCase(AAccount.Name));
  end
  else
  begin
    SetLength(Result, 2);
    Result[0] := 'CREATE USER ' + QuoteIdent(UpperCase(AAccount.Name)) + ' IDENTIFIED BY "' +
      StringReplace(APassword, '"', '', [rfReplaceAll]) + '"';
    Result[1] := 'GRANT CREATE SESSION TO ' + QuoteIdent(UpperCase(AAccount.Name));
  end;
end;

function TpgnOracleAdapter.PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string;
begin
  Result := 'ALTER USER ' + QuoteIdent(AAccount.Name) + ' IDENTIFIED BY "' +
    StringReplace(APassword, '"', '', [rfReplaceAll]) + '"';
end;

function TpgnOracleAdapter.AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT granted_role AS "Role", CASE WHEN admin_option = ''YES'' THEN ''yes'' END ' +
    'AS "Can pass on", CASE WHEN default_role = ''YES'' THEN ''yes'' END AS "Default" FROM dba_role_privs ' +
    'WHERE grantee = ' + L(AAccount.Name) + ' ORDER BY 1');
end;

function TpgnOracleAdapter.AccountMembers(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT grantee AS "Member", CASE WHEN admin_option = ''YES'' THEN ''yes'' END ' +
    'AS "Can pass on" FROM dba_role_privs WHERE granted_role = ' + L(AAccount.Name) + ' ORDER BY 1');
end;

function TpgnOracleAdapter.GrantRoleSQL(const ARole, AMember: TpgnAccount; AAdmin: Boolean): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := 'GRANT ' + QuoteIdent(ARole.Name) + ' TO ' + QuoteIdent(AMember.Name);
  if AAdmin then
  begin
    Result[0] := Result[0] + ' WITH ADMIN OPTION';
  end;
end;

function TpgnOracleAdapter.RevokeRoleSQL(const ARole, AMember: TpgnAccount): string;
begin
  Result := 'REVOKE ' + QuoteIdent(ARole.Name) + ' FROM ' + QuoteIdent(AMember.Name);
end;

{ Object grants, then system privileges (Object "(system)"). }
function TpgnOracleAdapter.AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT * FROM (' +
    'SELECT p.owner || ''.'' || p.table_name AS "Object", LOWER(NVL(p.type, ''object'')) AS "Type", ' +
    'p.privilege AS "Privilege", CASE WHEN p.grantable = ''YES'' THEN ''yes'' END AS "Can grant", ' +
    'p.grantor AS "Granted by" FROM dba_tab_privs p WHERE p.grantee = ' + L(AAccount.Name) +
    ' UNION ALL SELECT ''(system)'', ''system'', s.privilege, CASE WHEN s.admin_option = ''YES'' THEN ''yes'' END, ' +
    'NULL FROM dba_sys_privs s WHERE s.grantee = ' + L(AAccount.Name) + ') ORDER BY 2, 1, 3');
end;

function OraObject(const AObject: string): string;
var
  P: Integer;
begin
  // OWNER.NAME as shown: quote the parts only when they need it
  P := Pos('.', AObject);
  if P = 0 then
  begin
    Result := AObject;
  end
  else
  begin
    Result := '"' + Copy(AObject, 1, P - 1) + '"."' + Copy(AObject, P + 1, MaxInt) + '"';
  end;
end;

function TpgnOracleAdapter.RevokePrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string): string;
begin
  if AType = 'system' then
  begin
    Result := 'REVOKE ' + APrivilege + ' FROM ' + QuoteIdent(AAccount.Name);
  end
  else
  begin
    Result := 'REVOKE ' + APrivilege + ' ON ' + OraObject(AObject) + ' FROM ' + QuoteIdent(AAccount.Name);
  end;
end;

function TpgnOracleAdapter.GrantPrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string; AGrantOption: Boolean): string;
var
  Who: string;
begin
  if SameText(AAccount.Name, 'PUBLIC') then
  begin
    Who := 'PUBLIC';
  end
  else
  begin
    Who := QuoteIdent(AAccount.Name);
  end;
  if AType = 'system' then
  begin
    Result := 'GRANT ' + APrivilege + ' TO ' + Who;
    if AGrantOption then
    begin
      Result := Result + ' WITH ADMIN OPTION';
    end;
  end
  else
  begin
    Result := 'GRANT ' + APrivilege + ' ON ' + OraObject(AObject) + ' TO ' + Who;
    if AGrantOption then
    begin
      Result := Result + ' WITH GRANT OPTION';
    end;
  end;
end;

{ DBMS_METADATA's user DDL with the password hash taken out, then its role,
  system and object grants. }
function TpgnOracleAdapter.AccountDDL(const AAccount: TpgnAccount): string;
var
  S, Part: string;
  P1, P2: Integer;
  Kinds: array[0..2] of string = ('ROLE_GRANT', 'SYSTEM_GRANT', 'OBJECT_GRANT');
  I: Integer;
begin
  if AAccount.IsRole then
  begin
    S := MetadataDDL('ROLE', '', AAccount.Name);
  end
  else
  begin
    S := MetadataDDL('USER', '', AAccount.Name);
  end;
  // IDENTIFIED BY VALUES 'S:...;T:...' is the password hash
  P1 := Pos('IDENTIFIED BY VALUES ''', S);
  if P1 > 0 then
  begin
    P2 := P1 + Length('IDENTIFIED BY VALUES ''');
    while (P2 <= Length(S)) and (S[P2] <> '''') do
    begin
      Inc(P2);
    end;
    S := Copy(S, 1, P1 - 1) + 'IDENTIFIED BY "****"' + Copy(S, P2 + 1, MaxInt);
  end;
  Result := '-- ' + AAccount.Name + ' (the password is not included)' + LineEnding + S + ';' + LineEnding;
  for I := 0 to High(Kinds) do
  begin
    try
      Part := Trim(MetaValue('SELECT DBMS_METADATA.GET_GRANTED_DDL(' + L(Kinds[I]) + ', ' +
        L(AAccount.Name) + ') FROM dual'));
    except
      on E: Exception do
      begin
        Part := '';   // ORA-31608: none of this kind
      end;
    end;
    if Part <> '' then
    begin
      Result := Result + LineEnding + Part + ';' + LineEnding;
    end;
  end;
end;

function TpgnOracleAdapter.AccountOwns(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := MetaResult('SELECT object_name AS "Object", LOWER(object_type) AS "Type", ' +
    'owner AS "Where" FROM all_objects WHERE owner = ' + L(AAccount.Name) +
    ' AND object_type NOT IN (''INDEX'', ''LOB'', ''TABLE PARTITION'', ''INDEX PARTITION'') ' +
    'AND ROWNUM <= 1000 ORDER BY 2, 1');
end;

function TpgnOracleAdapter.DropOwnedChoice: Boolean;
begin
  Result := True;
end;

{ A user that owns anything can only go with CASCADE, which drops what it
  owns too. }
function TpgnOracleAdapter.DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
  ADropOwned: Boolean): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  if AAccount.IsRole then
  begin
    Result[0] := 'DROP ROLE ' + QuoteIdent(AAccount.Name);
  end
  else if ADropOwned then
  begin
    Result[0] := 'DROP USER ' + QuoteIdent(AAccount.Name) + ' CASCADE';
  end
  else
  begin
    Result[0] := 'DROP USER ' + QuoteIdent(AAccount.Name);
  end;
end;

{ ------------------------------------------------------ grants by object }

function TpgnOracleAdapter.GrantTargets: TpgnStringArray;
begin
  Result := Strings(['table', 'sequence', 'package', 'procedure', 'function', 'type']);
end;

function TpgnOracleAdapter.GrantTargetCaption(const AKind: string): string;
begin
  if AKind = 'table' then
  begin
    Result := 'A table or view';
  end
  else if AKind = 'sequence' then
  begin
    Result := 'A sequence';
  end
  else if AKind = 'package' then
  begin
    Result := 'A package';
  end
  else if AKind = 'procedure' then
  begin
    Result := 'A procedure';
  end
  else if AKind = 'function' then
  begin
    Result := 'A function';
  end
  else
  begin
    Result := 'A type';
  end;
end;

function TpgnOracleAdapter.GrantContainerCaption(const AKind: string): string;
begin
  Result := 'Schema';
end;

function TpgnOracleAdapter.GrantContainers(const AKind: string): TpgnStringArray;
begin
  Result := ListSchemas(False);
end;

function TpgnOracleAdapter.GrantNeedsObject(const AKind: string): Boolean;
begin
  Result := True;
end;

function TpgnOracleAdapter.GrantObjects(const AKind, AContainer: string): TpgnStringArray;
begin
  if AKind = 'table' then
  begin
    Result := MetaStrings('SELECT object_name FROM all_objects WHERE owner = ' + L(AContainer) +
      ' AND object_type IN (''TABLE'', ''VIEW'', ''MATERIALIZED VIEW'') ORDER BY 1');
  end
  else
  begin
    Result := MetaStrings('SELECT object_name FROM all_objects WHERE owner = ' + L(AContainer) +
      ' AND object_type = ' + L(UpperCase(AKind)) + ' ORDER BY 1');
  end;
end;

function TpgnOracleAdapter.GrantObjectText(const AKind, AContainer, AName: string): string;
begin
  Result := AContainer + '.' + AName;
end;

function TpgnOracleAdapter.GrantPrivileges(const AKind: string): TpgnStringArray;
begin
  if AKind = 'table' then
  begin
    Result := Strings(['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'ALTER', 'INDEX', 'REFERENCES', 'READ']);
  end
  else if AKind = 'sequence' then
  begin
    Result := Strings(['SELECT', 'ALTER']);
  end
  else if AKind = 'type' then
  begin
    Result := Strings(['EXECUTE', 'UNDER', 'DEBUG']);
  end
  else
  begin
    Result := Strings(['EXECUTE', 'DEBUG']);
  end;
end;

{ DBA_TAB_PRIVS for the grants; DBA_ROLE_PRIVS walked down (CONNECT BY)
  for who has them through roles. }
function TpgnOracleAdapter.ObjectAccess(const AKind, AContainer, AName: string;
  AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet;
var
  O, SQL: string;
begin
  O := 'p.owner = ' + L(AContainer) + ' AND p.table_name = ' + L(AName);
  SQL := 'SELECT p.grantee AS "Who", '''' AS "Kind", p.privilege AS "Can do", ''direct'' AS "How", ' +
    'CASE WHEN p.grantable = ''YES'' THEN ''yes'' END AS "Can grant" FROM dba_tab_privs p ' +
    'WHERE ' + O + ' AND p.grantee <> ''PUBLIC''';
  if AThroughRoles then
  begin
    SQL := SQL + ' UNION SELECT r.grantee, '''', p.privilege, ''through role '' || ' +
      'CONNECT_BY_ROOT r.granted_role, NULL FROM dba_role_privs r JOIN dba_tab_privs p ' +
      'ON p.grantee = CONNECT_BY_ROOT r.granted_role AND ' + O +
      ' START WITH r.granted_role IN (SELECT grantee FROM dba_tab_privs p WHERE ' + O + ') ' +
      'CONNECT BY PRIOR r.grantee = r.granted_role';
  end;
  if AOwners then
  begin
    SQL := SQL + ' UNION SELECT ' + L(AContainer) + ', ''user'', ''everything'', ''owner'', ''yes'' FROM dual';
  end;
  Result := MetaResult('SELECT * FROM (' + SQL + ') ORDER BY 1, 3, 4');
end;

function TpgnOracleAdapter.PublicAccess(const AKind, AContainer, AName: string): string;
begin
  Result := TryValue('SELECT LISTAGG(privilege, '', '') WITHIN GROUP (ORDER BY privilege) FROM all_tab_privs ' +
    'WHERE table_schema = ' + L(AContainer) + ' AND table_name = ' + L(AName) + ' AND grantee = ''PUBLIC''');
end;

function TpgnOracleAdapter.RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string;
begin
  Result := 'REVOKE ' + APrivileges + ' ON ' + Q2(AContainer, AName) + ' FROM PUBLIC';
end;

{ ------------------------------------------------------------ the session }

function AppendResult(AFirst, AMore: TpgnResultSet): TpgnResultSet;
var
  R: TpgnResultSet;
begin
  Result := AFirst;
  if AMore = nil then
  begin
    Exit;
  end;
  if (AFirst = nil) then
  begin
    Result := AMore;
    Exit;
  end;
  R := AFirst;
  while R.Next <> nil do
  begin
    R := R.Next;
  end;
  R.Next := AMore;
end;

function TpgnOracleAdapter.Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
var
  S, K, W2, Name, Kw, Errors, Id: string;
  P, St, Len: Integer;
  Words: TStringArray;
begin
  S := Trim(ASQL);
  K := FirstKeyword(S);

  // the Explain button sends "EXPLAIN <statement>"
  if (K = 'EXPLAIN') and not SameText(Copy(S, 1, 12), 'EXPLAIN PLAN') then
  begin
    Id := 'PGN' + IntToStr(GetTickCount64 mod 100000000);
    RunStatement(FConn, 'EXPLAIN PLAN SET STATEMENT_ID = ''' + Id + ''' FOR ' +
      OracleStatement(Copy(S, 9, MaxInt)), 0).Free;
    Result := RunStatement(FConn, 'SELECT plan_table_output AS "Plan" FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, ''' +
      Id + ''', ''TYPICAL''))', 0);
    Exit;
  end;

  // SQL*Plus lines that mean something here
  Words := UpperCase(StringReplace(S, ';', ' ', [rfReplaceAll])).Split([' ', #9, #10, #13],
    TStringSplitOptions.ExcludeEmpty);
  W2 := '';
  if Length(Words) > 1 then
  begin
    W2 := Words[1];
  end;
  if (K = 'SET') and (W2 = 'SERVEROUTPUT') then
  begin
    FDbmsOutput := (Length(Words) > 2) and (Words[2] = 'ON');
    if FDbmsOutput then
    begin
      RunStatement(FConn, 'BEGIN DBMS_OUTPUT.ENABLE(NULL); END;', 0).Free;
    end;
    Result := TpgnResultSet.Create;
    Exit;
  end;
  if ((K = 'SET') and (OracleStatement(S) = TrimStatement(S)) and (W2 <> '') and
    (Pos(W2 + ' ', 'ECHO FEEDBACK DEFINE LINESIZE PAGESIZE TIMING VERIFY HEADING TERMOUT TRIMSPOOL ' +
    'SQLBLANKLINES SCAN LONG TAB WRAP ') > 0)) or (K = 'REM') or (K = 'REMARK') or (K = 'SPOOL') or
    (K = 'WHENEVER') or (K = 'DEFINE') or (K = 'UNDEFINE') then
  begin
    Result := TpgnResultSet.Create;   // SQL*Plus settings: nothing to do here
    Exit;
  end;
  if K = 'PROMPT' then
  begin
    Result := TpgnResultSet.Create;
    Result.ReturnsRows := True;
    SetLength(Result.Columns, 1);
    Result.Columns[0] := 'Prompt';
    SetLength(Result.Rows, 1);
    SetLength(Result.Rows[0].Values, 1);
    SetLength(Result.Rows[0].Nulls, 1);
    Result.Rows[0].Values[0] := Trim(Copy(S, 7, MaxInt));
    Exit;
  end;
  if (K = 'SHOW') and ((W2 = 'ERRORS') or (W2 = 'ERR')) then
  begin
    Result := RunStatement(FConn, 'SELECT name AS "Object", LOWER(type) AS "Type", line AS "Line", ' +
      'position AS "Column", text AS "Error" FROM user_errors ORDER BY name, type, sequence', ARowLimit);
    Exit;
  end;
  if (K = 'EXEC') or (K = 'EXECUTE') then
  begin
    P := Pos(' ', S);
    S := 'BEGIN ' + TrimStatement(Trim(Copy(S, P + 1, MaxInt))) + '; END;';
  end;

  S := OracleStatement(S);
  try
    Result := RunStatement(FConn, S, ARowLimit);
  except
    on E: Exception do
    begin
      // ORA-24344: the code was saved, with compilation errors
      if (Pos('24344', E.Message) > 0) and FindCreateName(S, St, Len, Name, Kw) then
      begin
        if Pos('"', Copy(S, St, Len)) = 0 then
        begin
          Name := UpperCase(Name);
        end;
        Errors := CompileErrors(FConn, FSchema, Name, Kw);
        raise Exception.Create('Created ' + LowerCase(Kw) + ' ' + Name + ' with compilation errors ' +
          '(it is INVALID):' + LineEnding + Errors);
      end;
      raise;
    end;
  end;

  // code created without an error may still not compile (some clients
  // don't report ORA-24344): look
  if IsPlSqlBlock(S) and (K = 'CREATE') and FindCreateName(S, St, Len, Name, Kw) then
  begin
    if Pos('"', Copy(S, St, Len)) = 0 then
    begin
      Name := UpperCase(Name);
    end;
    try
      Errors := CompileErrors(FConn, FSchema, Name, Kw);
    except
      on E: Exception do
      begin
        Errors := '';
      end;
    end;
    if Errors <> '' then
    begin
      Result.Free;
      raise Exception.Create('Created ' + LowerCase(Kw) + ' ' + Name + ' with compilation errors ' +
        '(it is INVALID):' + LineEnding + Errors);
    end;
  end;

  if K = 'ALTER' then
  begin
    // ALTER SESSION SET CURRENT_SCHEMA typed in the editor: keep the picker honest
    try
      FSchema := RunStatement(FConn, 'SELECT SYS_CONTEXT(''USERENV'', ''CURRENT_SCHEMA'') FROM dual',
        0).Rows[0].Values[0];
    except
      on E: Exception do
      begin
        // the picker just stays as it was
      end;
    end;
  end;

  if FDbmsOutput then
  begin
    Result := AppendResult(Result, ReadDbmsOutput);
  end;
end;

{ ALTER SYSTEM CANCEL SQL (Oracle 18c on) from the metadata session; it
  needs the ALTER SYSTEM privilege and this session's serial number. }
procedure TpgnOracleAdapter.CancelCurrent;
begin
  if (FSid = '') or (FSerial = '') then
  begin
    raise Exception.Create('Oracle doesn''t let this login see its own session number (V$SESSION), ' +
      'so the statement can''t be canceled from here; it runs to the end.');
  end;
  MetaExec('ALTER SYSTEM CANCEL SQL ''' + FSid + ',' + FSerial + '''');
end;

procedure TpgnOracleAdapter.SetAutoCommit(AValue: Boolean);
begin
  if AValue = FAutoCommit then
  begin
    Exit;
  end;
  if FConn.Connected then
  begin
    if AValue then
    begin
      RunStatement(FConn, 'COMMIT', 0).Free;
    end;
    FConn.AutoCommit := AValue;
  end;
  FAutoCommit := AValue;
end;

function TpgnOracleAdapter.AutoCommit: Boolean;
begin
  Result := FAutoCommit;
end;

procedure TpgnOracleAdapter.Commit;
begin
  RunStatement(FConn, 'COMMIT', 0).Free;
end;

procedure TpgnOracleAdapter.Rollback;
begin
  RunStatement(FConn, 'ROLLBACK', 0).Free;
end;

end.
