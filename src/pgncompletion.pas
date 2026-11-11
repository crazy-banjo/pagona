// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnCompletion;

{ Code completion's reading of the SQL: what the word before a dot stands
  for, and the words the editor already has. The database lookups are the
  query tab's.

    SELECT c.|            FROM customer c       c → customer: its columns
    SELECT customer.|     FROM sales.customer   customer → sales.customer
    SELECT * FROM sales.|                       sales: a schema, its tables }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ The table AQualifier (an alias or a table's name) stands for in
  AStatement, as written there (schema.table, quotes kept); '' when the
  statement doesn't name it in a FROM, JOIN, UPDATE or INTO. }
function TableForQualifier(const AStatement, AQualifier: string): string;

{ The words written after "AQualifier." anywhere in AText (s.customer_id →
  customer_id): what can be offered without a connection. }
procedure WordsAfterQualifier(const AText, AQualifier: string; AList: TStrings);

{ The names in AText (three or more characters, not SQL keywords). }
procedure WordsInText(const AText: string; AList: TStrings);

{ AName in the case being typed: lower case when ATyped is all lower case,
  upper case when it's all upper case, else as the database has it (and a
  mixed-case name always as it is). }
function MatchCase(const AName, ATyped: string): string;

{ The word being typed before the caret (APrefix) and, when a dot comes
  before it, the name before the dot (AQualifier: s, or sales.customer). }
procedure WordAtCaret(const ALineToCaret: string; out AQualifier, APrefix: string);

implementation

const
  IdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#'];

type
  TTokens = array of string;

{ Names (a.b."c" as one token), and every other character on its own;
  comments and strings left out. }
