// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapterMySQL;

{ MySQL / MariaDB adapter, built on ZeosLib.

  It holds two connections:
    FConn - runs user statements (worker thread)
    FMeta - answers schema questions (main thread)
  so browsing the schema tree never waits behind a long-running query.
  Cancel opens a short-lived third connection and issues KILL QUERY. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, ZConnection, ZDataset,
  pgnTypes, pgnAdapter, pgnSqlSplit, pgnZeos;

type
  TpgnMySQLAdapter = class(TpgnAdapter)
  private
    FConn: TZConnection;
    FMeta: TZConnection;
    FConnectionId: Int64;
    FVersion: string;
    FAutoCommit: Boolean;
    procedure Configure(AConn: TZConnection);
    function MetaQuery(const ASQL: string; const AParams: array of string): TZReadOnlyQuery;
    function MetaStrings(const ASQL: string; const AParams: array of string): TpgnStringArray;
    function UseTarget(const ASQL: string): string;
    function MetaResult(const ASQL: string; const AParams: array of string): TpgnResultSet;
    procedure MetaExec(const ASQL: string);
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
    function ServerVersion: string; override;
    function OwnSessionId: string; override;
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
    function QuoteLiteral(const AText: string): string; override;
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

    function Acct(const AAccount: TpgnAccount): string;
    function AccountsHaveHost: Boolean; override;
    function HasRoles: Boolean; override;
    function ListAccounts(ASystem: Boolean): TpgnAccounts; override;
    function AccountFromText(const AText: string): TpgnAccount; override;
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
    function CopyAccessSQL(const AFrom, ATo: TpgnAccount): TpgnStringArray; override;
    function AccountOwns(const AAccount: TpgnAccount): TpgnResultSet; override;
    function DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
      ADropOwned: Boolean): TpgnStringArray; override;
    procedure RunAdmin(const ASQL: string); override;
    function ObjectAccess(const AKind, AContainer, AName: string;
      AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet; override;
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

implementation

constructor TpgnMySQLAdapter.Create(const AInfo: TpgnConnectionInfo; const APassword: string);
begin
  inherited Create(AInfo, APassword);
  FConn := TZConnection.Create(nil);
  FMeta := TZConnection.Create(nil);
  FConnectionId := 0;
  FAutoCommit := True;
end;

destructor TpgnMySQLAdapter.Destroy;
begin
  Disconnect;
  FreeAndNil(FMeta);
  FreeAndNil(FConn);
  inherited Destroy;
end;

procedure TpgnMySQLAdapter.Configure(AConn: TZConnection);
begin
  AConn.Protocol := EngineNames[FInfo.Engine];   // 'mysql' or 'mariadb'
  AConn.HostName := FInfo.Host;
  AConn.Port := FInfo.Port;
  AConn.User := FInfo.User;
  AConn.Password := FPassword;
  AConn.Database := FInfo.DefaultDatabase;
  AConn.LoginPrompt := False;
  AConn.AutoCommit := True;
  if FInfo.ClientLibrary <> '' then
  begin
    AConn.LibraryLocation := FInfo.ClientLibrary;
  end;
  AConn.Properties.Values['codepage'] := 'utf8mb4';
  AConn.Properties.Values['CLIENT_MULTI_RESULTS'] := 'TRUE';   // CALL returns result sets

  // TLS. Property names follow ZeosLib's MySQL driver; verify them
  // against the Zeos version you install (see README).
  if FInfo.UseTLS then
  begin
    AConn.Properties.Values['MYSQL_SSL'] := 'TRUE';
    if FInfo.TLSCAFile <> '' then
    begin
      AConn.Properties.Values['MYSQL_SSL_CA'] := FInfo.TLSCAFile;
    end;
  end;
end;

procedure TpgnMySQLAdapter.Connect;
var
  Q: TZReadOnlyQuery;
begin
  Configure(FConn);
  try
    FConn.Connect;
  except
    on E: Exception do
    begin
      if (Pos('SSL', E.Message) > 0) and ((Pos('not support', E.Message) > 0) or
        (Pos('not enabled', E.Message) > 0) or (Pos('is required', E.Message) > 0)) then
      begin
        raise Exception.Create('This server doesn''t offer TLS, so a TLS connection isn''t ' +
          'possible. Turn off "Use TLS" for this connection, or ask the server''s administrator ' +
          'to turn on SSL. (' + Trim(E.Message) + ')');
      end;
      raise;
    end;
  end;
  Configure(FMeta);
  FMeta.Connect;

  // Remember the server-side id of the query connection so Cancel can kill it.
  Q := TZReadOnlyQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.SQL.Text := 'SELECT CONNECTION_ID(), VERSION()';
    Q.Open;
    FConnectionId := Q.Fields[0].AsLargeInt;
    FVersion := Q.Fields[1].AsString;
    Q.Close;
  finally
    Q.Free;
  end;
end;

procedure TpgnMySQLAdapter.Disconnect;
begin
  if (FConn <> nil) and FConn.Connected then
  begin
    FConn.Disconnect;
  end;
  if (FMeta <> nil) and FMeta.Connected then
  begin
    FMeta.Disconnect;
  end;
  FConnectionId := 0;
end;

function TpgnMySQLAdapter.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.Connected;
end;

function TpgnMySQLAdapter.MetaQuery(const ASQL: string; const AParams: array of string): TZReadOnlyQuery;
var
  I: Integer;
begin
  Result := TZReadOnlyQuery.Create(nil);
  try
    Result.Connection := FMeta;
    Result.SQL.Text := ASQL;   // parameters are named :p0, :p1, ...
    for I := 0 to High(AParams) do
    begin
      Result.ParamByName('p' + IntToStr(I)).AsString := AParams[I];
    end;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function TpgnMySQLAdapter.MetaStrings(const ASQL: string; const AParams: array of string): TpgnStringArray;
var
  Q: TZReadOnlyQuery;
  N: Integer;
begin
  Result := nil;
  N := 0;
  Q := MetaQuery(ASQL, AParams);
  try
    while not Q.EOF do
    begin
      if N >= Length(Result) then
      begin
        SetLength(Result, N * 2 + 16);
      end;
      Result[N] := Q.Fields[0].AsString;
      Inc(N);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  SetLength(Result, N);
end;

function TpgnMySQLAdapter.ListDatabases: TpgnStringArray;
begin
  Result := MetaStrings('SHOW DATABASES', []);
end;

function TpgnMySQLAdapter.ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray;
var
  TableType: string;
begin
  if AKind = okView then
  begin
    TableType := 'VIEW';
  end
  else
  begin
    TableType := 'BASE TABLE';
  end;
  Result := MetaStrings(
    'SELECT TABLE_NAME FROM information_schema.TABLES ' +
    'WHERE TABLE_SCHEMA = :p0 AND TABLE_TYPE = :p1 ' +
    'ORDER BY TABLE_NAME',
    [ADatabase, TableType]);
end;

function TpgnMySQLAdapter.ListObjectNames(const ADatabase: string): TpgnStringArray;
begin
  Result := MetaStrings(
    'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = :p0 ' +
    'UNION SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = :p0',
    [ADatabase]);
end;

function TpgnMySQLAdapter.SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs;
var
  Q: TZReadOnlyQuery;
  N: Integer;
  Pattern: string;
begin
  Result := nil;
  // LIKE wildcards in the text are matched literally
  Pattern := '%' + StringReplace(StringReplace(StringReplace(AText, '\', '\\', [rfReplaceAll]),
    '%', '\%', [rfReplaceAll]), '_', '\_', [rfReplaceAll]) + '%';
  Q := MetaQuery(
    'SELECT TABLE_SCHEMA, TABLE_NAME, ' +
    'CASE TABLE_TYPE WHEN ''VIEW'' THEN ''View'' ELSE ''Table'' END ' +
    'FROM information_schema.TABLES WHERE TABLE_NAME LIKE :p0 ' +
    'UNION ALL ' +
    'SELECT ROUTINE_SCHEMA, ROUTINE_NAME, ' +
    'CASE ROUTINE_TYPE WHEN ''FUNCTION'' THEN ''Function'' ELSE ''Procedure'' END ' +
    'FROM information_schema.ROUTINES WHERE ROUTINE_NAME LIKE :p0 ' +
    'ORDER BY 2, 1 LIMIT ' + IntToStr(AMax),
    [Pattern]);
  try
    N := 0;
    while not Q.EOF do
    begin
      SetLength(Result, N + 1);
      Result[N].Database := Q.Fields[0].AsString;
      Result[N].Name := Q.Fields[1].AsString;
      Result[N].Kind := Q.Fields[2].AsString;
      Inc(N);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TpgnMySQLAdapter.DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet;
var
  Q: TZReadOnlyQuery;
begin
  Result := TpgnResultSet.Create;
  try
    Q := MetaQuery(
      'SELECT INDEX_NAME AS `Index`, COLUMN_NAME AS `Column`, ' +
      'SEQ_IN_INDEX AS `Position`, ' +
      'CASE NON_UNIQUE WHEN 0 THEN ''yes'' ELSE ''no'' END AS `Unique`, ' +
      'INDEX_TYPE AS `Type` ' +
      'FROM information_schema.STATISTICS ' +
      'WHERE TABLE_SCHEMA = :p0 AND TABLE_NAME = :p1 ' +
      'ORDER BY INDEX_NAME = ''PRIMARY'' DESC, INDEX_NAME, SEQ_IN_INDEX',
      [ADatabase, ATable]);
    try
      DataSetToResult(Q, 0, Result);
    finally
      Q.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ ------------------------------------------- procedures, functions, triggers }

function TpgnMySQLAdapter.MetaResult(const ASQL: string; const AParams: array of string): TpgnResultSet;
var
  Q: TZReadOnlyQuery;
begin
  Result := TpgnResultSet.Create;
  try
    Q := MetaQuery(ASQL, AParams);
    try
      DataSetToResult(Q, 0, Result);
    finally
      Q.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ DDL on the metadata session, as plain text. }
