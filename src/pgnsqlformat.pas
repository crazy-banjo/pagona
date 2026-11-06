// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnSqlFormat;

{ Format SQL and Join Lines.

  The SQL reader (Tokenize) knows each dialect's words, quoted names,
  strings (N'', E'', q'[ ]', $$ $$), comments, hints and symbols, and keeps
  the whitespace before each token so comments stay where they were.

  Format SQL changes only the layout: spaces, line breaks, indentation and
  the case of keywords. Each statement is formatted on its own; afterwards
  its words are compared with the original's (SameMeaning), and a
  statement whose words differ in anything but whitespace and keyword case
  is left exactly as written. Statements Pagona doesn't lay out (GRANT,
  ALTER, SQL*Plus lines, PostgreSQL function bodies...) stay as written.

  Join Lines puts each statement on one line, comments removed (optimizer
  hints kept), for jobs, shell scripts and report expressions. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, pgnTypes, pgnSqlSplit;

type
  TpgnKeywordCase = (kcUpper, kcLower, kcAsTyped);

  TpgnFormatOptions = record
    KeywordCase: TpgnKeywordCase;
    IndentSize: Integer;          // spaces per level
    UseTabs: Boolean;             // a tab per level instead
    LeadingCommas: Boolean;       // ", col" at the start of the line
    OneColumnPerLine: Boolean;    // else packed to LineWidth
    LineWidth: Integer;
    AndOrNewLine: Boolean;        // AND / OR start lines in WHERE, HAVING, ON
    JoinIndented: Boolean;        // JOIN under FROM, indented (else level with it)
    River: Boolean;               // SELECT / FROM / WHERE right-aligned
    BlankLineBetween: Boolean;    // a blank line between statements
  end;

  TpgnTokKind = (tkWord, tkQuoted, tkString, tkNumber, tkSymbol, tkOuterMark,
    tkLineComment, tkBlockComment);

  TpgnTok = record
    Kind: TpgnTokKind;
    Text: string;
    Up: string;          // words: upper case
    StartPos: Integer;   // 1-based in the text read
    EndPos: Integer;     // inclusive
    NLBefore: Integer;   // line breaks in the whitespace before it
  end;
  TpgnToks = array of TpgnTok;

function DefaultFormatOptions: TpgnFormatOptions;

{ The text as tokens (whitespace dropped, counted in NLBefore). }
function Tokenize(const AText: string; ADialect: TpgnDialect): TpgnToks;

{ True when B says what A says: the same tokens, keyword case aside (and,
  with AIgnoreComments, comments other than hints left out). AWhere: the
  1-based line in B of the first difference. }
function SameMeaning(const A, B: string; ADialect: TpgnDialect; AIgnoreComments: Boolean;
  out AWhere: Integer): Boolean;

{ Formats AText. ALeftAlone: how many statements were left as written
  because formatting would have changed more than the layout. }
function FormatSql(const AText: string; ADialect: TpgnDialect; const AOpt: TpgnFormatOptions;
  out ALeftAlone: Integer): string;

{ Each statement on one line, comments removed (hints kept). }
function JoinSqlLines(const AText: string; ADialect: TpgnDialect; out ALeftAlone: Integer): string;

function IsSqlKeyword(const AUpper: string): Boolean;

implementation

const
  { Keywords whose case Format may change. Words that are often column or
    table names (USER, DATE, TYPE, NAME, LEVEL, COMMENT, BODY...) are left out,
    and a word where a table name goes is never changed (MySQL table names
    are case-sensitive on Linux). }
  KeywordList: array[0..177] of string = (
    'ADD', 'AFTER', 'ALL', 'ALTER', 'AND', 'ANY', 'APPLY', 'AS', 'ASC', 'AUTHID', 'BEFORE',
    'BEGIN', 'BETWEEN', 'BREAK', 'BULK', 'BY', 'CASCADE', 'CASE', 'CATCH', 'CHECK',
    'CLOSE', 'COLLECT', 'COLUMN', 'COMMIT', 'CONNECT', 'CONSTRAINT', 'CONTINUE', 'CREATE',
    'CROSS', 'CURRENT', 'CURSOR', 'DEALLOCATE', 'DECLARE', 'DEFAULT', 'DEFINER', 'DELETE',
    'DESC', 'DETERMINISTIC', 'DISTINCT', 'DO', 'DROP', 'EACH', 'EDITIONABLE', 'ELSE',
    'ELSEIF', 'ELSIF', 'END', 'ESCAPE', 'EXCEPT', 'EXCEPTION', 'EXEC', 'EXECUTE', 'EXISTS',
    'EXIT', 'FALSE', 'FETCH', 'FIRST', 'FOLLOWING', 'FOR', 'FORALL', 'FORCE', 'FOREIGN',
    'FROM', 'FULL', 'FUNCTION', 'GLOBAL', 'GOTO', 'GRANT', 'GROUP', 'HANDLER', 'HAVING', 'IF',
    'IMMEDIATE', 'IN', 'INDEX', 'INNER', 'INOUT', 'INSERT', 'INSTEAD', 'INTERSECT', 'INTO',
    'IS', 'ITERATE', 'JOIN', 'KEY', 'LANGUAGE', 'LAST', 'LATERAL', 'LEAVE', 'LEFT', 'LIKE',
    'LIMIT', 'LOOP', 'MATCHED', 'MERGE', 'MINUS', 'NATURAL', 'NEXT', 'NOCOPY', 'NOT', 'NULL',
    'NULLS', 'OF', 'OFFSET', 'ON', 'ONLY', 'OPEN', 'OR', 'ORDER', 'OTHERS', 'OUT', 'OUTER',
    'OVER', 'PACKAGE', 'PARTITION', 'PIPELINED', 'PRECEDING', 'PRIMARY', 'PRINT', 'PRIOR',
    'PROCEDURE', 'RAISE', 'RAISERROR', 'RANGE', 'RECURSIVE', 'REFERENCES', 'REPEAT',
    'REPLACE', 'RETURN', 'RETURNING', 'RETURNS', 'REVOKE', 'RIGHT', 'ROLLBACK', 'ROW',
    'ROWS', 'ROWTYPE', 'SAVEPOINT', 'SELECT', 'SET', 'SIBLINGS', 'START', 'TABLE',
    'TEMPORARY', 'THEN', 'THROW', 'TIES', 'TO', 'TOP', 'TRAN', 'TRANSACTION', 'TRIGGER',
    'TRUE', 'TRUNCATE', 'TRY', 'UNBOUNDED', 'UNION', 'UNIQUE', 'UNTIL', 'UPDATE', 'USING',
    'VALUES', 'VIEW', 'WHEN', 'WHERE', 'WHILE', 'WITH', 'WITHIN', 'WORK', 'PERCENT',
    'NOWAIT', 'WAIT', 'SKIP', 'LOCKED', 'MATERIALIZED', 'PIVOT', 'UNPIVOT', 'STRAIGHT_JOIN');

var
  Keywords: TStringList = nil;

function IsSqlKeyword(const AUpper: string): Boolean;
var
  I: Integer;
begin
  if Keywords = nil then
  begin
    Keywords := TStringList.Create;
    Keywords.Sorted := True;
    Keywords.CaseSensitive := True;
    Keywords.Duplicates := dupIgnore;
    for I := Low(KeywordList) to High(KeywordList) do
    begin
      Keywords.Add(KeywordList[I]);
    end;
  end;
  Result := Keywords.IndexOf(AUpper) >= 0;
end;

function DefaultFormatOptions: TpgnFormatOptions;
begin
  Result.KeywordCase := kcUpper;
  Result.IndentSize := 4;
  Result.UseTabs := False;
  Result.LeadingCommas := False;
  Result.OneColumnPerLine := True;
  Result.LineWidth := 100;
  Result.AndOrNewLine := True;
  Result.JoinIndented := False;
  Result.River := False;
  Result.BlankLineBetween := True;
end;

{ ============================================================== reader }

