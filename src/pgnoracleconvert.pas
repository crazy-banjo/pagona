// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnOracleConvert;

{ Oracle/PostgreSQL Compatibility: rewrites Oracle-only SQL as SQL that runs on both
  Oracle 19c and PostgreSQL, so a query can be checked on Oracle today and
  moved to PostgreSQL later as it is.

  Three kinds of rule:
    - same meaning, runs on both (on to start): (+) joins, NVL, NVL2,
      DECODE, ROWNUM limits, date +/- days, SYSDATE, SYSTIMESTAMP, CAST
      types, TO_NUMBER(x), names for subqueries in FROM;
    - could change what a query returns (off to start): quoting numbers
      compared with Banner's text codes, COALESCE in concatenation;
    - flags: Oracle forms with nothing both run (LISTAGG, TRUNC of a date,
      ADD_MONTHS, MINUS, FROM DUAL, sequences, CONNECT BY ...): the code is
      left as it is, so it still runs on Oracle, with the PostgreSQL form in
      a /* TODO PG: ... */ comment after it.

  Each statement is read on its own (the existing splitter, as Run reads
  them); PL/SQL blocks and SQL*Plus lines are left alone. Running it again
  on its own output changes nothing more. The result is not formatted. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, pgnTypes, pgnSqlFormat, pgnSqlSplit, pgnJoinConvert;

type
  TpgnConvRule = (
    // same meaning, runs on both
    crJoins, crNvl, crNvl2, crDecode, crRownum, crDateArith, crSysdate, crSystimestamp,
    crCastTypes, crToNumber, crSubAlias,
    // could change what a query returns
    crExplicit, crConcatNull,
    // PostgreSQL only: exact PostgreSQL forms (the result no longer runs on Oracle 19c)
    rpDual, rpListagg, rpMinus, rpSequence, rpRegexpReplace, rpInstr, rpSubstrRight, rpTruncDate,
    rpLastDay, rpNextDay,
    // flags
    cfListagg, cfTruncDate, cfAddMonths, cfMonthsBetween, cfLastDay, cfNextDay, cfDateMath,
    cfMinus, cfDual, cfSequence, cfConnectBy, cfRegexp, cfRegexpReplace, cfToChar, cfRownum,
    cfRowid, cfSysContext, cfInstr, cfSubstr, cfNvlTypes, cfFunctions, cfPlsql);
  TpgnConvRules = set of TpgnConvRule;
  TpgnConvGroup = (cgSame, cgChanges, cgPgOnly, cgFlag);
  TpgnRuleCounts = array[TpgnConvRule] of Integer;

  TpgnRuleInfo = record
    Caption: string;
    Group: TpgnConvGroup;
    Why: string;
  end;

  { A stored function or procedure the SQL calls. }
  TpgnConvFunc = record
    Name: string;          // as called, upper case (HACCINST1.FH_GET_NAME)
    Schema: string;        // its schema ('' when unknown)
    Calls: Integer;
    Info: TpgnRoutineInfo; // from the data dictionary (Found = False without a connection)
  end;

  { One thing done or marked, for the report. }
  TpgnConvFinding = record
    Rule: TpgnConvRule;
    Schema: string;
    Func: string;
    Text: string;          // the TODO PG text, the replacement, or what was done
  end;

  { Looks a function up (connected); False when there's no way to. }
  TpgnRoutineLookup = function(const AName: string; out AInfo: TpgnRoutineInfo): Boolean of object;

  { One conversion: what to do and, afterwards, what was found and done. }
  TpgnConvJob = class
  public
    Rules: TpgnConvRules;
    SkipSchemas: TStringList;     // schemas whose functions get no TODO PG note
    Columns: TpgnColumnLookup;    // may be nil
    Routines: TpgnRoutineLookup;  // may be nil
    // results
    Counts, Applied: TpgnRuleCounts;
    Funcs: array of TpgnConvFunc;
    Findings: array of TpgnConvFinding;
    Notes: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    function FuncIndex(const AName: string): Integer;
    { The schemas of the functions found, with how many calls each. }
    function SchemaCalls: TStringList;
    function AppliedIn(AGroup: TpgnConvGroup): Integer;
    function RoutineOf(const AName: string; out AInfo: TpgnRoutineInfo): Boolean;
  end;

const
  TodoPG = '/* TODO PG: ';

function RuleInfo(ARule: TpgnConvRule): TpgnRuleInfo;

{ The rules on to start: everything but the ones that could change what a
  query returns and the PostgreSQL only ones. }
function DefaultConvRules: TpgnConvRules;

{ Converts AText as AJob says; AJob gets what was found (Counts, whether or
  not the rule is on), done (Applied), the functions called, the findings
  and notes. }
function ConvertOracleToAnsi(const AText: string; AJob: TpgnConvJob): string;

implementation

const
  PgOnlyWhy = 'The exact PostgreSQL form: the result no longer runs on Oracle 19c.';
  FlagWhy = 'Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), ' +
    'with the PostgreSQL form in a /* TODO PG */ comment.';

function RuleInfo(ARule: TpgnConvRule): TpgnRuleInfo;

  procedure SetR(const ACaption: string; AGroup: TpgnConvGroup; const AWhy: string);
  begin
    Result.Caption := ACaption;
    Result.Group := AGroup;
    Result.Why := AWhy;
  end;

begin
  case ARule of
    crJoins:
      begin
        SetR('(+) outer joins → LEFT JOIN ... ON', cgSame, 'Filters on the optional table move into ON; ' +
          'a block it can''t rewrite faithfully is left with a TODO PG note.');
      end;
    crNvl:
      begin
        SetR('NVL → COALESCE', cgSame, '');
      end;
    crNvl2:
      begin
        SetR('NVL2 → CASE', cgSame, '');
      end;
    crDecode:
      begin
        SetR('DECODE → CASE', cgSame, 'A NULL search becomes IS NULL, since DECODE matches NULL to NULL.');
      end;
    crRownum:
      begin
        SetR('WHERE ROWNUM <= n → FETCH FIRST n ROWS ONLY', cgSame, 'Only where it means the same: no ' +
          'ORDER BY, GROUP BY, DISTINCT or aggregate in that query (Oracle applies ROWNUM before those).');
      end;
    crDateArith:
      begin
        SetR('date ± n → date ± INTERVAL ''n'' DAY', cgSame, 'Whole days up to 99 (Oracle needs DAY(3) ' +
          'for more, which PostgreSQL won''t read).');
      end;
    crSysdate:
      begin
        SetR('SYSDATE → LOCALTIMESTAMP', cgSame, 'The date and time now. Left as SYSDATE where a date is ' +
          'subtracted from it (that''s flagged).');
      end;
    crSystimestamp:
      begin
        SetR('SYSTIMESTAMP → CURRENT_TIMESTAMP', cgSame, '');
      end;
    crCastTypes:
      begin
        SetR('CAST(... AS VARCHAR2 / NUMBER) → VARCHAR / NUMERIC', cgSame, '');
      end;
    crToNumber:
      begin
        SetR('TO_NUMBER(x) → CAST(x AS NUMERIC)', cgSame, 'PostgreSQL''s to_number needs a format.');
      end;
    crSubAlias:
      begin
        SetR('Names for subqueries in FROM', cgSame, 'PostgreSQL before 16 requires one.');
      end;
    crExplicit:
      begin
        SetR('Quote numbers compared with _CODE and _ID columns', cgChanges, 'Banner''s _CODE and _ID ' +
          'columns are text: Oracle converts 202640 for you, PostgreSQL stops with an error. Quoted, ' +
          '''01'' no longer matches ''1''.');
      end;
    crConcatNull:
      begin
        SetR('COALESCE(x, '''') in || concatenation', cgChanges, 'Oracle skips a NULL in a || b; ' +
          'PostgreSQL makes the whole string NULL. Columns and text functions are wrapped (not columns ' +
          'named like numbers or dates); a number wrapped this way fails on Oracle too: Run Both shows it.');
      end;
    cfListagg:
      begin
        SetR('Mark LISTAGG', cgFlag, FlagWhy);
      end;
    cfTruncDate:
      begin
        SetR('Mark TRUNC of a date', cgFlag, FlagWhy);
      end;
    cfAddMonths:
      begin
        SetR('Mark ADD_MONTHS', cgFlag, FlagWhy + ' At month end they differ: Oracle''s Apr 30 + 1 is May 31.');
      end;
    cfMonthsBetween:
      begin
        SetR('Mark MONTHS_BETWEEN', cgFlag, FlagWhy + ' The PG form counts whole months; Oracle gives fractions.');
      end;
    cfLastDay:
      begin
        SetR('Mark LAST_DAY', cgFlag, FlagWhy);
      end;
    cfNextDay:
      begin
        SetR('Mark NEXT_DAY', cgFlag, FlagWhy);
      end;
    cfDateMath:
      begin
        SetR('Mark date arithmetic to check', cgFlag, 'date - date (days in Oracle, an interval in PG), more ' +
          'than 99 days, or fractions of a day: left as it is, with the PG form in a TODO PG comment.');
      end;
    cfMinus:
      begin
        SetR('Mark MINUS', cgFlag, FlagWhy + ' Oracle has EXCEPT from 21c.');
      end;
    cfDual:
      begin
        SetR('Mark FROM DUAL', cgFlag, FlagWhy + ' PG has no DUAL; Oracle 19c needs a FROM.');
      end;
    cfSequence:
      begin
        SetR('Mark sequences', cgFlag, FlagWhy);
      end;
    cfConnectBy:
      begin
        SetR('Mark CONNECT BY', cgFlag, FlagWhy);
      end;
    cfRegexp:
      begin
        SetR('Mark REGEXP_SUBSTR / INSTR / COUNT / LIKE', cgFlag, 'The same functions exist in ' +
          'PostgreSQL 15 and later; flagged until the PG version is known.');
      end;
    cfRegexpReplace:
      begin
        SetR('Mark REGEXP_REPLACE', cgFlag, 'Oracle replaces every match; ' +
          'PostgreSQL only the first unless given ''g''.');
      end;
    cfToChar:
      begin
        SetR('Mark TO_CHAR / TO_DATE formats', cgFlag, 'No format (PG needs one), RR (PG has none), or an NLS ' +
          'parameter.');
      end;
    cfRownum:
      begin
        SetR('Mark ROWNUM that can''t convert', cgFlag, 'ROWNUM in a query with ORDER BY, GROUP BY or DISTINCT, ' +
          'or outside a WHERE limit: PG has no ROWNUM.');
      end;
    cfRowid:
      begin
        SetR('Mark ROWID', cgFlag, FlagWhy);
      end;
    cfSysContext:
      begin
        SetR('Mark SYS_CONTEXT / USERENV', cgFlag, FlagWhy);
      end;
    cfFunctions:
      begin
        SetR('Mark stored functions', cgFlag, 'One note per function per statement, at its first call, ' +
          'grouped by schema: PostgreSQL needs its own version of each.');
      end;
    cfInstr:
      begin
        SetR('Mark INSTR', cgFlag, 'PostgreSQL has no INSTR (strpos, without a start or occurrence).');
      end;
    cfSubstr:
      begin
        SetR('Mark SUBSTR from the end, or of a date', cgFlag, 'A negative start counts from the end ' +
          'in Oracle, not in PostgreSQL; SUBSTR of a date depends on Oracle''s date format.');
      end;
    cfNvlTypes:
      begin
        SetR('Mark NVL with two types', cgFlag, 'NVL converts one side to the other''s type; COALESCE ' +
          'needs both the same, on Oracle too. Left as NVL.');
      end;
    rpDual:
      begin
        SetR('Remove FROM DUAL', cgPgOnly, PgOnlyWhy);
      end;
    rpListagg:
      begin
        SetR('LISTAGG → string_agg', cgPgOnly, PgOnlyWhy + ' Text values only: a number needs CAST(x AS TEXT).');
      end;
    rpMinus:
      begin
        SetR('MINUS → EXCEPT', cgPgOnly, PgOnlyWhy);
      end;
    rpSequence:
      begin
        SetR('seq.NEXTVAL → nextval(''seq'')', cgPgOnly, PgOnlyWhy);
      end;
    rpRegexpReplace:
      begin
        SetR('REGEXP_REPLACE → regexp_replace(..., ''g'')', cgPgOnly, PgOnlyWhy + ' Replaces every match, ' +
          'as Oracle does.');
      end;
    rpInstr:
      begin
        SetR('INSTR(x, y) → strpos(x, y)', cgPgOnly, PgOnlyWhy);
      end;
    rpSubstrRight:
      begin
        SetR('SUBSTR(x, -n) → right(x, n)', cgPgOnly, PgOnlyWhy + ' NULL when x is shorter than n, as in ' +
          'Oracle.');
      end;
    rpTruncDate:
      begin
        SetR('TRUNC(date) → date_trunc', cgPgOnly, PgOnlyWhy + ' Day, month, year, quarter, hour, minute ' +
          'and ISO week; other week formats stay marked.');
      end;
    rpLastDay:
      begin
        SetR('LAST_DAY → date_trunc + interval', cgPgOnly, PgOnlyWhy + ' Keeps the time of day, as Oracle ' +
          'does.');
      end;
    rpNextDay:
      begin
        SetR('NEXT_DAY → date + days', cgPgOnly, PgOnlyWhy + ' English day names; keeps the time of day.');
      end;
    cfPlsql:
      begin
        SetR('Mark PL/SQL blocks', cgFlag, 'Left alone: PostgreSQL needs them rewritten in PL/pgSQL.');
      end;
  end;
end;

function DefaultConvRules: TpgnConvRules;
var
  R: TpgnConvRule;
begin
  Result := [];
  for R := Low(TpgnConvRule) to High(TpgnConvRule) do
  begin
    if RuleInfo(R).Group in [cgSame, cgFlag] then
    begin
      Include(Result, R);
    end;
  end;
end;


{ ------------------------------------------------------------ the job }

constructor TpgnConvJob.Create;
begin
  inherited Create;
  SkipSchemas := TStringList.Create;
  SkipSchemas.CaseSensitive := False;
  Notes := TStringList.Create;
  Rules := DefaultConvRules;
end;

destructor TpgnConvJob.Destroy;
begin
  SkipSchemas.Free;
  Notes.Free;
  inherited Destroy;
end;

procedure TpgnConvJob.Reset;
var
  R: TpgnConvRule;
begin
  for R := Low(TpgnConvRule) to High(TpgnConvRule) do
  begin
    Counts[R] := 0;
    Applied[R] := 0;
  end;
  Funcs := nil;
  Findings := nil;
  Notes.Clear;
end;

function TpgnConvJob.FuncIndex(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Funcs) do
  begin
    if SameText(Funcs[I].Name, AName) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnConvJob.SchemaCalls: TStringList;
var
  I, K: Integer;
  Sch: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.CaseSensitive := False;
  for I := 0 to High(Funcs) do
  begin
    Sch := Funcs[I].Schema;
    K := Result.IndexOf(Sch);
    if K < 0 then
    begin
      K := Result.AddObject(Sch, TObject(PtrInt(0)));
    end;
    Result.Objects[K] := TObject(PtrInt(Result.Objects[K]) + Funcs[I].Calls);
  end;
end;

function TpgnConvJob.AppliedIn(AGroup: TpgnConvGroup): Integer;
var
  R: TpgnConvRule;
begin
  Result := 0;
  for R := Low(TpgnConvRule) to High(TpgnConvRule) do
  begin
    if RuleInfo(R).Group = AGroup then
    begin
      Inc(Result, Applied[R]);
    end;
  end;
end;

function TpgnConvJob.RoutineOf(const AName: string; out AInfo: TpgnRoutineInfo): Boolean;
begin
  AInfo := Default(TpgnRoutineInfo);
  Result := Assigned(Routines) and Routines(AName, AInfo);
end;

type
  TArg = record
    A, B: Integer;   // first and last token
  end;
  TArgs = array of TArg;

  TEditRec = record
    A, B: Integer;   // characters A..B replaced (B = A - 1: insert before A)
    Text: string;
  end;

  { One statement: its text, tokens and paren depths. }
  TStmt = class
  public
    Job: TpgnConvJob;
    S: string;
    T: TpgnToks;
    Depth: array of Integer;
    SubN: Integer;
    procedure Load(const AText: string);
    function Nx(I: Integer): Integer;
    function Pv(I: Integer): Integer;
    function U(I: Integer): string;
    function IsWord(I: Integer): Boolean;
    function IsInt(I: Integer): Boolean;
    function CloseOf(I: Integer): Integer;
    function OpenOf(I: Integer): Integer;
    function ArgsOf(AOpen: Integer): TArgs;
    function Src(A, B: Integer): string;
    function IsCall(I: Integer; const AName: string): Boolean;
    function Marked(K: Integer): Boolean;
    function OperandStart(E: Integer): Integer;
    function OperandEnd(B: Integer): Integer;
    function IsOperandEnd(I: Integer): Boolean;
    function IsDateLike(A, B: Integer): Boolean;
    function Flag(K: Integer; const APg: string; out AEd: TEditRec): Boolean;
    function Replace(A, B: Integer; const AText: string; out AEd: TEditRec): Boolean;
    function RownumCheck(I: Integer; out AEd: TEditRec; out AWhy: string): Integer;
    function TryRule(R: TpgnConvRule; I: Integer; out AEd: TEditRec): Boolean;
    function FuncAt(I: Integer; out AName, ASchema: string; out AInfo: TpgnRoutineInfo): Boolean;
    function ArgKind(const AArg: TArg): Char;
    function NvlMixed(I: Integer): Boolean;
    function EndIncl(K: Integer): Integer;
  end;

procedure TStmt.Load(const AText: string);
var
  I, D: Integer;
begin
  S := AText;
  T := Tokenize(S, sdOracle);
  SetLength(Depth, Length(T));
  D := 0;
  for I := 0 to High(T) do
  begin
    if (T[I].Kind = tkSymbol) and (T[I].Text = '(') then
    begin
      Depth[I] := D;
      Inc(D);
    end
    else if (T[I].Kind = tkSymbol) and (T[I].Text = ')') then
    begin
      Dec(D);
      Depth[I] := D;
    end
    else
    begin
      Depth[I] := D;
    end;
  end;
end;

function IsCommentTok(const ATok: TpgnTok): Boolean;
begin
  Result := ATok.Kind in [tkLineComment, tkBlockComment];
end;

function TStmt.Nx(I: Integer): Integer;
begin
  Result := -1;
  if I < 0 then
  begin
    Exit;
  end;
  Inc(I);
  while (I <= High(T)) and IsCommentTok(T[I]) do
  begin
    Inc(I);
  end;
  if I <= High(T) then
  begin
    Result := I;
  end;
end;

function TStmt.Pv(I: Integer): Integer;
begin
  Result := -1;
  if I < 0 then
  begin
    Exit;
  end;
  Dec(I);
  while (I >= 0) and IsCommentTok(T[I]) do
  begin
    Dec(I);
  end;
  Result := I;
end;

function TStmt.U(I: Integer): string;
begin
  if (I < 0) or (I > High(T)) then
  begin
    Result := '';
  end
  else if T[I].Kind = tkWord then
  begin
    Result := T[I].Up;
  end
  else if T[I].Kind in [tkSymbol, tkNumber] then
  begin
    Result := T[I].Text;
  end
  else
  begin
    Result := #1;   // never equals a word or symbol
  end;
end;

function TStmt.IsWord(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I <= High(T)) and (T[I].Kind = tkWord) and (Copy(T[I].Text, 1, 1) <> ':');
end;

function TStmt.IsInt(I: Integer): Boolean;
var
  K: Integer;
begin
  Result := (I >= 0) and (I <= High(T)) and (T[I].Kind = tkNumber);
  if not Result then
  begin
    Exit;
  end;
  for K := 1 to Length(T[I].Text) do
  begin
    if not (T[I].Text[K] in ['0'..'9']) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function TStmt.CloseOf(I: Integer): Integer;
var
  K: Integer;
begin
  Result := -1;
  if (I < 0) or (U(I) <> '(') then
  begin
    Exit;
  end;
  for K := I + 1 to High(T) do
  begin
    if (U(K) = ')') and (Depth[K] = Depth[I]) then
    begin
      Result := K;
      Exit;
    end;
  end;
end;

function TStmt.OpenOf(I: Integer): Integer;
var
  K: Integer;
begin
  Result := -1;
  if (I < 0) or (U(I) <> ')') then
  begin
    Exit;
  end;
  for K := I - 1 downto 0 do
  begin
    if (U(K) = '(') and (Depth[K] = Depth[I]) then
    begin
      Result := K;
      Exit;
    end;
  end;
end;

function TStmt.ArgsOf(AOpen: Integer): TArgs;
var
  C, K, Start, N: Integer;
begin
  Result := nil;
  C := CloseOf(AOpen);
  if (C < 0) or (Nx(AOpen) = C) then
  begin
    Exit;
  end;
  N := 0;
  Start := Nx(AOpen);
  for K := Start to C - 1 do
  begin
    if (U(K) = ',') and (Depth[K] = Depth[AOpen] + 1) then
    begin
      SetLength(Result, N + 1);
      Result[N].A := Start;
      Result[N].B := Pv(K);
      Inc(N);
      Start := Nx(K);
    end;
  end;
  SetLength(Result, N + 1);
  Result[N].A := Start;
  Result[N].B := Pv(C);
end;

function TStmt.Src(A, B: Integer): string;
begin
  if (A < 0) or (B < A) then
  begin
    Result := '';
  end
  else
  begin
    Result := Copy(S, T[A].StartPos, T[B].EndPos - T[A].StartPos + 1);
  end;
end;

function TStmt.IsCall(I: Integer; const AName: string): Boolean;
begin
  Result := IsWord(I) and (T[I].Up = AName) and (U(Nx(I)) = '(') and (U(Pv(I)) <> '.');
end;

{ True when token K is already followed by a TODO PG comment. }
function TStmt.Marked(K: Integer): Boolean;
begin
  Result := (K + 1 <= High(T)) and (T[K + 1].Kind = tkBlockComment) and
    (Copy(T[K + 1].Text, 1, Length(TodoPG)) = TodoPG);
end;

function TStmt.Flag(K: Integer; const APg: string; out AEd: TEditRec): Boolean;
begin
  Result := (K >= 0) and not Marked(K);
  if Result then
  begin
    AEd.A := T[K].EndPos + 1;
    AEd.B := T[K].EndPos;
    AEd.Text := ' ' + TodoPG + StringReplace(APg, '*/', '* /', [rfReplaceAll]) + ' */';
  end;
end;

function TStmt.Replace(A, B: Integer; const AText: string; out AEd: TEditRec): Boolean;
begin
  AEd.A := T[A].StartPos;
  AEd.B := T[B].EndPos;
  AEd.Text := AText;
  Result := True;
end;

{ The first token of the operand ending at E: a column (a.b), a call
  (f(...), pkg.f(...)), a parenthesis, a literal (DATE '...'). }
function TStmt.OperandStart(E: Integer): Integer;
var
  M, P: Integer;
begin
  Result := E;
  if E < 0 then
  begin
    Exit;
  end;
  if U(E) = ')' then
  begin
    M := OpenOf(E);
    Result := M;
    P := Pv(M);
    if IsWord(P) and not IsSqlKeyword(T[P].Up) then
    begin
      Result := P;
    end;
  end
  else if (T[E].Kind = tkString) and (U(Pv(E)) = 'DATE') then
  begin
    Result := Pv(E);
    Exit;
  end;
  while (U(Pv(Result)) = '.') and IsWord(Pv(Pv(Result))) do
  begin
    Result := Pv(Pv(Result));
  end;
end;

function TStmt.OperandEnd(B: Integer): Integer;
var
  K: Integer;
begin
  Result := B;
  if B < 0 then
  begin
    Exit;
  end;
  if U(B) = '(' then
  begin
    Result := CloseOf(B);
    Exit;
  end;
  if (U(B) = 'DATE') and (Nx(B) >= 0) and (T[Nx(B)].Kind = tkString) then
  begin
    Result := Nx(B);
    Exit;
  end;
  if IsWord(B) then
  begin
    K := B;
    while (U(Nx(K)) = '.') and IsWord(Nx(Nx(K))) do
    begin
      K := Nx(Nx(K));
    end;
    if (U(Nx(K)) = '(') and not IsSqlKeyword(T[K].Up) then
    begin
      K := CloseOf(Nx(K));
    end;
    Result := K;
  end;
end;

{ True when token I ends an operand (so a following - is binary). }
function TStmt.IsOperandEnd(I: Integer): Boolean;
begin
  Result := (I >= 0) and ((T[I].Kind in [tkNumber, tkString, tkQuoted]) or (U(I) = ')') or
    (IsWord(I) and not IsSqlKeyword(T[I].Up)));
end;

function EndsWith(const S, ATail: string): Boolean;
begin
  Result := (Length(S) >= Length(ATail)) and (Copy(S, Length(S) - Length(ATail) + 1, MaxInt) = ATail);
end;

function IsTextFunction(const AUp: string): Boolean;
begin
  Result := (AUp = 'SUBSTR') or (AUp = 'TRIM') or (AUp = 'LTRIM') or (AUp = 'RTRIM') or (AUp = 'UPPER') or
    (AUp = 'LOWER') or (AUp = 'INITCAP') or (AUp = 'LPAD') or (AUp = 'RPAD') or (AUp = 'REPLACE') or
    (AUp = 'TO_CHAR') or (AUp = 'SUBSTRING') or (AUp = 'TRANSLATE');
end;

function TStmt.IsDateLike(A, B: Integer): Boolean;
var
  W: string;
  Args: TArgs;
  K: Integer;
begin
  Result := False;
  if (A < 0) or (B < A) then
  begin
    Exit;
  end;
  if (A = B) and IsWord(A) then
  begin
    W := T[A].Up;
    Result := (W = 'SYSDATE') or (W = 'LOCALTIMESTAMP') or (W = 'CURRENT_DATE') or
      (W = 'CURRENT_TIMESTAMP') or (W = 'SYSTIMESTAMP') or EndsWith(W, '_DATE');
    Exit;
  end;
  if (U(A) = 'DATE') and (T[B].Kind = tkString) and (Nx(A) = B) then
  begin
    Result := True;
    Exit;
  end;
  if IsWord(B) and (U(Pv(B)) = '.') then
  begin
    Result := EndsWith(T[B].Up, '_DATE');
    Exit;
  end;
  if (U(B) = ')') and IsWord(A) and (U(Nx(A)) = '(') and (CloseOf(Nx(A)) = B) then
  begin
    W := T[A].Up;
    if (W = 'TO_DATE') or (W = 'TO_TIMESTAMP') or (W = 'ADD_MONTHS') or (W = 'LAST_DAY') or
      (W = 'NEXT_DAY') then
    begin
      Result := True;
    end
    else if W = 'TRUNC' then
    begin
      Args := ArgsOf(Nx(A));
      if Length(Args) = 2 then
      begin
        Result := T[Args[1].A].Kind = tkString;
      end
      else if Length(Args) = 1 then
      begin
        Result := IsDateLike(Args[0].A, Args[0].B);
      end;
    end;
    Exit;
  end;
  // (SELECT x_date FROM ...): the one value it selects
  if (U(A) = '(') and (CloseOf(A) = B) and (U(Nx(A)) = 'SELECT') then
  begin
    for K := Nx(A) + 1 to B - 1 do
    begin
      if (Depth[K] = Depth[A] + 1) and (U(K) = 'FROM') then
      begin
        if (Pv(K) > Nx(A)) and (OperandEnd(Nx(Nx(A))) = Pv(K)) then
        begin
          Result := IsDateLike(Nx(Nx(A)), Pv(K));
        end;
        Exit;
      end;
    end;
    Exit;
  end;
  if (U(A) = '(') and (CloseOf(A) = B) and (OperandEnd(Nx(A)) = Pv(B)) then
  begin
    Result := IsDateLike(Nx(A), Pv(B));
  end;
end;

{ Oracle's own functions, never looked up as stored ones. }
function IsBuiltinFunc(const W: string): Boolean;
const
  Names: array[0..89] of string = ('ABS', 'ADD_MONTHS', 'AGE', 'CURRVAL', 'NEXTVAL', 'ASCII', 'AVG', 'BITAND', 'CAST', 'CEIL',
    'CHR', 'COALESCE', 'CONCAT', 'COUNT', 'CUME_DIST', 'CURRENT_DATE', 'CURRENT_TIMESTAMP', 'DATE_TRUNC',
    'DECODE', 'DENSE_RANK', 'DUMP', 'EXP', 'EXTRACT', 'FIRST_VALUE', 'FLOOR', 'GREATEST', 'HEXTORAW',
    'INITCAP', 'INSTR', 'LAG', 'LAST_DAY', 'LAST_VALUE', 'LEAD', 'LEAST', 'LENGTH', 'LISTAGG', 'LN',
    'LOCALTIMESTAMP', 'LOG', 'LOWER', 'LPAD', 'LTRIM', 'MAKE_INTERVAL', 'MAX', 'MEDIAN', 'MIN', 'MOD',
    'MONTHS_BETWEEN', 'NEXT_DAY', 'NTILE', 'NULLIF', 'NUMTODSINTERVAL', 'NUMTOYMINTERVAL', 'NVL', 'NVL2',
    'PERCENT_RANK', 'POWER', 'RANK', 'RATIO_TO_REPORT', 'RAWTOHEX', 'REGEXP_COUNT', 'REGEXP_INSTR',
    'REGEXP_LIKE', 'REGEXP_REPLACE', 'REGEXP_SUBSTR', 'REPLACE', 'RIGHT', 'ROUND', 'ROW_NUMBER', 'RPAD',
    'RTRIM', 'SIGN', 'SOUNDEX', 'SQRT', 'STDDEV', 'STRING_AGG', 'STRPOS', 'SUBSTR', 'SUM', 'SYS_CONTEXT',
    'TO_CHAR', 'TO_CLOB', 'TO_DATE', 'TO_NUMBER', 'TO_TIMESTAMP', 'TRANSLATE', 'TRIM', 'TRUNC', 'UPPER',
    'VARIANCE');
var
  K: Integer;
begin
  Result := False;
  for K := Low(Names) to High(Names) do
  begin
    if Names[K] = W then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ A call to a stored function at I (its name's last part): pkg.f(, schema.f(,
  schema.pkg.f(, or a name the data dictionary knows (without a connection,
  Banner's F_ names). }
function TStmt.FuncAt(I: Integer; out AName, ASchema: string; out AInfo: TpgnRoutineInfo): Boolean;
var
  K: Integer;
  W: string;
begin
  Result := False;
  AName := '';
  ASchema := '';
  AInfo := Default(TpgnRoutineInfo);
  if not IsWord(I) or (U(Nx(I)) <> '(') or IsSqlKeyword(T[I].Up) then
  begin
    Exit;
  end;
  if (U(Pv(I)) = '.') and IsWord(Pv(Pv(I))) then
  begin
    K := OperandStart(I);
    AName := UpperCase(StringReplace(Src(K, I), ' ', '', [rfReplaceAll]));
    if Job.RoutineOf(AName, AInfo) and AInfo.Found then
    begin
      ASchema := AInfo.Owner;
    end
    else
    begin
      ASchema := Copy(AName, 1, Pos('.', AName) - 1);
    end;
    Result := True;
    Exit;
  end;
  if U(Pv(I)) = '.' then
  begin
    Exit;
  end;
  W := T[I].Up;
  if IsBuiltinFunc(W) then
  begin
    Exit;
  end;
  if Job.RoutineOf(W, AInfo) then
  begin
    // looked up: the data dictionary decides
    if AInfo.Found then
    begin
      AName := W;
      ASchema := AInfo.Owner;
      Result := True;
    end;
  end
  else if Copy(W, 1, 2) = 'F_' then
  begin
    AName := W;
    Result := True;
  end;
end;

{ N number literal, S text literal, D date, T text from a function, n a
  number from a function, F a stored function of unknown type, U unknown. }
function TStmt.ArgKind(const AArg: TArg): Char;
var
  Nm, Sch, RT: string;
  Info: TpgnRoutineInfo;
  K: Integer;
begin
  Result := 'U';
  if ((AArg.A = AArg.B) and (T[AArg.A].Kind = tkNumber)) or
    ((Nx(AArg.A) = AArg.B) and (U(AArg.A) = '-') and (T[AArg.B].Kind = tkNumber)) then
  begin
    Result := 'N';
    Exit;
  end;
  if (AArg.A = AArg.B) and (T[AArg.A].Kind = tkString) then
  begin
    Result := 'S';
    Exit;
  end;
  if IsDateLike(AArg.A, AArg.B) then
  begin
    Result := 'D';
    Exit;
  end;
  if (U(AArg.B) = ')') and (OperandStart(AArg.B) = AArg.A) then
  begin
    K := Pv(OpenOf(AArg.B));
    if FuncAt(K, Nm, Sch, Info) then
    begin
      Result := 'F';
      if Info.Found then
      begin
        RT := UpperCase(Info.ReturnType);
        if (Pos('CHAR', RT) > 0) or (Pos('CLOB', RT) > 0) then
        begin
          Result := 'T';
        end
        else if (Pos('NUMBER', RT) > 0) or (Pos('INTEGER', RT) > 0) or (Pos('FLOAT', RT) > 0) or
          (Pos('BINARY', RT) > 0) or (Pos('DECIMAL', RT) > 0) then
        begin
          Result := 'n';
        end
        else if (Pos('DATE', RT) > 0) or (Pos('TIMESTAMP', RT) > 0) then
        begin
          Result := 'D';
        end
        else
        begin
          Result := 'U';
        end;
      end;
    end
    else if IsWord(K) and IsTextFunction(T[K].Up) then
    begin
      Result := 'T';
    end;
  end;
end;

{ NVL(a, b) whose two sides are plainly different types (or a number
  against a stored function whose type isn't known). }
function TStmt.NvlMixed(I: Integer): Boolean;
var
  Args: TArgs;
  K1, K2: Char;

  function Mix(X, Y: Char): Boolean;
  begin
    Result := ((X in ['N', 'n']) and (Y in ['S', 'T'])) or ((X = 'D') and (Y in ['N', 'n', 'S', 'T'])) or
      ((X = 'F') and (Y = 'N'));
  end;

begin
  Result := False;
  Args := ArgsOf(Nx(I));
  if Length(Args) <> 2 then
  begin
    Exit;
  end;
  K1 := ArgKind(Args[0]);
  K2 := ArgKind(Args[1]);
  Result := Mix(K1, K2) or Mix(K2, K1);
end;

{ K, or the TODO PG comment right after it (a replacement takes it too). }
function TStmt.EndIncl(K: Integer): Integer;
begin
  Result := K;
  if Marked(K) then
  begin
    Result := K + 1;
  end;
end;

function TruncUnit(const AFmt: string): string;
var
  F: string;
begin
  F := UpperCase(StringReplace(AFmt, '''', '', [rfReplaceAll]));
  if (F = 'MM') or (F = 'MON') or (F = 'MONTH') or (F = 'RM') then
  begin
    Result := 'month';
  end
  else if (F = 'YYYY') or (F = 'YEAR') or (F = 'YYY') or (F = 'YY') or (F = 'Y') or (F = 'SYYYY') or
    (F = 'SYEAR') then
  begin
    Result := 'year';
  end
  else if F = 'Q' then
  begin
    Result := 'quarter';
  end
  else if (F = 'DD') or (F = 'DDD') or (F = 'J') then
  begin
    Result := 'day';
  end
  else if (F = 'HH') or (F = 'HH12') or (F = 'HH24') then
  begin
    Result := 'hour';
  end
  else if F = 'MI' then
  begin
    Result := 'minute';
  end
  else if (F = 'IW') or (F = 'WW') or (F = 'W') or (F = 'D') or (F = 'DAY') or (F = 'DY') then
  begin
    Result := 'week';
  end
  else
  begin
    Result := '';
  end;
end;

function DayNumber(const ALit: string): Integer;
var
  D: string;
begin
  D := Copy(UpperCase(StringReplace(ALit, '''', '', [rfReplaceAll])), 1, 3);
  if D = 'SUN' then
  begin
    Result := 0;
  end
  else if D = 'MON' then
  begin
    Result := 1;
  end
  else if D = 'TUE' then
  begin
    Result := 2;
  end
  else if D = 'WED' then
  begin
    Result := 3;
  end
  else if D = 'THU' then
  begin
    Result := 4;
  end
  else if D = 'FRI' then
  begin
    Result := 5;
  end
  else if D = 'SAT' then
  begin
    Result := 6;
  end
  else
  begin
    Result := -1;
  end;
end;

{ ROWNUM at I: 1 = a WHERE limit that converts (AEd), -1 = can't
  (AWhy), 0 = not ROWNUM. }
function TStmt.RownumCheck(I: Integer; out AEd: TEditRec; out AWhy: string): Integer;
var
  D, K, Sel, BlockEnd, Op, V, CondStart, CondEnd, Before, AfterC, RemStart, RemEnd, N: Integer;
  W, Rest: string;
  InWhere, Reversed: Boolean;
begin
  Result := 0;
  AWhy := '';
  if not IsWord(I) or (T[I].Up <> 'ROWNUM') or (U(Pv(I)) = '.') then
  begin
    Exit;
  end;
  Result := -1;
  D := Depth[I];
  Sel := -1;
  for K := I - 1 downto 0 do
  begin
    if Depth[K] < D then
    begin
      Break;
    end;
    if (Depth[K] = D) and (U(K) = 'SELECT') then
    begin
      Sel := K;
      Break;
    end;
  end;
  if Sel < 0 then
  begin
    AWhy := 'ROWNUM outside a query';
    Exit;
  end;
  BlockEnd := -1;
  for K := I + 1 to High(T) do
  begin
    if Depth[K] < D then
    begin
      BlockEnd := Pv(K);
      Break;
    end;
    if (Depth[K] = D) and ((U(K) = 'UNION') or (U(K) = 'INTERSECT') or (U(K) = 'MINUS') or
      (U(K) = 'EXCEPT')) then
    begin
      BlockEnd := Pv(K);
      Break;
    end;
  end;
  if BlockEnd < 0 then
  begin
    BlockEnd := High(T);
    while (BlockEnd > I) and IsCommentTok(T[BlockEnd]) do
    begin
      Dec(BlockEnd);
    end;
  end;
  // what Oracle applies after ROWNUM
  W := U(Nx(Sel));
  if (W = 'DISTINCT') or (W = 'UNIQUE') then
  begin
    AWhy := 'DISTINCT is applied after ROWNUM here';
    Exit;
  end;
  InWhere := False;
  for K := Sel + 1 to BlockEnd do
  begin
    if Depth[K] <> D then
    begin
      Continue;
    end;
    W := U(K);
    if W = 'WHERE' then
    begin
      InWhere := True;
    end
    else if (W = 'ORDER') or (W = 'GROUP') or (W = 'HAVING') or (W = 'CONNECT') then
    begin
      AWhy := W + ' BY is applied after ROWNUM here';
      if W = 'HAVING' then
      begin
        AWhy := 'GROUP BY / HAVING are applied after ROWNUM here';
      end;
      Exit;
    end
    else if (W = 'FETCH') or ((W = 'FOR') and (U(Nx(K)) = 'UPDATE')) then
    begin
      AWhy := 'the query already has ' + W;
      Exit;
    end
    else if InWhere and (W = 'OR') then
    begin
      AWhy := 'ROWNUM sits in a WHERE with OR';
      Exit;
    end
    else if not InWhere and ((W = 'COUNT') or (W = 'SUM') or (W = 'AVG') or (W = 'MIN') or (W = 'MAX') or
      (W = 'LISTAGG')) and (U(Nx(K)) = '(') then
    begin
      AWhy := 'the aggregate is applied after ROWNUM here';
      Exit;
    end;
  end;
  // ROWNUM <= n, ROWNUM < n, ROWNUM = 1 (or n >= ROWNUM ...)
  Reversed := False;
  Op := Nx(I);
  V := Nx(Op);
  CondStart := I;
  CondEnd := V;
  if not ((U(Op) = '<=') or (U(Op) = '<') or (U(Op) = '=')) or not IsInt(V) then
  begin
    Op := Pv(I);
    V := Pv(Op);
    Reversed := True;
    CondStart := V;
    CondEnd := I;
    if not ((U(Op) = '>=') or (U(Op) = '>') or (U(Op) = '=')) or not IsInt(V) then
    begin
      AWhy := 'ROWNUM isn''t a plain limit (ROWNUM <= n) here';
      Exit;
    end;
  end;
  N := StrToIntDef(T[V].Text, -1);
  if (U(Op) = '<') or (U(Op) = '>') then
  begin
    Dec(N);
  end
  else if (U(Op) = '=') and (N <> 1) then
  begin
    AWhy := 'ROWNUM = ' + T[V].Text + ' returns no rows in Oracle';
    Exit;
  end;
  if N < 1 then
  begin
    AWhy := 'the limit is less than 1';
    Exit;
  end;
  Before := Pv(CondStart);
  AfterC := Nx(CondEnd);
  if not ((U(Before) = 'WHERE') or (U(Before) = 'AND')) or (Depth[Before] <> D) then
  begin
    AWhy := 'ROWNUM isn''t a plain limit in the WHERE clause here';
    Exit;
  end;
  if (U(AfterC) <> 'AND') and (AfterC >= 0) and (AfterC <= BlockEnd) then
  begin
    AWhy := 'ROWNUM isn''t a plain limit in the WHERE clause here';
    Exit;
  end;
  if U(Before) = 'WHERE' then
  begin
    if U(AfterC) = 'AND' then
    begin
      RemStart := CondStart;
      RemEnd := AfterC;
    end
    else
    begin
      RemStart := Before;
      RemEnd := CondEnd;
    end;
  end
  else
  begin
    RemStart := Before;
    RemEnd := CondEnd;
  end;
  if Reversed then
  begin
    // nothing different: the span is the same either way
  end;
  Rest := Copy(S, T[RemEnd].EndPos + 1, T[BlockEnd].EndPos - T[RemEnd].EndPos);
  if RemEnd = BlockEnd then
  begin
    Rest := '';
  end;
  AEd.A := T[RemStart].StartPos;
  AEd.B := T[BlockEnd].EndPos;
  if Trim(Rest) = '' then
  begin
    AEd.Text := 'FETCH FIRST ' + IntToStr(N) + ' ROWS ONLY';
  end
  else
  begin
    AEd.Text := TrimLeft(Rest) + LineEnding + 'FETCH FIRST ' + IntToStr(N) + ' ROWS ONLY';
  end;
  Result := 1;
end;

function IsCodeColumn(const AUp: string): Boolean;
begin
  Result := EndsWith(AUp, '_CODE') or EndsWith(AUp, '_ID');
end;

function LooksNumericOrDate(const AUp: string): Boolean;
const
  Tails: array[0..16] of string = ('_PIDM', '_SEQ_NO', '_SEQNO', '_NO', '_NUM', '_NUMBER', '_AMT', '_AMOUNT',
    '_HR', '_HRS', '_HOURS', '_CNT', '_COUNT', '_DATE', '_CREDITS', '_GPA', '_YEAR');
var
  K: Integer;
begin
  Result := False;
  for K := Low(Tails) to High(Tails) do
  begin
    if EndsWith(AUp, Tails[K]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;


function TStmt.TryRule(R: TpgnConvRule; I: Integer; out AEd: TEditRec): Boolean;
var
  Args: TArgs;
  O, C, K, L, Ls, Rs, Re, P, A, G, GC, N, Op: Integer;
  X, Txt, Pg, Order, Over, W, FName, FSchema: string;
  AllLit: Boolean;
  FInfo, OInfo: TpgnRoutineInfo;

  function Lit(const AArg: TArg): Boolean;
  begin
    Result := ((AArg.A = AArg.B) and (T[AArg.A].Kind in [tkString, tkNumber])) or
      ((Nx(AArg.A) = AArg.B) and (U(AArg.A) = '-') and (T[AArg.B].Kind = tkNumber));
  end;

  function IsNullArg(const AArg: TArg): Boolean;
  begin
    Result := (AArg.A = AArg.B) and (U(AArg.A) = 'NULL');
  end;

  function ArgSrc(AIdx: Integer): string;
  begin
    Result := Src(Args[AIdx].A, Args[AIdx].B);
  end;

  function NeedsWrap(AFrom, ATo: Integer): Boolean;
  var
    Last: Integer;
  begin
    Result := False;
    if (AFrom < 0) or (ATo < AFrom) then
    begin
      Exit;
    end;
    if (U(Pv(AFrom)) = '+') or (U(Pv(AFrom)) = '-') or (U(Pv(AFrom)) = '*') or (U(Pv(AFrom)) = '/') or
      (U(Nx(ATo)) = '+') or (U(Nx(ATo)) = '-') or (U(Nx(ATo)) = '*') or (U(Nx(ATo)) = '/') then
    begin
      Exit;
    end;
    if U(ATo) = ')' then
    begin
      // a call: text functions only
      Result := IsWord(AFrom) and IsTextFunction(T[AFrom].Up) and (U(Pv(AFrom)) <> '.');
      Exit;
    end;
    Last := ATo;
    if not IsWord(Last) or IsSqlKeyword(T[Last].Up) then
    begin
      Exit;
    end;
    W := T[Last].Up;
    if (W = 'NULL') or (W = 'SYSDATE') or (W = 'LOCALTIMESTAMP') or (W = 'CURRENT_DATE') or
      (W = 'CURRENT_TIMESTAMP') or (W = 'SYSTIMESTAMP') or (W = 'USER') or (W = 'ROWNUM') or
      (W = 'LEVEL') then
    begin
      Exit;
    end;
    Result := not LooksNumericOrDate(W);
  end;

begin
  Result := False;
  case R of
    crNvl:
      begin
        if IsCall(I, 'NVL') and (Length(ArgsOf(Nx(I))) = 2) and not NvlMixed(I) then
        begin
          Result := Replace(I, I, 'COALESCE', AEd);
        end;
      end;
    crNvl2:
      begin
        if IsCall(I, 'NVL2') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 3 then
          begin
            Result := Replace(I, CloseOf(Nx(I)), 'CASE WHEN ' + ArgSrc(0) + ' IS NOT NULL THEN ' + ArgSrc(1) +
              ' ELSE ' + ArgSrc(2) + ' END', AEd);
          end;
        end;
      end;
    crDecode:
      begin
        if IsCall(I, 'DECODE') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) >= 3 then
          begin
            X := ArgSrc(0);
            AllLit := True;
            K := 1;
            while K + 1 <= High(Args) do
            begin
              if not Lit(Args[K]) then
              begin
                AllLit := False;
              end;
              Inc(K, 2);
            end;
            if AllLit then
            begin
              Txt := 'CASE ' + X;
              K := 1;
              while K + 1 <= High(Args) do
              begin
                Txt := Txt + ' WHEN ' + ArgSrc(K) + ' THEN ' + ArgSrc(K + 1);
                Inc(K, 2);
              end;
            end
            else
            begin
              Txt := 'CASE';
              K := 1;
              while K + 1 <= High(Args) do
              begin
                if IsNullArg(Args[K]) then
                begin
                  Txt := Txt + ' WHEN ' + X + ' IS NULL THEN ' + ArgSrc(K + 1);
                end
                else if Lit(Args[K]) then
                begin
                  Txt := Txt + ' WHEN ' + X + ' = ' + ArgSrc(K) + ' THEN ' + ArgSrc(K + 1);
                end
                else
                begin
                  Txt := Txt + ' WHEN (' + X + ' = ' + ArgSrc(K) + ' OR (' + X + ' IS NULL AND ' + ArgSrc(K) +
                    ' IS NULL)) THEN ' + ArgSrc(K + 1);
                end;
                Inc(K, 2);
              end;
            end;
            if not Odd(Length(Args)) then
            begin
              Txt := Txt + ' ELSE ' + ArgSrc(High(Args));
            end;
            Result := Replace(I, CloseOf(Nx(I)), Txt + ' END', AEd);
          end;
        end;
      end;
    crRownum:
      begin
        Result := RownumCheck(I, AEd, X) = 1;
      end;
    cfRownum:
      begin
        if RownumCheck(I, AEd, X) = -1 then
        begin
          Result := Flag(I, 'ROWNUM: ' + X + '; PG has no ROWNUM: ROW_NUMBER() OVER (...) or FETCH FIRST',
            AEd);
        end;
      end;
    crDateArith, cfDateMath:
      begin
        if (U(I) = '+') or (U(I) = '-') then
        begin
          L := Pv(I);
          Rs := Nx(I);
          if not IsOperandEnd(L) then
          begin
            Exit;
          end;
          Ls := OperandStart(L);
          if not IsDateLike(Ls, L) then
          begin
            Exit;
          end;
          P := Pv(Ls);
          if (U(P) = '-') or (U(P) = '+') or (U(P) = '*') or (U(P) = '/') then
          begin
            Exit;
          end;
          if IsInt(Rs) then
          begin
            W := U(Nx(Rs));
            N := StrToIntDef(T[Rs].Text, -1);
            if (W = '*') or (W = '/') or (W = '.') then
            begin
              if (R = cfDateMath) and (W = '/') then
              begin
                K := Nx(Nx(Rs));
                if K >= 0 then
                begin
                  Result := Flag(K, 'fractions of a day: ' + Src(Ls, L) + ' ' + U(I) + ' INTERVAL ''n'' HOUR ' +
                    '(or MINUTE) runs on both', AEd);
                end;
              end;
              Exit;
            end;
            if R = crDateArith then
            begin
              if (N >= 0) and (N <= 99) then
              begin
                Result := Replace(Rs, Rs, 'INTERVAL ''' + IntToStr(N) + ''' DAY', AEd);
              end;
            end
            else if N > 99 then
            begin
              Result := Flag(Rs, Src(Ls, L) + ' ' + U(I) + ' INTERVAL ''' + IntToStr(N) + ' days''', AEd);
            end;
            Exit;
          end;
          if (R = cfDateMath) and (U(I) = '-') then
          begin
            Re := OperandEnd(Rs);
            if (Re >= 0) and IsDateLike(Rs, Re) then
            begin
              Result := Flag(Re, 'date - date is days in Oracle, an interval for timestamps in PG: (' +
                Src(Ls, L) + ')::date - (' + Src(Rs, Re) + ')::date for whole days', AEd);
            end;
          end;
        end;
      end;
    crSysdate:
      begin
        if IsWord(I) and (T[I].Up = 'SYSDATE') and (U(Pv(I)) <> '.') then
        begin
          if (U(Nx(I)) = '-') and not IsInt(Nx(Nx(I))) then
          begin
            Exit;
          end;
          P := Pv(I);
          if (U(P) = '-') and IsOperandEnd(Pv(P)) then
          begin
            Exit;
          end;
          Result := Replace(I, I, 'LOCALTIMESTAMP', AEd);
        end;
      end;
    crSystimestamp:
      begin
        if IsWord(I) and (T[I].Up = 'SYSTIMESTAMP') and (U(Pv(I)) <> '.') then
        begin
          Result := Replace(I, I, 'CURRENT_TIMESTAMP', AEd);
        end;
      end;
    crCastTypes:
      begin
        if IsWord(I) and ((T[I].Up = 'VARCHAR2') or (T[I].Up = 'NUMBER')) and (U(Pv(I)) = 'AS') then
        begin
          O := -1;
          for K := I - 1 downto 0 do
          begin
            if (U(K) = '(') and (Depth[K] = Depth[I] - 1) then
            begin
              O := K;
              Break;
            end;
          end;
          if (O < 0) or (U(Pv(O)) <> 'CAST') then
          begin
            Exit;
          end;
          if T[I].Up = 'NUMBER' then
          begin
            Result := Replace(I, I, 'NUMERIC', AEd);
            Exit;
          end;
          // VARCHAR2(n CHAR | BYTE): PG has no CHAR / BYTE
          C := Nx(I);
          if (U(C) = '(') and IsInt(Nx(C)) and ((U(Nx(Nx(C))) = 'CHAR') or (U(Nx(Nx(C))) = 'BYTE')) and
            (U(Nx(Nx(Nx(C)))) = ')') then
          begin
            Result := Replace(I, Nx(Nx(Nx(C))), 'VARCHAR(' + T[Nx(C)].Text + ')', AEd);
          end
          else
          begin
            Result := Replace(I, I, 'VARCHAR', AEd);
          end;
        end;
      end;
    crToNumber:
      begin
        if IsCall(I, 'TO_NUMBER') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 1 then
          begin
            Result := Replace(I, CloseOf(Nx(I)), 'CAST(' + ArgSrc(0) + ' AS NUMERIC)', AEd);
          end;
        end;
      end;
    crSubAlias:
      begin
        if (U(I) = '(') and ((U(Nx(I)) = 'SELECT') or (U(Nx(I)) = 'WITH')) then
        begin
          P := Pv(I);
          W := U(P);
          if W = ',' then
          begin
            // a comma in a FROM list?
            W := '';
            for K := P - 1 downto 0 do
            begin
              if Depth[K] < Depth[I] then
              begin
                Break;
              end;
              if Depth[K] = Depth[I] then
              begin
                if U(K) = 'FROM' then
                begin
                  W := 'FROM';
                  Break;
                end;
                if (U(K) = 'SELECT') or (U(K) = 'WHERE') or (U(K) = 'SET') or (U(K) = 'VALUES') or
                  (U(K) = 'BY') or (U(K) = 'ON') then
                begin
                  Break;
                end;
              end;
            end;
          end;
          if (W <> 'FROM') and (W <> 'JOIN') then
          begin
            Exit;
          end;
          C := CloseOf(I);
          A := Nx(C);
          if (A >= 0) and ((U(A) = 'AS') or (IsWord(A) and not IsSqlKeyword(T[A].Up))) then
          begin
            Exit;   // named already
          end;
          if (A >= 0) and not ((U(A) = ',') or (U(A) = ')') or (U(A) = ';') or IsSqlKeyword(U(A))) then
          begin
            Exit;
          end;
          repeat
            Inc(SubN);
          until Pos('SUB' + IntToStr(SubN), UpperCase(S)) = 0;
          AEd.A := T[C].EndPos + 1;
          AEd.B := T[C].EndPos;
          AEd.Text := ' sub' + IntToStr(SubN);
          Result := True;
        end;
      end;
    crExplicit:
      begin
        if IsInt(I) then
        begin
          Op := Pv(I);
          W := U(Op);
          if (W = '=') or (W = '<>') or (W = '!=') or (W = '<') or (W = '>') or (W = '<=') or (W = '>=') then
          begin
            if IsWord(Pv(Op)) and IsCodeColumn(T[Pv(Op)].Up) then
            begin
              Result := Replace(I, I, '''' + T[I].Text + '''', AEd);
            end;
            Exit;
          end;
          W := U(Nx(I));
          if (W = '=') or (W = '<>') or (W = '!=') or (W = '<') or (W = '>') or (W = '<=') or (W = '>=') then
          begin
            if IsWord(Nx(Nx(I))) and IsCodeColumn(T[Nx(Nx(I))].Up) and (U(Nx(Nx(Nx(I)))) <> '.') then
            begin
              Result := Replace(I, I, '''' + T[I].Text + '''', AEd);
            end;
            Exit;
          end;
          // x_code IN (1, 2)
          if (W = ',') or (W = ')') then
          begin
            O := -1;
            for K := I - 1 downto 0 do
            begin
              if (U(K) = '(') and (Depth[K] = Depth[I] - 1) then
              begin
                O := K;
                Break;
              end;
            end;
            if (O >= 0) and (U(Pv(O)) = 'IN') then
            begin
              P := Pv(Pv(O));
              if U(P) = 'NOT' then
              begin
                P := Pv(P);
              end;
              if IsWord(P) and IsCodeColumn(T[P].Up) then
              begin
                Result := Replace(I, I, '''' + T[I].Text + '''', AEd);
              end;
            end;
          end;
        end;
      end;
    crConcatNull:
      begin
        if U(I) = '||' then
        begin
          Re := Pv(I);
          Ls := OperandStart(Re);
          if NeedsWrap(Ls, Re) then
          begin
            Result := Replace(Ls, Re, 'COALESCE(' + Src(Ls, Re) + ', '''')', AEd);
            Exit;
          end;
          Rs := Nx(I);
          Re := OperandEnd(Rs);
          if NeedsWrap(Rs, Re) then
          begin
            Result := Replace(Rs, Re, 'COALESCE(' + Src(Rs, Re) + ', '''')', AEd);
          end;
        end;
      end;
    cfListagg:
      begin
        if IsCall(I, 'LISTAGG') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 0 then
          begin
            Exit;
          end;
          C := CloseOf(Nx(I));
          K := C;
          Order := '';
          Over := '';
          G := Nx(C);
          if (U(G) = 'WITHIN') and (U(Nx(G)) = 'GROUP') and (U(Nx(Nx(G))) = '(') then
          begin
            G := Nx(Nx(G));
            GC := CloseOf(G);
            Order := ' ' + Src(Nx(G), Pv(GC));
            K := GC;
          end;
          if (U(Nx(K)) = 'OVER') and (U(Nx(Nx(K))) = '(') then
          begin
            G := Nx(Nx(K));
            GC := CloseOf(G);
            Over := ' OVER ' + Src(G, GC);
            K := GC;
          end;
          if Length(Args) >= 2 then
          begin
            Txt := ArgSrc(1);
          end
          else
          begin
            Txt := '''''';
          end;
          Result := Flag(K, 'string_agg(' + ArgSrc(0) + ', ' + Txt + Order + ')' + Over +
            ' (add ::text if it isn''t text)', AEd);
        end;
      end;
    cfTruncDate:
      begin
        if IsCall(I, 'TRUNC') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          if (Length(Args) = 2) and (T[Args[1].A].Kind = tkString) and (Args[1].A = Args[1].B) then
          begin
            W := TruncUnit(T[Args[1].A].Text);
            if W = '' then
            begin
              Result := Flag(C, 'date_trunc(...) (Oracle format ' + T[Args[1].A].Text + ')', AEd);
            end
            else if W = 'week' then
            begin
              Result := Flag(C, 'date_trunc(''week'', ' + ArgSrc(0) + ') (PG weeks start on Monday)', AEd);
            end
            else
            begin
              Result := Flag(C, 'date_trunc(''' + W + ''', ' + ArgSrc(0) + ')', AEd);
            end;
          end
          else if (Length(Args) = 1) and IsDateLike(Args[0].A, Args[0].B) then
          begin
            W := U(Args[0].A);
            if (Args[0].A = Args[0].B) and ((W = 'SYSDATE') or (W = 'LOCALTIMESTAMP')) then
            begin
              Result := Flag(C, 'CURRENT_DATE', AEd);
            end
            else
            begin
              Result := Flag(C, 'date_trunc(''day'', ' + ArgSrc(0) + ')', AEd);
            end;
          end;
        end;
      end;
    cfAddMonths:
      begin
        if IsCall(I, 'ADD_MONTHS') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 2 then
          begin
            if Lit(Args[1]) and (T[Args[1].B].Kind = tkNumber) then
            begin
              Pg := '(' + ArgSrc(0) + ' + INTERVAL ''' + StringReplace(ArgSrc(1), ' ', '', [rfReplaceAll]) +
                ' months'')';
            end
            else
            begin
              Pg := '(' + ArgSrc(0) + ' + make_interval(months => ' + ArgSrc(1) + '))';
            end;
            Result := Flag(CloseOf(Nx(I)), Pg, AEd);
          end;
        end;
      end;
    cfMonthsBetween:
      begin
        if IsCall(I, 'MONTHS_BETWEEN') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 2 then
          begin
            X := 'age(' + ArgSrc(0) + ', ' + ArgSrc(1) + ')';
            Result := Flag(CloseOf(Nx(I)), '(EXTRACT(YEAR FROM ' + X + ') * 12 + EXTRACT(MONTH FROM ' + X +
              ')), whole months', AEd);
          end;
        end;
      end;
    cfLastDay:
      begin
        if IsCall(I, 'LAST_DAY') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 1 then
          begin
            X := ArgSrc(0);
            Result := Flag(CloseOf(Nx(I)), '(date_trunc(''month'', ' + X + ') + INTERVAL ''1 month - 1 day'' + (' +
              X + ' - date_trunc(''day'', ' + X + ')))', AEd);
          end;
        end;
      end;
    cfNextDay:
      begin
        if IsCall(I, 'NEXT_DAY') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 2 then
          begin
            N := -1;
            if (Args[1].A = Args[1].B) and (T[Args[1].A].Kind = tkString) then
            begin
              N := DayNumber(T[Args[1].A].Text);
            end;
            if N >= 0 then
            begin
              X := ArgSrc(0);
              Result := Flag(CloseOf(Nx(I)), '(' + X + ' + ((' + IntToStr(N) + ' - EXTRACT(DOW FROM ' + X +
                ')::int + 6) % 7 + 1) * INTERVAL ''1 day'')', AEd);
            end
            else
            begin
              Result := Flag(CloseOf(Nx(I)), 'no NEXT_DAY: add (day wanted - EXTRACT(DOW FROM x) + 6) % 7 + 1 ' +
                'days', AEd);
            end;
          end;
        end;
      end;
    cfMinus:
      begin
        if IsWord(I) and (T[I].Up = 'MINUS') then
        begin
          Result := Flag(I, 'EXCEPT', AEd);
        end;
      end;
    cfDual:
      begin
        if IsWord(I) and (T[I].Up = 'DUAL') and (U(Pv(I)) = 'FROM') then
        begin
          Result := Flag(I, 'leave out FROM DUAL', AEd);
        end;
      end;
    cfSequence:
      begin
        if IsWord(I) and ((T[I].Up = 'NEXTVAL') or (T[I].Up = 'CURRVAL')) and (U(Pv(I)) = '.') then
        begin
          K := OperandStart(Pv(Pv(I)));
          Result := Flag(I, LowerCase(T[I].Up) + '(''' + Src(K, Pv(Pv(I))) + ''')', AEd);
        end;
      end;
    cfConnectBy:
      begin
        if IsWord(I) and (T[I].Up = 'CONNECT') and (U(Nx(I)) = 'BY') then
        begin
          Result := Flag(Nx(I), 'rewrite as WITH RECURSIVE; LEVEL, PRIOR and SYS_CONNECT_BY_PATH have no ' +
            'direct form', AEd);
        end;
      end;
    cfRegexp:
      begin
        if IsWord(I) and ((T[I].Up = 'REGEXP_SUBSTR') or (T[I].Up = 'REGEXP_INSTR') or
          (T[I].Up = 'REGEXP_COUNT') or (T[I].Up = 'REGEXP_LIKE')) and IsCall(I, T[I].Up) then
        begin
          Pg := LowerCase(T[I].Up) + ' needs PostgreSQL 15 or later';
          if T[I].Up = 'REGEXP_LIKE' then
          begin
            Pg := Pg + '; before 15: x ~ ''pattern''';
          end
          else if T[I].Up = 'REGEXP_SUBSTR' then
          begin
            Pg := Pg + '; before 15: substring(x from ''pattern'')';
          end;
          Result := Flag(CloseOf(Nx(I)), Pg, AEd);
        end;
      end;
    cfRegexpReplace:
      begin
        if IsCall(I, 'REGEXP_REPLACE') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 3 then
          begin
            Pg := 'regexp_replace(' + ArgSrc(0) + ', ' + ArgSrc(1) + ', ' + ArgSrc(2) + ', ''g'')';
          end
          else if Length(Args) = 2 then
          begin
            Pg := 'regexp_replace(' + ArgSrc(0) + ', ' + ArgSrc(1) + ', '''', ''g'')';
          end
          else if (Length(Args) = 4) and (ArgSrc(3) = '''g''') then
          begin
            Exit;   // already PostgreSQL's form
          end
          else
          begin
            Pg := 'regexp_replace: PG''s 4th argument is flags (''g'' for every match), not a position';
          end;
          Result := Flag(CloseOf(Nx(I)), Pg, AEd);
        end;
      end;
    cfToChar:
      begin
        if IsCall(I, 'TO_CHAR') or IsCall(I, 'TO_DATE') or IsCall(I, 'TO_TIMESTAMP') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          W := T[I].Up;
          if Length(Args) = 1 then
          begin
            if W = 'TO_CHAR' then
            begin
              if IsDateLike(Args[0].A, Args[0].B) then
              begin
                Result := Flag(C, 'to_char needs a format: to_char(' + ArgSrc(0) + ', ''MM/DD/YYYY'') (or the one ' +
                  'you need; runs on both)', AEd);
              end
              else
              begin
                Result := Flag(C, 'to_char needs a format: CAST(' + ArgSrc(0) + ' AS VARCHAR(40)) runs on both ' +
                  'for a number', AEd);
              end;
            end
            else
            begin
              Result := Flag(C, LowerCase(W) + ' needs a format mask in PG: ' + LowerCase(W) + '(' + ArgSrc(0) +
                ', ''DD-MON-YY'') (the one your data uses)', AEd);
            end;
          end
          else if Length(Args) >= 2 then
          begin
            if (T[Args[1].A].Kind = tkString) and (Pos('RR', UpperCase(T[Args[1].A].Text)) > 0) then
            begin
              Result := Flag(C, 'PG has no RR in formats: use YYYY (or YY)', AEd);
            end
            else if Length(Args) >= 3 then
            begin
              Result := Flag(C, 'PG has no NLS parameter: leave out ' + ArgSrc(2), AEd);
            end;
          end;
        end;
      end;
    cfRowid:
      begin
        if IsWord(I) and (T[I].Up = 'ROWID') then
        begin
          Result := Flag(I, 'PG has no ROWID (ctid changes): use the table''s key', AEd);
        end;
      end;
    cfSysContext:
      begin
        if IsCall(I, 'SYS_CONTEXT') then
        begin
          Result := Flag(CloseOf(Nx(I)), 'current_user, inet_client_addr() or current_setting(...)', AEd);
        end
        else if IsWord(I) and (T[I].Up = 'USERENV') and (U(Nx(I)) = '(') then
        begin
          Result := Flag(CloseOf(Nx(I)), 'current_user, inet_client_addr() or current_setting(...)', AEd);
        end;
      end;
    cfFunctions:
      begin
        // one note per function per statement: at its first call, with the count
        if FuncAt(I, FName, FSchema, FInfo) and (Job.SkipSchemas.IndexOf(FSchema) < 0) then
        begin
          N := 0;
          for K := 0 to High(T) do
          begin
            if FuncAt(K, X, W, OInfo) and SameText(X, FName) then
            begin
              if K < I then
              begin
                Exit;   // not the first call
              end;
              Inc(N);
            end;
          end;
          Pg := FName;
          if N > 1 then
          begin
            Pg := Pg + ' (' + IntToStr(N) + ' calls)';
          end;
          if FInfo.Found then
          begin
            if FInfo.ReturnType <> '' then
            begin
              Pg := Pg + ', returns ' + FInfo.ReturnType;
            end
            else
            begin
              Pg := Pg + ', a procedure';
            end;
          end;
          Result := Flag(CloseOf(Nx(I)), Pg + ': PostgreSQL needs its own version', AEd);
        end;
      end;
    cfNvlTypes:
      begin
        if IsCall(I, 'NVL') and NvlMixed(I) then
        begin
          Args := ArgsOf(Nx(I));
          Result := Flag(CloseOf(Nx(I)), 'NVL kept: COALESCE needs one type on both sides, e.g. ' +
            'COALESCE(CAST(' + ArgSrc(0) + ' AS NUMERIC), ' + ArgSrc(1) + ') or a text value for ' +
            ArgSrc(1), AEd);
        end;
      end;
    cfInstr, rpInstr:
      begin
        if IsCall(I, 'INSTR') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          if Length(Args) < 2 then
          begin
            Exit;
          end;
          // INSTR(x, y), INSTR(x, y, 1), INSTR(x, y, 1, 1): strpos
          AllLit := (Length(Args) = 2) or ((Length(Args) = 3) and (ArgSrc(2) = '1')) or
            ((Length(Args) = 4) and (ArgSrc(2) = '1') and (ArgSrc(3) = '1'));
          Pg := 'strpos(' + ArgSrc(0) + ', ' + ArgSrc(1) + ')';
          if R = rpInstr then
          begin
            if AllLit then
            begin
              Result := Replace(I, EndIncl(C), Pg, AEd);
            end;
          end
          else if AllLit then
          begin
            Result := Flag(C, Pg, AEd);
          end
          else
          begin
            Result := Flag(C, 'PG has no INSTR with a start or occurrence: strpos on substr(x, start) ' +
              'plus start - 1, or regexp_instr (PG 15+)', AEd);
          end;
        end;
      end;
    cfSubstr, rpSubstrRight:
      begin
        if IsCall(I, 'SUBSTR') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          if (Length(Args) < 2) or (Length(Args) > 3) then
          begin
            Exit;
          end;
          if IsDateLike(Args[0].A, Args[0].B) then
          begin
            if R = cfSubstr then
            begin
              Result := Flag(C, 'SUBSTR of a date uses Oracle''s date format (NLS); to_char(' + ArgSrc(0) +
                ', ''YYYY'') (or the part you need) runs on both', AEd);
            end;
            Exit;
          end;
          if not ((Nx(Args[1].A) = Args[1].B) and (U(Args[1].A) = '-') and IsInt(Args[1].B)) then
          begin
            Exit;   // not a negative start
          end;
          N := StrToIntDef(T[Args[1].B].Text, 0);
          if N <= 0 then
          begin
            Exit;
          end;
          AllLit := (Length(Args) = 2) or (IsInt(Args[2].A) and (Args[2].A = Args[2].B) and
            (StrToIntDef(T[Args[2].A].Text, 0) >= N));
          Pg := 'CASE WHEN length(' + ArgSrc(0) + ') >= ' + IntToStr(N) + ' THEN right(' + ArgSrc(0) + ', ' +
            IntToStr(N) + ') END';
          if R = rpSubstrRight then
          begin
            if AllLit then
            begin
              Result := Replace(I, EndIncl(C), Pg, AEd);
            end;
          end
          else if AllLit then
          begin
            Result := Flag(C, 'PG''s substr doesn''t count from the end: ' + Pg, AEd);
          end
          else
          begin
            Result := Flag(C, 'PG''s substr doesn''t count from the end: substr(x, length(x) - ' +
              IntToStr(N) + ' + 1, length) when x is at least ' + IntToStr(N) + ' long', AEd);
          end;
        end;
      end;
    rpDual:
      begin
        if IsWord(I) and (T[I].Up = 'DUAL') and (U(Pv(I)) = 'FROM') then
        begin
          Result := Replace(Pv(I), EndIncl(I), '', AEd);
        end;
      end;
    rpMinus:
      begin
        if IsWord(I) and (T[I].Up = 'MINUS') then
        begin
          Result := Replace(I, EndIncl(I), 'EXCEPT', AEd);
        end;
      end;
    rpSequence:
      begin
        if IsWord(I) and ((T[I].Up = 'NEXTVAL') or (T[I].Up = 'CURRVAL')) and (U(Pv(I)) = '.') then
        begin
          K := OperandStart(Pv(Pv(I)));
          Result := Replace(K, EndIncl(I), LowerCase(T[I].Up) + '(''' + Src(K, Pv(Pv(I))) + ''')', AEd);
        end;
      end;
    rpRegexpReplace:
      begin
        if IsCall(I, 'REGEXP_REPLACE') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          if Length(Args) = 3 then
          begin
            Result := Replace(I, EndIncl(C), 'regexp_replace(' + ArgSrc(0) + ', ' + ArgSrc(1) + ', ' + ArgSrc(2) +
              ', ''g'')', AEd);
          end
          else if Length(Args) = 2 then
          begin
            Result := Replace(I, EndIncl(C), 'regexp_replace(' + ArgSrc(0) + ', ' + ArgSrc(1) + ', '''', ''g'')',
              AEd);
          end;
        end;
      end;
    rpListagg:
      begin
        if IsCall(I, 'LISTAGG') then
        begin
          Args := ArgsOf(Nx(I));
          if (Length(Args) = 0) or (Length(Args) > 2) or (U(Args[0].A) = 'DISTINCT') or
            (Pos('OVERFLOW', UpperCase(Src(Nx(I), CloseOf(Nx(I))))) > 0) then
          begin
            Exit;
          end;
          C := CloseOf(Nx(I));
          K := C;
          Order := '';
          G := Nx(C);
          if (U(G) = 'WITHIN') and (U(Nx(G)) = 'GROUP') and (U(Nx(Nx(G))) = '(') then
          begin
            G := Nx(Nx(G));
            GC := CloseOf(G);
            Order := ' ' + Src(Nx(G), Pv(GC));
            K := GC;
          end;
          if U(Nx(K)) = 'OVER' then
          begin
            Exit;   // PG can't order an aggregate used as a window function
          end;
          if Length(Args) = 2 then
          begin
            Txt := ArgSrc(1);
          end
          else
          begin
            Txt := '''''';
          end;
          Result := Replace(I, EndIncl(K), 'string_agg(' + ArgSrc(0) + ', ' + Txt + Order + ')', AEd);
        end;
      end;
    rpTruncDate:
      begin
        if IsCall(I, 'TRUNC') then
        begin
          Args := ArgsOf(Nx(I));
          C := CloseOf(Nx(I));
          if (Length(Args) = 2) and (T[Args[1].A].Kind = tkString) and (Args[1].A = Args[1].B) then
          begin
            W := TruncUnit(T[Args[1].A].Text);
            if (W <> '') and ((W <> 'week') or
              (UpperCase(StringReplace(T[Args[1].A].Text, '''', '', [rfReplaceAll])) = 'IW')) then
            begin
              Result := Replace(I, EndIncl(C), 'date_trunc(''' + W + ''', ' + ArgSrc(0) + ')', AEd);
            end;
          end
          else if (Length(Args) = 1) and IsDateLike(Args[0].A, Args[0].B) then
          begin
            Result := Replace(I, EndIncl(C), 'date_trunc(''day'', ' + ArgSrc(0) + ')', AEd);
          end;
        end;
      end;
    rpLastDay:
      begin
        if IsCall(I, 'LAST_DAY') then
        begin
          Args := ArgsOf(Nx(I));
          if Length(Args) = 1 then
          begin
            X := ArgSrc(0);
            Result := Replace(I, EndIncl(CloseOf(Nx(I))), '(date_trunc(''month'', ' + X +
              ') + INTERVAL ''1 month - 1 day'' + (' + X + ' - date_trunc(''day'', ' + X + ')))', AEd);
          end;
        end;
      end;
    rpNextDay:
      begin
        if IsCall(I, 'NEXT_DAY') then
        begin
          Args := ArgsOf(Nx(I));
          if (Length(Args) = 2) and (Args[1].A = Args[1].B) and (T[Args[1].A].Kind = tkString) then
          begin
            N := DayNumber(T[Args[1].A].Text);
            if N >= 0 then
            begin
              X := ArgSrc(0);
              Result := Replace(I, EndIncl(CloseOf(Nx(I))), '(' + X + ' + ((' + IntToStr(N) +
                ' - EXTRACT(DOW FROM ' + X + ')::int + 6) % 7 + 1) * INTERVAL ''1 day'')', AEd);
            end;
          end;
        end;
      end;
  else
    begin
      // crJoins and cfPlsql are handled per text and per statement
    end;
  end;
end;

{ The order the rules are tried in at each token. }
const
  ApplyOrder: array[0..42] of TpgnConvRule = (
    crDecode, crNvl2, crNvl, crToNumber, crCastTypes, crSystimestamp, crSysdate, crDateArith,
    crRownum, crSubAlias, crExplicit, crConcatNull,
    rpDual, rpListagg, rpMinus, rpSequence, rpRegexpReplace, rpInstr, rpSubstrRight, rpTruncDate,
    rpLastDay, rpNextDay,
    cfListagg, cfTruncDate, cfAddMonths, cfMonthsBetween, cfLastDay, cfNextDay, cfDateMath, cfMinus,
    cfDual, cfSequence, cfConnectBy, cfRegexp, cfRegexpReplace, cfToChar, cfRownum, cfRowid, cfSysContext,
    cfInstr, cfSubstr, cfNvlTypes, cfFunctions);

function StatementKind(St: TStmt): Integer;   // 1 = convert, 2 = PL/SQL, 0 = leave alone
var
  I: Integer;
  W: string;
begin
  Result := 0;
  I := 0;
  while (I <= High(St.T)) and IsCommentTok(St.T[I]) do
  begin
    Inc(I);
  end;
  if I > High(St.T) then
  begin
    Exit;
  end;
  W := St.U(I);
  if (W = 'SELECT') or (W = 'WITH') or (W = 'INSERT') or (W = 'UPDATE') or (W = 'DELETE') or
    (W = 'MERGE') or (W = '(') then
  begin
    Result := 1;
  end
  else if (W = 'DECLARE') or (W = 'BEGIN') then
  begin
    Result := 2;
  end
  else if W = 'CREATE' then
  begin
    Inc(I);
    while (I <= High(St.T)) and ((St.U(I) = 'OR') or (St.U(I) = 'REPLACE') or (St.U(I) = 'FORCE') or
      (St.U(I) = 'NOFORCE') or (St.U(I) = 'EDITIONABLE') or (St.U(I) = 'NONEDITIONABLE') or
      (St.U(I) = 'GLOBAL') or (St.U(I) = 'TEMPORARY') or IsCommentTok(St.T[I])) do
    begin
      Inc(I);
    end;
    W := St.U(I);
    if (W = 'VIEW') or (W = 'TABLE') or (W = 'MATERIALIZED') then
    begin
      Result := 1;
    end
    else if (W = 'PROCEDURE') or (W = 'FUNCTION') or (W = 'PACKAGE') or (W = 'TRIGGER') or (W = 'TYPE') then
    begin
      Result := 2;
    end;
  end;
end;

procedure AddFinding(AJob: TpgnConvJob; ARule: TpgnConvRule; const ASchema, AFunc, AText: string);
var
  N: Integer;
begin
  N := Length(AJob.Findings);
  SetLength(AJob.Findings, N + 1);
  AJob.Findings[N].Rule := ARule;
  AJob.Findings[N].Schema := ASchema;
  AJob.Findings[N].Func := AFunc;
  AJob.Findings[N].Text := AText;
end;

{ The TODO PG text inside a flag's edit (' /* TODO PG: text */'). }
function FlagText(const AEdText: string): string;
begin
  Result := Trim(AEdText);
  if Copy(Result, 1, Length(TodoPG)) = TodoPG then
  begin
    Result := Copy(Result, Length(TodoPG) + 1, MaxInt);
  end;
  if Copy(Result, Length(Result) - 1, 2) = '*/' then
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 2));
  end;
end;

function ConvertStatement(const AText: string; AJob: TpgnConvJob): string;
var
  St: TStmt;
  I, Iter, K, F: Integer;
  R: TpgnConvRule;
  Ed: TEditRec;
  Found: Boolean;
  Phase: Integer;
  Lead, Nm, Sch: string;
  Info: TpgnRoutineInfo;
  G: TpgnConvGroup;
begin
  Result := AText;
  St := TStmt.Create;
  try
    St.Job := AJob;
    St.Load(AText);
    case StatementKind(St) of
      2:
        begin
          Inc(AJob.Counts[cfPlsql]);
          if (cfPlsql in AJob.Rules) and (Pos(TodoPG, TrimLeft(AText)) <> 1) then
          begin
            Inc(AJob.Applied[cfPlsql]);
            AddFinding(AJob, cfPlsql, '', '', 'PL/SQL: rewrite in PL/pgSQL');
            // on its own line, above the block
            Lead := Copy(AText, 1, Length(AText) - Length(TrimLeft(AText)));
            Result := Lead + TodoPG + 'PL/SQL: rewrite in PL/pgSQL */' + LineEnding + TrimLeft(AText);
          end;
          Exit;
        end;
      0:
        begin
          Exit;
        end;
    end;
    // what each rule finds, whether or not it's on; the functions called
    for I := 0 to High(St.T) do
    begin
      for K := Low(ApplyOrder) to High(ApplyOrder) do
      begin
        if St.TryRule(ApplyOrder[K], I, Ed) then
        begin
          Inc(AJob.Counts[ApplyOrder[K]]);
        end;
      end;
      if St.FuncAt(I, Nm, Sch, Info) then
      begin
        F := AJob.FuncIndex(Nm);
        if F < 0 then
        begin
          F := Length(AJob.Funcs);
          SetLength(AJob.Funcs, F + 1);
          AJob.Funcs[F].Name := Nm;
          AJob.Funcs[F].Schema := Sch;
          AJob.Funcs[F].Calls := 0;
          AJob.Funcs[F].Info := Info;
        end;
        Inc(AJob.Funcs[F].Calls);
      end;
    end;
    St.SubN := 0;
    // then the rules that are on, one change at a time: conversions, then
    // PostgreSQL only replacements, then flags (so their PostgreSQL forms
    // show the converted code)
    Iter := 0;
    for Phase := 1 to 3 do
    repeat
      Found := False;
      Inc(Iter);
      for I := 0 to High(St.T) do
      begin
        for K := Low(ApplyOrder) to High(ApplyOrder) do
        begin
          R := ApplyOrder[K];
          G := RuleInfo(R).Group;
          if not (R in AJob.Rules) or ((Phase = 1) and not (G in [cgSame, cgChanges])) or
            ((Phase = 2) and (G <> cgPgOnly)) or ((Phase = 3) and (G <> cgFlag)) then
          begin
            Continue;
          end;
          if St.TryRule(R, I, Ed) then
          begin
            Nm := '';
            Sch := '';
            if R in [cfFunctions, cfNvlTypes] then
            begin
              if R = cfNvlTypes then
              begin
                Nm := 'NVL';
              end
              else
              begin
                St.FuncAt(I, Nm, Sch, Info);
              end;
            end;
            if G = cgFlag then
            begin
              AddFinding(AJob, R, Sch, Nm, FlagText(Ed.Text));
            end
            else if G = cgPgOnly then
            begin
              AddFinding(AJob, R, '', '', Trim(Ed.Text));
            end
            else
            begin
              AddFinding(AJob, R, '', '', '');
            end;
            St.Load(Copy(St.S, 1, Ed.A - 1) + Ed.Text + Copy(St.S, Ed.B + 1, MaxInt));
            Inc(AJob.Applied[R]);
            Found := True;
            Break;
          end;
        end;
        if Found then
        begin
          Break;
        end;
      end;
    until not Found or (Iter > 5000);
    Result := St.S;
  finally
    St.Free;
  end;
end;

function ConvertOracleToAnsi(const AText: string; AJob: TpgnConvJob): string;
var
  R: TpgnConvRule;
  JoinNotes, Sch: TStringList;
  Conv, Skip, I, K, Last, NF: Integer;
  Joined, Piece, Line: string;
  Spans: TpgnStatementSpans;
  Info: TpgnRuleInfo;
begin
  AJob.Reset;
  // (+) joins first: they read the original FROM and WHERE
  JoinNotes := TStringList.Create;
  try
    Joined := AText;
    if HasOuterJoinMarks(AText) then
    begin
      Joined := ConvertOuterJoins(AText, AJob.Columns, JoinNotes, Conv, Skip);
      AJob.Counts[crJoins] := Conv + Skip;
      if crJoins in AJob.Rules then
      begin
        AJob.Applied[crJoins] := Conv;
        for I := 1 to Conv do
        begin
          AddFinding(AJob, crJoins, '', '', '');
        end;
      end
      else
      begin
        Joined := AText;
        JoinNotes.Clear;
      end;
    end;
    // then each statement
    Spans := SplitStatements(Joined, sdOracle);
    Result := '';
    Last := 1;
    for I := 0 to High(Spans) do
    begin
      Result := Result + Copy(Joined, Last, Spans[I].StartPos - Last);
      Piece := Copy(Joined, Spans[I].StartPos, Spans[I].EndPos - Spans[I].StartPos + 1);
      if Trim(Piece) <> '' then
      begin
        Piece := ConvertStatement(Piece, AJob);
      end;
      Result := Result + Piece;
      Last := Spans[I].EndPos + 1;
    end;
    Result := Result + Copy(Joined, Last, MaxInt);
    // what was done
    for R := Low(TpgnConvRule) to High(TpgnConvRule) do
    begin
      if (AJob.Applied[R] = 0) or (R = cfFunctions) then
      begin
        Continue;
      end;
      Info := RuleInfo(R);
      case Info.Group of
        cgFlag:
          begin
            Line := 'TODO PG ' + Copy(Info.Caption, Length('Mark ') + 1, MaxInt) + ': ' +
              IntToStr(AJob.Applied[R]) + ' marked.';
          end;
        cgPgOnly:
          begin
            Line := 'PostgreSQL only, ' + Info.Caption + ': ' + IntToStr(AJob.Applied[R]) + '.';
          end;
      else
        begin
          Line := Info.Caption + ': ' + IntToStr(AJob.Applied[R]) + '.';
        end;
      end;
      if (R <> crJoins) and (Info.Why <> '') and (Info.Why <> FlagWhy) and (Info.Why <> PgOnlyWhy) then
      begin
        Line := Line + ' ' + Info.Why;
      end;
      AJob.Notes.Add(Line);
      if R = crJoins then
      begin
        AJob.Notes.AddStrings(JoinNotes);
      end;
    end;
    if (AJob.Counts[crJoins] > 0) and (AJob.Applied[crJoins] = 0) and (crJoins in AJob.Rules) then
    begin
      AJob.Notes.AddStrings(JoinNotes);
    end;
    // stored functions, by schema
    if Length(AJob.Funcs) > 0 then
    begin
      Sch := AJob.SchemaCalls;
      try
        for K := 0 to Sch.Count - 1 do
        begin
          NF := 0;
          for I := 0 to High(AJob.Funcs) do
          begin
            if SameText(AJob.Funcs[I].Schema, Sch[K]) then
            begin
              Inc(NF);
            end;
          end;
          if Sch[K] = '' then
          begin
            Line := 'Functions, schema unknown';
          end
          else
          begin
            Line := Sch[K] + ' functions';
          end;
          Line := Line + ': ' + IntToStr(NF) + ' function(s), ' + IntToStr(PtrInt(Sch.Objects[K])) + ' call(s)';
          if (cfFunctions in AJob.Rules) and (AJob.SkipSchemas.IndexOf(Sch[K]) < 0) then
          begin
            Line := Line + ', marked TODO PG (one note per function per statement).';
          end
          else
          begin
            Line := Line + ', not marked.';
          end;
          AJob.Notes.Add(Line);
        end;
      finally
        Sch.Free;
      end;
    end;
  finally
    JoinNotes.Free;
  end;
end;

end.