procedure TpgnMySQLAdapter.MetaExec(const ASQL: string);
begin
  RunStatement(FMeta, ASQL, 0).Free;
end;

function TpgnMySQLAdapter.ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray;
begin
  if AKind = rkTrigger then
  begin
    Result := MetaStrings(
      'SELECT TRIGGER_NAME FROM information_schema.TRIGGERS ' +
      'WHERE TRIGGER_SCHEMA = :p0 ORDER BY TRIGGER_NAME', [ADatabase]);
  end
  else
  begin
    Result := MetaStrings(
      'SELECT ROUTINE_NAME FROM information_schema.ROUTINES ' +
      'WHERE ROUTINE_SCHEMA = :p0 AND ROUTINE_TYPE = :p1 ORDER BY ROUTINE_NAME',
      [ADatabase, RoutineWord[AKind]]);
  end;
end;

function TpgnMySQLAdapter.GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
var
  Q: TZReadOnlyQuery;
begin
  Result := '';
  // column 3 holds the CREATE statement; it is NULL when the login may
  // not see the body
  Q := MetaQuery('SHOW CREATE ' + RoutineWord[AKind] + ' ' + QuoteIdent(ADatabase) + '.' +
    QuoteIdent(AName), []);
  try
    if (not Q.EOF) and (Q.FieldCount >= 3) and not Q.Fields[2].IsNull then
    begin
      Result := Q.Fields[2].AsString;
    end;
  finally
    Q.Free;
  end;
end;

function TpgnMySQLAdapter.RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean;
var
  L: TpgnStringArray;
begin
  if AKind = rkTrigger then
  begin
    L := MetaStrings('SELECT TRIGGER_NAME FROM information_schema.TRIGGERS ' +
      'WHERE TRIGGER_SCHEMA = :p0 AND TRIGGER_NAME = :p1', [ADatabase, AName]);
  end
  else
  begin
    L := MetaStrings('SELECT ROUTINE_NAME FROM information_schema.ROUTINES ' +
      'WHERE ROUTINE_SCHEMA = :p0 AND ROUTINE_NAME = :p1 AND ROUTINE_TYPE = :p2',
      [ADatabase, AName, RoutineWord[AKind]]);
  end;
  Result := Length(L) > 0;
end;

function TpgnMySQLAdapter.DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT tc.CONSTRAINT_NAME AS `Constraint`, CASE tc.CONSTRAINT_TYPE ' +
    'WHEN ''PRIMARY KEY'' THEN ''Primary key'' WHEN ''UNIQUE'' THEN ''Unique'' ' +
    'WHEN ''FOREIGN KEY'' THEN ''Foreign key'' WHEN ''CHECK'' THEN ''Check'' ' +
    'ELSE tc.CONSTRAINT_TYPE END AS `Type`, ' +
    'GROUP_CONCAT(k.COLUMN_NAME ORDER BY k.ORDINAL_POSITION SEPARATOR '', '') AS `Columns`, ' +
    'MAX(CONCAT(k.REFERENCED_TABLE_SCHEMA, ''.'', k.REFERENCED_TABLE_NAME)) AS `References` ' +
    'FROM information_schema.TABLE_CONSTRAINTS tc ' +
    'LEFT JOIN information_schema.KEY_COLUMN_USAGE k ON k.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA ' +
    'AND k.CONSTRAINT_NAME = tc.CONSTRAINT_NAME AND k.TABLE_NAME = tc.TABLE_NAME ' +
    'WHERE tc.TABLE_SCHEMA = :p0 AND tc.TABLE_NAME = :p1 ' +
    'GROUP BY tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE ' +
    'ORDER BY FIELD(tc.CONSTRAINT_TYPE, ''PRIMARY KEY'', ''UNIQUE'', ''FOREIGN KEY'', ''CHECK''), 1',
    [ADatabase, ATable]);
end;

{ Views that name it, tables whose foreign keys point at it, and routines
  whose text mentions it (MySQL keeps no list of those). }
function TpgnMySQLAdapter.DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT TABLE_SCHEMA AS `Database`, TABLE_NAME AS `Name`, ''View'' AS `Type` ' +
    'FROM information_schema.VIEWS ' +
    'WHERE VIEW_DEFINITION LIKE CONCAT(''%`'', :p0, ''`.`'', :p1, ''`%'') ' +
    'UNION SELECT TABLE_SCHEMA, TABLE_NAME, ''Table (foreign key)'' ' +
    'FROM information_schema.KEY_COLUMN_USAGE ' +
    'WHERE REFERENCED_TABLE_SCHEMA = :p0 AND REFERENCED_TABLE_NAME = :p1 ' +
    'UNION SELECT ROUTINE_SCHEMA, ROUTINE_NAME, CONCAT(CASE ROUTINE_TYPE WHEN ''FUNCTION'' ' +
    'THEN ''Function'' ELSE ''Procedure'' END, '' (mentions it)'') ' +
    'FROM information_schema.ROUTINES WHERE ROUTINE_DEFINITION LIKE CONCAT(''%'', :p1, ''%'') ' +
    'ORDER BY 3, 1, 2',
    [ADatabase, AName]);
end;