function IsWordStart(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_']) or (Ord(C) >= 128);
end;

function IsWordChar(C: Char; ADialect: TpgnDialect): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_', '0'..'9', '$']) or (Ord(C) >= 128);
  if (not Result) and (ADialect in [sdOracle, sdTSQL]) then
  begin
    Result := C = '#';
  end;
end;

{ PostgreSQL dollar-quote tag at P ($$ or $tag$), or ''. }
function DollarTag(const S: string; P: Integer): string;
var
  J, N: Integer;
begin
  Result := '';
  N := Length(S);
  if (P > N) or (S[P] <> '$') then
  begin
    Exit;
  end;
  if (P > 1) and IsWordChar(S[P - 1], sdPostgreSQL) then
  begin
    Exit;
  end;
  J := P + 1;
  if (J <= N) and (S[J] in ['0'..'9']) then
  begin
    Exit;
  end;
  while (J <= N) and ((S[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(S[J]) >= 128)) do
  begin
    Inc(J);
  end;
  if (J <= N) and (S[J] = '$') then
  begin
    Result := Copy(S, P, J - P + 1);
  end;
end;

function Tokenize(const AText: string; ADialect: TpgnDialect): TpgnToks;
var
  S: string;
  N, P, Q, Count, NL: Integer;
  T: TpgnTok;
  C, Close: Char;
  Tag: string;

  procedure Add(AKind: TpgnTokKind; AFrom, ATo: Integer);
  begin
    T.Kind := AKind;
    T.Text := Copy(S, AFrom, ATo - AFrom + 1);
    if AKind = tkWord then
    begin
      T.Up := UpperCase(T.Text);
    end
    else
    begin
      T.Up := T.Text;
    end;
    T.StartPos := AFrom;
    T.EndPos := ATo;
    T.NLBefore := NL;
    if Count >= Length(Result) then
    begin
      SetLength(Result, Count * 2 + 16);
    end;
    Result[Count] := T;
    Inc(Count);
    NL := 0;
  end;

  { A quoted run from P (the opening quote) to its closing quote, a doubled
    quote standing for one; MySQL also knows backslash escapes. }
  function QuoteEnd(AFrom: Integer; AQuote: Char; ABackslash: Boolean): Integer;
  var
    J: Integer;
  begin
    J := AFrom + 1;
    while J <= N do
    begin
      if ABackslash and (S[J] = '\') then
      begin
        Inc(J, 2);
        Continue;
      end;
      if S[J] = AQuote then
      begin
        if (J < N) and (S[J + 1] = AQuote) then
        begin
          Inc(J, 2);
          Continue;
        end;
        Result := J;
        Exit;
      end;
      Inc(J);
    end;
    Result := N;
  end;

  function SymbolLen(AAt: Integer): Integer;
  const
    Three: array[0..1] of string = ('->>', '#>>');
    Two: array[0..17] of string = (':=', '=>', '<>', '!=', '>=', '<=', '||', '::', '..', '**',
      '<<', '>>', '->', '^=', '~=', '@>', '<@', '#>');
  var
    K: Integer;
  begin
    for K := Low(Three) to High(Three) do
    begin
      if Copy(S, AAt, 3) = Three[K] then
      begin
        Result := 3;
        Exit;
      end;
    end;
    for K := Low(Two) to High(Two) do
    begin
      if Copy(S, AAt, 2) = Two[K] then
      begin
        Result := 2;
        Exit;
      end;
    end;
    Result := 1;
  end;

begin
  Result := nil;
  S := AText;
  N := Length(S);
  P := 1;
  Count := 0;
  NL := 0;
  while P <= N do
  begin
    C := S[P];
    // whitespace
    if C in [' ', #9, #10, #13, #12, #11] then
    begin
      if C = #10 then
      begin
        Inc(NL);
      end
      else if (C = #13) and ((P = N) or (S[P + 1] <> #10)) then
      begin
        Inc(NL);
      end;
      Inc(P);
      Continue;
    end;
    // comments
    if (C = '-') and (P < N) and (S[P + 1] = '-') then
    begin
      Q := P;
      while (Q <= N) and not (S[Q] in [#10, #13]) do
      begin
        Inc(Q);
      end;
      Add(tkLineComment, P, Q - 1);
      P := Q;
      Continue;
    end;
    if (C = '#') and (ADialect = sdMySQL) then
    begin
      Q := P;
      while (Q <= N) and not (S[Q] in [#10, #13]) do
      begin
        Inc(Q);
      end;
      Add(tkLineComment, P, Q - 1);
      P := Q;
      Continue;
    end;
    if (C = '/') and (P < N) and (S[P + 1] = '*') then
    begin
      Q := Pos('*/', Copy(S, P + 2, MaxInt));
      if Q = 0 then
      begin
        Q := N;
      end
      else
      begin
        Q := P + 2 + Q;   // the '/' of '*/'
      end;
      Add(tkBlockComment, P, Q);
      P := Q + 1;
      Continue;
    end;
    // Oracle q'[...]' and prefixed strings: N'..', E'..', X'..', B'..'
    if (ADialect = sdOracle) and (C in ['q', 'Q']) and (P + 2 <= N) and (S[P + 1] = '''') then
    begin
      C := S[P + 2];
      case C of
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
          Close := C;
        end;
      end;
      Q := P + 3;
      while (Q < N) and not ((S[Q] = Close) and (S[Q + 1] = '''')) do
      begin
        Inc(Q);
      end;
      Add(tkString, P, Min(N, Q + 1));
      P := Q + 2;
      Continue;
    end;
    if (C in ['N', 'n', 'E', 'e', 'X', 'x', 'B', 'b']) and (P < N) and (S[P + 1] = '''') and
      ((P = 1) or not IsWordChar(S[P - 1], ADialect)) then
    begin
      Q := QuoteEnd(P + 1, '''', (ADialect = sdMySQL) or (C in ['E', 'e']));
      Add(tkString, P, Q);
      P := Q + 1;
      Continue;
    end;
    if C = '''' then
    begin
      Q := QuoteEnd(P, '''', ADialect = sdMySQL);
      Add(tkString, P, Q);
      P := Q + 1;
      Continue;
    end;
    if C = '"' then
    begin
      Q := QuoteEnd(P, '"', ADialect = sdMySQL);
      Add(tkQuoted, P, Q);
      P := Q + 1;
      Continue;
    end;
    if C = '`' then
    begin
      Q := QuoteEnd(P, '`', False);
      Add(tkQuoted, P, Q);
      P := Q + 1;
      Continue;
    end;
    if (C = '[') and (ADialect = sdTSQL) then
    begin
      Q := QuoteEnd(P, ']', False);
      Add(tkQuoted, P, Q);
      P := Q + 1;
      Continue;
    end;
    if (C = '$') and (ADialect = sdPostgreSQL) then
    begin
      Tag := DollarTag(S, P);
      if Tag <> '' then
      begin
        Q := Pos(Tag, Copy(S, P + Length(Tag), MaxInt));
        if Q = 0 then
        begin
          Q := N;
        end
        else
        begin
          Q := P + Length(Tag) + Q - 1 + Length(Tag) - 1;
        end;
        Add(tkString, P, Q);
        P := Q + 1;
        Continue;
      end;
    end;
    // Oracle's outer-join mark (+), spaces allowed inside
    if (C = '(') and (ADialect = sdOracle) then
    begin
      Q := P + 1;
      while (Q <= N) and (S[Q] in [' ', #9]) do
      begin
        Inc(Q);
      end;
      if (Q <= N) and (S[Q] = '+') then
      begin
        Inc(Q);
        while (Q <= N) and (S[Q] in [' ', #9]) do
        begin
          Inc(Q);
        end;
        if (Q <= N) and (S[Q] = ')') then
        begin
          Add(tkOuterMark, P, Q);
          Result[Count - 1].Text := '(+)';
          Result[Count - 1].Up := '(+)';
          P := Q + 1;
          Continue;
        end;
      end;
    end;
    // numbers (1..10 is a range: the dots are their own token)
    if (C in ['0'..'9']) or ((C = '.') and (P < N) and (S[P + 1] in ['0'..'9']) and
      ((P = 1) or not IsWordChar(S[P - 1], ADialect))) then
    begin
      Q := P;
      if (C = '0') and (P < N) and (S[P + 1] in ['x', 'X']) then
      begin
        Inc(Q, 2);
        while (Q <= N) and (S[Q] in ['0'..'9', 'a'..'f', 'A'..'F']) do
        begin
          Inc(Q);
        end;
      end
      else
      begin
        while (Q <= N) and (S[Q] in ['0'..'9']) do
        begin
          Inc(Q);
        end;
        if (Q <= N) and (S[Q] = '.') and not ((Q < N) and (S[Q + 1] = '.')) then
        begin
          Inc(Q);
          while (Q <= N) and (S[Q] in ['0'..'9']) do
          begin
            Inc(Q);
          end;
        end;
        if (Q < N) and (S[Q] in ['e', 'E']) and ((S[Q + 1] in ['0'..'9']) or
          ((Q + 1 < N) and (S[Q + 1] in ['+', '-']) and (S[Q + 2] in ['0'..'9']))) then
        begin
          Inc(Q, 2);
          while (Q <= N) and (S[Q] in ['0'..'9']) do
          begin
            Inc(Q);
          end;
        end;
      end;
      // a number glued to letters (1st, 2d) reads as one word
      while (Q <= N) and IsWordChar(S[Q], ADialect) do
      begin
        Inc(Q);
      end;
      Add(tkNumber, P, Q - 1);
      P := Q;
      Continue;
    end;
    // words, and words with a prefix: :bind, @var, @@var, &subst, #temp, $1
    if IsWordStart(C) or
      ((C = ':') and (P < N) and (IsWordStart(S[P + 1]) or (S[P + 1] in ['0'..'9']))) or
      ((C = '@') and (ADialect in [sdTSQL, sdMySQL]) and (P < N) and
        (IsWordStart(S[P + 1]) or (S[P + 1] = '@'))) or
      ((C = '&') and (ADialect = sdOracle) and (P < N) and (IsWordStart(S[P + 1]) or (S[P + 1] = '&'))) or
      ((C = '#') and (ADialect = sdTSQL) and (P < N) and (IsWordStart(S[P + 1]) or (S[P + 1] = '#'))) or
      ((C = '$') and (ADialect = sdPostgreSQL) and (P < N) and (S[P + 1] in ['0'..'9'])) then
    begin
      Q := P + 1;
      while (Q <= N) and ((S[Q] = '@') or (S[Q] = '&') or (S[Q] = '#')) and (Q = P + 1) do
      begin
        Inc(Q);
      end;
      while (Q <= N) and IsWordChar(S[Q], ADialect) do
      begin
        Inc(Q);
      end;
      // Oracle database links: table@link
      if (ADialect = sdOracle) and (Q < N) and (S[Q] = '@') and IsWordStart(S[Q + 1]) then
      begin
        Inc(Q);
        while (Q <= N) and (IsWordChar(S[Q], ADialect) or (S[Q] = '.')) do
        begin
          Inc(Q);
        end;
      end;
      Add(tkWord, P, Q - 1);
      P := Q;
      Continue;
    end;
    // symbols
    Q := SymbolLen(P);
    Add(tkSymbol, P, P + Q - 1);
    P := P + Q;
  end;
  SetLength(Result, Count);
end;

function IsHint(const T: TpgnTok): Boolean;
begin
  Result := (T.Kind = tkBlockComment) and (Copy(T.Text, 1, 3) = '/*+');
end;

function IsComment(const T: TpgnTok): Boolean;
begin
  Result := T.Kind in [tkLineComment, tkBlockComment];
end;

function LineOfPos(const AText: string; APos: Integer): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Min(APos, Length(AText)) - 1 do
  begin
    if AText[I] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

function SameMeaning(const A, B: string; ADialect: TpgnDialect; AIgnoreComments: Boolean;
  out AWhere: Integer): Boolean;
var
  TA, TB: TpgnToks;
  I, J: Integer;

  procedure Skip(const T: TpgnToks; var K: Integer);
  begin
    while AIgnoreComments and (K <= High(T)) and IsComment(T[K]) and not IsHint(T[K]) do
    begin
      Inc(K);
    end;
  end;

begin
  TA := Tokenize(A, ADialect);
  TB := Tokenize(B, ADialect);
  I := 0;
  J := 0;
  AWhere := 0;
  Result := False;
  while True do
  begin
    Skip(TA, I);
    Skip(TB, J);
    if (I > High(TA)) or (J > High(TB)) then
    begin
      Break;
    end;
    if TA[I].Kind <> TB[J].Kind then
    begin
      AWhere := LineOfPos(B, TB[J].StartPos);
      Exit;
    end;
    if (TA[I].Kind = tkWord) and IsSqlKeyword(TA[I].Up) then
    begin
      if TA[I].Up <> TB[J].Up then
      begin
        AWhere := LineOfPos(B, TB[J].StartPos);
        Exit;
      end;
    end
    else if IsComment(TA[I]) then
    begin
      if TrimRight(TA[I].Text) <> TrimRight(TB[J].Text) then
      begin
        AWhere := LineOfPos(B, TB[J].StartPos);
        Exit;
      end;
    end
    else if TA[I].Text <> TB[J].Text then
    begin
      AWhere := LineOfPos(B, TB[J].StartPos);
      Exit;
    end;
    Inc(I);
    Inc(J);
  end;
  Result := (I > High(TA)) and (J > High(TB));
  if not Result then
  begin
    if J <= High(TB) then
    begin
      AWhere := LineOfPos(B, TB[J].StartPos);
    end
    else
    begin
      AWhere := LineOfPos(B, Length(B));
    end;
  end;
end;

{ ============================================================ spacing }

function IsOperatorSym(const S: string): Boolean;
begin
  Result := (S = '=') or (S = '<') or (S = '>') or (S = '<>') or (S = '!=') or (S = '>=') or
    (S = '<=') or (S = '+') or (S = '-') or (S = '*') or (S = '/') or (S = '||') or (S = ':=') or
    (S = '=>') or (S = '%') or (S = '^=') or (S = '~=') or (S = '**') or (S = '->') or
    (S = '->>') or (S = '@>') or (S = '<@') or (S = '&') or (S = '|') or (S = '^') or (S = '~');
end;

{ What comes before a '(' that belongs to it with no space: a function or
  type name (COUNT(, NVL(, VARCHAR2(), not a keyword such as IN or AS. }
function GluesToParen(const APrev: TpgnTok): Boolean;
begin
  Result := False;
  if APrev.Kind = tkQuoted then
  begin
    Result := True;
  end
  else if APrev.Kind = tkWord then
  begin
    // LEFT( RIGHT( REPLACE( are functions too
    Result := (not IsSqlKeyword(APrev.Up)) or (APrev.Up = 'LEFT') or (APrev.Up = 'RIGHT') or
      (APrev.Up = 'REPLACE');
  end;
end;

{ Whether a space goes between APrev and ACur on one line. APrevUnary:
  APrev was a sign (-1). }
function SpaceBetween(const APrev, ACur: TpgnTok; APrevUnary: Boolean): Boolean;
begin
  Result := True;
  if APrevUnary then
  begin
    Result := False;
    Exit;
  end;
  if (ACur.Kind = tkSymbol) and ((ACur.Text = ',') or (ACur.Text = ';') or (ACur.Text = ')') or
    (ACur.Text = '.') or (ACur.Text = '::') or (ACur.Text = '..')) then
  begin
    Result := False;
  end
  else if ACur.Kind = tkOuterMark then
  begin
    Result := False;
  end
  else if (APrev.Kind = tkSymbol) and ((APrev.Text = '(') or (APrev.Text = '.') or
    (APrev.Text = '::') or (APrev.Text = '..')) then
  begin
    Result := False;
  end
  else if (ACur.Kind = tkSymbol) and (ACur.Text = '(') then
  begin
    Result := not GluesToParen(APrev);
  end
  else if (ACur.Kind = tkSymbol) and (ACur.Text = '%') and (APrev.Kind = tkWord) then
  begin
    Result := True;   // modulo; %TYPE is handled by the caller
  end;
end;

{ A sign rather than a minus: after an operator, '(', ',', a keyword or
  at the start. }
function IsUnaryAt(const T: TpgnToks; I: Integer): Boolean;
var
  J: Integer;
begin
  Result := False;
  if (T[I].Kind <> tkSymbol) or not ((T[I].Text = '-') or (T[I].Text = '+')) then
  begin
    Exit;
  end;
  J := I - 1;
  while (J >= 0) and IsComment(T[J]) do
  begin
    Dec(J);
  end;
  if J < 0 then
  begin
    Result := True;
    Exit;
  end;
  if T[J].Kind = tkSymbol then
  begin
    Result := (T[J].Text = '(') or (T[J].Text = ',') or IsOperatorSym(T[J].Text);
  end
  else if T[J].Kind = tkWord then
  begin
    Result := IsSqlKeyword(T[J].Up) and (T[J].Up <> 'END') and (T[J].Up <> 'NULL');
  end;
end;

{ ========================================================= the formatter }

type
  TFrameKind = (fkUnit, fkDeclare, fkBegin, fkIf, fkLoop, fkCase);

  TFrame = record
    Kind: TFrameKind;
    Level: Integer;
    Begun: Boolean;
    InExc: Boolean;
  end;

  TQueryState = record
    Active: Boolean;
    Kind: string;        // SELECT, INSERT, UPDATE, DELETE, MERGE, WITH
    Base: Integer;       // column of the clause keywords
    Clause: string;
    Depth: Integer;      // paren depth the clauses are at
    OnePerLine: Boolean;
    PendingItemNL: Boolean;
    InOn: Boolean;
    Between: Integer;
    SawSelect: Boolean;
  end;

  TParenKind = (pkSub, pkList, pkPlain);

  TParen = record
    Kind: TParenKind;
    SavedQ: TQueryState;
    SavedIndent: Integer;
    ListCol: Integer;
  end;

  TCaseCtx = record
    Base: Integer;
    Depth: Integer;
  end;

  TFormatter = class
  private
    T: TpgnToks;
    Opt: TpgnFormatOptions;
    Dialect: TpgnDialect;
    Block: Boolean;       // procedural code (PL/SQL, T-SQL, MySQL routines)
    Src: string;
    Out: string;
    LineIndent: Integer;
    AtLineStart: Boolean;
    ForceNL: Boolean;
    Level: Integer;
    StmtLevel: Integer;
    AtStmtStart: Boolean;
    Frames: array of TFrame;
    Q: TQueryState;
    Parens: array of TParen;
    Cases: array of TCaseCtx;
    InHeader: Boolean;
    HeaderIsOracleUnit: Boolean;
    AfterThenLevel: Integer;   // >= 0: after THEN, statements go to this level
    PrevIdx: Integer;          // last token emitted (not a comment)
    PrevUnary: Boolean;
    PendingWhenLevel: Integer; // exception / case-statement WHEN: level after THEN
    StmtFirst: string;         // the first word of the statement in progress
    function U(AIdx: Integer): string;
    function NextSig(AIdx: Integer): Integer;
    function Depth: Integer;
    function Col(ALevel: Integer): Integer;
    function Step: Integer;
    function IndentText(ACol: Integer): string;
    procedure NL(ACol: Integer);
    procedure BlankLine;
    procedure Put(const S: string; ASpace: Boolean);
    function CaseOf(AIdx: Integer): string;
    procedure EmitTok(AIdx: Integer);
    function ClauseCol(const AWord: string): Integer;
    function ItemCol: Integer;
    function JoinCol: Integer;
    function CountItems(AFrom: Integer): Integer;
    procedure StartQuery(const AKind: string; ABase: Integer);
    procedure PushFrame(AKind: TFrameKind; ALevel: Integer);
    function TopFrame: Integer;
    procedure PopFrame;
    procedure StartStatement(AIdx: Integer);
    procedure HandleComment(AIdx: Integer);
    function IsTsqlStatementStart(AIdx: Integer): Boolean;
    function InTablePosition(AIdx: Integer): Boolean;
    function AfterInto(AIdx: Integer): Boolean;
  public
    function Run(const AText: string; ADialect: TpgnDialect; const AOpt: TpgnFormatOptions;
      ABlock: Boolean): string;
  end;

function TFormatter.U(AIdx: Integer): string;
begin
  if (AIdx >= 0) and (AIdx <= High(T)) and (T[AIdx].Kind = tkWord) then
  begin
    Result := T[AIdx].Up;
  end
  else if (AIdx >= 0) and (AIdx <= High(T)) and (T[AIdx].Kind = tkSymbol) then
  begin
    Result := T[AIdx].Text;
  end
  else
  begin
    Result := '';
  end;
end;

function TFormatter.NextSig(AIdx: Integer): Integer;
begin
  Result := AIdx + 1;
  while (Result <= High(T)) and IsComment(T[Result]) do
  begin
    Inc(Result);
  end;
end;

function TFormatter.Depth: Integer;
begin
  Result := Length(Parens);
end;

function TFormatter.Step: Integer;
begin
  Result := Max(1, Opt.IndentSize);
end;

function TFormatter.Col(ALevel: Integer): Integer;
begin
  Result := ALevel * Step;
end;

function TFormatter.IndentText(ACol: Integer): string;
begin
  if Opt.UseTabs then
  begin
    Result := StringOfChar(#9, ACol div Step) + StringOfChar(' ', ACol mod Step);
  end
  else
  begin
    Result := StringOfChar(' ', ACol);
  end;
end;

procedure TFormatter.NL(ACol: Integer);
begin
  ForceNL := False;
  if ACol < 0 then
  begin
    ACol := 0;
  end;
  if Out = '' then
  begin
    Out := IndentText(ACol);
    AtLineStart := True;
    LineIndent := ACol;
    Exit;
  end;
  if AtLineStart then
  begin
    // still nothing on this line: just change its indent
    while (Out <> '') and (Out[Length(Out)] in [' ', #9]) do
    begin
      SetLength(Out, Length(Out) - 1);
    end;
    Out := Out + IndentText(ACol);
    LineIndent := ACol;
    Exit;
  end;
  while (Out <> '') and (Out[Length(Out)] in [' ', #9]) do
  begin
    SetLength(Out, Length(Out) - 1);
  end;
  Out := Out + LineEnding + IndentText(ACol);
  AtLineStart := True;
  LineIndent := ACol;
end;

procedure TFormatter.BlankLine;
var
  Cur: Integer;
begin
  Cur := LineIndent;
  if Out = '' then
  begin
    Exit;
  end;
  NL(Cur);
  // the line just started becomes the blank one
  while (Out <> '') and (Out[Length(Out)] in [' ', #9]) do
  begin
    SetLength(Out, Length(Out) - 1);
  end;
  if (Length(Out) >= 2 * Length(LineEnding)) and
    (Copy(Out, Length(Out) - 2 * Length(LineEnding) + 1, 2 * Length(LineEnding)) = LineEnding + LineEnding) then
  begin
    Out := Out + IndentText(Cur);
  end
  else
  begin
    Out := Out + LineEnding + IndentText(Cur);
  end;
  AtLineStart := True;
end;

procedure TFormatter.Put(const S: string; ASpace: Boolean);
var
  Last: Char;
begin
  if ForceNL then
  begin
    NL(LineIndent);
  end;
  if AtLineStart then
  begin
    Out := Out + S;
    AtLineStart := False;
    Exit;
  end;
  if (Out <> '') and (S <> '') then
  begin
    Last := Out[Length(Out)];
    // never let two tokens run into a comment marker or a longer symbol
    if ((Last = '-') and (S[1] = '-')) or ((Last = '/') and (S[1] = '*')) or
      ((Last = '*') and (S[1] = '/')) or ((Last in ['<', '>', '!', ':', '=', '|']) and (S[1] in ['=', '>', '|'])) then
    begin
      ASpace := True;
    end;
  end;
  if ASpace then
  begin
    Out := Out + ' ' + S;
  end
  else
  begin
    Out := Out + S;
  end;
end;

function TFormatter.InTablePosition(AIdx: Integer): Boolean;
var
  J: Integer;
  P: string;
begin
  Result := False;
  J := AIdx - 1;
  while (J >= 0) and IsComment(T[J]) do
  begin
    Dec(J);
  end;
  if J < 0 then
  begin
    Exit;
  end;
  P := U(J);
  Result := (P = 'FROM') or (P = 'JOIN') or (P = 'INTO') or (P = 'UPDATE') or (P = 'TABLE') or
    (P = '.') or ((P = ',') and Q.Active and (Q.Clause = 'FROM') and (Depth = Q.Depth));
  if (not Result) and (NextSig(AIdx) <= High(T)) and (U(NextSig(AIdx)) = '.') then
  begin
    Result := True;
  end;
end;

{ The name at AIdx follows INTO or TABLE (perhaps as schema.name). }
function TFormatter.AfterInto(AIdx: Integer): Boolean;
var
  J: Integer;
begin
  J := AIdx - 1;
  while (J >= 0) and IsComment(T[J]) do
  begin
    Dec(J);
  end;
  if (J >= 1) and (U(J) = '.') then
  begin
    J := J - 2;
    while (J >= 0) and IsComment(T[J]) do
    begin
      Dec(J);
    end;
  end;
  Result := (J >= 0) and ((U(J) = 'INTO') or (U(J) = 'TABLE'));
end;

function TFormatter.CaseOf(AIdx: Integer): string;
begin
  Result := T[AIdx].Text;
  if (T[AIdx].Kind <> tkWord) or (Opt.KeywordCase = kcAsTyped) then
  begin
    Exit;
  end;
  if not IsSqlKeyword(T[AIdx].Up) or InTablePosition(AIdx) then
  begin
    Exit;
  end;
  if Opt.KeywordCase = kcUpper then
  begin
    Result := T[AIdx].Up;
  end
  else
  begin
    Result := LowerCase(T[AIdx].Text);
  end;
end;

{ Puts token AIdx on the current line with the usual spacing. }
procedure TFormatter.EmitTok(AIdx: Integer);
var
  Space: Boolean;
  S: string;
begin
  S := CaseOf(AIdx);
  if PrevIdx < 0 then
  begin
    Space := True;
  end
  else
  begin
    Space := SpaceBetween(T[PrevIdx], T[AIdx], PrevUnary);
    // emp.sal%TYPE, c%ROWCOUNT: no spaces around the %
    if (T[AIdx].Kind = tkSymbol) and (T[AIdx].Text = '%') and (T[PrevIdx].Kind in [tkWord, tkQuoted]) and
      (NextSig(AIdx) <= High(T)) and (T[NextSig(AIdx)].Kind = tkWord) then
    begin
      S := T[AIdx].Text;
      if (Pos(';' + T[NextSig(AIdx)].Up + ';', ';TYPE;ROWTYPE;FOUND;NOTFOUND;ISOPEN;ROWCOUNT;BULK_ROWCOUNT;') > 0) then
      begin
        Space := False;
      end;
    end;
    if (T[PrevIdx].Kind = tkSymbol) and (T[PrevIdx].Text = '%') and (PrevIdx > 0) and
      (Pos(';' + T[AIdx].Up + ';', ';TYPE;ROWTYPE;FOUND;NOTFOUND;ISOPEN;ROWCOUNT;BULK_ROWCOUNT;') > 0) then
    begin
      Space := False;
    end;
  end;
  // INSERT INTO t (a, b): a table's column list keeps its space
  if (T[AIdx].Kind = tkSymbol) and (T[AIdx].Text = '(') and (PrevIdx >= 0) and
    (T[PrevIdx].Kind in [tkWord, tkQuoted]) and AfterInto(PrevIdx) then
  begin
    Space := True;
  end;
  if AtLineStart then
  begin
    Space := False;
  end;
  // a long packed list wraps after a comma
  if (not AtLineStart) and (Opt.LineWidth > 0) and (PrevIdx >= 0) and (U(PrevIdx) = ',') and
    (Length(Out) - LastDelimiter(#10, Out) + Length(S) > Opt.LineWidth) then
  begin
    NL(ItemCol);
    Space := False;
  end;
  Put(S, Space);
  PrevUnary := IsUnaryAt(T, AIdx);
  PrevIdx := AIdx;
end;

function TFormatter.ClauseCol(const AWord: string): Integer;
begin
  if Opt.River then
  begin
    Result := Max(Q.Base, Q.Base + 6 - Length(AWord));
  end
  else
  begin
    Result := Q.Base;
  end;
end;

function TFormatter.ItemCol: Integer;
begin
  if Opt.River then
  begin
    Result := Q.Base + 7;
  end
  else
  begin
    Result := Q.Base + Step;
  end;
end;

function TFormatter.JoinCol: Integer;
begin
  if Opt.River then
  begin
    Result := Q.Base + 7;
  end
  else if Opt.JoinIndented then
  begin
    Result := Q.Base + Step;
  end
  else
  begin
    Result := Q.Base;
  end;
end;

{ Items in the select list starting after AFrom (top-level commas + 1). }
function TFormatter.CountItems(AFrom: Integer): Integer;
var
  J, D: Integer;
  W: string;
begin
  Result := 1;
  D := 0;
  J := AFrom + 1;
  while J <= High(T) do
  begin
    W := U(J);
    if W = '(' then
    begin
      Inc(D);
    end
    else if W = ')' then
    begin
      Dec(D);
      if D < 0 then
      begin
        Break;
      end;
    end
    else if D = 0 then
    begin
      if W = ',' then
      begin
        Inc(Result);
      end
      else if (W = 'FROM') or (W = 'INTO') or (W = ';') or (W = 'UNION') or (W = 'WHERE') then
      begin
        Break;
      end;
    end;
    Inc(J);
  end;
end;

procedure TFormatter.StartQuery(const AKind: string; ABase: Integer);
begin
  Q.Active := True;
  Q.Kind := AKind;
  Q.Base := ABase;
  Q.Clause := '';
  Q.Depth := Depth;
  Q.OnePerLine := False;
  Q.PendingItemNL := False;
  Q.InOn := False;
  Q.Between := 0;
  Q.SawSelect := False;
end;

procedure TFormatter.PushFrame(AKind: TFrameKind; ALevel: Integer);
var
  N: Integer;
begin
  N := Length(Frames);
  SetLength(Frames, N + 1);
  Frames[N].Kind := AKind;
  Frames[N].Level := ALevel;
  Frames[N].Begun := False;
  Frames[N].InExc := False;
end;

function TFormatter.TopFrame: Integer;
begin
  Result := High(Frames);
end;

procedure TFormatter.PopFrame;
begin
  if Length(Frames) > 0 then
  begin
    SetLength(Frames, Length(Frames) - 1);
  end;
end;

{ T-SQL: statements needn't end with ';', so a statement word at the top
  level starts the next one (not SELECT after INSERT or UNION, not SET in
  UPDATE, not WITH (NOLOCK)...). }
function TFormatter.IsTsqlStatementStart(AIdx: Integer): Boolean;
var
  W, P: string;
  J: Integer;
begin
  Result := False;
  if (Dialect <> sdTSQL) or (Depth > 0) or (Length(Cases) > 0) or AtStmtStart then
  begin
    Exit;
  end;
  W := T[AIdx].Up;
  if T[AIdx].Kind <> tkWord then
  begin
    Exit;
  end;
  J := AIdx - 1;
  while (J >= 0) and IsComment(T[J]) do
  begin
    Dec(J);
  end;
  P := '';
  if J >= 0 then
  begin
    P := U(J);
  end;
  if Pos(';' + W + ';', ';IF;ELSE;WHILE;BEGIN;END;DECLARE;PRINT;RETURN;RAISERROR;THROW;USE;' +
    'EXEC;EXECUTE;OPEN;CLOSE;DEALLOCATE;COMMIT;ROLLBACK;BREAK;CONTINUE;GOTO;WAITFOR;' +
    'INSERT;UPDATE;DELETE;MERGE;SELECT;WITH;SET;TRUNCATE;CREATE;ALTER;DROP;GRANT;FETCH;') = 0 then
  begin
    Exit;
  end;
  if InHeader then
  begin
    Exit;
  end;
  if (W = 'SELECT') and Q.Active and ((Q.Kind = 'INSERT') or (Q.Kind = 'WITH') or
    (P = 'UNION') or (P = 'ALL') or (P = 'EXCEPT') or (P = 'INTERSECT') or (P = 'DISTINCT')) then
  begin
    Exit;
  end;
  if (W = 'SET') and Q.Active and ((Q.Kind = 'UPDATE') or (Q.Kind = 'MERGE')) then
  begin
    Exit;
  end;
  if ((W = 'UPDATE') or (W = 'DELETE') or (W = 'INSERT')) and Q.Active and (Q.Kind = 'MERGE') then
  begin
    Exit;
  end;
  if (W = 'WITH') and (NextSig(AIdx) <= High(T)) and (U(NextSig(AIdx)) = '(') then
  begin
    Exit;
  end;
  if (W = 'FETCH') and Q.Active and (Q.Kind <> '') then
  begin
    Exit;
  end;
  if (W = 'END') and (P = 'BEGIN') then
  begin
    Exit;
  end;
  if (P = 'BEGIN') and ((W = 'TRAN') or (W = 'TRANSACTION')) then
  begin
    Exit;
  end;
  if (P = 'END') and ((W = 'TRY') or (W = 'CATCH')) then
  begin
    Exit;
  end;
  if (P = 'BEGIN') and ((W = 'TRY') or (W = 'CATCH')) then
  begin
    Exit;
  end;
  if (P = 'ELSE') and (W = 'IF') then
  begin
    Exit;   // ELSE IF stays on one line
  end;
  // after IF's condition the body starts; after ELSE too
  Result := True;
end;

procedure TFormatter.StartStatement(AIdx: Integer);
var
  W, W2: string;
  J: Integer;
begin
  AtStmtStart := False;
  if AfterThenLevel >= 0 then
  begin
    Level := AfterThenLevel;
    AfterThenLevel := -1;
  end;
  StmtLevel := Level;
  // T-SQL: the one statement after IF's condition or ELSE goes a level in
  // (a BEGIN block doesn't)
  if (Dialect = sdTSQL) and ((StmtFirst = 'IF') or (StmtFirst = 'ELSE') or (StmtFirst = 'WHILE')) and
    (T[AIdx].Up <> 'BEGIN') then
  begin
    StmtLevel := Level + 1;
  end;
  StmtFirst := T[AIdx].Up;
  if (Out <> '') and (T[AIdx].NLBefore >= 2) and Block then
  begin
    BlankLine;
  end;
  NL(Col(StmtLevel));
  Q.Active := False;
  W := T[AIdx].Up;
  if (W = 'SELECT') or (W = 'INSERT') or (W = 'UPDATE') or (W = 'DELETE') or (W = 'MERGE') or
    (W = 'WITH') then
  begin
    StartQuery(W, Col(StmtLevel));
  end;
  // a routine's header: its parameter list and IS / AS
  if Block and ((W = 'CREATE') or (W = 'PROCEDURE') or (W = 'FUNCTION') or (W = 'TRIGGER')) then
  begin
    J := AIdx;
    W2 := W;
    while (J <= High(T)) and ((W2 = 'CREATE') or (W2 = 'OR') or (W2 = 'REPLACE') or (W2 = 'ALTER') or
      (W2 = 'EDITIONABLE') or (W2 = 'NONEDITIONABLE') or (W2 = 'DEFINER') or (W2 = '=') or
      (T[J].Kind in [tkQuoted, tkString]) or (Pos('@', T[J].Text) > 0) or IsComment(T[J])) do
    begin
      J := NextSig(J);
      W2 := U(J);
    end;
    if (W2 = 'PROCEDURE') or (W2 = 'FUNCTION') or (W2 = 'PACKAGE') or (W2 = 'TRIGGER') or (W2 = 'PROC') then
    begin
      InHeader := True;
      HeaderIsOracleUnit := (Dialect = sdOracle) and (W2 <> 'TRIGGER');
    end;
  end;
end;

procedure TFormatter.HandleComment(AIdx: Integer);
var
  Own: Boolean;
begin
  Own := (T[AIdx].NLBefore > 0) or (Out = '');
  if IsHint(T[AIdx]) and not Own then
  begin
    Put(T[AIdx].Text, True);
    Exit;
  end;
  if Own then
  begin
    if (T[AIdx].NLBefore >= 2) and (Out <> '') then
    begin
      BlankLine;
    end;
    if AtStmtStart then
    begin
      if AfterThenLevel >= 0 then
      begin
        NL(Col(AfterThenLevel));
      end
      else
      begin
        NL(Col(Level));
      end;
    end
    else if not AtLineStart then
    begin
      NL(LineIndent);
    end;
    Put(T[AIdx].Text, False);
    ForceNL := True;
  end
  else
  begin
    Put(T[AIdx].Text, True);
    if T[AIdx].Kind = tkLineComment then
    begin
      ForceNL := True;
    end;
  end;
end;

function TFormatter.Run(const AText: string; ADialect: TpgnDialect; const AOpt: TpgnFormatOptions;
  ABlock: Boolean): string;
var
  I, J, F, N, Items: Integer;
  W, NextW, PrevW: string;
  P: TParen;
  IsSub: Boolean;
begin
  Src := AText;
  T := Tokenize(AText, ADialect);
  Opt := AOpt;
  Dialect := ADialect;
  Block := ABlock;
  Out := '';
  LineIndent := 0;
  AtLineStart := True;
  ForceNL := False;
  Level := 0;
  StmtLevel := 0;
  AtStmtStart := True;
  SetLength(Frames, 0);
  SetLength(Parens, 0);
  SetLength(Cases, 0);
  Q.Active := False;
  InHeader := False;
  AfterThenLevel := -1;
  PendingWhenLevel := -1;
  StmtFirst := '';
  PrevIdx := -1;
  PrevUnary := False;

  I := 0;
  while I <= High(T) do
  begin
    if IsComment(T[I]) then
    begin
      HandleComment(I);
      Inc(I);
      Continue;
    end;
    W := U(I);
    NextW := U(NextSig(I));
    PrevW := '';
    if PrevIdx >= 0 then
    begin
      PrevW := U(PrevIdx);
    end;

    if (not AtStmtStart) and Block and IsTsqlStatementStart(I) then
    begin
      AtStmtStart := True;
      // IF's body and ELSE's go one level in, for that one statement
    end;
    if AtStmtStart then
    begin
      StartStatement(I);
    end;
    // the select list's first column goes on its own line
    if Q.Active and Q.PendingItemNL and (Depth = Q.Depth) and (W <> 'DISTINCT') and (W <> 'ALL') and
      (W <> 'UNIQUE') and (W <> 'TOP') and (PrevW <> 'TOP') and (W <> 'FROM') and (W <> 'INTO') and
      (W <> 'SELECT') then
    begin
      Q.PendingItemNL := False;
      NL(ItemCol);
    end;

    // ------------------------------------------------ procedural code
    if Block and (Depth = 0) and (T[I].Kind = tkWord) and (Length(Cases) = 0) then
    begin
      if (W = 'DECLARE') and (Dialect = sdOracle) and (PrevW <> 'CURSOR') then
      begin
        if InHeader then
        begin
          InHeader := False;
          NL(Col(StmtLevel));
        end;
        PushFrame(fkDeclare, StmtLevel);
        EmitTok(I);
        Level := StmtLevel + 1;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'BEGIN') and not ((Dialect = sdTSQL) and ((NextW = 'TRAN') or (NextW = 'TRANSACTION') or
        (NextW = 'DISTRIBUTED'))) and (PrevW <> 'END') then
      begin
        if InHeader then
        begin
          InHeader := False;
          NL(Col(StmtLevel));
        end;
        F := TopFrame;
        if (F >= 0) and (Frames[F].Kind in [fkUnit, fkDeclare]) and not Frames[F].Begun then
        begin
          NL(Col(Frames[F].Level));
          EmitTok(I);
          Frames[F].Begun := True;
          Level := Frames[F].Level + 1;
        end
        else
        begin
          PushFrame(fkBegin, StmtLevel);
          Frames[High(Frames)].Begun := True;
          NL(Col(StmtLevel));
          EmitTok(I);
          Level := StmtLevel + 1;
        end;
        if (Dialect = sdTSQL) and ((NextW = 'TRY') or (NextW = 'CATCH')) then
        begin
          Inc(I);
          while (I <= High(T)) and IsComment(T[I]) do
          begin
            Inc(I);
          end;
          if I <= High(T) then
          begin
            EmitTok(I);
          end;
        end;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'EXCEPTION') and (Dialect = sdOracle) then
      begin
        F := TopFrame;
        if (F >= 0) and Frames[F].Begun then
        begin
          NL(Col(Frames[F].Level));
          EmitTok(I);
          Frames[F].InExc := True;
          Level := Frames[F].Level + 1;
          AtStmtStart := True;
          Inc(I);
          Continue;
        end;
      end;
      if (W = 'WHEN') and (PrevIdx >= 0) then
      begin
        F := TopFrame;
        if (F >= 0) and ((Frames[F].Kind = fkCase) or Frames[F].InExc) then
        begin
          NL(Col(Frames[F].Level + 1));
          EmitTok(I);
          PendingWhenLevel := Frames[F].Level + 2;
          Inc(I);
          Continue;
        end;
      end;
      if (W = 'THEN') and (PendingWhenLevel >= 0) then
      begin
        EmitTok(I);
        Level := PendingWhenLevel;
        PendingWhenLevel := -1;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'END') and (Dialect <> sdTSQL) or ((W = 'END') and (Dialect = sdTSQL)) then
      begin
        F := TopFrame;
        if F >= 0 then
        begin
          if ((NextW = 'IF') or (NextW = 'LOOP') or (NextW = 'CASE') or (NextW = 'WHILE') or
            (NextW = 'REPEAT')) then
          begin
            // the matching frame (normally the top one)
            J := F;
            while (J > 0) and not (((NextW = 'IF') and (Frames[J].Kind = fkIf)) or
              ((NextW = 'CASE') and (Frames[J].Kind = fkCase)) or
              ((NextW <> 'IF') and (NextW <> 'CASE') and (Frames[J].Kind = fkLoop))) do
            begin
              Dec(J);
            end;
            Level := Frames[J].Level;
            SetLength(Frames, J);
          end
          else
          begin
            Level := Frames[F].Level;
            PopFrame;
          end;
          NL(Col(Level));
          EmitTok(I);
          if (Dialect = sdTSQL) and ((NextW = 'TRY') or (NextW = 'CATCH')) then
          begin
            Inc(I);
            while (I <= High(T)) and IsComment(T[I]) do
            begin
              Inc(I);
            end;
            if I <= High(T) then
            begin
              EmitTok(I);
            end;
          end;
          if Dialect = sdTSQL then
          begin
            AtStmtStart := True;
          end;
          Inc(I);
          Continue;
        end;
      end;
      if ((W = 'IF') and (Dialect <> sdTSQL) and (PrevIdx >= 0) and (U(PrevIdx) <> 'END') and
        (NextW <> '(') or ((W = 'IF') and (Dialect <> sdTSQL) and (NextW = '(') and (Dialect = sdOracle))) and
        (PrevW <> 'END') and ((PrevW = ';') or (Out = '') or AtLineStart or (PrevW = 'THEN') or
        (PrevW = 'ELSE') or (PrevW = 'BEGIN') or (PrevW = 'LOOP') or (PrevW = 'IS') or (PrevW = 'AS')) then
      begin
        PushFrame(fkIf, StmtLevel);
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if ((W = 'ELSIF') or (W = 'ELSEIF')) and (TopFrame >= 0) and (Frames[TopFrame].Kind = fkIf) then
      begin
        Level := Frames[TopFrame].Level;
        NL(Col(Level));
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'ELSE') and (TopFrame >= 0) and (Frames[TopFrame].Kind = fkIf) and (Dialect <> sdTSQL) then
      begin
        Level := Frames[TopFrame].Level;
        NL(Col(Level));
        EmitTok(I);
        Level := Frames[TopFrame].Level + 1;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'ELSE') and (TopFrame >= 0) and (Frames[TopFrame].Kind = fkCase) then
      begin
        NL(Col(Frames[TopFrame].Level + 1));
        EmitTok(I);
        Level := Frames[TopFrame].Level + 2;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'THEN') and (TopFrame >= 0) and (Frames[TopFrame].Kind = fkIf) then
      begin
        EmitTok(I);
        Level := Frames[TopFrame].Level + 1;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if ((W = 'LOOP') and (PrevW <> 'END')) or ((W = 'DO') and (Dialect = sdMySQL)) or
        ((W = 'REPEAT') and (Dialect = sdMySQL) and (PrevW <> 'END')) then
      begin
        PushFrame(fkLoop, StmtLevel);
        EmitTok(I);
        Level := StmtLevel + 1;
        AtStmtStart := True;
        Inc(I);
        Continue;
      end;
      if (W = 'UNTIL') and (Dialect = sdMySQL) and (TopFrame >= 0) and (Frames[TopFrame].Kind = fkLoop) then
      begin
        NL(Col(Frames[TopFrame].Level));
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'CASE') and (StmtLevel = Level) and (PrevIdx >= 0) and
        ((PrevW = ';') or (PrevW = 'THEN') or (PrevW = 'BEGIN') or (PrevW = 'ELSE') or (PrevW = 'LOOP')) and
        not Q.Active then
      begin
        PushFrame(fkCase, StmtLevel);
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if ((W = 'IS') or (W = 'AS')) and InHeader then
      begin
        InHeader := False;
        NL(Col(StmtLevel));
        EmitTok(I);
        if HeaderIsOracleUnit then
        begin
          PushFrame(fkUnit, StmtLevel);
          Level := StmtLevel + 1;
          AtStmtStart := True;
        end
        else if Dialect = sdTSQL then
        begin
          AtStmtStart := True;
        end;
        Inc(I);
        Continue;
      end;
    end;

    // --------------------------------------------- statement ends
    if (W = ';') and (Depth = 0) then
    begin
      EmitTok(I);
      Q.Active := False;
      InHeader := False;
      SetLength(Cases, 0);
      AtStmtStart := True;
      Inc(I);
      Continue;
    end;

    // ------------------------------------------------ parentheses
    if W = '(' then
    begin
      J := NextSig(I);
      IsSub := (J <= High(T)) and ((U(J) = 'SELECT') or (U(J) = 'WITH'));
      P.SavedQ := Q;
      P.SavedIndent := LineIndent;
      P.ListCol := 0;
      if IsSub then
      begin
        P.Kind := pkSub;
        EmitTok(I);
        SetLength(Parens, Length(Parens) + 1);
        Parens[High(Parens)] := P;
        StartQuery('SELECT', LineIndent + Step);
        Q.Kind := '';
        Inc(I);
        Continue;
      end;
      // a column list (CREATE TABLE) or a routine's parameters, one per line
      if (Depth = 0) and ((InHeader and (PrevIdx >= 0) and (T[PrevIdx].Kind in [tkWord, tkQuoted])) or
        ((not Q.Active) and (PrevIdx >= 1) and (T[PrevIdx].Kind in [tkWord, tkQuoted]) and
        (Pos('TABLE', UpperCase(Copy(Src, 1, T[PrevIdx].StartPos))) > 0) and
        (FirstKeyword(Copy(Src, 1, T[I].StartPos)) = 'CREATE'))) then
      begin
        // count the items: one item stays on the line
        Items := 1;
        N := 0;
        J := I + 1;
        while J <= High(T) do
        begin
          if U(J) = '(' then
          begin
            Inc(N);
          end
          else if U(J) = ')' then
          begin
            if N = 0 then
            begin
              Break;
            end;
            Dec(N);
          end
          else if (U(J) = ',') and (N = 0) then
          begin
            Inc(Items);
          end;
          Inc(J);
        end;
        if Items > 1 then
        begin
          P.Kind := pkList;
          P.ListCol := LineIndent + Step;
          EmitTok(I);
          SetLength(Parens, Length(Parens) + 1);
          Parens[High(Parens)] := P;
          NL(P.ListCol);
          Inc(I);
          Continue;
        end;
      end;
      P.Kind := pkPlain;
      EmitTok(I);
      SetLength(Parens, Length(Parens) + 1);
      Parens[High(Parens)] := P;
      Inc(I);
      Continue;
    end;
    if W = ')' then
    begin
      if Depth > 0 then
      begin
        P := Parens[High(Parens)];
        SetLength(Parens, Length(Parens) - 1);
        // CASE expressions left open inside the parens are done
        while (Length(Cases) > 0) and (Cases[High(Cases)].Depth > Depth) do
        begin
          SetLength(Cases, Length(Cases) - 1);
        end;
        if P.Kind = pkSub then
        begin
          Q := P.SavedQ;
          NL(P.SavedIndent);
          EmitTok(I);
        end
        else if P.Kind = pkList then
        begin
          NL(P.SavedIndent);
          EmitTok(I);
        end
        else
        begin
          EmitTok(I);
        end;
      end
      else
      begin
        EmitTok(I);
      end;
      Inc(I);
      Continue;
    end;
    if (W = ',') and (Depth > 0) and (Parens[High(Parens)].Kind = pkList) and
      ((not Q.Active) or (Q.Depth < Depth)) then
    begin
      if Opt.LeadingCommas then
      begin
        NL(Parens[High(Parens)].ListCol);
        Put(',', False);
        PrevIdx := I;
        PrevUnary := False;
      end
      else
      begin
        EmitTok(I);
        NL(Parens[High(Parens)].ListCol);
      end;
      Inc(I);
      Continue;
    end;

    // ------------------------------------------ CASE expressions
    if (W = 'CASE') and (T[I].Kind = tkWord) then
    begin
      SetLength(Cases, Length(Cases) + 1);
      Cases[High(Cases)].Base := LineIndent;
      Cases[High(Cases)].Depth := Depth;
      EmitTok(I);
      Inc(I);
      Continue;
    end;
    if (Length(Cases) > 0) and (Cases[High(Cases)].Depth = Depth) and (T[I].Kind = tkWord) then
    begin
      if (W = 'WHEN') or (W = 'ELSE') then
      begin
        NL(Cases[High(Cases)].Base + Step);
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if W = 'END' then
      begin
        NL(Cases[High(Cases)].Base);
        EmitTok(I);
        SetLength(Cases, Length(Cases) - 1);
        Inc(I);
        Continue;
      end;
    end;

    // ---------------------------------------------------- queries
    if (T[I].Kind = tkWord) and (not Q.Active) and (Depth = 0) and
      ((W = 'SELECT') or (W = 'WITH') or (W = 'INSERT') or (W = 'UPDATE') or (W = 'DELETE') or
      (W = 'MERGE')) and (PrevW <> 'FOR') and (PrevW <> 'ON') and (PrevW <> 'INSTEAD') and
      (PrevW <> ',') and (PrevW <> 'OF') and (PrevW <> 'BEFORE') and (PrevW <> 'AFTER') and
      (PrevW <> 'OR') then
    begin
      // a query after a header: CREATE VIEW v AS SELECT, a cursor's IS SELECT
      if PrevW = 'IS' then
      begin
        StartQuery(W, Col(Level) + Step);
      end
      else
      begin
        StartQuery(W, Col(Level));
      end;
      if (W = 'SELECT') or (W = 'WITH') then
      begin
        NL(Q.Base);
      end;
    end;
    if Q.Active and (Depth = Q.Depth) and (T[I].Kind = tkWord) then
    begin
      if W = 'SELECT' then
      begin
        if not AtLineStart then
        begin
          NL(ClauseCol('SELECT'));
        end;
        Q.Clause := 'SELECT';
        Q.SawSelect := True;
        Q.OnePerLine := Opt.OneColumnPerLine and (CountItems(I) > 1);
        Q.PendingItemNL := Q.OnePerLine and not Opt.River;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'FROM') and not ((Q.Kind = 'DELETE') and (PrevW = 'DELETE')) then
      begin
        Q.PendingItemNL := False;
        NL(ClauseCol('FROM'));
        Q.Clause := 'FROM';
        Q.InOn := False;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'INTO') and (Q.Clause = 'SELECT') then
      begin
        Q.PendingItemNL := False;
        NL(ClauseCol('INTO'));
        Q.Clause := 'INTO';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'WHERE') or (W = 'HAVING') then
      begin
        NL(ClauseCol(W));
        Q.Clause := 'WHERE';
        Q.InOn := False;
        Q.Between := 0;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if ((W = 'GROUP') or (W = 'ORDER')) and ((NextW = 'BY') or (NextW = 'SIBLINGS')) then
      begin
        NL(ClauseCol(W));
        Q.Clause := W;
        Q.InOn := False;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if ((W = 'CONNECT') and (NextW = 'BY')) or ((W = 'START') and (NextW = 'WITH')) then
      begin
        NL(ClauseCol(W));
        Q.Clause := 'WHERE';
        Q.InOn := False;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'UNION') or (W = 'INTERSECT') or (W = 'MINUS') or ((W = 'EXCEPT') and (Dialect <> sdOracle)) then
      begin
        NL(Q.Base);
        Q.Clause := '';
        Q.InOn := False;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if ((W = 'LIMIT') or (W = 'OFFSET') or ((W = 'FETCH') and (Q.Clause <> ''))) and (Q.SawSelect) then
      begin
        NL(ClauseCol(W));
        Q.Clause := 'LIMIT';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'FOR') and ((NextW = 'UPDATE') or (NextW = 'SHARE')) and Q.SawSelect then
      begin
        NL(ClauseCol(W));
        Q.Clause := 'FOR';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'RETURNING') then
      begin
        NL(ClauseCol(W));
        Q.Clause := 'RETURNING';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'SET') and ((Q.Kind = 'UPDATE') or ((Q.Kind = 'MERGE') and (PrevW = 'UPDATE'))) then
      begin
        if Q.Kind = 'MERGE' then
        begin
          NL(Q.Base + Step);
        end
        else
        begin
          NL(ClauseCol(W));
        end;
        Q.Clause := 'SET';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'VALUES') and ((Q.Kind = 'INSERT') or (Q.Kind = 'MERGE')) then
      begin
        if Q.Kind = 'MERGE' then
        begin
          NL(Q.Base + Step);
        end
        else
        begin
          NL(ClauseCol(W));
        end;
        Q.Clause := 'VALUES';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (Q.Kind = 'MERGE') and (Q.Clause <> 'FROM') and ((W = 'USING') or (W = 'WHEN') or
        ((W = 'ON') and (PrevW <> 'THEN'))) then
      begin
        NL(Q.Base);
        Q.Clause := W;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'WITH') and (Q.Kind = 'WITH') and (Q.Clause = '') then
      begin
        Q.Clause := 'WITH';
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      // joins
      if (Q.Clause = 'FROM') and (((W = 'LEFT') or (W = 'RIGHT') or (W = 'FULL')) and
        ((NextW = 'JOIN') or (NextW = 'OUTER')) or (W = 'INNER') or (W = 'NATURAL') or
        ((W = 'CROSS') and ((NextW = 'JOIN') or (NextW = 'APPLY'))) or
        ((W = 'OUTER') and (NextW = 'APPLY')) or (W = 'STRAIGHT_JOIN') or
        ((W = 'JOIN') and not ((PrevW = 'LEFT') or (PrevW = 'RIGHT') or (PrevW = 'FULL') or
        (PrevW = 'INNER') or (PrevW = 'OUTER') or (PrevW = 'CROSS') or (PrevW = 'NATURAL')))) then
      begin
        NL(JoinCol);
        Q.InOn := False;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if (W = 'ON') and (Q.Clause = 'FROM') then
      begin
        NL(JoinCol + Step);
        Q.InOn := True;
        Q.Between := 0;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
      if W = 'BETWEEN' then
      begin
        Inc(Q.Between);
      end;
      if ((W = 'AND') or (W = 'OR')) and ((Q.Clause = 'WHERE') or Q.InOn) then
      begin
        if (W = 'AND') and (Q.Between > 0) then
        begin
          Dec(Q.Between);
        end
        else if Opt.AndOrNewLine then
        begin
          if Q.InOn then
          begin
            NL(JoinCol + Step);
          end
          else if Opt.River then
          begin
            NL(ClauseCol(W));
          end
          else
          begin
            NL(Q.Base + Step);
          end;
        end;
        EmitTok(I);
        Inc(I);
        Continue;
      end;
    end;
    // commas in a query's lists
    if (W = ',') and Q.Active and (Depth = Q.Depth) then
    begin
      if ((Q.Clause = 'SELECT') and Q.OnePerLine) or (Q.Clause = 'FROM') or (Q.Clause = 'SET') or
        (Q.Clause = 'WITH') then
      begin
        if Q.Clause = 'WITH' then
        begin
          EmitTok(I);
          NL(Q.Base);
        end
        else if Opt.LeadingCommas then
        begin
          NL(ItemCol);
          Put(',', False);
          PrevIdx := I;
          PrevUnary := False;
        end
        else
        begin
          EmitTok(I);
          NL(ItemCol);
        end;
        Inc(I);
        Continue;
      end;
    end;

    EmitTok(I);
    Inc(I);
  end;
  Result := Out;
  while (Result <> '') and (Result[Length(Result)] in [' ', #9, #10, #13]) do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

{ ============================================================ per statement }

type
  TStmtKind = (skLayout, skBlock, skAsIs);

{ What kind of statement this is, for Format: a query or DML to lay out,
  procedural code, or something left as written. }
function KindOf(const AText: string; ADialect: TpgnDialect): TStmtKind;
var
  Toks: TpgnToks;
  I: Integer;
  W: string;
begin
  Result := skAsIs;
  Toks := Tokenize(AText, ADialect);
  I := 0;
  while (I <= High(Toks)) and IsComment(Toks[I]) do
  begin
    Inc(I);
  end;
  if I > High(Toks) then
  begin
    Exit;
  end;
  W := Toks[I].Up;
  if (W = 'SELECT') or (W = 'WITH') or (W = 'INSERT') or (W = 'UPDATE') or (W = 'DELETE') or
    (W = 'MERGE') or (W = '(') then
  begin
    Result := skLayout;
    if ADialect = sdTSQL then
    begin
      Result := skBlock;   // a batch may hold several statements
    end;
    Exit;
  end;
  if (W = 'DECLARE') or (W = 'BEGIN') then
  begin
    if (ADialect = sdOracle) or (ADialect = sdTSQL) or (ADialect = sdMySQL) then
    begin
      Result := skBlock;
    end;
    Exit;
  end;
  if (ADialect = sdTSQL) and ((W = 'IF') or (W = 'WHILE') or (W = 'SET') or (W = 'PRINT') or
    (W = 'EXEC') or (W = 'EXECUTE')) then
  begin
    Result := skBlock;
    Exit;
  end;
  if W = 'CREATE' then
  begin
    Inc(I);
    while (I <= High(Toks)) and (IsComment(Toks[I]) or (Toks[I].Up = 'OR') or (Toks[I].Up = 'REPLACE') or
      (Toks[I].Up = 'ALTER') or (Toks[I].Up = 'FORCE') or (Toks[I].Up = 'NOFORCE') or
      (Toks[I].Up = 'EDITIONABLE') or (Toks[I].Up = 'NONEDITIONABLE') or (Toks[I].Up = 'GLOBAL') or
      (Toks[I].Up = 'TEMPORARY') or (Toks[I].Up = 'TEMP') or (Toks[I].Up = 'DEFINER') or
      (Toks[I].Up = '=') or (Toks[I].Kind in [tkQuoted, tkString]) or (Pos('@', Toks[I].Text) > 0)) do
    begin
      Inc(I);
    end;
    if I > High(Toks) then
    begin
      Exit;
    end;
    W := Toks[I].Up;
    if (W = 'VIEW') or (W = 'MATERIALIZED') or (W = 'TABLE') then
    begin
      Result := skLayout;
    end
    else if ((W = 'PROCEDURE') or (W = 'FUNCTION') or (W = 'PACKAGE') or (W = 'TRIGGER') or
      (W = 'PROC')) and (ADialect <> sdPostgreSQL) then
    begin
      Result := skBlock;
    end;
  end;
end;

{ Whitespace between statements: lines trimmed, at most one blank line,
  nothing before a ';'. }
{ The statements that hold something (not an empty piece after the last ;). }
function RealSpans(const AText: string; ADialect: TpgnDialect): TpgnStatementSpans;
var
  All: TpgnStatementSpans;
  I, N: Integer;
begin
  All := SplitStatements(AText, ADialect);
  Result := nil;
  N := 0;
  for I := 0 to High(All) do
  begin
    if Trim(Copy(AText, All[I].StartPos, All[I].EndPos - All[I].StartPos + 1)) <> '' then
    begin
      SetLength(Result, N + 1);
      Result[N] := All[I];
      Inc(N);
    end;
  end;
end;

function TidyGap(AGap: string; ABlankLine, AIsLast, AOwnLine: Boolean): string;
var
  L: TStringList;
  I: Integer;
  Lead, Body: string;
  Blank: Boolean;
begin
  // the delimiter right after the statement stays glued to it
  if AOwnLine then
  begin
    AGap := LineEnding + AGap;
  end;
  Lead := '';
  I := 1;
  while (I <= Length(AGap)) and (AGap[I] in [' ', #9]) do
  begin
    Inc(I);
  end;
  if (I <= Length(AGap)) and not (AGap[I] in [#10, #13]) then
  begin
    // ';' or $$ (MySQL DELIMITER) on the statement's line
    while (I <= Length(AGap)) and not (AGap[I] in [#10, #13]) do
    begin
      Lead := Lead + AGap[I];
      Inc(I);
    end;
    Lead := TrimRight(Lead);
  end;
  Body := Copy(AGap, I, MaxInt);
  L := TStringList.Create;
  try
    L.Text := Body;
    Result := Lead;
    Blank := False;
    for I := 0 to L.Count - 1 do
    begin
      if Trim(L[I]) = '' then
      begin
        Blank := True;
        Continue;
      end;
      if Blank and (Result <> Lead) then
      begin
        Result := Result + LineEnding;
      end;
      Blank := False;
      Result := Result + LineEnding + TrimRight(L[I]);
    end;
    if not AIsLast then
    begin
      Result := Result + LineEnding;
      if ABlankLine then
      begin
        Result := Result + LineEnding;
      end;
    end;
  finally
    L.Free;
  end;
end;

function FormatSql(const AText: string; ADialect: TpgnDialect; const AOpt: TpgnFormatOptions;
  out ALeftAlone: Integer): string;
var
  Spans: TpgnStatementSpans;
  I, Where: Integer;
  Stmt, Done, Gap: string;
  F: TFormatter;
  K: TStmtKind;
begin
  ALeftAlone := 0;
  Spans := RealSpans(AText, ADialect);
  if Length(Spans) = 0 then
  begin
    Result := AText;
    Exit;
  end;
  F := TFormatter.Create;
  try
    // anything before the first statement (comments) stays as written
    Result := TrimRight(Copy(AText, 1, Spans[0].StartPos - 1));
    if Result <> '' then
    begin
      Result := Result + LineEnding;
    end;
    for I := 0 to High(Spans) do
    begin
      Stmt := Copy(AText, Spans[I].StartPos, Spans[I].EndPos - Spans[I].StartPos + 1);
      K := KindOf(Stmt, ADialect);
      if K = skAsIs then
      begin
        Done := Trim(Stmt);
      end
      else
      begin
        try
          Done := F.Run(Stmt, ADialect, AOpt, K = skBlock);
        except
          on E: Exception do
          begin
            Done := '';
          end;
        end;
        if (Done = '') or not SameMeaning(Stmt, Done, ADialect, False, Where) then
        begin
          Done := Trim(Stmt);
          Inc(ALeftAlone);
        end;
      end;
      Result := Result + Done;
      if I < High(Spans) then
      begin
        Gap := Copy(AText, Spans[I].EndPos + 1, Spans[I + 1].StartPos - Spans[I].EndPos - 1);
        Result := Result + TidyGap(Gap, AOpt.BlankLineBetween, False,
          AText[Spans[I].EndPos] in [#10, #13]);
      end
      else
      begin
        Gap := Copy(AText, Spans[I].EndPos + 1, MaxInt);
        Result := Result + TidyGap(Gap, AOpt.BlankLineBetween, True,
          AText[Spans[I].EndPos] in [#10, #13]);
      end;
    end;
  finally
    F.Free;
  end;
  // the text ended with a line break: keep one
  if (AText <> '') and (AText[Length(AText)] in [#10, #13]) then
  begin
    Result := Result + LineEnding;
  end;
end;

{ ============================================================ Join Lines }

function JoinOne(const AText: string; ADialect: TpgnDialect): string;
var
  Toks: TpgnToks;
  I, Prev: Integer;
  PrevUnary, Space: Boolean;
begin
  Toks := Tokenize(AText, ADialect);
  Result := '';
  Prev := -1;
  PrevUnary := False;
  for I := 0 to High(Toks) do
  begin
    if IsComment(Toks[I]) and not IsHint(Toks[I]) then
    begin
      Continue;
    end;
    if Prev < 0 then
    begin
      Space := False;
    end
    else
    begin
      Space := SpaceBetween(Toks[Prev], Toks[I], PrevUnary);
      // emp.sal%TYPE
      if (Toks[I].Kind = tkSymbol) and (Toks[I].Text = '%') and (I < High(Toks)) and
        (Pos(';' + Toks[I + 1].Up + ';', ';TYPE;ROWTYPE;FOUND;NOTFOUND;ISOPEN;ROWCOUNT;BULK_ROWCOUNT;') > 0) then
      begin
        Space := False;
      end;
      if (Toks[Prev].Kind = tkSymbol) and (Toks[Prev].Text = '%') and
        (Pos(';' + Toks[I].Up + ';', ';TYPE;ROWTYPE;FOUND;NOTFOUND;ISOPEN;ROWCOUNT;BULK_ROWCOUNT;') > 0) then
      begin
        Space := False;
      end;
      if (Result <> '') and (Toks[I].Text <> '') then
      begin
        if ((Result[Length(Result)] = '-') and (Toks[I].Text[1] = '-')) or
          ((Result[Length(Result)] = '/') and (Toks[I].Text[1] = '*')) or
          ((Result[Length(Result)] = '*') and (Toks[I].Text[1] = '/')) or
          ((Result[Length(Result)] in ['<', '>', '!', ':', '=', '|']) and (Toks[I].Text[1] in ['=', '>', '|'])) then
        begin
          Space := True;
        end;
      end;
    end;
    if Space then
    begin
      Result := Result + ' ' + Toks[I].Text;
    end
    else
    begin
      Result := Result + Toks[I].Text;
    end;
    PrevUnary := IsUnaryAt(Toks, I);
    Prev := I;
  end;
end;

function JoinSqlLines(const AText: string; ADialect: TpgnDialect; out ALeftAlone: Integer): string;
var
  Spans: TpgnStatementSpans;
  I, J, Where: Integer;
  Stmt, Done, Gap, Line: string;
  L: TStringList;
begin
  ALeftAlone := 0;
  Spans := RealSpans(AText, ADialect);
  if Length(Spans) = 0 then
  begin
    Result := AText;
    Exit;
  end;
  Result := '';
  L := TStringList.Create;
  try
    // before the first statement: DELIMITER lines stay, comments go
    L.Text := Copy(AText, 1, Spans[0].StartPos - 1);
    for J := 0 to L.Count - 1 do
    begin
      Line := Trim(L[J]);
      if (Line <> '') and (Copy(Line, 1, 2) <> '--') and (Copy(Line, 1, 2) <> '/*') and
        not ((ADialect = sdMySQL) and (Copy(Line, 1, 1) = '#')) then
      begin
        if Result <> '' then
        begin
          Result := Result + LineEnding;
        end;
        Result := Result + Line;
      end;
    end;
    for I := 0 to High(Spans) do
    begin
      Stmt := Copy(AText, Spans[I].StartPos, Spans[I].EndPos - Spans[I].StartPos + 1);
      Done := JoinOne(Stmt, ADialect);
      if not SameMeaning(Stmt, Done, ADialect, True, Where) then
      begin
        Done := Trim(Stmt);
        Inc(ALeftAlone);
      end;
      if Result <> '' then
      begin
        Result := Result + LineEnding;
      end;
      Result := Result + Done;
      if I < High(Spans) then
      begin
        Gap := Copy(AText, Spans[I].EndPos + 1, Spans[I + 1].StartPos - Spans[I].EndPos - 1);
      end
      else
      begin
        Gap := Copy(AText, Spans[I].EndPos + 1, MaxInt);
      end;
      // keep the delimiters (; / GO DELIMITER), drop comments and blank lines
      L.Text := Gap;
      for J := 0 to L.Count - 1 do
      begin
        Line := Trim(L[J]);
        if Line = '' then
        begin
          Continue;
        end;
        // the delimiter on the statement's own line stays glued to it
        if (J = 0) and not (AText[Spans[I].EndPos] in [#10, #13]) and (Gap <> '') and
          not (Gap[1] in [#10, #13]) and (Copy(Line, 1, 2) <> '--') and (Copy(Line, 1, 2) <> '/*') then
        begin
          if Pos(' ', Line) > 0 then
          begin
            Line := Copy(Line, 1, Pos(' ', Line) - 1);
          end;
          Result := Result + Line;
          Continue;
        end;
        if (Copy(Line, 1, 2) = '--') or (Copy(Line, 1, 2) = '/*') or
          ((ADialect = sdMySQL) and (Copy(Line, 1, 1) = '#')) then
        begin
          Continue;
        end;
        Result := Result + LineEnding + Line;
      end;
    end;
  finally
    L.Free;
  end;
  if (AText <> '') and (AText[Length(AText)] in [#10, #13]) then
  begin
    Result := Result + LineEnding;
  end;
end;

finalization
  Keywords.Free;
end.
