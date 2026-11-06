// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapter;

{ The database adapter contract. The UI only talks to TpgnAdapter, never to
  a specific driver, so adding Postgres, SQL Server or Oracle later means
  writing one new descendant class and registering it in pgnAdapters. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, pgnTypes;

type
  { Where in the Explorer a folder sits: under the connection, a database,
    a schema, or a table. }
  TpgnFolderLevel = (flServer, flDatabase, flSchema, flTable);

  TpgnAdapter = class;
  TpgnAdapterClass = class of TpgnAdapter;

  { "Container" below means what holds tables and code: the database in
    MySQL, the schema in PostgreSQL (within the adapter's own database). }
  TpgnAdapter = class
  protected
    FInfo: TpgnConnectionInfo;
    FPassword: string;
    FCurrentDatabase: string;
  public
    constructor Create(const AInfo: TpgnConnectionInfo; const APassword: string); virtual;

    procedure Connect; virtual; abstract;
    procedure Disconnect; virtual; abstract;
    function IsConnected: Boolean; virtual; abstract;

    { Metadata. Called on the main thread; adapters use a separate
      connection for this so the schema tree works while a query runs. }
    function ListDatabases: TpgnStringArray; virtual; abstract;
    function ListObjects(const ADatabase: string; AKind: TpgnObjectKind): TpgnStringArray; virtual; abstract;
    function DescribeTable(const ADatabase, ATable: string): TpgnResultSet; virtual; abstract;
    function GetDDL(const ADatabase, AObject: string; AKind: TpgnObjectKind): string; virtual; abstract;

    { Every table, view, procedure and function name in ADatabase, for the
      editor to color. The base version lists tables and views. }
    function ListObjectNames(const ADatabase: string): TpgnStringArray; virtual;

    { Objects whose names contain AText (any case), across every database
      the login can see, at most AMax. The base version finds nothing. }
    function SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs; virtual;

    { A table's indexes, one row per indexed column; nil if the engine
      can't say. }
    function DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet; virtual;

    { --- The Describe window (F4 / Alt+F1) }

    { The object a name in the editor means, found as the database would
      find it. AName may be container.name (quotes allowed); ADefault is
      the tab's database or schema. AVia says how it was reached ('' or
      "via public synonym SPRIDEN"). The base version searches by name,
      preferring ADefault. }
    function ResolveObject(const AName, ADefault: string; out ARef: TpgnObjectRef;
      out AVia: string): Boolean; virtual;
    { A table's primary key, unique, foreign key and check constraints;
      nil if the engine can't say. }
    function DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet; virtual;
    { What depends on an object (views, code, foreign keys); nil if the
      engine can't say. }
    function DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet; virtual;
    { What an object reads (tables, views, other code); nil if the engine
      can't say. }
    function DescribeUses(const ADatabase, AName: string): TpgnResultSet; virtual;
    { A function or procedure called as AName (name, pkg.name,
      schema.name or schema.pkg.name), looked up from ADefault's schema:
      its signature, status and what it reads. Never its source. }
    function DescribeRoutine(const AName, ADefault: string): TpgnRoutineInfo; virtual;
    { The source of an object the routine calls don't cover (an Oracle
      package: spec and body); '' if none. }
    function ObjectScript(const ADatabase, AName, AKind: string): string; virtual;

    { --- Code objects: procedures, functions, triggers. The base versions
      say the engine can't do it (empty lists, nil results, an error on
      save); each engine's adapter fills them in. }

    function ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray; virtual;
    { The full CREATE statement as the server keeps it; '' when the login
      may not see the body (the definition is then read-only). }
    function GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; virtual;
    function RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean; virtual;
    { Mode, Parameter, Type; a function's return type is a RETURNS row. }
    function DescribeParameters(const ADatabase, AName: string): TpgnResultSet; virtual;
    { The triggers on a table: Trigger, Timing, Event. }
    function DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet; virtual;
    { Who holds which rights on an object. AObjectWord is TABLE, VIEW,
      PROCEDURE or FUNCTION. Raises if the login can't read them. }
    function DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet; virtual;
    { Replaces (or, with AOldName = '', creates) a routine from ASQL, one
      CREATE statement, safely: see the engine's notes. Adds what it did to
      ALog. Raises with a plain explanation when it can't; the database is
      then left as it was. }
    function SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
      const ASQL: string; ALog: TStrings): string; virtual;
    { (Returns the name the routine was saved under, as ListRoutines
      would list it; '' leaves it to the caller.) }

    { --- The engine's shape. }

    { How this engine writes SQL. }
    function Dialect: TpgnDialect; virtual;
    { True when containers are schemas inside databases (PostgreSQL). }
    function HasSchemas: Boolean; virtual;
    { True when a session can only see one database, so each database
      needs a session of its own (PostgreSQL). }
    function SessionPerDatabase: Boolean; virtual;
    { The schemas of the session's database: the user's, or (ASystem) the
      system catalogs. }
    function ListSchemas(ASystem: Boolean): TpgnStringArray; virtual;
    { The schema unqualified names are looked up in; '' if none. }
    function CurrentSchema: string; virtual;
    { Every schema unqualified names are looked up in, in order (PostgreSQL's
      search_path, the schemas that exist); nil where there's no such list. }
    function SearchPath: TpgnStringArray; virtual;
    procedure UseSchema(const ASchema: string); virtual;
    { A new, connected session like this one on another database. }
    function NewSession(const ADatabase: string): TpgnAdapter; virtual;

    { Extra Explorer folders at a level, by name ("Sequences"). AMore:
      the rarely used ones, kept together in a "More" folder. }
    function ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray; virtual;
    { The items in an extra folder (AContainer is '' at server and
      database level; the table at table level is AContainer.ATable). }
    function ListFolder(const AContainer, AFolder: string): TpgnStringArray; virtual;
    { A definition to show for an item of an extra folder; '' if none. }
    function FolderItemSQL(const AContainer, AFolder, AName: string): string; virtual;
    { True when a table opens to Columns / Indexes / Triggers folders
      instead of straight to its columns. }
    function TableFolders: Boolean; virtual;

    { --- Writing SQL for the Explorer's forms and menus. }

    { The routine as written to call it: `db`.`name`, schema.name. }
    function RoutineTarget(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; virtual;
    function DropRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string; virtual;
    { A statement that lists a table's columns (MySQL: DESCRIBE). }
    function DescribeSQL(const ADatabase, ATable: string): string; virtual;
    function QuoteLiteral(const AText: string): string; virtual;
    { A CREATE statement for a new procedure or function, ready to fill in. }
    function NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs; const AReturns: string): string; virtual;
    function NewTriggerSQL(const ADatabase, ATable: string): string; virtual;
    { What to run to execute a routine with these values. }
    function ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
      const AParams: TpgnParamDefs): string; virtual;
    { What can be granted on a TABLE, VIEW, PROCEDURE or FUNCTION. }
    function GrantRights(const AObjectWord: string): TpgnStringArray; virtual;
    { The grantee field's label: who can be named, and how. }
    function GranteeHint: string; virtual;
    function GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
      AWithGrantOption: Boolean): string; virtual;

    { --- DBA: who is connected, and who is waiting on whom. Read on the
      metadata session; the database's privileges decide what shows. }

    { Session, User, Machine, Program, Database, State, Time, Statement,
      Note ("this tab" for this adapter's own sessions). }
    function ListSessions: TpgnResultSet; virtual;
    { Waiting, Waiting user, Waiting for, Blocked by, Blocker user,
      Blocker state, Blocker time, Head of chain, Object, Waiting
      statement, Blocker statement. Empty when nobody is waiting. }
    function ListLocks: TpgnResultSet; virtual;
    { The full statement a session is running (or last ran). }
    function SessionStatement(const ASession: string): string; virtual;
    { Stops what a session is running / ends the session. Each returns
      the statement it ran, for the DBA log. }
    function CancelSession(const ASession: string): string; virtual;
    function KillSession(const ASession: string): string; virtual;

    { --- DBA: users and roles. Read and written on the metadata session.
      The *SQL functions only write statements; RunAdmin runs them. A
      password goes into the SQL as given: callers pass '****' to get the
      version that may be shown or logged. }

    { Accounts have a host part (MySQL user@host). }
    function AccountsHaveHost: Boolean; virtual;
    { The server has roles that can be granted (grayed out when not). }
    function HasRoles: Boolean; virtual;
    function ListAccounts(ASystem: Boolean): TpgnAccounts; virtual;
    { As people write it: "reports@10.%" / "reports". }
    function AccountText(const AAccount: TpgnAccount): string; virtual;
    { The other way: an AccountText back into an account. }
    function AccountFromText(const AText: string): TpgnAccount; virtual;
    function AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs; virtual;
    { The statements that turn AOld into ANew (same keys, same order). }
    function AlterAccountSQL(const AAccount: TpgnAccount;
      const AOld, ANew: TpgnAccountAttrs): TpgnStringArray; virtual;
    function CreateAccountSQL(const AAccount: TpgnAccount; const APassword: string): TpgnStringArray; virtual;
    function PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string; virtual;
    { Role, Can pass on / Member, Can pass on. }
    function AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet; virtual;
    function AccountMembers(const AAccount: TpgnAccount): TpgnResultSet; virtual;
    function GrantRoleSQL(const ARole, AMember: TpgnAccount; AAdmin: Boolean): TpgnStringArray; virtual;
    function RevokeRoleSQL(const ARole, AMember: TpgnAccount): string; virtual;
    { Object, Type, Privilege, Can grant, Granted by. }
    function AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet; virtual;
    function RevokePrivilegeSQL(const AAccount: TpgnAccount;
      const AObject, AType, APrivilege: string): string; virtual;
    function GrantPrivilegeSQL(const AAccount: TpgnAccount;
      const AObject, AType, APrivilege: string; AGrantOption: Boolean): string; virtual;
    { Granting: what a privilege can be granted on (keys such as 'table',
      also the Type shown on the Privileges tab), what holds those things
      (databases / schemas), the things themselves, and which privileges
      apply. GrantObjectText gives the object as GrantPrivilegeSQL wants it. }
    function GrantTargets: TpgnStringArray; virtual;
    function GrantTargetCaption(const AKind: string): string; virtual;
    { 'Database' or 'Schema'; '' when AKind needs no container. }
    function GrantContainerCaption(const AKind: string): string; virtual;
    function GrantContainers(const AKind: string): TpgnStringArray; virtual;
    { False: the container (or nothing at all) is the object. }
    function GrantNeedsObject(const AKind: string): Boolean; virtual;
    function GrantObjects(const AKind, AContainer: string): TpgnStringArray; virtual;
    function GrantObjectText(const AKind, AContainer, AName: string): string; virtual;
    function GrantPrivileges(const AKind: string): TpgnStringArray; virtual;
    { Who Can Do What: everyone who can use one object (AKind, AContainer
      and AName as for granting). Columns: Who, Kind, Can do, How, Can
      grant. How is 'direct', 'through role X', 'whole database (db.*)',
      'whole server (*.*)', 'owner' or 'superuser'; Kind may be '' when the
      engine can't say cheaply (the screen fills it in). PUBLIC is not a
      row: PublicAccess says what everyone may do ('' = nothing). }
    function ObjectAccess(const AKind, AContainer, AName: string;
      AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet; virtual;
    function PublicAccess(const AKind, AContainer, AName: string): string; virtual;
    function RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string; virtual;
    { Everything needed to make the account again, passwords left out. }
    function AccountDDL(const AAccount: TpgnAccount): string; virtual;
    { The roles and object grants of AFrom, granted to ATo. }
    function CopyAccessSQL(const AFrom, ATo: TpgnAccount): TpgnStringArray; virtual;
    { What the account owns or is definer of: Object, Type, Where. }
    function AccountOwns(const AAccount: TpgnAccount): TpgnResultSet; virtual;
    { The engine can hand an account's objects to another (REASSIGN). }
    function CanReassignOwned: Boolean; virtual;
    { The engine can only drop an owner together with what it owns
      (Oracle's DROP USER ... CASCADE): the Drop dialog asks for that. }
    function DropOwnedChoice: Boolean; virtual;
    { AReassignTo: give what it owns to that account first; ADropOwned:
      remove what it still owns. }
    function DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
      ADropOwned: Boolean): TpgnStringArray; virtual;
    { '' when the login may do AAction, or can't be told; otherwise what it
      lacks, in words ("Needs the CREATE USER privilege"). Actions:
      'kill' (other users' sessions; one's own always work), 'accounts'
      (create, change and drop users and roles). Look-only screens never
      ask: anyone may look, the server shows what it allows. }
    function MissingRight(const AAction: string): string; virtual;
    { Runs one administrative statement on the metadata session. }
    procedure RunAdmin(const ASQL: string); virtual;

    { The server's version as the server reports it ("8.0.36"); '' if
      unknown. Read once at connect time. }
    function ServerVersion: string; virtual;
    { This session's id on the server (PostgreSQL's backend pid, MySQL's
      connection id, Oracle's SID); '' if unknown. Seattle's status bar. }
    function OwnSessionId: string; virtual;

    { Runs one statement. Called from the worker thread only. }
    function Execute(const ASQL: string; ARowLimit: Integer): TpgnResultSet; virtual; abstract;

    { Asks the server to stop the statement Execute is running.
      Called from the main thread while Execute is blocked. }
    procedure CancelCurrent; virtual; abstract;

    function QuoteIdent(const AName: string): string; virtual; abstract;

    { Makes ADatabase the session's current database (MySQL: USE).
      Called from the main thread, never while a query is running. }
    procedure UseDatabase(const ADatabase: string); virtual; abstract;

    { Transactions. With auto-commit off, changes stay pending until
      Commit or Rollback. Called from the main thread only. }
    { SQL for "select the first N rows". MySQL and PostgreSQL use LIMIT;
      engines with other syntax override this. }
    function SelectTopSQL(const AQualifiedName: string; ARows: Integer): string; virtual;

    procedure SetAutoCommit(AValue: Boolean); virtual; abstract;
    function AutoCommit: Boolean; virtual; abstract;
    procedure Commit; virtual; abstract;
    procedure Rollback; virtual; abstract;

    property Info: TpgnConnectionInfo read FInfo;

    { The session's current database, kept up to date by UseDatabase
      and by USE statements run through Execute. }
    property CurrentDatabase: string read FCurrentDatabase;
  end;

{ Copies an open dataset into a result set, stopping at ARowLimit rows
  (0 = no limit). Shared by every adapter that uses TDataSet-based drivers. }
{ container.name split in two, quotes taken off ("x", `x`, [x]). }
procedure SplitObjectName(const AName: string; out AContainer, AObject: string);
{ A name part without its quotes. }
function Unquoted(const S: string): string;
procedure DataSetToResult(ADataSet: TDataSet; ARowLimit: Integer; AResult: TpgnResultSet);

{ A session id as a number, so it can go into SQL safely; raises if not. }
function SessionNumber(const ASession: string): string;

implementation

constructor TpgnAdapter.Create(const AInfo: TpgnConnectionInfo; const APassword: string);
begin
  inherited Create;
  FInfo := AInfo;
  FPassword := APassword;
  FCurrentDatabase := AInfo.DefaultDatabase;
end;

function TpgnAdapter.ListObjectNames(const ADatabase: string): TpgnStringArray;
var
  Views: TpgnStringArray;
  I, N: Integer;
begin
  Result := ListObjects(ADatabase, okTable);
  Views := ListObjects(ADatabase, okView);
  N := Length(Result);
  SetLength(Result, N + Length(Views));
  for I := 0 to High(Views) do
  begin
    Result[N + I] := Views[I];
  end;
end;

function TpgnAdapter.SearchObjects(const AText: string; AMax: Integer): TpgnObjectRefs;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeIndexes(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := nil;
end;

{ A name part without its quotes: "x", `x` or [x]. }
function Unquoted(const S: string): string;
begin
  Result := Trim(S);
  if (Length(Result) >= 2) and (((Result[1] = '"') and (Result[Length(Result)] = '"')) or
    ((Result[1] = '`') and (Result[Length(Result)] = '`')) or
    ((Result[1] = '[') and (Result[Length(Result)] = ']'))) then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

{ Splits container.name (the last two parts of a longer name). }
procedure SplitObjectName(const AName: string; out AContainer, AObject: string);
var
  P: Integer;
begin
  P := LastDelimiter('.', AName);
  if P > 0 then
  begin
    AObject := Unquoted(Copy(AName, P + 1, MaxInt));
    AContainer := Copy(AName, 1, P - 1);
    P := LastDelimiter('.', AContainer);
    if P > 0 then
    begin
      AContainer := Copy(AContainer, P + 1, MaxInt);
    end;
    AContainer := Unquoted(AContainer);
  end
  else
  begin
    AContainer := '';
    AObject := Unquoted(AName);
  end;
end;

function TpgnAdapter.ResolveObject(const AName, ADefault: string; out ARef: TpgnObjectRef;
  out AVia: string): Boolean;
var
  Qual, N, C: string;
  Found: TpgnObjectRefs;
  I, Best: Integer;
begin
  Result := False;
  AVia := '';
  ARef.Database := '';
  ARef.Schema := '';
  ARef.Name := '';
  ARef.Kind := '';
  SplitObjectName(AName, Qual, N);
  if N = '' then
  begin
    Exit;
  end;
  Found := SearchObjects(N, 500);
  Best := -1;
  for I := 0 to High(Found) do
  begin
    if not SameText(Found[I].Name, N) then
    begin
      Continue;
    end;
    C := Found[I].Schema;
    if C = '' then
    begin
      C := Found[I].Database;
    end;
    if Qual <> '' then
    begin
      if SameText(C, Qual) or SameText(Found[I].Database, Qual) then
      begin
        Best := I;
        Break;
      end;
    end
    else
    begin
      if SameText(C, ADefault) then
      begin
        Best := I;
        Break;
      end;
      if Best < 0 then
      begin
        Best := I;
      end;
    end;
  end;
  if Best >= 0 then
  begin
    ARef := Found[Best];
    Result := True;
  end;
end;

function TpgnAdapter.DescribeConstraints(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeUsedBy(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeUses(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeRoutine(const AName, ADefault: string): TpgnRoutineInfo;
begin
  Result := Default(TpgnRoutineInfo);
  Result.Name := AName;
  Result.Note := 'Pagona can''t look this up for this database yet.';
end;

function TpgnAdapter.ObjectScript(const ADatabase, AName, AKind: string): string;
begin
  Result := '';
end;

function TpgnAdapter.ListRoutines(const ADatabase: string; AKind: TpgnRoutineKind): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.GetRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := '';
end;

function TpgnAdapter.RoutineExists(const ADatabase, AName: string; AKind: TpgnRoutineKind): Boolean;
begin
  Result := False;
end;

function TpgnAdapter.DescribeParameters(const ADatabase, AName: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeTriggers(const ADatabase, ATable: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.DescribeGrants(const ADatabase, AName, AObjectWord: string): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.SaveRoutine(const ADatabase, AOldName: string; AKind: TpgnRoutineKind;
  const ASQL: string; ALog: TStrings): string;
begin
  Result := '';
  raise Exception.Create('Saving procedures is not available for this database yet.');
end;

function TpgnAdapter.Dialect: TpgnDialect;
begin
  Result := sdMySQL;
end;

function TpgnAdapter.HasSchemas: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.SessionPerDatabase: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.ListSchemas(ASystem: Boolean): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.CurrentSchema: string;
begin
  Result := '';
end;

function TpgnAdapter.SearchPath: TpgnStringArray;
begin
  Result := nil;
end;

procedure TpgnAdapter.UseSchema(const ASchema: string);
begin
  // engines without schemas: nothing to do
end;

function TpgnAdapter.NewSession(const ADatabase: string): TpgnAdapter;
var
  I: TpgnConnectionInfo;
begin
  I := FInfo;
  I.DefaultDatabase := ADatabase;
  Result := TpgnAdapterClass(ClassType).Create(I, FPassword);
  try
    Result.Connect;
  except
    Result.Free;
    raise;
  end;
end;

function TpgnAdapter.ExtraFolders(ALevel: TpgnFolderLevel; AMore: Boolean): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.ListFolder(const AContainer, AFolder: string): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.FolderItemSQL(const AContainer, AFolder, AName: string): string;
begin
  Result := '';
end;

function TpgnAdapter.TableFolders: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.RoutineTarget(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := QuoteIdent(ADatabase) + '.' + QuoteIdent(AName);
end;

function TpgnAdapter.DropRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind): string;
begin
  Result := 'DROP ' + RoutineWord[AKind] + ' ' + RoutineTarget(ADatabase, AName, AKind);
end;

function TpgnAdapter.DescribeSQL(const ADatabase, ATable: string): string;
begin
  Result := 'DESCRIBE ' + QuoteIdent(ADatabase) + '.' + QuoteIdent(ATable);
end;

function TpgnAdapter.QuoteLiteral(const AText: string): string;
begin
  Result := '''' + StringReplace(AText, '''', '''''', [rfReplaceAll]) + '''';
end;

function TpgnAdapter.NewRoutineSQL(const AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs; const AReturns: string): string;
begin
  Result := '';
  raise Exception.Create('New procedures are not available for this database yet.');
end;

function TpgnAdapter.NewTriggerSQL(const ADatabase, ATable: string): string;
begin
  Result := '';
  raise Exception.Create('New triggers are not available for this database yet.');
end;

function TpgnAdapter.ExecuteRoutineSQL(const ADatabase, AName: string; AKind: TpgnRoutineKind;
  const AParams: TpgnParamDefs): string;
begin
  Result := '';
  raise Exception.Create('Running procedures is not available for this database yet.');
end;

function TpgnAdapter.GrantRights(const AObjectWord: string): TpgnStringArray;
begin
  Result := nil;
  if (AObjectWord = 'PROCEDURE') or (AObjectWord = 'FUNCTION') then
  begin
    SetLength(Result, 1);
    Result[0] := 'EXECUTE';
  end
  else
  begin
    SetLength(Result, 4);
    Result[0] := 'SELECT';
    Result[1] := 'INSERT';
    Result[2] := 'UPDATE';
    Result[3] := 'DELETE';
  end;
end;

function TpgnAdapter.GranteeHint: string;
begin
  Result := 'To (user or role)';
end;

function TpgnAdapter.ListSessions: TpgnResultSet;
begin
  Result := nil;
  raise Exception.Create('Sessions are not available for this database yet.');
end;

function TpgnAdapter.ListLocks: TpgnResultSet;
begin
  Result := nil;
  raise Exception.Create('Locks are not available for this database yet.');
end;

function TpgnAdapter.SessionStatement(const ASession: string): string;
begin
  Result := '';
end;

function TpgnAdapter.CancelSession(const ASession: string): string;
begin
  Result := '';
  raise Exception.Create('Canceling a session is not available for this database yet.');
end;

function TpgnAdapter.KillSession(const ASession: string): string;
begin
  Result := '';
  raise Exception.Create('Killing a session is not available for this database yet.');
end;

{ ------------------------------------------------------ users and roles }

procedure NotYet(const AWhat: string);
begin
  raise Exception.Create(AWhat + ' is not available for this database yet.');
end;

function TpgnAdapter.AccountsHaveHost: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.HasRoles: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.ListAccounts(ASystem: Boolean): TpgnAccounts;
begin
  Result := nil;
  NotYet('Users and Roles');
end;

function TpgnAdapter.AccountText(const AAccount: TpgnAccount): string;
begin
  Result := AAccount.Name;
  if AAccount.Host <> '' then
  begin
    Result := Result + '@' + AAccount.Host;
  end;
end;

function TpgnAdapter.AccountFromText(const AText: string): TpgnAccount;
begin
  Result := Default(TpgnAccount);
  Result.Name := AText;
end;

function TpgnAdapter.AccountAttrs(const AAccount: TpgnAccount): TpgnAccountAttrs;
begin
  Result := nil;
end;

function TpgnAdapter.AlterAccountSQL(const AAccount: TpgnAccount;
  const AOld, ANew: TpgnAccountAttrs): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.CreateAccountSQL(const AAccount: TpgnAccount; const APassword: string): TpgnStringArray;
begin
  Result := nil;
  NotYet('Creating accounts');
end;

function TpgnAdapter.PasswordSQL(const AAccount: TpgnAccount; const APassword: string): string;
begin
  Result := '';
  NotYet('Changing passwords');
end;

function TpgnAdapter.AccountMemberOf(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.AccountMembers(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.GrantRoleSQL(const ARole, AMember: TpgnAccount; AAdmin: Boolean): TpgnStringArray;
begin
  Result := nil;
  NotYet('Granting roles');
end;

function TpgnAdapter.RevokeRoleSQL(const ARole, AMember: TpgnAccount): string;
begin
  Result := '';
  NotYet('Revoking roles');
end;

function TpgnAdapter.AccountPrivileges(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.RevokePrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string): string;
begin
  Result := '';
  NotYet('Revoking privileges');
end;

function TpgnAdapter.GrantPrivilegeSQL(const AAccount: TpgnAccount;
  const AObject, AType, APrivilege: string; AGrantOption: Boolean): string;
begin
  Result := '';
  NotYet('Granting privileges');
end;

function TpgnAdapter.GrantTargets: TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.GrantTargetCaption(const AKind: string): string;
begin
  Result := AKind;
end;

function TpgnAdapter.GrantContainerCaption(const AKind: string): string;
begin
  Result := '';
end;

function TpgnAdapter.GrantContainers(const AKind: string): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.GrantNeedsObject(const AKind: string): Boolean;
begin
  Result := False;
end;

function TpgnAdapter.GrantObjects(const AKind, AContainer: string): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.GrantObjectText(const AKind, AContainer, AName: string): string;
begin
  Result := AName;
end;

function TpgnAdapter.GrantPrivileges(const AKind: string): TpgnStringArray;
begin
  Result := nil;
end;

function TpgnAdapter.ObjectAccess(const AKind, AContainer, AName: string;
  AThroughRoles, AOwners, ASystem: Boolean): TpgnResultSet;
begin
  Result := nil;
  NotYet('Who Can Do What');
end;

function TpgnAdapter.PublicAccess(const AKind, AContainer, AName: string): string;
begin
  Result := '';
end;

function TpgnAdapter.RevokePublicSQL(const AKind, AContainer, AName, APrivileges: string): string;
begin
  Result := '';
  NotYet('Revoking from PUBLIC');
end;

function TpgnAdapter.AccountDDL(const AAccount: TpgnAccount): string;
begin
  Result := '';
end;

{ Generic: every role it's a member of, then every object grant. }
function TpgnAdapter.CopyAccessSQL(const AFrom, ATo: TpgnAccount): TpgnStringArray;
var
  R: TpgnResultSet;
  I: Integer;

  procedure Add(const AStatement: string);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AStatement;
  end;

  procedure AddAll(const AList: TpgnStringArray);
  var
    J: Integer;
  begin
    for J := 0 to High(AList) do
    begin
      Add(AList[J]);
    end;
  end;

begin
  Result := nil;
  R := AccountMemberOf(AFrom);
  try
    if R <> nil then
    begin
      for I := 0 to R.RowCount - 1 do
      begin
        AddAll(GrantRoleSQL(AccountFromText(R.Rows[I].Values[0]), ATo, R.Rows[I].Values[1] = 'yes'));
      end;
    end;
  finally
    R.Free;
  end;
  R := AccountPrivileges(AFrom);
  try
    if R <> nil then
    begin
      for I := 0 to R.RowCount - 1 do
      begin
        Add(GrantPrivilegeSQL(ATo, R.Rows[I].Values[0], R.Rows[I].Values[1], R.Rows[I].Values[2],
          R.Rows[I].Values[3] = 'yes'));
      end;
    end;
  finally
    R.Free;
  end;
end;

function TpgnAdapter.AccountOwns(const AAccount: TpgnAccount): TpgnResultSet;
begin
  Result := nil;
end;

function TpgnAdapter.CanReassignOwned: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.DropOwnedChoice: Boolean;
begin
  Result := False;
end;

function TpgnAdapter.OwnSessionId: string;
begin
  Result := '';
end;

function TpgnAdapter.DropAccountSQL(const AAccount: TpgnAccount; const AReassignTo: string;
  ADropOwned: Boolean): TpgnStringArray;
begin
  Result := nil;
  NotYet('Dropping accounts');
end;

function TpgnAdapter.MissingRight(const AAction: string): string;
begin
  Result := '';
end;

procedure TpgnAdapter.RunAdmin(const ASQL: string);
begin
  NotYet('Changing accounts');
end;

{ A session id as a number, so it can go into SQL safely. }
function SessionNumber(const ASession: string): string;
var
  N: Int64;
begin
  if not TryStrToInt64(Trim(ASession), N) or (N <= 0) then
  begin
    raise Exception.Create('"' + ASession + '" is not a session number.');
  end;
  Result := IntToStr(N);
end;

function TpgnAdapter.GrantSQL(const ADatabase, AName, AObjectWord, AGrantee, ARights: string;
  AWithGrantOption: Boolean): string;
begin
  Result := '';
  raise Exception.Create('Granting is not available for this database yet.');
end;

function TpgnAdapter.ServerVersion: string;
begin
  Result := '';
end;

function TpgnAdapter.SelectTopSQL(const AQualifiedName: string; ARows: Integer): string;
begin
  Result := 'SELECT * FROM ' + AQualifiedName + ' LIMIT ' + IntToStr(ARows);
end;

procedure DataSetToResult(ADataSet: TDataSet; ARowLimit: Integer; AResult: TpgnResultSet);
var
  I, N, Cap, FieldCount: Integer;
  F: TField;
begin
  FieldCount := ADataSet.FieldCount;
  SetLength(AResult.Columns, FieldCount);
  for I := 0 to FieldCount - 1 do
  begin
    AResult.Columns[I] := ADataSet.Fields[I].FieldName;
  end;

  N := 0;
  Cap := 0;
  AResult.Rows := nil;
  while (not ADataSet.EOF) and ((ARowLimit <= 0) or (N < ARowLimit)) do
  begin
    if N >= Cap then
    begin
      if Cap = 0 then
      begin
        Cap := 256;
      end
      else
      begin
        Cap := Cap * 2;
      end;
      SetLength(AResult.Rows, Cap);
    end;

    SetLength(AResult.Rows[N].Values, FieldCount);
    SetLength(AResult.Rows[N].Nulls, FieldCount);
    for I := 0 to FieldCount - 1 do
    begin
      F := ADataSet.Fields[I];
      AResult.Rows[N].Nulls[I] := F.IsNull;
      if F.IsNull then
      begin
        AResult.Rows[N].Values[I] := '';
      end
      else if F.DataType in [ftBlob, ftGraphic, ftBytes, ftVarBytes, ftTypedBinary] then
      begin
        AResult.Rows[N].Values[I] := Format('(binary, %d bytes)', [Length(F.AsString)]);
      end
      else
      begin
        AResult.Rows[N].Values[I] := F.AsString;
      end;
    end;

    Inc(N);
    ADataSet.Next;
  end;

  SetLength(AResult.Rows, N);
  AResult.HasMoreRows := not ADataSet.EOF;
  AResult.ReturnsRows := True;
end;

end.