function TpgnMySQLAdapter.DescribeParameters(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT CASE WHEN ORDINAL_POSITION = 0 THEN ''RETURNS'' ELSE PARAMETER_MODE END AS `Mode`, ' +
    'COALESCE(PARAMETER_NAME, '''') AS `Parameter`, DTD_IDENTIFIER AS `Type` ' +
    'FROM information_schema.PARAMETERS ' +
    'WHERE SPECIFIC_SCHEMA = :p0 AND SPECIFIC_NAME = :p1 ORDER BY ORDINAL_POSITION',
    [ADatabase, AName]);
end;

function TpgnMySQLAdapter.DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := MetaResult(
    'SELECT TRIGGER_NAME AS `Trigger`, ACTION_TIMING AS `Timing`, ' +
    'EVENT_MANIPULATION AS `Event`, ACTION_ORDER AS `Order` ' +
    'FROM information_schema.TRIGGERS ' +
    'WHERE EVENT_OBJECT_SCHEMA = :p0 AND EVENT_OBJECT_TABLE = :p1 ' +
    'ORDER BY ACTION_TIMING DESC, EVENT_MANIPULATION, ACTION_ORDER',
    [ADatabase, ATable]);
end;

function TpgnMySQLAdapter.DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet;
begin
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    // routine rights live only in mysql.procs_priv, which many logins
    // can't read; the caller says so when this raises
    Result := MetaResult(
      'SELECT CONCAT(''`'', User, ''`@`'', Host, ''`'') AS `Grantee`, ' +
      'Proc_priv AS `Privileges`, Grantor AS `Granted by` FROM mysql.procs_priv ' +
      'WHERE Db = :p0 AND Routine_name = :p1 AND Routine_type = :p2 ORDER BY 1',
      [ADatabase, AName, AObjectWord]);
  end
  else
  begin
    Result := MetaResult(
      'SELECT GRANTEE AS `Grantee`, PRIVILEGE_TYPE AS `Privilege`, ' +
      'IS_GRANTABLE AS `Can grant` FROM information_schema.TABLE_PRIVILEGES ' +
      'WHERE TABLE_SCHEMA = :p0 AND TABLE_NAME = :p1 ORDER BY 1, 2',
      [ADatabase, AName]);
  end;
end;

{ ASQL with the object's name replaced by `db`.`ANewName`. }
function RenameInCreate(const ASQL, ADb, ANewName: string; AAdapter: TpgnMySQLAdapter): string;
var
  St, Len: Integer;
  Nm, Kw: string;
begin
  if not FindCreateName(ASQL, St, Len, Nm, Kw) then
  begin
    raise Exception.Create('This doesn''t look like a CREATE PROCEDURE, FUNCTION or TRIGGER statement.');
  end;
  Result := Copy(ASQL, 1, St - 1) + AAdapter.QuoteIdent(ADb) + '.' + AAdapter.QuoteIdent(ANewName) +
    Copy(ASQL, St + Len, MaxInt);
end;

{ "Execute,Alter Routine,Grant" as GRANT words; AWithGrant says whether
  the holder could pass them on. '' when there's nothing to grant. }
function GrantWords(const AProcPriv: string; out AWithGrant: Boolean): string;
var
  Parts: TStringList;
begin
  Result := '';
  Parts := TStringList.Create;
  try
    Parts.CommaText := StringReplace(AProcPriv, ' ', '_', [rfReplaceAll]);
    if Parts.IndexOf('Execute') >= 0 then
    begin
      Result := 'EXECUTE';
    end;
    if Parts.IndexOf('Alter_Routine') >= 0 then
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + 'ALTER ROUTINE';
    end;
    AWithGrant := Parts.IndexOf('Grant') >= 0;
  finally
    Parts.Free;
  end;
end;

{ How MySQL routines are saved. There is no way to change a routine's body
  in place, so:
    1. A test copy is created under another name. If that fails (a typo,
       a DEFINER only an admin may set), nothing has been touched.
    2. The rights others hold on the routine are read (dropping a routine
       removes them).
    3. The routine is dropped and created from the new text. If that fails,
       the previous version is put back.
    4. The rights are granted again.
  Triggers skip the test copy (a copy on the same table would fire too),
  and are put back as they were if the new version fails. }
function TpgnMySQLAdapter.SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
  const ASQL: string; ALog: TStrings): string;
var
  St, Len, I: Integer;
  NewName, Kw, Word, Target, OldSQL, CheckName, Privs, G, Fail: string;
  Grants: TpgnResultSet;
  GrantsKnown, WithGrant, PutBack: Boolean;
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
  // the session's database matters for unqualified names inside the body
  MetaExec('USE ' + QuoteIdent(ADatabase));
  Target := QuoteIdent(ADatabase) + '.' + QuoteIdent(NewName);

  if ((AOldName = '') or not SameText(NewName, AOldName)) and
    RoutineExists(ADatabase, NewName, AKind) then
  begin
    raise Exception.Create('A ' + LowerCase(Word) + ' named ' + NewName + ' already exists in ' +
      ADatabase + '. Nothing was changed.');
  end;

  // 1. test copy
  if AKind <> rkTrigger then
  begin
    CheckName := 'pgn_check_' + Copy(NewName, 1, 50);
    MetaExec('DROP ' + Word + ' IF EXISTS ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(CheckName));
    try
      MetaExec(RenameInCreate(ASQL, ADatabase, CheckName, Self));
    except
      on E: Exception do
      begin
        if (Pos('SUPER', E.Message) > 0) or (Pos('SET_USER_ID', E.Message) > 0) or
          (Pos('SET_ANY_DEFINER', E.Message) > 0) then
        begin
          raise Exception.Create('Nothing was changed. The DEFINER = ... clause names another ' +
            'login, and only an administrator may save it that way. To save it as your own ' +
            'login, remove the DEFINER clause (it will then run with your rights). ' +
            E.Message);
        end;
        raise Exception.Create('Nothing was changed: the new version has a problem. ' + E.Message);
      end;
    end;
    MetaExec('DROP ' + Word + ' IF EXISTS ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(CheckName));
    ALog.Add('Checked the new version (a test copy was created and removed)');
  end;

  // 2. rights to restore
  Grants := nil;
  GrantsKnown := True;
  if (AOldName <> '') and (AKind <> rkTrigger) then
  begin
    try
      Grants := DescribeGrants(ADatabase, AOldName, Word);
    except
      on E: Exception do
      begin
        GrantsKnown := False;
      end;
    end;
  end;
  try
    // 3. replace
    OldSQL := '';
    if AOldName <> '' then
    begin
      OldSQL := GetRoutineSQL(ADatabase, AOldName, AKind);
      MetaExec('DROP ' + Word + ' IF EXISTS ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(AOldName));
    end;
    Fail := '';
    try
      MetaExec(RenameInCreate(ASQL, ADatabase, NewName, Self));
    except
      on E: Exception do
      begin
        Fail := E.Message;
      end;
    end;
    if Fail <> '' then
    begin
      PutBack := False;
      if OldSQL <> '' then
      begin
        try
          MetaExec(OldSQL);
          PutBack := True;
        except
          on E: Exception do
          begin
            PutBack := False;
          end;
        end;
      end;
      if PutBack then
      begin
        raise Exception.Create('The new version could not be created, so the previous version ' +
          'was put back. ' + Fail);
      end;
      if OldSQL <> '' then
      begin
        ALog.Add('The previous version, to restore it by hand:');
        ALog.Add(OldSQL);
        raise Exception.Create('The new version could not be created, and putting the previous ' +
          'version back failed too. Its text is in Messages; run it to restore it. ' + Fail);
      end;
      raise Exception.Create(Fail);
    end;
    if AOldName = '' then
    begin
      ALog.Add('Created ' + LowerCase(Word) + ' ' + ADatabase + '.' + NewName);
    end
    else
    begin
      ALog.Add('Saved ' + LowerCase(Word) + ' ' + ADatabase + '.' + NewName);
    end;

    // 4. rights back
    if not GrantsKnown then
    begin
      ALog.Add('WARNING: your login can''t read who had rights on ' + AOldName +
        ', so they could not be granted again. Check them with your DBA.');
    end
    else if Grants <> nil then
    begin
      for I := 0 to Grants.RowCount - 1 do
      begin
        G := Grants.Rows[I].Values[0];
        Privs := GrantWords(Grants.Rows[I].Values[1], WithGrant);
        if Privs = '' then
        begin
          Continue;
        end;
        try
          if WithGrant then
          begin
            MetaExec('GRANT ' + Privs + ' ON ' + Word + ' ' + Target + ' TO ' + G +
              ' WITH GRANT OPTION');
          end
          else
          begin
            MetaExec('GRANT ' + Privs + ' ON ' + Word + ' ' + Target + ' TO ' + G);
          end;
          ALog.Add('Granted again: ' + Privs + ' to ' + G);
        except
          on E: Exception do
          begin
            ALog.Add('WARNING: could not grant ' + Privs + ' to ' + G + ' again: ' + E.Message);
          end;
        end;
      end;
    end;
  finally
    Grants.Free;
  end;
  Result := NewName;
end;

function TpgnMySQLAdapter.OwnSessionId: string;
begin
  if FConnectionId = 0 then
  begin
    Result := '';
  end
  else
  begin
    Result := IntToStr(FConnectionId);
  end;
end;

function TpgnMySQLAdapter.ServerVersion: string;
begin
  Result := FVersion;
end;

function TpgnMySQLAdapter.DescribeTable(const ADatabase, ATable: string): TpgnResultSet;
var
  Q: TZReadOnlyQuery;
begin
  Result := TpgnResultSet.Create;
  try
    Q := MetaQuery(
      'SELECT COLUMN_NAME AS `Column`, COLUMN_TYPE AS `Type`, ' +
      'IS_NULLABLE AS `Nullable`, COLUMN_KEY AS `Key`, ' +
      'COLUMN_DEFAULT AS `Default`, EXTRA AS `Extra`, ' +
      'COLUMN_COMMENT AS `Comment` ' +
      'FROM information_schema.COLUMNS ' +
      'WHERE TABLE_SCHEMA = :p0 AND TABLE_NAME = :p1 ' +
      'ORDER BY ORDINAL_POSITION',
      [ADatabase, ATable]);
    try
      DataSetToResult(Q, 0, Result);
    finally
      Q.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TpgnMySQLAdapter.GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string;
var
  Q: TZReadOnlyQuery;
  Verb: string;
begin
  if AKind = okView then
  begin
    Verb := 'SHOW CREATE VIEW ';
  end
  else
  begin
    Verb := 'SHOW CREATE TABLE ';
  end;
  Q := MetaQuery(Verb + QuoteIdent(ADatabase) + '.' + QuoteIdent(AObject), []);
  try
    Result := Q.Fields[1].AsString;
  finally
    Q.Free;
  end;
end;

{ The database name from a USE statement, without quotes. }
function TpgnMySQLAdapter.UseTarget(const ASQL: string): string;
var
  P: Integer;
begin
  Result := TrimStatement(ASQL);
  P := Pos('USE', UpperCase(Result));
  Result := Trim(Copy(Result, P + 3, MaxInt));
  if (Length(Result) >= 2) and (Result[1] = '`') and (Result[Length(Result)] = '`') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '``', '`', [rfReplaceAll]);
  end;
end;

procedure TpgnMySQLAdapter.UseDatabase(const ADatabase: string);
begin
  FConn.ExecuteDirect('USE ' + QuoteIdent(ADatabase));
  FCurrentDatabase := ADatabase;
end;

{ Transactions are driven with plain SQL on the session, so Zeos's own
  transaction handling (left in auto-commit) never gets in the way. }
procedure TpgnMySQLAdapter.SetAutoCommit(AValue: Boolean);
begin
  if AValue then
  begin
    FConn.ExecuteDirect('SET autocommit = 1');   // also commits pending work
  end
  else
  begin
    FConn.ExecuteDirect('SET autocommit = 0');
  end;
  FAutoCommit := AValue;
end;

function TpgnMySQLAdapter.AutoCommit: Boolean;
begin
  Result := FAutoCommit;
end;

procedure TpgnMySQLAdapter.Commit;
begin
  FConn.ExecuteDirect('COMMIT');
end;

procedure TpgnMySQLAdapter.Rollback;
begin
  FConn.ExecuteDirect('ROLLBACK');
end;

{ Sent as text; the server's answer decides whether there are rows. That
  covers SELECT, CALL (including procedures that return several result
  sets), DDL, USE and anything else, with no guessing from the SQL. }
function TpgnMySQLAdapter.Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
begin
  Result := RunStatement(FConn, TrimStatement(ASQL), ARowLimit);
  if FirstKeyword(ASQL) = 'USE' then
  begin
    FCurrentDatabase := UseTarget(ASQL);
  end;
end;

procedure TpgnMySQLAdapter.CancelCurrent;
var
  C: TZConnection;
begin
  if FConnectionId = 0 then
  begin
    Exit;
  end;
  C := TZConnection.Create(nil);
  try
    Configure(C);
    C.Database := '';
    C.Connect;
    C.ExecuteDirect('KILL QUERY ' + IntToStr(FConnectionId));
    C.Disconnect;
  finally
    C.Free;
  end;
end;

function TpgnMySQLAdapter.QuoteIdent(const AName: string): string;
begin
  Result := '`' + StringReplace(AName, '`', '``', [rfReplaceAll]) + '`';
end;

{ ------------------------------------------- SQL for the forms and menus }

function TpgnMySQLAdapter.QuoteLiteral(const AText: string): string;
begin
  Result := '''' + StringReplace(StringReplace(AText, '\', '\\', [rfReplaceAll]),
    '''', '''''', [rfReplaceAll]) + '''';
end;

{ "IN p_pidm INT, OUT p_total INT" laid out one per line when there are
  several. }
function ParamList(const AParams: TpgnParamDefs; AWithMode: Boolean): string;
var
  I: Integer;
  Line: string;
begin
  Result := '';
  for I := 0 to High(AParams) do
  begin
    Line := AParams[I].Name + ' ' + AParams[I].DataType;
    if AWithMode and (AParams[I].Mode <> '') then
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

function TpgnMySQLAdapter.NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs; const AReturns: string): string;
begin
  if AKind = rkProcedure then
  begin
    Result := 'CREATE PROCEDURE ' + QuoteIdent(AName) + '(' + ParamList(AParams, True) + ')' +
      LineEnding + 'BEGIN' + LineEnding + '  -- your code here' + LineEnding + 'END';
  end
  else
  begin
    Result := 'CREATE FUNCTION ' + QuoteIdent(AName) + '(' + ParamList(AParams, False) + ')' +
      LineEnding + 'RETURNS ' + AReturns + LineEnding +
      '-- MySQL needs one of: DETERMINISTIC, NO SQL, READS SQL DATA, MODIFIES SQL DATA' +
      LineEnding + 'READS SQL DATA' + LineEnding + 'BEGIN' + LineEnding +
      '  -- your code here' + LineEnding + '  RETURN NULL;' + LineEnding + 'END';
  end;
