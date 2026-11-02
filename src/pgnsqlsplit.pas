// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnSqlSplit;

{ Splits SQL text into statements, respecting quotes and comments.
  Used for "run statement at cursor" and "run as script".

  The statement delimiter starts as ';'. A line of the form
      DELIMITER $$
  (as in the mysql command-line client) changes it, so procedure and
  trigger bodies containing ';' stay in one piece. DELIMITER lines are
  instructions to Pagona and are never sent to the server. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, pgnTypes;

type
  TpgnStatementSpan = record
    StartPos: Integer;   // 1-based, inclusive
    EndPos: Integer;     // 1-based, inclusive, excludes the delimiter
    DelimEnd: Integer;   // last character of the delimiter (= EndPos if none)
  end;

  TpgnStatementSpans = array of TpgnStatementSpan;

  { What part of the schema tree a statement can change. }
  TpgnSchemaChange = (scNone, scDatabases, scObjects);

{ ADialect: MySQL knows backtick quotes, # comments, backslash escapes
  and DELIMITER lines; PostgreSQL knows dollar quotes ($$ ... $$,
  $body$ ... $body$) and E'...' escape strings. Oracle works as SQL*Plus
  and Toad do: a PL/SQL block (DECLARE, BEGIN, CREATE PROCEDURE /
  FUNCTION / PACKAGE / TRIGGER / TYPE) runs to a line holding only '/',
  other statements end at ';' or such a line; q'[...]' quotes; SQL*Plus
  lines (SET SERVEROUTPUT ..., PROMPT, REM, EXEC ...) are one line each.
  SQL Server works as SSMS does: a line holding only GO (or GO n) ends a
  batch, and each batch goes to the server whole, semicolons and all. }
function SplitStatements(const AText: string; ADialect: TpgnDialect = sdMySQL): TpgnStatementSpans;
function StatementList(const AText: string; ADialect: TpgnDialect = sdMySQL): TpgnStringArray;
function StatementAt(const AText: string; ACaretPos: Integer; ADialect: TpgnDialect = sdMySQL): string;
{ Where the statement StatementAt would return sits in the text (1-based,
  inclusive, without the delimiter). False if there's none. }
function StatementSpanAt(const AText: string; ACaretPos: Integer;
  out AStart, AEnd: Integer; ADialect: TpgnDialect = sdMySQL): Boolean;
function TrimStatement(const AText: string): string;
function FirstKeyword(const AText: string): string;

{ True for statements that change data and wait for Commit when
  auto-commit is off (INSERT, UPDATE, DELETE, MERGE, calls and blocks). }
function StatementChangesData(const ASQL: string): Boolean;

{ True for a statement that only reads and takes no locks: SELECT (without
  FOR UPDATE / FOR SHARE / LOCK IN SHARE MODE), SHOW, DESCRIBE, EXPLAIN,
  SET, USE. }
function StatementOnlyReads(const ASQL: string): Boolean;

{ CREATE, ALTER, DROP, TRUNCATE, RENAME, GRANT, REVOKE, COMMENT. }
function StatementIsDDL(const ASQL: string): Boolean;

{ True for statements that end the transaction: COMMIT and ROLLBACK, and
  DDL where the database commits it implicitly (Oracle, MySQL; not
  PostgreSQL, where ATransactionalDDL is True and DDL waits for Commit). }
function StatementEndsTransaction(const ASQL: string; ATransactionalDDL: Boolean): Boolean;

{ True if the text has anything besides comments and whitespace. }
function HasCode(const AText: string; ADialect: TpgnDialect = sdMySQL): Boolean;

{ True if the line holding ACaretPos is only a comment (and isn't blank). }
function CaretOnCommentLine(const AText: string; ACaretPos: Integer;
  ADialect: TpgnDialect = sdMySQL): Boolean;
function SchemaChangeOf(const AText: string): TpgnSchemaChange;

{ In a CREATE PROCEDURE / FUNCTION / TRIGGER statement, finds the object's
  name (as written, possibly `db`.`name`): its position and length, the
  name itself without quotes or database, and the kind word (uppercase).
  Skips comments, DEFINER = ..., OR REPLACE, AGGREGATE, IF NOT EXISTS. }
function FindCreateName(const ASQL: string; out AStart, ALength: Integer;
  out AName, AKindWord: string): Boolean;

implementation

type
  TScanState = (ssNormal, ssSingle, ssDouble, ssBacktick, ssLineComment, ssBlockComment);

{ PostgreSQL: the dollar-quote tag starting at P ("$$", "$body$"), or ''.
  "$1" (a parameter) is not a tag. }
function DollarTagAt(const AText: string; P: Integer): string;
var
  J, N: Integer;
begin
  Result := '';
  N := Length(AText);
  if (P > N) or (AText[P] <> '$') then
  begin
    Exit;
  end;
  // not the end of an identifier such as abc$ (names may hold $ in PostgreSQL)
  if (P > 1) and (AText[P - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) then
  begin
    Exit;
  end;
  J := P + 1;
  if (J <= N) and (AText[J] in ['0'..'9']) then
  begin
    Exit;
  end;
  while (J <= N) and (AText[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_', #128..#255]) do
  begin
    Inc(J);
  end;
  if (J <= N) and (AText[J] = '$') then
  begin
    Result := Copy(AText, P, J - P + 1);
  end;
end;

{ Where the dollar-quoted text opened at P ends (the last character of the
  closing tag), or the end of the text if it is never closed. }
function DollarQuoteEnd(const AText: string; P: Integer; const ATag: string): Integer;
var
  Q: Integer;
begin
  Q := Pos(ATag, Copy(AText, P + Length(ATag), MaxInt));
  if Q = 0 then
  begin
    Result := Length(AText);
  end
  else
  begin
    Result := P + Length(ATag) + Q - 1 + Length(ATag) - 1;
  end;
end;

{ A quote at P opens a string where backslash escapes: always in MySQL,
  only in E'...' in PostgreSQL. }
function BackslashString(const AText: string; P: Integer; ADialect: TpgnDialect): Boolean;
begin
  if ADialect = sdMySQL then
  begin
    Result := True;
  end
  else if ADialect in [sdOracle, sdTSQL] then
  begin
    Result := False;   // Oracle and SQL Server strings only double the quote
  end
  else
  begin
    Result := (P > 1) and (AText[P - 1] in ['E', 'e']) and
      ((P = 2) or not (AText[P - 2] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']));
  end;
end;

{ Oracle q'X...X' quoting at P (q or Q, then a quote, then the delimiter):
  where it ends, or 0 if P doesn't start one. Brackets close with their
  partner: q'[...]', q'(...)', q'<...>' and the curly pair. }
function OracleQQuoteEnd(const AText: string; P: Integer): Integer;
var
  N, J: Integer;
  Open, Close: Char;
begin
  Result := 0;
  N := Length(AText);
  if (P + 2 > N) or not (AText[P] in ['q', 'Q']) or (AText[P + 1] <> '''') then
  begin
    Exit;
  end;
  // not the end of a name such as "seq'..." (which isn't valid anyway)
  if (P > 1) and (AText[P - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']) and
    not ((P > 1) and (AText[P - 1] in ['n', 'N']) and ((P = 2) or not (AText[P - 2] in
    ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']))) then
  begin
    Exit;
  end;
  Open := AText[P + 2];
  case Open of
    '[':
      begin
        Close := ']';
      end;
    '{':
      begin
        Close := '}';
      end;
    '(':
      begin
        Close := ')';
      end;
    '<':
      begin
        Close := '>';
      end;
  else
    begin
      Close := Open;
    end;
  end;
  J := P + 3;
  while J < N do
  begin
    if (AText[J] = Close) and (AText[J + 1] = '''') then
    begin
      Result := J + 1;
      Exit;
    end;
    Inc(J);
  end;
  Result := N;
end;

{ The next word at or after P (letters, digits, _ $ #), skipping blanks
  and comments; P moves past it. '' at the end. }
function OracleWord(const AText: string; var P: Integer): string;
var
  N, S: Integer;
begin
  N := Length(AText);
  while P <= N do
  begin
    if AText[P] in [' ', #9, #10, #13] then
    begin
      Inc(P);
    end
    else if (AText[P] = '-') and (P < N) and (AText[P + 1] = '-') then
    begin
      while (P <= N) and (AText[P] <> #10) do
      begin
        Inc(P);
      end;
    end
    else if (AText[P] = '/') and (P < N) and (AText[P + 1] = '*') then
    begin
      Inc(P, 2);
      while (P < N) and not ((AText[P] = '*') and (AText[P + 1] = '/')) do
      begin
        Inc(P);
      end;
      Inc(P, 2);
    end
    else
    begin
      Break;
    end;
  end;
  S := P;
  while (P <= N) and (AText[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']) do
  begin
    Inc(P);
  end;
  Result := UpperCase(Copy(AText, S, P - S));
end;

type
  TOracleMode = (omUndecided, omStatement, omBlock, omLine);

{ What kind of statement starts at P: a PL/SQL block, a SQL*Plus line or
  a plain statement. }
function OracleModeAt(const AText: string; P: Integer): TOracleMode;
var
  W, W2: string;
begin
  Result := omStatement;
  W := OracleWord(AText, P);
  if (W = 'DECLARE') or (W = 'BEGIN') then
  begin
    Result := omBlock;
  end
  else if W = 'CREATE' then
  begin
    repeat
      W2 := OracleWord(AText, P);
    until not ((W2 = 'OR') or (W2 = 'REPLACE') or (W2 = 'EDITIONABLE') or (W2 = 'NONEDITIONABLE') or
      (W2 = 'EDITIONING') or (W2 = 'AND') or (W2 = 'COMPILE') or (W2 = 'RESOLVE') or (W2 = 'NOFORCE'));
    if (W2 = 'PROCEDURE') or (W2 = 'FUNCTION') or (W2 = 'PACKAGE') or (W2 = 'TRIGGER') or
      (W2 = 'TYPE') or (W2 = 'LIBRARY') or (W2 = 'JAVA') then
    begin
      Result := omBlock;
    end;
  end
  else if W = 'WITH' then
  begin
    W2 := OracleWord(AText, P);
    if (W2 = 'FUNCTION') or (W2 = 'PROCEDURE') then
    begin
      Result := omBlock;
    end;
  end
  else if (W = 'REM') or (W = 'REMARK') or (W = 'PROMPT') or (W = 'SPOOL') or (W = 'WHENEVER') or
    (W = 'EXEC') or (W = 'EXECUTE') or (W = 'DEFINE') or (W = 'UNDEFINE') or (W = 'SHOW') then
  begin
    Result := omLine;
  end
  else if W = 'SET' then
  begin
    W2 := OracleWord(AText, P);
    if (W2 = 'SERVEROUTPUT') or (W2 = 'ECHO') or (W2 = 'FEEDBACK') or (W2 = 'DEFINE') or
      (W2 = 'LINESIZE') or (W2 = 'PAGESIZE') or (W2 = 'TIMING') or (W2 = 'VERIFY') or
      (W2 = 'HEADING') or (W2 = 'TERMOUT') or (W2 = 'TRIMSPOOL') or (W2 = 'SQLBLANKLINES') or
      (W2 = 'SCAN') or (W2 = 'LONG') or (W2 = 'TAB') or (W2 = 'WRAP') then
    begin
      Result := omLine;
    end;
  end;
end;

function SplitOracle(const AText: string): TpgnStatementSpans;
var
  I, N, StartPos, Count, J: Integer;
  State: TScanState;
  C: Char;
  Mode: TOracleMode;

  procedure AddSpan(AStart, AEnd, ADelimEnd: Integer);
  begin
    if Count >= Length(Result) then
    begin
      SetLength(Result, Count * 2 + 8);
    end;
    Result[Count].StartPos := AStart;
    Result[Count].EndPos := AEnd;
    Result[Count].DelimEnd := ADelimEnd;
    Inc(Count);
    Mode := omUndecided;
  end;

  // a '/' with nothing but blanks around it on its line
  function SlashLine(P: Integer): Boolean;
  var
    K: Integer;
  begin
    K := P - 1;
    while (K >= 1) and (AText[K] in [' ', #9]) do
    begin
      Dec(K);
    end;
    Result := (K < 1) or (AText[K] in [#10, #13]);
    if not Result then
    begin
      Exit;
    end;
    K := P + 1;
    while (K <= N) and (AText[K] in [' ', #9, #13]) do
    begin
      Inc(K);
    end;
    Result := (K > N) or (AText[K] = #10);
  end;

begin
  Result := nil;
  Count := 0;
  N := Length(AText);
  State := ssNormal;
  StartPos := 1;
  Mode := omUndecided;
  I := 1;
  while I <= N do
  begin
    C := AText[I];
    case State of
      ssNormal:
        begin
          if (Mode = omUndecided) and (C in ['A'..'Z', 'a'..'z']) then
          begin
            Mode := OracleModeAt(AText, I);
          end;
          if (C = '/') and SlashLine(I) then
          begin
            AddSpan(StartPos, I - 1, I);
            StartPos := I + 1;
          end
          else if (Mode = omLine) and (C = #10) then
          begin
            AddSpan(StartPos, I - 1, I - 1);
            StartPos := I + 1;
          end
          else if (C = ';') and (Mode in [omUndecided, omStatement]) then
          begin
            AddSpan(StartPos, I - 1, I);
            StartPos := I + 1;
          end
          else if (C in ['q', 'Q']) and (OracleQQuoteEnd(AText, I) > 0) then
          begin
            I := OracleQQuoteEnd(AText, I);
          end
          else if C = '''' then
          begin
            State := ssSingle;
          end
          else if C = '"' then
          begin
            State := ssDouble;
          end
          else if (C = '-') and (I < N) and (AText[I + 1] = '-') then
          begin
            State := ssLineComment;
            Inc(I);
          end
          else if (C = '/') and (I < N) and (AText[I + 1] = '*') then
          begin
            State := ssBlockComment;
            Inc(I);
          end;
        end;
      ssSingle:
        begin
          if C = '''' then
          begin
            State := ssNormal;   // '' inside reopens at once
          end;
        end;
      ssDouble:
        begin
          if C = '"' then
          begin
            State := ssNormal;
          end;
        end;
      ssLineComment:
        begin
          if C = #10 then
          begin
            State := ssNormal;
            if Mode = omLine then
            begin
              AddSpan(StartPos, I - 1, I - 1);
              StartPos := I + 1;
            end;
          end;
        end;
      ssBlockComment:
        begin
          if (C = '*') and (I < N) and (AText[I + 1] = '/') then
          begin
            State := ssNormal;
            Inc(I);
          end;
        end;
    end;
    Inc(I);
  end;
  J := N;
  AddSpan(StartPos, J, J);
  SetLength(Result, Count);
end;

{ SQL Server: batches end at a line holding only GO (or "GO 5"), outside
  strings, [names] and comments; the GO line itself is never sent. }
function SplitTSQL(const AText: string): TpgnStatementSpans;
var
  I, N, StartPos, Count, LineStart: Integer;
  State: TScanState;
  C: Char;
  InBracket: Boolean;
  Depth: Integer;
  Line: string;

  procedure AddSpan(AStart, AEnd, ADelimEnd: Integer);
  begin
    if Count >= Length(Result) then
    begin
      SetLength(Result, Count * 2 + 8);
    end;
    Result[Count].StartPos := AStart;
    Result[Count].EndPos := AEnd;
    Result[Count].DelimEnd := ADelimEnd;
    Inc(Count);
  end;

  function IsGoLine(const AL: string): Boolean;
  var
    T: string;
    J: Integer;
  begin
    T := Trim(AL);
    // a comment after GO is allowed
    J := Pos('--', T);
    if J > 0 then
    begin
      T := Trim(Copy(T, 1, J - 1));
    end;
    Result := False;
    if not SameText(Copy(T, 1, 2), 'GO') then
    begin
      Exit;
    end;
    T := Trim(Copy(T, 3, MaxInt));
    for J := 1 to Length(T) do
    begin
      if not (T[J] in ['0'..'9']) then
      begin
        Exit;
      end;
    end;
    Result := True;
  end;

begin
  Result := nil;
  Count := 0;
  N := Length(AText);
  State := ssNormal;
  InBracket := False;
  Depth := 0;
  StartPos := 1;
  LineStart := 1;
  I := 1;
  while I <= N + 1 do
  begin
    if I <= N then
    begin
      C := AText[I];
    end
    else
    begin
      C := #10;
    end;
    if C = #10 then
    begin
      // the end of a line outside strings and block comments: a GO line?
      if (State in [ssNormal, ssLineComment]) and not InBracket then
      begin
        Line := Copy(AText, LineStart, I - LineStart);
        if IsGoLine(Line) then
        begin
          AddSpan(StartPos, LineStart - 1, Min(I, N));
          StartPos := I + 1;
        end;
      end;
      if State = ssLineComment then
      begin
        State := ssNormal;
      end;
      LineStart := I + 1;
      Inc(I);
      Continue;
    end;
    case State of
      ssNormal:
        begin
          if InBracket then
          begin
            if C = ']' then
            begin
              if (I < N) and (AText[I + 1] = ']') then
              begin
                Inc(I);
              end
              else
              begin
                InBracket := False;
              end;
            end;
          end
          else if C = '[' then
          begin
            InBracket := True;
          end
          else if C = '''' then
          begin
            State := ssSingle;
          end
          else if C = '"' then
          begin
            State := ssDouble;
          end
          else if (C = '-') and (I < N) and (AText[I + 1] = '-') then
          begin
            State := ssLineComment;
            Inc(I);
          end
          else if (C = '/') and (I < N) and (AText[I + 1] = '*') then
          begin
            State := ssBlockComment;
            Depth := 1;
            Inc(I);
          end;
        end;
      ssSingle:
        begin
          if C = '''' then
          begin
            State := ssNormal;   // a doubled quote reopens at once
          end;
        end;
      ssDouble:
        begin
          if C = '"' then
          begin
            State := ssNormal;
          end;
        end;
      ssBlockComment:
        begin
          // SQL Server's block comments nest
          if (C = '/') and (I < N) and (AText[I + 1] = '*') then
          begin
            Inc(Depth);
            Inc(I);
          end
          else if (C = '*') and (I < N) and (AText[I + 1] = '/') then
          begin
            Dec(Depth);
            Inc(I);
            if Depth = 0 then
            begin
              State := ssNormal;
            end;
          end;
        end;
    end;
    Inc(I);
  end;
  if StartPos <= N then
  begin
    AddSpan(StartPos, N, N);
  end;
  SetLength(Result, Count);
end;

function SplitStatements(const AText: string; ADialect: TpgnDialect): TpgnStatementSpans;
var
  I, J, N, StartPos, Count: Integer;
  State: TScanState;
  C: Char;
  Delim, NewDelim: string;
  Escapes: Boolean;

  procedure AddSpan(AStart, AEnd, ADelimEnd: Integer);
  begin
    if Count >= Length(Result) then
    begin
      SetLength(Result, Count * 2 + 8);
    end;
    Result[Count].StartPos := AStart;
    Result[Count].EndPos := AEnd;
    Result[Count].DelimEnd := ADelimEnd;
    Inc(Count);
  end;

  // only spaces or tabs between the start of the line and position P
  function AtLineStart(P: Integer): Boolean;
  var
    K: Integer;
  begin
    K := P - 1;
    while (K >= 1) and (AText[K] in [' ', #9]) do
    begin
      Dec(K);
    end;
    Result := (K < 1) or (AText[K] in [#10, #13]);
  end;

  function IsDelimiterCommand(P: Integer): Boolean;
  begin
    Result := (P + 9 <= N) and SameText(Copy(AText, P, 9), 'DELIMITER') and
              (AText[P + 9] in [' ', #9]) and AtLineStart(P);
  end;

begin
  if ADialect = sdOracle then
  begin
    Result := SplitOracle(AText);
    Exit;
  end;
  if ADialect = sdTSQL then
  begin
    Result := SplitTSQL(AText);
    Exit;
  end;
  Result := nil;
  Count := 0;
  N := Length(AText);
  State := ssNormal;
  Escapes := True;
  StartPos := 1;
  Delim := ';';
  I := 1;
  while I <= N do
  begin
    C := AText[I];
    case State of
      ssNormal:
        begin
          if (C in ['D', 'd']) and (ADialect = sdMySQL) and IsDelimiterCommand(I) then
          begin
            // whatever came before this line is a statement of its own
            AddSpan(StartPos, I - 1, I - 1);
            J := I + 9;
            while (J <= N) and (AText[J] in [' ', #9]) do
            begin
              Inc(J);
            end;
            NewDelim := '';
            while (J <= N) and not (AText[J] in [' ', #9, #10, #13]) do
            begin
              NewDelim := NewDelim + AText[J];
              Inc(J);
            end;
            if NewDelim <> '' then
            begin
              Delim := NewDelim;
            end;
            // skip the rest of the DELIMITER line
            while (J <= N) and (AText[J] <> #10) do
            begin
              Inc(J);
            end;
            StartPos := J + 1;
            I := J;
          end
          else if (C = Delim[1]) and (Copy(AText, I, Length(Delim)) = Delim) then
          begin
            AddSpan(StartPos, I - 1, I + Length(Delim) - 1);
            StartPos := I + Length(Delim);
            I := I + Length(Delim) - 1;
          end
          else if C = '''' then
          begin
            State := ssSingle;
            Escapes := BackslashString(AText, I, ADialect);
          end
          else if C = '"' then
          begin
            State := ssDouble;
          end
          else if (C = '`') and (ADialect = sdMySQL) then
          begin
            State := ssBacktick;
          end
          else if (C = '$') and (ADialect = sdPostgreSQL) and (DollarTagAt(AText, I) <> '') then
          begin
            // $$ ... $$: a function body, semicolons and all
            I := DollarQuoteEnd(AText, I, DollarTagAt(AText, I));
          end
          else if (C = '-') and (I < N) and (AText[I + 1] = '-') then
          begin
            State := ssLineComment;
            Inc(I);
          end
          else if (C = '#') and (ADialect = sdMySQL) then
          begin
            State := ssLineComment;
          end
          else if (C = '/') and (I < N) and (AText[I + 1] = '*') then
          begin
            State := ssBlockComment;
            Inc(I);
          end;
        end;
      ssSingle:
        begin
          if (C = '\') and Escapes then
          begin
            Inc(I);  // skip escaped character
          end
          else if C = '''' then
          begin
            State := ssNormal;
          end;
        end;
      ssDouble:
        begin
          if (C = '\') and (ADialect = sdMySQL) then
          begin
            Inc(I);
          end
          else if C = '"' then
          begin
            State := ssNormal;
          end;
        end;
      ssBacktick:
        begin
          if C = '`' then
          begin
            State := ssNormal;
          end;
        end;
      ssLineComment:
        begin
          if C = #10 then
          begin
            State := ssNormal;
          end;
        end;
      ssBlockComment:
        begin
          if (C = '*') and (I < N) and (AText[I + 1] = '/') then
          begin
            State := ssNormal;
            Inc(I);
          end;
        end;
    end;
    Inc(I);
  end;
  AddSpan(StartPos, N, N);
  SetLength(Result, Count);
end;

function SpanText(const AText: string; const ASpan: TpgnStatementSpan): string;
begin
  Result := Trim(Copy(AText, ASpan.StartPos, ASpan.EndPos - ASpan.StartPos + 1));
end;


{ Marks which characters are inside comments (the -- # /* */ markers
  included). Quoted text is never a comment. Index 0 = character 1. }
function CommentMask(const AText: string; ADialect: TpgnDialect): TpgnBoolArray;
var
  I, N: Integer;
  State: TScanState;
  C: Char;
  Escapes: Boolean;

  // "/*!" or "/*M!" at P: a MySQL / MariaDB executable comment
  function IsExecutableComment(P: Integer): Boolean;
  begin
    Result := ((P + 2 <= N) and (AText[P + 2] = '!')) or
              ((P + 3 <= N) and (AText[P + 2] = 'M') and (AText[P + 3] = '!'));
  end;

begin
  N := Length(AText);
  Result := nil;
  SetLength(Result, N);
  State := ssNormal;
  Escapes := True;
  I := 1;
  while I <= N do
  begin
    C := AText[I];
    case State of
      ssNormal:
        begin
          if C = '''' then
          begin
            State := ssSingle;
            Escapes := BackslashString(AText, I, ADialect);
          end
          else if C = '"' then
          begin
            State := ssDouble;
          end
          else if (C = '`') and (ADialect = sdMySQL) then
          begin
            State := ssBacktick;
          end
          else if (C = '$') and (ADialect = sdPostgreSQL) and (DollarTagAt(AText, I) <> '') then
          begin
            I := DollarQuoteEnd(AText, I, DollarTagAt(AText, I));
          end
          else if (C = '-') and (I < N) and (AText[I + 1] = '-') then
          begin
            State := ssLineComment;
            Result[I - 1] := True;
            Inc(I);
            Result[I - 1] := True;
          end
          else if (C = '#') and (ADialect = sdMySQL) then
          begin
            State := ssLineComment;
            Result[I - 1] := True;
          end
          else if (C = '/') and (I < N) and (AText[I + 1] = '*') and (ADialect = sdMySQL) and
            IsExecutableComment(I) then
          begin
            // /*! ... */ (and MariaDB's /*M! ... */) is code on MySQL: leave it unmarked
            Inc(I);
          end
          else if (C = '/') and (I < N) and (AText[I + 1] = '*') then
          begin
            State := ssBlockComment;
            Result[I - 1] := True;
            Inc(I);
            Result[I - 1] := True;
          end;
        end;
      ssSingle:
        begin
          if (C = '\') and Escapes then
          begin
            Inc(I);
          end
          else if C = '''' then
          begin
            State := ssNormal;
          end;
        end;
      ssDouble:
        begin
          if (C = '\') and (ADialect = sdMySQL) then
          begin
            Inc(I);
          end
          else if C = '"' then
          begin
            State := ssNormal;
          end;
        end;
      ssBacktick:
        begin
          if C = '`' then
          begin
            State := ssNormal;
          end;
        end;
      ssLineComment:
        begin
          if C = #10 then
          begin
            State := ssNormal;
          end
          else
          begin
            Result[I - 1] := True;
          end;
        end;
      ssBlockComment:
        begin
          Result[I - 1] := True;
          if (C = '*') and (I < N) and (AText[I + 1] = '/') then
          begin
            Inc(I);
            Result[I - 1] := True;
            State := ssNormal;
          end;
        end;
    end;
    Inc(I);
  end;
end;

function HasCode(const AText: string; ADialect: TpgnDialect): Boolean;
var
  Mask: TpgnBoolArray;
  I: Integer;
begin
  Result := False;
  Mask := CommentMask(AText, ADialect);
  for I := 1 to Length(AText) do
  begin
    if (not Mask[I - 1]) and not (AText[I] in [' ', #9, #10, #13]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function CaretOnCommentLine(const AText: string; ACaretPos: Integer;
  ADialect: TpgnDialect): Boolean;
var
  Mask: TpgnBoolArray;
  LineStart, LineEnd, I, N: Integer;
  SawComment: Boolean;
begin
  Result := False;
  N := Length(AText);
  if N = 0 then
  begin
    Exit;
  end;
  if ACaretPos > N then
  begin
    ACaretPos := N;
  end;
  if ACaretPos < 1 then
  begin
    ACaretPos := 1;
  end;
  // the caret can sit on the line break itself; that's still its line
  LineStart := ACaretPos;
  if (AText[LineStart] = #10) and (LineStart > 1) then
  begin
    Dec(LineStart);
  end;
  if (AText[LineStart] = #13) and (LineStart > 1) then
  begin
    Dec(LineStart);
  end;
  while (LineStart > 1) and not (AText[LineStart - 1] in [#10, #13]) do
  begin
    Dec(LineStart);
  end;
  LineEnd := LineStart;
  while (LineEnd < N) and not (AText[LineEnd + 1] in [#10, #13]) do
  begin
    Inc(LineEnd);
  end;

  Mask := CommentMask(AText, ADialect);
  SawComment := False;
  for I := LineStart to LineEnd do
  begin
    if AText[I] in [' ', #9, #10, #13] then
    begin
      Continue;
    end;
    if not Mask[I - 1] then
    begin
      Exit;   // real code on this line
    end;
    SawComment := True;
  end;
  Result := SawComment;
end;

function StatementList(const AText: string; ADialect: TpgnDialect): TpgnStringArray;
var
  Spans: TpgnStatementSpans;
  I, Count: Integer;
  S: string;
begin
  Result := nil;
  Spans := SplitStatements(AText, ADialect);
  SetLength(Result, Length(Spans));
  Count := 0;
  for I := 0 to High(Spans) do
  begin
    S := SpanText(AText, Spans[I]);
    if HasCode(S, ADialect) then   // a statement that is only comments is never sent
    begin
      Result[Count] := S;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function FirstNonBlank(const AText: string; const ASpan: TpgnStatementSpan): Integer;
var
  I: Integer;
begin
  Result := ASpan.EndPos + 1;
  for I := ASpan.StartPos to ASpan.EndPos do
  begin
    if not (AText[I] in [' ', #9, #10, #13]) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

{ Returns the statement under the caret. If the caret sits in the blank
  space before a statement (for example right after the previous ';'),
  the previous statement is chosen, which matches how people expect
  "run current statement" to behave. }
function StatementSpanAt(const AText: string; ACaretPos: Integer;
  out AStart, AEnd: Integer; ADialect: TpgnDialect): Boolean;
var
  Spans: TpgnStatementSpans;
  I, Hit: Integer;
begin
  Result := False;
  AStart := 0;
  AEnd := 0;
  // a commented-out line is never run, even though the statement it
  // belongs to (the one after it) would be
  if CaretOnCommentLine(AText, ACaretPos, ADialect) then
  begin
    Exit;
  end;
  Spans := SplitStatements(AText, ADialect);
  if Length(Spans) = 0 then
  begin
    Exit;
  end;

  Hit := High(Spans);
  for I := 0 to High(Spans) do
  begin
    // the delimiter itself belongs to the statement it ends
    if ACaretPos <= Spans[I].DelimEnd then
    begin
      Hit := I;
      Break;
    end;
  end;

  if (ACaretPos < FirstNonBlank(AText, Spans[Hit])) or
    not HasCode(SpanText(AText, Spans[Hit]), ADialect) then
  begin
    I := Hit - 1;
    while (I >= 0) and not HasCode(SpanText(AText, Spans[I]), ADialect) do
    begin
      Dec(I);
    end;
    if I >= 0 then
    begin
      Hit := I;
    end;
  end;

  if not HasCode(SpanText(AText, Spans[Hit]), ADialect) then
  begin
    Exit;
  end;
  AStart := Spans[Hit].StartPos;
  AEnd := Spans[Hit].EndPos;
  Result := True;
end;

function StatementAt(const AText: string; ACaretPos: Integer; ADialect: TpgnDialect): string;
var
  A, B: Integer;
begin
  Result := '';
  if StatementSpanAt(AText, ACaretPos, A, B, ADialect) then
  begin
    Result := Copy(AText, A, B - A + 1);
    Result := Trim(Result);
  end;
end;

function TrimStatement(const AText: string): string;
begin
  Result := Trim(AText);
  while (Result <> '') and (Result[Length(Result)] = ';') do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
end;

{ First SQL keyword, uppercased, skipping whitespace and leading comments. }
function StatementOnlyReads(const ASQL: string): Boolean;
var
  K, U: string;
begin
  K := FirstKeyword(ASQL);
  if (K = 'SHOW') or (K = 'DESCRIBE') or (K = 'DESC') or (K = 'EXPLAIN') or
    (K = 'SET') or (K = 'USE') or (K = 'HELP') then
  begin
    Result := True;
  end
  else if (K = 'SELECT') or (K = 'WITH') or (K = 'TABLE') or (K = 'VALUES') then
  begin
    U := UpperCase(ASQL);
    Result := (Pos('FOR UPDATE', U) = 0) and (Pos('FOR SHARE', U) = 0) and
      (Pos('LOCK IN SHARE MODE', U) = 0);
  end
  else
  begin
    Result := False;
  end;
end;

function StatementChangesData(const ASQL: string): Boolean;
var
  K: string;
begin
  K := FirstKeyword(ASQL);
  Result := (K = 'INSERT') or (K = 'UPDATE') or (K = 'DELETE') or (K = 'MERGE') or
    (K = 'REPLACE') or (K = 'CALL') or (K = 'EXEC') or (K = 'EXECUTE') or
    (K = 'BEGIN') or (K = 'DECLARE');
end;

function StatementIsDDL(const ASQL: string): Boolean;
var
  K: string;
begin
  K := FirstKeyword(ASQL);
  Result := (K = 'CREATE') or (K = 'ALTER') or (K = 'DROP') or (K = 'TRUNCATE') or
    (K = 'RENAME') or (K = 'GRANT') or (K = 'REVOKE') or (K = 'COMMENT');
end;

function StatementEndsTransaction(const ASQL: string; ATransactionalDDL: Boolean): Boolean;
var
  K: string;
begin
  K := FirstKeyword(ASQL);
  Result := (K = 'COMMIT') or (K = 'ROLLBACK') or ((not ATransactionalDDL) and StatementIsDDL(ASQL));
end;

function FirstKeyword(const AText: string): string;
var
  I, N, Start: Integer;
begin
  Result := '';
  N := Length(AText);
  I := 1;
  while I <= N do
  begin
    if AText[I] in [' ', #9, #10, #13, '('] then
    begin
      Inc(I);
    end
    else if (AText[I] = '-') and (I < N) and (AText[I + 1] = '-') then
    begin
      while (I <= N) and (AText[I] <> #10) do
      begin
        Inc(I);
      end;
    end
    else if AText[I] = '#' then
    begin
      while (I <= N) and (AText[I] <> #10) do
      begin
        Inc(I);
      end;
    end
    else if (AText[I] = '/') and (I < N) and (AText[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < N) and not ((AText[I] = '*') and (AText[I + 1] = '/')) do
      begin
        Inc(I);
      end;
      Inc(I, 2);
    end
    else
    begin
      Break;
    end;
  end;

  Start := I;
  while (I <= N) and (AText[I] in ['A'..'Z', 'a'..'z']) do
  begin
    Inc(I);
  end;
  Result := UpperCase(Copy(AText, Start, I - Start));
end;

{ CREATE / DROP / ALTER / RENAME of a database or schema changes the
  database list; of a table or view, the object lists. Looks at the first
  few words only (after modifiers like OR REPLACE, TEMPORARY, DEFINER=...). }
function SchemaChangeOf(const AText: string): TpgnSchemaChange;
var
  K, W, U: string;
  I, N, Words: Integer;
begin
  Result := scNone;
  K := FirstKeyword(AText);
  if not ((K = 'CREATE') or (K = 'DROP') or (K = 'ALTER') or (K = 'RENAME')) then
  begin
    Exit;
  end;

  U := UpperCase(AText);
  N := Length(U);
  I := 1;
  Words := 0;
  while (I <= N) and (Words < 12) do
  begin
    while (I <= N) and not (U[I] in ['A'..'Z', '_']) do
    begin
      Inc(I);
    end;
    W := '';
    while (I <= N) and (U[I] in ['A'..'Z', '_']) do
    begin
      W := W + U[I];
      Inc(I);
    end;
    if W = '' then
    begin
      Break;
    end;
    Inc(Words);
    if (W = 'DATABASE') or (W = 'SCHEMA') then
    begin
      Result := scDatabases;
      Exit;
    end;
    if (W = 'TABLE') or (W = 'VIEW') or (W = 'PROCEDURE') or (W = 'FUNCTION') or
      (W = 'TRIGGER') then
    begin
      Result := scObjects;
      Exit;
    end;
  end;
end;

{ Next token from position P (1-based), skipping blanks and comments.
  Quoted identifiers and strings are one token. Returns '' at the end. }
function NextToken(const S: string; var P: Integer; out AStart: Integer): string;
var
  N: Integer;
  Q: Char;
begin
  Result := '';
  N := Length(S);
  while P <= N do
  begin
    if S[P] in [' ', #9, #10, #13] then
    begin
      Inc(P);
    end
    else if (S[P] = '-') and (P < N) and (S[P + 1] = '-') then
    begin
      while (P <= N) and not (S[P] in [#10, #13]) do
      begin
        Inc(P);
      end;
    end
    else if S[P] = '#' then
    begin
      while (P <= N) and not (S[P] in [#10, #13]) do
      begin
        Inc(P);
      end;
    end
    else if (S[P] = '/') and (P < N) and (S[P + 1] = '*') then
    begin
      Inc(P, 2);
      while (P < N) and not ((S[P] = '*') and (S[P + 1] = '/')) do
      begin
        Inc(P);
      end;
      Inc(P, 2);
    end
    else
    begin
      Break;
    end;
  end;
  AStart := P;
  if P > N then
  begin
    Exit;
  end;
  if S[P] in ['`', '''', '"'] then
  begin
    Q := S[P];
    Inc(P);
    while (P <= N) and (S[P] <> Q) do
    begin
      Inc(P);
    end;
    Inc(P);
  end
  else if S[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', #128..#255] then
  begin
    while (P <= N) and (S[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', #128..#255]) do
    begin
      Inc(P);
    end;
  end
  else
  begin
    Inc(P);
  end;
  Result := Copy(S, AStart, P - AStart);
end;

function Unquote(const T: string): string;
begin
  Result := T;
  if (Length(T) >= 2) and (T[1] in ['`', '"', '''']) then
  begin
    Result := Copy(T, 2, Length(T) - 2);
  end;
end;

function FindCreateName(const ASQL: string; out AStart, ALength: Integer;
  out AName, AKindWord: string): Boolean;
var
  P, TS, NameStart, AfterName: Integer;
  T, U: string;
begin
  Result := False;
  AStart := 0;
  ALength := 0;
  AName := '';
  AKindWord := '';
  P := 1;
  T := NextToken(ASQL, P, TS);
  if not SameText(T, 'CREATE') then
  begin
    Exit;
  end;
  repeat
    T := NextToken(ASQL, P, TS);
    U := UpperCase(T);
    if U = 'DEFINER' then
    begin
      // DEFINER = user@host, or CURRENT_USER / CURRENT_USER()
      NextToken(ASQL, P, TS);                  // =
      NextToken(ASQL, P, TS);                  // user or CURRENT_USER
      T := NextToken(ASQL, P, TS);
      if T = '@' then
      begin
        NextToken(ASQL, P, TS);                // host
      end
      else if T = '(' then
      begin
        NextToken(ASQL, P, TS);                // )
      end
      else
      begin
        P := TS;                               // not part of DEFINER
      end;
      U := '';
    end
    else if (U = 'OR') or (U = 'REPLACE') or (U = 'AGGREGATE') or (U = 'EDITIONABLE') or
      (U = 'NONEDITIONABLE') then
    begin
      U := '';   // Oracle: CREATE OR REPLACE EDITIONABLE PROCEDURE ...
    end;
  until (U <> '') or (T = '');
  if (U <> 'PROCEDURE') and (U <> 'FUNCTION') and (U <> 'TRIGGER') then
  begin
    Exit;
  end;
  AKindWord := U;

  T := NextToken(ASQL, P, TS);
  if SameText(T, 'IF') then
  begin
    NextToken(ASQL, P, TS);                    // NOT
    NextToken(ASQL, P, TS);                    // EXISTS
    T := NextToken(ASQL, P, TS);
  end;
  if T = '' then
  begin
    Exit;
  end;
  NameStart := TS;
  AName := Unquote(T);
  AfterName := P;
  // db.name: the name is the part after the dot
  T := NextToken(ASQL, P, TS);
  if T = '.' then
  begin
    T := NextToken(ASQL, P, TS);
    AName := Unquote(T);
    AfterName := P;
  end;
  AStart := NameStart;
  ALength := AfterName - NameStart;
  Result := AName <> '';
end;

end.