function Tokens(const S: string): TTokens;
var
  I, N, K: Integer;
  T: string;

  procedure Add(const AToken: string);
  begin
    if N > High(Result) then
    begin
      SetLength(Result, N * 2 + 16);
    end;
    Result[N] := AToken;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '-') and (I < Length(S)) and (S[I + 1] = '-') then
    begin
      while (I <= Length(S)) and (S[I] <> #10) do
      begin
        Inc(I);
      end;
    end
    else if (S[I] = '/') and (I < Length(S)) and (S[I + 1] = '*') then
    begin
      K := Pos('*/', Copy(S, I + 2, MaxInt));
      if K = 0 then
      begin
        I := Length(S) + 1;
      end
      else
      begin
        I := I + 2 + K + 1;
      end;
    end
    else if S[I] = '''' then
    begin
      Inc(I);
      while I <= Length(S) do
      begin
        if S[I] = '''' then
        begin
          if (I < Length(S)) and (S[I + 1] = '''') then
          begin
            Inc(I, 2);
            Continue;
          end;
          Break;
        end;
        Inc(I);
      end;
      Inc(I);
      Add('''''');
    end
    else if (S[I] in IdentChars) or (S[I] = '"') or (S[I] = '`') or (S[I] = '[') then
    begin
      T := '';
      // one name with its dots: schema.table, "Odd Name".col
      repeat
        if S[I] in ['"', '`', '['] then
        begin
          K := I + 1;
          while (K <= Length(S)) and not (S[K] in ['"', '`', ']']) do
          begin
            Inc(K);
          end;
          T := T + Copy(S, I, K - I + 1);
          I := K + 1;
        end
        else
        begin
          while (I <= Length(S)) and (S[I] in IdentChars) do
          begin
            T := T + S[I];
            Inc(I);
          end;
        end;
        if (I < Length(S)) and (S[I] = '.') and ((S[I + 1] in IdentChars) or (S[I + 1] in ['"', '`', '['])) then
        begin
          T := T + '.';
          Inc(I);
        end
        else
        begin
          Break;
        end;
      until I > Length(S);
      Add(T);
    end
    else if S[I] in [#9, #10, #13, ' '] then
    begin
      Inc(I);
    end
    else
    begin
      Add(S[I]);
      Inc(I);
    end;
  end;
  SetLength(Result, N);
end;

function Unquote(const S: string): string;
begin
  Result := S;
  if (Length(Result) >= 2) and (Result[1] in ['"', '`', '[']) then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

{ The last part of a dotted name, without quotes. }
function LastPart(const S: string): string;
var
  I: Integer;
  InQ: Boolean;
begin
  InQ := False;
  for I := Length(S) downto 1 do
  begin
    if S[I] in ['"', '`', '[', ']'] then
    begin
      InQ := not InQ;
    end
    else if (S[I] = '.') and not InQ then
    begin
      Result := Unquote(Copy(S, I + 1, MaxInt));
      Exit;
    end;
  end;
  Result := Unquote(S);
end;

function IsName(const T: string): Boolean;
begin
  Result := (T <> '') and ((T[1] in ['A'..'Z', 'a'..'z', '_', '"', '`', '[']) or (Ord(T[1]) >= 128));
end;

const
  { Words that end a table name in FROM (so they aren't taken as its alias). }
  NotAlias: array[0..37] of string = ('WHERE', 'ON', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'FULL',
    'CROSS', 'GROUP', 'ORDER', 'HAVING', 'UNION', 'SET', 'USING', 'NATURAL', 'CONNECT', 'START', 'FETCH',
    'LIMIT', 'OFFSET', 'WINDOW', 'PARTITION', 'MINUS', 'INTERSECT', 'EXCEPT', 'RETURNING', 'VALUES',
    'SELECT', 'WITH', 'FOR', 'LATERAL', 'APPLY', 'PIVOT', 'UNPIVOT', 'SAMPLE', 'TABLESAMPLE', 'MODEL');

function InList(const T: string; const AList: array of string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(AList) to High(AList) do
  begin
    if SameText(T, AList[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TableForQualifier(const AStatement, AQualifier: string): string;
var
  T: TTokens;
  I, J, Depth: Integer;
  Name, Alias, Q, Kw: string;
  InFrom, Level: array of Boolean;
begin
  Result := '';
  Q := AQualifier;
  T := Tokens(AStatement);
  // which tokens are in a FROM clause, by nesting level: a comma there
  // starts another table (FROM a JOIN b ON ..., c)
  SetLength(InFrom, Length(T));
  SetLength(Level, 1);
  Level[0] := False;
  Depth := 0;
  for I := 0 to High(T) do
  begin
    Kw := UpperCase(T[I]);
    if T[I] = '(' then
    begin
      Inc(Depth);
      if Depth > High(Level) then
      begin
        SetLength(Level, Depth + 1);
      end;
      Level[Depth] := False;
    end
    else if T[I] = ')' then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
      end;
    end
    else if Kw = 'FROM' then
    begin
      Level[Depth] := True;
    end
    else if InList(Kw, ['WHERE', 'GROUP', 'ORDER', 'HAVING', 'UNION', 'MINUS', 'INTERSECT', 'EXCEPT', 'CONNECT',
      'START', 'SELECT', 'SET', 'VALUES', 'RETURNING', 'LIMIT', 'FETCH', 'WINDOW']) then
    begin
      Level[Depth] := False;
    end;
    InFrom[I] := Level[Depth];
  end;
  // the alias first, anywhere; then a table named like the qualifier
  for I := 0 to High(T) do
  begin
    Kw := UpperCase(T[I]);
    if not ((Kw = 'FROM') or (Kw = 'JOIN') or (Kw = 'UPDATE') or (Kw = 'INTO') or ((Kw = ',') and InFrom[I])) then
    begin
      Continue;
    end;
    J := I + 1;
    while J <= High(T) do
    begin
      Name := '';
      if T[J] = '(' then
      begin
        // a subquery: its alias names no table
        Depth := 0;
        repeat
          if T[J] = '(' then
          begin
            Inc(Depth);
          end
          else if T[J] = ')' then
          begin
            Dec(Depth);
          end;
          Inc(J);
        until (J > High(T)) or (Depth = 0);
      end
      else if IsName(T[J]) and not InList(T[J], NotAlias) then
      begin
        Name := T[J];
        Inc(J);
      end
      else
      begin
        Break;
      end;
      if (J <= High(T)) and SameText(T[J], 'AS') then
      begin
        Inc(J);
      end;
      Alias := '';
      if (J <= High(T)) and IsName(T[J]) and not InList(T[J], NotAlias) then
      begin
        Alias := T[J];
        Inc(J);
      end;
      if (Name <> '') and (((Alias <> '') and SameText(Unquote(Alias), Unquote(Q))) or SameText(Name, Q) or
        ((Alias = '') and (Pos('.', Q) = 0) and SameText(LastPart(Name), Unquote(Q)))) then
      begin
        Result := Name;
        Exit;
      end;
      // FROM a, b, c
      if (Kw = 'FROM') and (J <= High(T)) and (T[J] = ',') then
      begin
        Inc(J);
      end
      else
      begin
        Break;
      end;
    end;
  end;
  // a table written with an alias but used by its own name (FROM customer s ... customer.x)
  for I := 0 to High(T) do
  begin
    Kw := UpperCase(T[I]);
    if ((Kw = 'FROM') or (Kw = 'JOIN') or (Kw = 'UPDATE') or (Kw = 'INTO') or (Kw = ',')) and (I < High(T)) and
      IsName(T[I + 1]) and (Pos('.', Q) = 0) and SameText(LastPart(T[I + 1]), Unquote(Q)) then
    begin
      Result := T[I + 1];
      Exit;
    end;
  end;
end;

procedure AddUnique(AList: TStrings; const S: string);
begin
  if (S <> '') and (AList.IndexOf(S) < 0) then
  begin
    AList.Add(S);
  end;
end;

procedure WordsAfterQualifier(const AText, AQualifier: string; AList: TStrings);
var
  T: TTokens;
  I: Integer;
  Pre: string;
begin
  T := Tokens(AText);
  Pre := LowerCase(AQualifier) + '.';
  for I := 0 to High(T) do
  begin
    if (Length(T[I]) > Length(Pre)) and (LowerCase(Copy(T[I], 1, Length(Pre))) = Pre) then
    begin
      AddUnique(AList, Unquote(Copy(T[I], Length(Pre) + 1, MaxInt)));
    end;
  end;
end;

const
  Keywords: array[0..63] of string = ('SELECT', 'FROM', 'WHERE', 'AND', 'NOT', 'NULL', 'JOIN', 'LEFT', 'RIGHT',
    'INNER', 'OUTER', 'FULL', 'CROSS', 'GROUP', 'ORDER', 'HAVING', 'UNION', 'INSERT', 'INTO', 'VALUES', 'UPDATE',
    'DELETE', 'CREATE', 'TABLE', 'VIEW', 'INDEX', 'DROP', 'ALTER', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END',
    'DISTINCT', 'BETWEEN', 'LIKE', 'EXISTS', 'ALL', 'ANY', 'WITH', 'ASC', 'DESC', 'LIMIT', 'OFFSET', 'FETCH',
    'FIRST', 'ROWS', 'ONLY', 'USING', 'BEGIN', 'COMMIT', 'ROLLBACK', 'GRANT', 'REVOKE', 'TRUE', 'FALSE',
    'DUAL', 'SYSDATE', 'ROWNUM', 'MINUS', 'INTERSECT', 'EXCEPT', 'OVER', 'PARTITION');

procedure WordsInText(const AText: string; AList: TStrings);
var
  T: TTokens;
  I, K: Integer;
  W: string;
begin
  T := Tokens(AText);
  for I := 0 to High(T) do
  begin
    if not IsName(T[I]) then
    begin
      Continue;
    end;
    // each part of a dotted name
    W := T[I];
    repeat
      K := Pos('.', W);
      if K > 0 then
      begin
        if Length(Unquote(Copy(W, 1, K - 1))) >= 3 then
        begin
          if not InList(Copy(W, 1, K - 1), Keywords) then
          begin
            AddUnique(AList, Unquote(Copy(W, 1, K - 1)));
          end;
        end;
        W := Copy(W, K + 1, MaxInt);
      end;
    until K = 0;
    if (Length(Unquote(W)) >= 3) and not InList(W, Keywords) then
    begin
      AddUnique(AList, Unquote(W));
    end;
  end;
end;

function MatchCase(const AName, ATyped: string): string;
begin
  Result := AName;
  // a name in mixed case was quoted when it was made: kept as it is
  if (ATyped = '') or ((UpperCase(AName) <> AName) and (LowerCase(AName) <> AName)) then
  begin
    Exit;
  end;
  if (LowerCase(ATyped) = ATyped) and (UpperCase(ATyped) <> ATyped) then
  begin
    Result := LowerCase(AName);
  end
  else if (UpperCase(ATyped) = ATyped) and (LowerCase(ATyped) <> ATyped) then
  begin
    Result := UpperCase(AName);
  end;
end;

procedure WordAtCaret(const ALineToCaret: string; out AQualifier, APrefix: string);
var
  I, K: Integer;
begin
  AQualifier := '';
  I := Length(ALineToCaret);
  while (I >= 1) and ((ALineToCaret[I] in IdentChars) or (Ord(ALineToCaret[I]) >= 128)) do
  begin
    Dec(I);
  end;
  APrefix := Copy(ALineToCaret, I + 1, MaxInt);
  if (I >= 1) and (ALineToCaret[I] = '.') then
  begin
    K := I - 1;
    while (K >= 1) and ((ALineToCaret[K] in IdentChars) or (ALineToCaret[K] in ['.', '"', '`', '[', ']']) or
      (Ord(ALineToCaret[K]) >= 128)) do
    begin
      Dec(K);
    end;
    AQualifier := Copy(ALineToCaret, K + 1, I - K - 1);
  end;
end;

end.