end;

function TpgnMySQLAdapter.NewTriggerSQL(const ADatabase, ATable: string): string;
begin
  Result := 'CREATE TRIGGER ' + QuoteIdent(ATable + '_before_insert') + LineEnding +
    'BEFORE INSERT ON ' + QuoteIdent(ATable) + LineEnding +
    '-- timing: BEFORE or AFTER;  event: INSERT, UPDATE or DELETE' + LineEnding +
    'FOR EACH ROW' + LineEnding + 'BEGIN' + LineEnding +
    '  -- NEW.column is the row being written; OLD.column the row before it' +
    LineEnding + 'END';
end;

{ OUT and INOUT parameters travel in @variables, read back afterwards. }
function TpgnMySQLAdapter.ExecuteRoutineSQL(const ADatabase, AName: string;
  AKind: TpgnRoutineKind; const AParams: TpgnParamDefs): string;
var
  I: Integer;
  Args, Pre, Post, V, Mode: string;
begin
  Args := '';
  Pre := '';
  Post := '';
  for I := 0 to High(AParams) do
  begin
    if I > 0 then
    begin
      Args := Args + ', ';
    end;
    Mode := UpperCase(AParams[I].Mode);
    V := AParams[I].Value;
    if Mode = 'OUT' then
    begin
      Args := Args + '@' + AParams[I].Name;
      if Post <> '' then
      begin
        Post := Post + ', ';
      end;
      Post := Post + '@' + AParams[I].Name + ' AS ' + QuoteIdent(AParams[I].Name);
    end
    else if Mode = 'INOUT' then
    begin
      Pre := Pre + 'SET @' + AParams[I].Name + ' = ' + V + ';' + LineEnding;
      Args := Args + '@' + AParams[I].Name;
      if Post <> '' then
      begin
        Post := Post + ', ';
      end;
      Post := Post + '@' + AParams[I].Name + ' AS ' + QuoteIdent(AParams[I].Name);
    end
    else
    begin
      Args := Args + V;
    end;
  end;
  if AKind = rkFunction then
  begin
    Result := 'SELECT ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args + ') AS ' +
      QuoteIdent(AName) + ';';
  end
  else
  begin
    Result := Pre + 'CALL ' + RoutineTarget(ADatabase, AName, AKind) + '(' + Args + ');';
    if Post <> '' then
    begin
      Result := Result + LineEnding + 'SELECT ' + Post + ';';
    end;
  end;
end;

function TpgnMySQLAdapter.GrantRights(const AObjectWord: string): TpgnStringArray;
begin
  Result := nil;
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    SetLength(Result, 2);
    Result[0] := 'EXECUTE';
    Result[1] := 'ALTER ROUTINE';
  end
  else
  begin
    Result := inherited GrantRights(AObjectWord);
  end;
end;

function TpgnMySQLAdapter.GranteeHint: string;
begin
  Result := 'To (user@host, e.g. jsmith@%)';
end;

{ user@host, 'user'@'host' or `user`@`host` -> 'user'@'host' }
function GranteeText(const AText: string): string;
var
  S, U, H: string;
  P: Integer;
begin
  S := Trim(AText);
  if (Pos('''', S) > 0) or (Pos('`', S) > 0) then
  begin
    Result := S;
    Exit;
  end;
  P := Pos('@', S);
  if P > 0 then
  begin
    U := Copy(S, 1, P - 1);
    H := Copy(S, P + 1, MaxInt);
  end
  else
  begin
    U := S;
    H := '%';
  end;
  Result := '''' + U + '''@''' + H + '''';
end;

function TpgnMySQLAdapter.GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
  AWithGrantOption: Boolean): string;
var
  OnWhat: string;
begin
  OnWhat := '';
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    OnWhat := AObjectWord + ' ';
  end;
  Result := 'GRANT ' + ARights + ' ON ' + OnWhat + QuoteIdent(ADatabase) + '.' + QuoteIdent(AName) +
    ' TO ' + GranteeText(AGrantee);
  if AWithGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
  Result := Result + ';';
end;

{ ------------------------------------------------------------------- DBA }

function TpgnMySQLAdapter.ListSessions: TpgnResultSet;
const
  Cols = 'SELECT p.ID AS `Session`, p.USER AS `User`, SUBSTRING_INDEX(p.HOST, '':'', 1) AS `Machine`, ';
  Rest = 'p.DB AS `Database`, ' +
    'CONCAT(p.COMMAND, IF(p.STATE IS NULL OR p.STATE = '''', '''', CONCAT('' / '', p.STATE))) AS `State`, ' +
    'SEC_TO_TIME(p.TIME) AS `Time`, ' +
    'LEFT(REPLACE(REPLACE(COALESCE(p.INFO, ''''), CHAR(10), '' ''), CHAR(13), '' ''), 200) AS `Statement`, ';
  Tail = ' FROM information_schema.PROCESSLIST p WHERE p.COMMAND <> ''Daemon'' ' +
    'ORDER BY p.COMMAND = ''Sleep'', p.TIME DESC';
var
  Note: string;
begin
  Note := 'IF(p.ID IN (CONNECTION_ID(), ' + IntToStr(FConnectionId) + '), ''this tab'', '''') AS `Note`';
  try
    // the program name, where the performance schema has it
    Result := MetaResult(Cols + '(SELECT a.ATTR_VALUE FROM performance_schema.session_connect_attrs a ' +
      'WHERE a.PROCESSLIST_ID = p.ID AND a.ATTR_NAME = ''program_name'' LIMIT 1) AS `Program`, ' +
      Rest + Note + Tail, []);
  except
    on E: Exception do
    begin
      Result := MetaResult(Cols + ''''' AS `Program`, ' + Rest + Note + Tail, []);
    end;
  end;
end;

function TpgnMySQLAdapter.ListLocks: TpgnResultSet;
begin
  try
    // MySQL 8: the sys schema's view of InnoDB lock waits
    Result := MetaResult(
      'SELECT w.waiting_pid AS `Waiting`, pw.USER AS `Waiting user`, w.wait_age AS `Waiting for`, ' +
      'w.blocking_pid AS `Blocked by`, pb.USER AS `Blocker user`, pb.COMMAND AS `Blocker state`, ' +
      'SEC_TO_TIME(pb.TIME) AS `Blocker time`, ' +
      'IF(NOT EXISTS (SELECT 1 FROM sys.innodb_lock_waits x WHERE x.waiting_pid = w.blocking_pid), ' +
      '''yes'', '''') AS `Head of chain`, w.locked_table AS `Object`, ' +
      'LEFT(w.waiting_query, 200) AS `Waiting statement`, ' +
      'LEFT(COALESCE(w.blocking_query, ''''), 200) AS `Blocker statement` ' +
      'FROM sys.innodb_lock_waits w ' +
      'LEFT JOIN information_schema.PROCESSLIST pw ON pw.ID = w.waiting_pid ' +
      'LEFT JOIN information_schema.PROCESSLIST pb ON pb.ID = w.blocking_pid ' +
      'ORDER BY w.wait_age DESC', []);
  except
    on E: Exception do
    begin
      // MariaDB and older MySQL keep it in information_schema
      Result := MetaResult(
        'SELECT rt.trx_mysql_thread_id AS `Waiting`, pw.USER AS `Waiting user`, ' +
        'TIMEDIFF(NOW(), rt.trx_wait_started) AS `Waiting for`, ' +
        'bt.trx_mysql_thread_id AS `Blocked by`, pb.USER AS `Blocker user`, pb.COMMAND AS `Blocker state`, ' +
        'SEC_TO_TIME(pb.TIME) AS `Blocker time`, '''' AS `Head of chain`, '''' AS `Object`, ' +
        'LEFT(rt.trx_query, 200) AS `Waiting statement`, ' +
        'LEFT(COALESCE(bt.trx_query, ''''), 200) AS `Blocker statement` ' +
        'FROM information_schema.INNODB_LOCK_WAITS w ' +
        'JOIN information_schema.INNODB_TRX rt ON rt.trx_id = w.requesting_trx_id ' +
        'JOIN information_schema.INNODB_TRX bt ON bt.trx_id = w.blocking_trx_id ' +
        'LEFT JOIN information_schema.PROCESSLIST pw ON pw.ID = rt.trx_mysql_thread_id ' +
        'LEFT JOIN information_schema.PROCESSLIST pb ON pb.ID = bt.trx_mysql_thread_id', []);
    end;
  end;
end;

function TpgnMySQLAdapter.SessionStatement(const ASession: string): string;
var
  R: TpgnResultSet;
begin
  Result := '';
  R := MetaResult('SELECT INFO FROM information_schema.PROCESSLIST WHERE ID = ' +
    SessionNumber(ASession), []);
  try
    if R.RowCount > 0 then
    begin
      Result := R.Rows[0].Values[0];
    end;
  finally
    R.Free;
  end;
end;

function TpgnMySQLAdapter.CancelSession(const ASession: string): string;
begin
  Result := 'KILL QUERY ' + SessionNumber(ASession);
  MetaExec(Result);
end;

function TpgnMySQLAdapter.KillSession(const ASession: string): string;
begin
  Result := 'KILL ' + SessionNumber(ASession);
  MetaExec(Result);
end;

{ ------------------------------------------------------ users and roles }

function TpgnMySQLAdapter.Acct(const AAccount: TpgnAccount): string;
begin
  Result := QuoteLiteral(AAccount.Name) + '@' + QuoteLiteral(AAccount.Host);
end;

function TpgnMySQLAdapter.AccountsHaveHost: Boolean;
begin
  Result := True;
end;

{ Grantable roles: MySQL 8.0 on. (MariaDB has roles of its own kind;
  they come later.) }
function TpgnMySQLAdapter.HasRoles: Boolean;
begin
  Result := (FInfo.Engine = feMySQL) and (StrToIntDef(Copy(FVersion, 1, Pos('.', FVersion) - 1), 0) >= 8);
end;

function TpgnMySQLAdapter.ListAccounts(ASystem: Boolean): TpgnAccounts;
var
  R: TpgnResultSet;
  I, N: Integer;
  A: TpgnAccount;
begin
  Result := nil;
  R := nil;
  try
    if HasRoles then
    begin
      // a role: granted to someone, or locked with no password (CREATE ROLE)
      R := MetaResult('SELECT u.User, u.Host, IF(EXISTS (SELECT 1 FROM mysql.role_edges e ' +
        'WHERE e.FROM_USER = u.User AND e.FROM_HOST = u.Host) OR ' +
        '(u.account_locked = ''Y'' AND u.authentication_string = ''''), ''1'', ''0'') ' +
        'FROM mysql.user u ORDER BY u.User, u.Host', []);
    end
    else
    begin
      R := MetaResult('SELECT User, Host, ''0'' FROM mysql.user ORDER BY User, Host', []);
    end;
  except
    on E: Exception do
    begin
      raise Exception.Create('Could not read the accounts (this needs SELECT on mysql.user): ' + E.Message);
    end;
  end;
  try
    SetLength(Result, R.RowCount);
    N := 0;
    for I := 0 to R.RowCount - 1 do
    begin
      A := Default(TpgnAccount);
      A.Name := R.Rows[I].Values[0];
      A.Host := R.Rows[I].Values[1];
      A.IsRole := R.Rows[I].Values[2] = '1';
      A.IsSystem := (A.Name = '') or (A.Name = 'mysql.sys') or (A.Name = 'mysql.session') or
        (A.Name = 'mysql.infoschema') or (A.Name = 'mariadb.sys');
      if ASystem or not A.IsSystem then
      begin
        Result[N] := A;
        Inc(N);
      end;
    end;
    SetLength(Result, N);
  finally
    R.Free;
  end;
end;

function TpgnMySQLAdapter.AccountFromText(const AText: string): TpgnAccount;
var
  P: Integer;
begin
  Result := Default(TpgnAccount);
  P := Length(AText);
  while (P > 0) and (AText[P] <> '@') do
  begin
    Dec(P);
  end;
  if P = 0 then
  begin
    Result.Name := AText;
    Result.Host := '%';
  end
  else
  begin
    Result.Name := Copy(AText, 1, P - 1);
    Result.Host := Copy(AText, P + 1, MaxInt);
  end;
end;

function MyAttr(const AKey, ACaption, AHint: string; AKind: TpgnAttrKind; const AValue: string): TpgnAccountAttr;
begin
  Result := Default(TpgnAccountAttr);
  Result.Key := AKey;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Kind := AKind;
  Result.Value := AValue;
end;

const
  MyTlsChoices: array[0..2] of string = ('No', 'TLS', 'TLS with a client certificate (X509)');

function TpgnMySQLAdapter.AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs;
var
  R: TpgnResultSet;
  Full: Boolean;
  W, Tls: string;
  I, B: Integer;

  procedure Add(const AAttr: TpgnAccountAttr);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AAttr;
  end;

  function NoLimit(const AValue: string): string;
  begin
    if AValue = '0' then
    begin
      Result := '';
    end
    else
    begin
      Result := AValue;
    end;
  end;

begin
  Result := nil;
  W := ' FROM mysql.user WHERE User = ' + QuoteLiteral(AAccount.Name) + ' AND Host = ' +
    QuoteLiteral(AAccount.Host);
  Full := True;
  try
    R := MetaResult('SELECT max_questions, max_updates, max_connections, max_user_connections, ssl_type, ' +
      'IF(account_locked = ''Y'', ''1'', ''0''), IF(password_expired = ''Y'', ''1'', ''0''), ' +
      'IFNULL(password_lifetime, '''')' + W, []);
  except
    on E: Exception do
    begin
      // older servers: no locking or password lifetime
      Full := False;
      R := MetaResult('SELECT max_questions, max_updates, max_connections, max_user_connections, ssl_type' +
        W, []);
    end;
  end;
  try
    if R.RowCount = 0 then
    begin
      raise Exception.Create('Account ' + AccountText(AAccount) + ' no longer exists.');
    end;
    if Full then
    begin
      Add(MyAttr('locked', 'Account locked', 'Locked accounts cannot log in', akBool, R.Rows[0].Values[5]));
      Add(MyAttr('expired', 'Must change password at next login', '', akBool, R.Rows[0].Values[6]));
      if R.Rows[0].Values[6] = '1' then
      begin
        // only a new password clears it
        Result[High(Result)].ReadOnly := True;
        Result[High(Result)].Hint := 'Cleared when a new password is set';
      end;
      Add(MyAttr('lifetime', 'Password lifetime (days)', 'Empty: the server''s default; 0: never expires',
        akInt, R.Rows[0].Values[7]));
    end;
    Add(MyAttr('maxuserconn', 'Connections at once', 'Empty or 0: no limit', akInt, NoLimit(R.Rows[0].Values[3])));
    Add(MyAttr('maxconn', 'Connections per hour', 'Empty or 0: no limit', akInt, NoLimit(R.Rows[0].Values[2])));
    Add(MyAttr('maxqueries', 'Queries per hour', 'Empty or 0: no limit', akInt, NoLimit(R.Rows[0].Values[0])));
    Add(MyAttr('maxupdates', 'Updates per hour', 'Empty or 0: no limit', akInt, NoLimit(R.Rows[0].Values[1])));
    Tls := UpperCase(R.Rows[0].Values[4]);
    Add(MyAttr('tls', 'Requires TLS', '', akChoice, ''));
    SetLength(Result[High(Result)].Choices, Length(MyTlsChoices));
    for I := 0 to High(MyTlsChoices) do
    begin
      Result[High(Result)].Choices[I] := MyTlsChoices[I];
    end;
    if Tls = 'ANY' then
    begin
      B := 1;
    end
    else if Tls = 'X509' then
    begin
      B := 2;
    end
    else
    begin
      B := 0;
    end;
    Result[High(Result)].Value := MyTlsChoices[B];
    if Tls = 'SPECIFIED' then
    begin
      Result[High(Result)].Value := 'A specific certificate';
      Result[High(Result)].ReadOnly := True;
      Result[High(Result)].Hint := 'Set with REQUIRE ISSUER/SUBJECT/CIPHER; change it in SQL';
    end;
  finally
    R.Free;
  end;
end;

function TpgnMySQLAdapter.AlterAccountSQL(const AAccount: TpgnAccount;
  const AOld, ANew: TpgnAccountAttrs): TpgnStringArray;
var
  I, N: Integer;
  K, V, A: string;

  procedure Add(const AStatement: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'ALTER USER ' + A + ' ' + AStatement;
  end;

  function Num(const ACaption: string): Integer;
  begin
    if V = '' then
    begin
      Result := 0;
    end
    else if not TryStrToInt(V, Result) or (Result < 0) then
    begin
      raise Exception.Create(ACaption + ' must be a whole number.');
    end;
  end;

begin
  Result := nil;
  A := Acct(AAccount);
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
    else if K = 'lifetime' then
    begin
      if V = '' then
      begin
        Add('PASSWORD EXPIRE DEFAULT');
      end
      else
      begin
        N := Num(ANew[I].Caption);
        if N = 0 then
        begin
          Add('PASSWORD EXPIRE NEVER');
        end
        else
        begin
          Add('PASSWORD EXPIRE INTERVAL ' + IntToStr(N) + ' DAY');
        end;
      end;
    end
    else if K = 'maxuserconn' then
    begin
      Add('WITH MAX_USER_CONNECTIONS ' + IntToStr(Num(ANew[I].Caption)));
    end
    else if K = 'maxconn' then
    begin
      Add('WITH MAX_CONNECTIONS_PER_HOUR ' + IntToStr(Num(ANew[I].Caption)));
    end
    else if K = 'maxqueries' then
    begin
      Add('WITH MAX_QUERIES_PER_HOUR ' + IntToStr(Num(ANew[I].Caption)));
    end
    else if K = 'maxupdates' then
    begin
      Add('WITH MAX_UPDATES_PER_HOUR ' + IntToStr(Num(ANew[I].Caption)));
    end
    else if K = 'tls' then
    begin
      if V = MyTlsChoices[1] then
      begin
        Add('REQUIRE SSL');
      end
      else if V = MyTlsChoices[2] then
      begin
        Add('REQUIRE X509');
      end
      else
      begin
        Add('REQUIRE NONE');
      end;
    end;
  end;
end;

function TpgnMySQLAdapter.CreateAccountSQL(const AAccount: TpgnAccount;
  const APassword: string): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  if AAccount.IsRole then
  begin
    Result[0] := 'CREATE ROLE ' + Acct(AAccount);
  end
  else if APassword <> '' then
  begin
    Result[0] := 'CREATE USER ' + Acct(AAccount) + ' IDENTIFIED BY ' + QuoteLiteral(APassword);
  end
  else
  begin
    Result[0] := 'CREATE USER ' + Acct(AAccount);
  end;
end;

function TpgnMySQLAdapter.PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string;
begin
  Result := 'ALTER USER ' + Acct(AAccount) + ' IDENTIFIED BY ' + QuoteLiteral(APassword);
end;

function TpgnMySQLAdapter.AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
  if HasRoles then
  begin
    Result := MetaResult('SELECT CONCAT(FROM_USER, ''@'', FROM_HOST) AS `Role`, ' +
      'IF(WITH_ADMIN_OPTION = ''Y'', ''yes'', '''') AS `Can pass on` FROM mysql.role_edges ' +
      'WHERE TO_USER = ' + QuoteLiteral(AAccount.Name) + ' AND TO_HOST = ' + QuoteLiteral(AAccount.Host) +
      ' ORDER BY 1', []);
  end;
end;

function TpgnMySQLAdapter.AccountMembers(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
  if HasRoles then
  begin
    Result := MetaResult('SELECT CONCAT(TO_USER, ''@'', TO_HOST) AS `Member`, ' +
      'IF(WITH_ADMIN_OPTION = ''Y'', ''yes'', '''') AS `Can pass on` FROM mysql.role_edges ' +
      'WHERE FROM_USER = ' + QuoteLiteral(AAccount.Name) + ' AND FROM_HOST = ' + QuoteLiteral(AAccount.Host) +
      ' ORDER BY 1', []);
  end;
end;

{ A granted role does nothing in MySQL until it's active, so it's also
  made a default role (active at login). }
function TpgnMySQLAdapter.GrantRoleSQL(const ARole, AMember: TpgnAccount;
  AAdmin: Boolean): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := 'GRANT ' + Acct(ARole) + ' TO ' + Acct(AMember);
  if AAdmin then
  begin
    Result[0] := Result[0] + ' WITH ADMIN OPTION';
  end;
  Result[1] := 'SET DEFAULT ROLE ALL TO ' + Acct(AMember);
end;

function TpgnMySQLAdapter.RevokeRoleSQL(const ARole, AMember: TpgnAccount): string;
begin
  Result := 'REVOKE ' + Acct(ARole) + ' FROM ' + Acct(AMember);
end;

function TpgnMySQLAdapter.AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet;
const
  Can = 'IF(IS_GRANTABLE = ''YES'', ''yes'', '''') AS `Can grant`, '''' AS `Granted by`';

  function BQ(const ACol: string): string;
  begin
    Result := 'CONCAT(''`'', REPLACE(' + ACol + ', ''`'', ''``''), ''`'')';
  end;

var
  G, Who, Base, Routines: string;
begin
  G := QuoteLiteral('''' + AAccount.Name + '''@''' + AAccount.Host + '''');
  Base :=
    'SELECT ''*.*'' AS `Object`, ''global'' AS `Type`, PRIVILEGE_TYPE AS `Privilege`, ' + Can +
    ' FROM information_schema.USER_PRIVILEGES WHERE GRANTEE = ' + G + ' AND PRIVILEGE_TYPE <> ''USAGE''' +
    ' UNION ALL SELECT CONCAT(' + BQ('TABLE_SCHEMA') + ', ''.*''), ''database'', PRIVILEGE_TYPE, ' + Can +
    ' FROM information_schema.SCHEMA_PRIVILEGES WHERE GRANTEE = ' + G +
    ' UNION ALL SELECT CONCAT(' + BQ('TABLE_SCHEMA') + ', ''.'', ' + BQ('TABLE_NAME') + '), ''table'', ' +
    'PRIVILEGE_TYPE, ' + Can + ' FROM information_schema.TABLE_PRIVILEGES WHERE GRANTEE = ' + G +
    ' UNION ALL SELECT CONCAT(' + BQ('TABLE_SCHEMA') + ', ''.'', ' + BQ('TABLE_NAME') + ', '' ('', ' +
    BQ('COLUMN_NAME') + ', '')''), ''column'', PRIVILEGE_TYPE, ' + Can +
    ' FROM information_schema.COLUMN_PRIVILEGES WHERE GRANTEE = ' + G;
  Who := 'User = ' + QuoteLiteral(AAccount.Name) + ' AND Host = ' + QuoteLiteral(AAccount.Host);
  Routines :=
    ' UNION ALL SELECT CONCAT(' + BQ('Db') + ', ''.'', ' + BQ('Routine_name') + '), LOWER(Routine_type), ' +
    '''EXECUTE'', IF(FIND_IN_SET(''Grant'', Proc_priv) > 0, ''yes'', ''''), Grantor FROM mysql.procs_priv ' +
    'WHERE ' + Who + ' AND FIND_IN_SET(''Execute'', Proc_priv) > 0' +
    ' UNION ALL SELECT CONCAT(' + BQ('Db') + ', ''.'', ' + BQ('Routine_name') + '), LOWER(Routine_type), ' +
    '''ALTER ROUTINE'', IF(FIND_IN_SET(''Grant'', Proc_priv) > 0, ''yes'', ''''), Grantor FROM mysql.procs_priv ' +
    'WHERE ' + Who + ' AND FIND_IN_SET(''Alter Routine'', Proc_priv) > 0';
  try
    Result := MetaResult('SELECT * FROM (' + Base + Routines + ') x ORDER BY 2, 1, 3', []);
  except
    on E: Exception do
    begin
      // no access to mysql.procs_priv: everything but routine grants
      Result := MetaResult('SELECT * FROM (' + Base + ') x ORDER BY 2, 1, 3', []);
    end;
  end;
end;

{ "ON `db`.`t`" for a privilege row; a column row adds "(`c`)" before ON. }
function MyGrantTarget(const AObject, AType, APrivilege: string): string;
var
  P: Integer;
begin
  if AType = 'column' then
  begin
    P := Pos(' (', AObject);
    Result := APrivilege + ' ' + Copy(AObject, P + 1, MaxInt) + ' ON ' + Copy(AObject, 1, P - 1);
  end
  else if (AType = 'procedure') or (AType = 'function') then
  begin
    Result := APrivilege + ' ON ' + UpperCase(AType) + ' ' + AObject;
  end
  else
  begin
    Result := APrivilege + ' ON ' + AObject;
  end;
end;

function TpgnMySQLAdapter.RevokePrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string): string;
begin
  Result := 'REVOKE ' + MyGrantTarget(AObject, AType, APrivilege) + ' FROM ' + Acct(AAccount);
end;

function TpgnMySQLAdapter.GrantPrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string; AGrantOption: Boolean): string;
begin
  Result := 'GRANT ' + MyGrantTarget(AObject, AType, APrivilege) + ' TO ' + Acct(AAccount);
  if AGrantOption then
  begin
    Result := Result + ' WITH GRANT OPTION';
  end;
end;

{ SHOW CREATE USER without the password hash, then SHOW GRANTS. }
function TpgnMySQLAdapter.AccountDDL(const AAccount: TpgnAccount): string;
var
  L: TpgnStringArray;
  S: string;
  I, P1, P2: Integer;
begin
  Result := '-- ' + AccountText(AAccount) + ' (the password is not included)' + LineEnding;
  try
    L := MetaStrings('SHOW CREATE USER ' + Acct(AAccount), []);
    if Length(L) > 0 then
    begin
      S := L[0];
      P1 := Pos(' AS ''', S);
      P2 := Pos(' REQUIRE ', S);
      if (P1 > 0) and (P2 > P1) then
      begin
        S := Copy(S, 1, P1 - 1) + Copy(S, P2, MaxInt);
      end;
      Result := Result + S + ';' + LineEnding;
    end;
  except
    on E: Exception do
    begin
      Result := Result + '-- SHOW CREATE USER: ' + E.Message + LineEnding;
    end;
  end;
  L := MetaStrings('SHOW GRANTS FOR ' + Acct(AAccount), []);
  Result := Result + LineEnding;
  for I := 0 to High(L) do
  begin
    Result := Result + L[I] + ';' + LineEnding;
  end;
end;

{ SHOW GRANTS of AFrom, each pointed at ATo. }
function TpgnMySQLAdapter.CopyAccessSQL(const AFrom, ATo: TpgnAccount): TpgnStringArray;
var
  L: TpgnStringArray;
  I, P, W: Integer;
  S, Rest: string;
  Roles: Boolean;
begin
  Result := nil;
  Roles := False;
  L := MetaStrings('SHOW GRANTS FOR ' + Acct(AFrom), []);
  for I := 0 to High(L) do
  begin
    S := L[I];
    if (Pos('GRANT USAGE ON *.* TO', S) = 1) or (Pos('GRANT PROXY', S) = 1) then
    begin
      Continue;
    end;
    P := Length(S) - 3;
    while (P > 0) and (Copy(S, P, 4) <> ' TO ') do
    begin
      Dec(P);
    end;
    if P = 0 then
    begin
      Continue;
    end;
    Rest := Copy(S, P + 4, MaxInt);
    W := Pos(' WITH ', Rest);
    if W > 0 then
    begin
      Rest := Copy(Rest, W, MaxInt);
    end
    else
    begin
      Rest := '';
    end;
    if Pos(' ON ', Copy(S, 1, P)) = 0 then
    begin
      Roles := True;   // GRANT role TO account
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(S, 1, P - 1) + ' TO ' + Acct(ATo) + Rest;
  end;
  if Roles then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := 'SET DEFAULT ROLE ALL TO ' + Acct(ATo);
  end;
end;

function TpgnMySQLAdapter.AccountOwns(const AAccount: TpgnAccount): TpgnResultSet;
var
  D: string;
begin
  D := QuoteLiteral(AAccount.Name + '@' + AAccount.Host);
  Result := MetaResult('SELECT * FROM (' +
    'SELECT CONCAT(ROUTINE_SCHEMA, ''.'', ROUTINE_NAME) AS `Object`, LOWER(ROUTINE_TYPE) AS `Type`, ' +
    'ROUTINE_SCHEMA AS `Where` FROM information_schema.ROUTINES WHERE DEFINER = ' + D +
    ' UNION ALL SELECT CONCAT(TABLE_SCHEMA, ''.'', TABLE_NAME), ''view'', TABLE_SCHEMA ' +
    'FROM information_schema.VIEWS WHERE DEFINER = ' + D +
    ' UNION ALL SELECT CONCAT(TRIGGER_SCHEMA, ''.'', TRIGGER_NAME), ''trigger'', TRIGGER_SCHEMA ' +
    'FROM information_schema.TRIGGERS WHERE DEFINER = ' + D +
    ' UNION ALL SELECT CONCAT(EVENT_SCHEMA, ''.'', EVENT_NAME), ''event'', EVENT_SCHEMA ' +
    'FROM information_schema.EVENTS WHERE DEFINER = ' + D +
    ') x ORDER BY 3, 2, 1', []);
end;

function TpgnMySQLAdapter.DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
  ADropOwned: Boolean): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := 'DROP USER ' + Acct(AAccount);
end;

{ From SHOW GRANTS of the login itself. A granted role may carry the
  right, so with any role granted the answer is "can't tell". }
function TpgnMySQLAdapter.MissingRight(const AAction: string): string;
var
  L: TpgnStringArray;
  I: Integer;
  S: string;
  Has, Roles: Boolean;
begin
  Result := '';
  if (AAction <> 'kill') and (AAction <> 'accounts') then
  begin
    Exit;
  end;
  try
    L := MetaStrings('SHOW GRANTS', []);
  except
    on E: Exception do
    begin
      Exit;
    end;
  end;
  Has := False;
  Roles := False;
  for I := 0 to High(L) do
  begin
    S := UpperCase(L[I]);
    if Pos(' ON ', S) = 0 then
    begin
      Roles := True;   // GRANT role TO login
    end
    else if Pos(' ON *.* ', S) > 0 then
    begin
      if Pos('ALL PRIVILEGES', S) > 0 then
      begin
        Has := True;
      end;
      if (AAction = 'kill') and ((Pos('SUPER', S) > 0) or (Pos('CONNECTION_ADMIN', S) > 0)) then
      begin
        Has := True;
      end;
      if (AAction = 'accounts') and (Pos('CREATE USER', S) > 0) then
      begin
        Has := True;
      end;
    end;
  end;
  if not Has and not Roles and (Length(L) > 0) then
  begin
    if AAction = 'kill' then
    begin
      Result := 'Needs CONNECTION_ADMIN or SUPER (your own sessions are fine)';
    end
    else
    begin
      Result := 'Needs the CREATE USER privilege to change accounts';
    end;
  end;
end;

procedure TpgnMySQLAdapter.RunAdmin(const ASQL: string);
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

function TpgnMySQLAdapter.GrantTargets: TpgnStringArray;
begin
  Result := WordList('database table procedure function global');
end;

function TpgnMySQLAdapter.GrantTargetCaption(const AKind: string): string;
begin
  if AKind = 'database' then
  begin
    Result := 'A whole database (all its tables and code)';
  end
  else if AKind = 'table' then
  begin
    Result := 'A table or view';
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
    Result := 'Everything on the server (*.*)';
  end;
end;

function TpgnMySQLAdapter.GrantContainerCaption(const AKind: string): string;
begin
  if AKind = 'global' then
  begin
    Result := '';
  end
  else
  begin
    Result := 'Database';
  end;
end;

{ The server's own databases can't be granted on (information_schema,
  performance_schema) or shouldn't be from here (mysql, sys). }
function TpgnMySQLAdapter.GrantContainers(const AKind: string): TpgnStringArray;
var
  All: TpgnStringArray;
  I, N: Integer;
  D: string;
begin
  Result := nil;
  All := ListDatabases;
  SetLength(Result, Length(All));
  N := 0;
  for I := 0 to High(All) do
  begin
    D := LowerCase(All[I]);
    if (D <> 'information_schema') and (D <> 'performance_schema') and (D <> 'mysql') and (D <> 'sys') then
    begin
      Result[N] := All[I];
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function TpgnMySQLAdapter.GrantNeedsObject(const AKind: string): Boolean;
begin
  Result := (AKind = 'table') or (AKind = 'procedure') or (AKind = 'function');
end;

function TpgnMySQLAdapter.GrantObjects(const AKind, AContainer: string): TpgnStringArray;
begin
  if AKind = 'table' then
  begin
    Result := MetaStrings('SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = :p0 ' +
      'ORDER BY TABLE_NAME', [AContainer]);
  end
  else if (AKind = 'procedure') or (AKind = 'function') then
  begin
    Result := MetaStrings('SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = :p0 ' +
      'AND ROUTINE_TYPE = :p1 ORDER BY ROUTINE_NAME', [AContainer, UpperCase(AKind)]);
  end
  else
  begin
    Result := nil;
  end;
end;

{ In the form the Privileges tab shows: *.*, `db`.*, `db`.`name`. }
function TpgnMySQLAdapter.GrantObjectText(const AKind, AContainer, AName: string): string;
begin
  if AKind = 'global' then
  begin
    Result := '*.*';
  end
  else if AKind = 'database' then
  begin
    Result := QuoteIdent(AContainer) + '.*';
  end
  else
  begin
    Result := QuoteIdent(AContainer) + '.' + QuoteIdent(AName);
  end;
end;

function TpgnMySQLAdapter.GrantPrivileges(const AKind: string): TpgnStringArray;
const
  DataWords = 'SELECT INSERT UPDATE DELETE CREATE DROP ALTER INDEX REFERENCES TRIGGER CREATE_VIEW SHOW_VIEW';
  CodeWords = ' EXECUTE CREATE_ROUTINE ALTER_ROUTINE EVENT CREATE_TEMPORARY_TABLES LOCK_TABLES';
begin
  if AKind = 'table' then
  begin
    Result := WordList(DataWords);
  end
  else if (AKind = 'procedure') or (AKind = 'function') then
  begin
    Result := WordList('EXECUTE ALTER_ROUTINE');
  end
  else if AKind = 'database' then
  begin
    Result := WordList(DataWords + CodeWords);
  end
  else
  begin
    Result := WordList(DataWords + CodeWords + ' PROCESS RELOAD SHOW_DATABASES REPLICATION_CLIENT ' +
      'REPLICATION_SLAVE CREATE_USER FILE');
  end;
end;


{ ------------------------------------------------------ who can do what }

{ From information_schema (a login sees the rows its privileges allow) and
  mysql.procs_priv for routines. Grants on the whole database or server
  count for every table in it. Roles are followed in mysql.role_edges. }
function TpgnMySQLAdapter.ObjectAccess(const AKind, AContainer, AName: string;
  AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet;
const
  Who = 'REPLACE(GRANTEE, '''''''', '''')';
  Can = 'IF(IS_GRANTABLE = ''YES'', ''yes'', '''')';
var
  Privs, Db, SQL: string;
  List: TpgnStringArray;
  I, J, K, Start: Integer;
  Edges: TpgnResultSet;
  Row: TpgnResultRow;
  Added: Boolean;

  function Member(const AUser, AHost: string): string;
  begin
    Result := AUser + '@' + AHost;
  end;

begin
  List := GrantPrivileges(AKind);
  Privs := '';
  for I := 0 to High(List) do
  begin
    if Privs <> '' then
    begin
      Privs := Privs + ', ';
    end;
    Privs := Privs + QuoteLiteral(List[I]);
  end;
  Db := QuoteLiteral(AContainer);
  SQL := 'SELECT ' + Who + ' AS `Who`, '''' AS `Kind`, PRIVILEGE_TYPE AS `Can do`, ' +
    '''whole server (*.*)'' AS `How`, ' + Can + ' AS `Can grant` FROM information_schema.USER_PRIVILEGES ' +
    'WHERE PRIVILEGE_TYPE IN (' + Privs + ')';
  if AKind = 'database' then
  begin
    SQL := SQL + ' UNION ALL SELECT ' + Who + ', '''', PRIVILEGE_TYPE, ''direct'', ' + Can +
      ' FROM information_schema.SCHEMA_PRIVILEGES WHERE TABLE_SCHEMA = ' + Db;
  end
  else
  begin
    SQL := SQL + ' UNION ALL SELECT ' + Who + ', '''', PRIVILEGE_TYPE, ' +
      'CONCAT(''whole database ('', TABLE_SCHEMA, ''.*)''), ' + Can +
      ' FROM information_schema.SCHEMA_PRIVILEGES WHERE TABLE_SCHEMA = ' + Db +
      ' AND PRIVILEGE_TYPE IN (' + Privs + ')';
  end;
  if AKind = 'table' then
  begin
    SQL := SQL + ' UNION ALL SELECT ' + Who + ', '''', PRIVILEGE_TYPE, ''direct'', ' + Can +
      ' FROM information_schema.TABLE_PRIVILEGES WHERE TABLE_SCHEMA = ' + Db + ' AND TABLE_NAME = ' +
      QuoteLiteral(AName) +
      ' UNION ALL SELECT ' + Who + ', '''', PRIVILEGE_TYPE, CONCAT(''some columns ('', ' +
      'GROUP_CONCAT(COLUMN_NAME ORDER BY COLUMN_NAME SEPARATOR '', ''), '')''), MAX(' + Can + ') ' +
      'FROM information_schema.COLUMN_PRIVILEGES WHERE TABLE_SCHEMA = ' + Db + ' AND TABLE_NAME = ' +
      QuoteLiteral(AName) + ' GROUP BY GRANTEE, PRIVILEGE_TYPE';
  end;
  Result := nil;
  if (AKind = 'procedure') or (AKind = 'function') then
  begin
    try
      Result := MetaResult('SELECT * FROM (' + SQL +
        ' UNION ALL SELECT CONCAT(User, ''@'', Host), '''', ''EXECUTE'', ''direct'', ' +
        'IF(FIND_IN_SET(''Grant'', Proc_priv) > 0, ''yes'', '''') FROM mysql.procs_priv ' +
        'WHERE Db = ' + Db + ' AND Routine_name = ' + QuoteLiteral(AName) +
        ' AND Routine_type = ' + QuoteLiteral(UpperCase(AKind)) + ' AND FIND_IN_SET(''Execute'', Proc_priv) > 0' +
        ' UNION ALL SELECT CONCAT(User, ''@'', Host), '''', ''ALTER ROUTINE'', ''direct'', ' +
        'IF(FIND_IN_SET(''Grant'', Proc_priv) > 0, ''yes'', '''') FROM mysql.procs_priv ' +
        'WHERE Db = ' + Db + ' AND Routine_name = ' + QuoteLiteral(AName) +
        ' AND Routine_type = ' + QuoteLiteral(UpperCase(AKind)) +
        ' AND FIND_IN_SET(''Alter Routine'', Proc_priv) > 0) x ORDER BY 1, 3', []);
    except
      on E: Exception do
      begin
        Result := nil;   // no access to mysql.procs_priv: the rest still shows
      end;
    end;
  end;
  if Result = nil then
  begin
    Result := MetaResult('SELECT * FROM (' + SQL + ') x ORDER BY 1, 3', []);
  end;

  // through roles: everyone a role holder has been granted to, all the way down
  if AThroughRoles and HasRoles then
  begin
    try
      Edges := MetaResult('SELECT FROM_USER, FROM_HOST, TO_USER, TO_HOST FROM mysql.role_edges', []);
    except
      on E: Exception do
      begin
        Edges := nil;
      end;
    end;
    if Edges <> nil then
    begin
      try
        Start := 0;
        repeat
          Added := False;
          K := Result.RowCount;
          for I := Start to K - 1 do
          begin
            for J := 0 to Edges.RowCount - 1 do
            begin
              if Member(Edges.Rows[J].Values[0], Edges.Rows[J].Values[1]) = Result.Rows[I].Values[0] then
              begin
                Row := Default(TpgnResultRow);
                SetLength(Row.Values, 5);
                SetLength(Row.Nulls, 5);
                Row.Values[0] := Member(Edges.Rows[J].Values[2], Edges.Rows[J].Values[3]);
                Row.Values[1] := '';
                Row.Values[2] := Result.Rows[I].Values[2];
                if Pos('through role ', Result.Rows[I].Values[3]) = 1 then
                begin
                  Row.Values[3] := Result.Rows[I].Values[3];
                end
                else
                begin
                  Row.Values[3] := 'through role ' + Result.Rows[I].Values[0];
                end;
                Row.Values[4] := Result.Rows[I].Values[4];
                SetLength(Result.Rows, Length(Result.Rows) + 1);
                Result.Rows[High(Result.Rows)] := Row;
                Added := True;
              end;
            end;
          end;
          Start := K;
        until not Added or (Result.RowCount > 5000);
      finally
        Edges.Free;
      end;
    end;
  end;
end;

end.
