// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnJoinConvert;

{ Convert (+) Joins to ANSI: rewrites Oracle's old outer-join marks as
  LEFT JOIN ... ON, query block by query block (each SELECT, subqueries
  first).

  In one query block:
    - a condition with (+) on table A's columns, the other side on table P,
      is A's join condition: P ... LEFT JOIN A ON (condition without (+)).
      Every (+) condition on A goes into that ON, filters on A included
      (a.kind(+) = 'SHIP'); left in WHERE they would turn the outer join
      into an inner one.
    - the other comma joins become JOIN ... ON with the conditions between
      the tables they join, so the FROM reads one way; a table nothing
      joins to becomes CROSS JOIN.
    - every other condition stays in WHERE, as Oracle applied it there.
    - tables keep their FROM order, except that a table outer-joined to one
      listed after it waits until that one is in (refused with SELECT *,
      where the order of the columns would change).

  Left as written, with a /* TODO PG: (+) left as written: ... */ note, are the blocks Pagona
  can't rewrite faithfully: (+) with OR or IN, a table outer-joined to two
  others, (+) inside a function, a condition that refers outside the
  block, a column it can't tie to a table, ANSI joins already mixed in.

  Unqualified columns are tied to their table by their names (a column
  that starts with the table's name: customer_city is CUSTOMER's) or, when
  a lookup is given (a connected tab), by the table's own columns. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, pgnTypes, pgnSqlFormat, pgnSqlSplit;

type
  { The columns of a table (as written in the query), upper case; nil when
    unknown. The caller owns the list. }
  TpgnColumnLookup = function(const ATable: string): TStrings of object;

{ Converts the (+) joins in AText (Oracle SQL). ANotes gets one line per
  query block that had (+): what was done, or why it was left. AConverted
  and ASkipped count them. The result is not formatted. }
function ConvertOuterJoins(const AText: string; ALookup: TpgnColumnLookup; ANotes: TStrings;
  out AConverted, ASkipped: Integer): string;

{ True when the text has any (+) mark (outside strings and comments). }
function HasOuterJoinMarks(const AText: string): Boolean;

implementation

const
  TodoMark = '/* TODO PG: (+) left as written: ';

type
  TBlock = record
    SelectIdx: Integer;    // the SELECT token
    EndIdx: Integer;       // last token of the block
    Depth: Integer;
    Parent: Integer;
  end;

  TItem = record
    FromTok, ToTok: Integer;     // tokens of the FROM item (comments included)
    Name: string;                // what columns are qualified with (alias or table)
    Disp: string;                // the same, as written
    Table: string;               // the table's own name, upper case ('' for a subquery)
    Full: string;                // with its schema when written (SALES.CUSTOMER): what's looked up
    Placed: Boolean;
  end;

  TCond = record
    FromTok, ToTok: Integer;
    HasMark: Boolean;
    OptItem: Integer;            // the table the (+) columns belong to
    Refs: array of Integer;      // the FROM items it mentions
    HasSub: Boolean;
    Problem: string;
    Target: Integer;             // the FROM item whose ON takes it; -1 = WHERE
  end;

function HasOuterJoinMarks(const AText: string): Boolean;
var
  T: TpgnToks;
  I: Integer;
begin
  Result := False;
  T := Tokenize(AText, sdOracle);
  for I := 0 to High(T) do
  begin
    if T[I].Kind = tkOuterMark then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function IsCmt(const T: TpgnTok): Boolean;
begin
  Result := T.Kind in [tkLineComment, tkBlockComment];
end;

function TU(const T: TpgnToks; I: Integer): string;
begin
  if (I < 0) or (I > High(T)) then
  begin
    Result := '';
  end
  else if T[I].Kind in [tkWord, tkSymbol] then
  begin
    Result := T[I].Up;
  end
  else
  begin
    Result := '';
  end;
end;

{ A quoted name without its quotes ("Mixed" -> Mixed); a plain one upper-cased. }
function NameKey(const T: TpgnTok): string;
begin
  if T.Kind = tkQuoted then
  begin
    Result := Copy(T.Text, 2, Length(T.Text) - 2);
  end
  else
  begin
    Result := UpperCase(T.Text);
  end;
end;

function IsPseudo(const AUp: string): Boolean;
begin
  Result := Pos(';' + AUp + ';', ';SYSDATE;SYSTIMESTAMP;ROWNUM;LEVEL;USER;UID;CURRENT_DATE;' +
    'CURRENT_TIMESTAMP;LOCALTIMESTAMP;NULL;TRUE;FALSE;ROWID;DUAL;') > 0;
end;

type
  TConverter = class
  private
    Text: string;
    T: TpgnToks;
    Blocks: array of TBlock;
    Lookup: TpgnColumnLookup;
    Cache: TStringList;   // table -> columns (TStringList objects)
    procedure FindBlocks;
    function Owner(AIdx: Integer): Integer;
    function OwnMarks(AB: Integer): Boolean;
    function HasTodo(AB: Integer): Boolean;
    function ColumnsOf(const ATable: string): TStrings;
    function TokText(AFrom, ATo: Integer; ADropMarks: Boolean): string;
    function TryBlock(AB: Integer; out ANew: string; out AFromPos, AToPos: Integer;
      out ANote: string): Boolean;
  public
    constructor Create(ALookup: TpgnColumnLookup);
    destructor Destroy; override;
    function Run(const AText: string; ANotes: TStrings; out AConverted, ASkipped: Integer): string;
  end;

constructor TConverter.Create(ALookup: TpgnColumnLookup);
begin
  inherited Create;
  Lookup := ALookup;
  Cache := TStringList.Create;
  Cache.OwnsObjects := True;
  Cache.CaseSensitive := False;
end;

destructor TConverter.Destroy;
begin
  Cache.Free;
  inherited Destroy;
end;

function TConverter.ColumnsOf(const ATable: string): TStrings;
var
  I: Integer;
  L: TStrings;
  Own: TStringList;
begin
  Result := nil;
  if (ATable = '') or not Assigned(Lookup) then
  begin
    Exit;
  end;
  I := Cache.IndexOf(ATable);
  if I >= 0 then
  begin
    Result := TStrings(Cache.Objects[I]);
    Exit;
  end;
  Own := nil;
  try
    L := Lookup(ATable);
    if L <> nil then
    begin
      Own := TStringList.Create;
      Own.CaseSensitive := False;
      Own.Assign(L);
      L.Free;
    end;
  except
    on E: Exception do
    begin
      Own := nil;
    end;
  end;
  Cache.AddObject(ATable, Own);
  Result := Own;
end;

{ Each SELECT and the tokens up to where its block ends: a ')' closing
  the parens it sits in, ';', or the end. Set operators continue a block's
  statement but start a new block for the next SELECT. }
procedure TConverter.FindBlocks;
var
  I, J, D, N, Stack: Integer;
  Depths: array of Integer;
begin
  SetLength(Blocks, 0);
  SetLength(Depths, Length(T));
  D := 0;
  for I := 0 to High(T) do
  begin
    if TU(T, I) = '(' then
    begin
      Depths[I] := D;
      Inc(D);
    end
    else if TU(T, I) = ')' then
    begin
      Dec(D);
      Depths[I] := D;
    end
    else
    begin
      Depths[I] := D;
    end;
  end;
  for I := 0 to High(T) do
  begin
    if (T[I].Kind = tkWord) and (T[I].Up = 'SELECT') then
    begin
      N := Length(Blocks);
      SetLength(Blocks, N + 1);
      Blocks[N].SelectIdx := I;
      Blocks[N].Depth := Depths[I];
      J := I + 1;
      while J <= High(T) do
      begin
        if (TU(T, J) = ')') and (Depths[J] < Depths[I]) then
        begin
          Break;
        end;
        if (Depths[J] = Depths[I]) and ((TU(T, J) = ';') or (TU(T, J) = 'UNION') or
          (TU(T, J) = 'INTERSECT') or (TU(T, J) = 'MINUS') or (TU(T, J) = 'EXCEPT')) then
        begin
          Break;
        end;
        Inc(J);
      end;
      Blocks[N].EndIdx := J - 1;
      // the parent: the innermost block before it that contains it
      Blocks[N].Parent := -1;
      for Stack := N - 1 downto 0 do
      begin
        if (Blocks[Stack].SelectIdx < I) and (Blocks[Stack].EndIdx >= Blocks[N].EndIdx) then
        begin
          Blocks[N].Parent := Stack;
          Break;
        end;
      end;
    end;
  end;
end;

{ The innermost block a token belongs to. }
function TConverter.Owner(AIdx: Integer): Integer;
var
  B: Integer;
begin
  Result := -1;
  for B := 0 to High(Blocks) do
  begin
    if (Blocks[B].SelectIdx <= AIdx) and (AIdx <= Blocks[B].EndIdx) then
    begin
      if (Result < 0) or (Blocks[B].SelectIdx > Blocks[Result].SelectIdx) then
      begin
        Result := B;
      end;
    end;
  end;
end;

function TConverter.OwnMarks(AB: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Blocks[AB].SelectIdx to Blocks[AB].EndIdx do
  begin
    if (T[I].Kind = tkOuterMark) and (Owner(I) = AB) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TConverter.HasTodo(AB: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  // the note goes just before the block's FROM
  for I := Blocks[AB].SelectIdx to Blocks[AB].EndIdx do
  begin
    if (T[I].Kind = tkBlockComment) and (Copy(T[I].Text, 1, Length(TodoMark)) = TodoMark) and
      (Owner(I) = AB) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ The text of tokens AFrom..ATo as written (comments too), (+) marks left
  out when ADropMarks. A trailing line comment keeps a line break after it. }
function TConverter.TokText(AFrom, ATo: Integer; ADropMarks: Boolean): string;
var
  I, P: Integer;
begin
  Result := '';
  if AFrom > ATo then
  begin
    Exit;
  end;
  P := T[AFrom].StartPos;
  for I := AFrom to ATo do
  begin
    if ADropMarks and (T[I].Kind = tkOuterMark) then
    begin
      Result := Result + Copy(Text, P, T[I].StartPos - P);
      P := T[I].EndPos + 1;
    end;
  end;
  Result := Result + Copy(Text, P, T[ATo].EndPos - P + 1);
  Result := Trim(Result);
  if T[ATo].Kind = tkLineComment then
  begin
    Result := Result + LineEnding;
  end;
end;

function TConverter.TryBlock(AB: Integer; out ANew: string; out AFromPos, AToPos: Integer;
  out ANote: string): Boolean;
var
  B: TBlock;
  I, J, K, D, FromIdx, WhereIdx, RegionEnd, Start, N, Next, First: Integer;
  Items: array of TItem;
  Conds: array of TCond;
  Order: array of Integer;
  W, Q, Col, Problem, Names, OnText, WhereText: string;
  Found, Ready, StarSelect, Moved: Boolean;
  Pres: array of Integer;
  Cols: TStrings;
  LeftJoins, InnerJoins, Crosses: Integer;

  function ItemOf(const AName: string): Integer;
  var
    M: Integer;
  begin
    Result := -1;
    for M := 0 to High(Items) do
    begin
      if (Items[M].Name <> '') and (Items[M].Name = AName) then
      begin
        Result := M;
        Exit;
      end;
    end;
  end;

  { An unqualified column's table: its name first (customer_city),
    then the tables' own columns when they can be looked up. }
  function ItemOfColumn(const ACol: string): Integer;
  var
    M, Hits: Integer;
    L: TStrings;
    AllKnown: Boolean;
  begin
    // the tables' own columns, when they can be looked up (a connected tab)
    Result := -1;
    Hits := 0;
    AllKnown := True;
    for M := 0 to High(Items) do
    begin
      L := ColumnsOf(Items[M].Full);
      if L = nil then
      begin
        AllKnown := False;
      end
      else if L.IndexOf(ACol) >= 0 then
      begin
        Result := M;
        Inc(Hits);
      end;
    end;
    if Hits = 1 then
    begin
      Exit;
    end;
    Result := -1;
    if (Hits > 1) or AllKnown then
    begin
      Exit;   // in two tables, or in none of them
    end;
    // columns named after their table: CUSTOMER's columns CUSTOMER_...
    Hits := 0;
    for M := 0 to High(Items) do
    begin
      if (Items[M].Table <> '') and (Copy(ACol, 1, Length(Items[M].Table) + 1) = Items[M].Table + '_') then
      begin
        Result := M;
        Inc(Hits);
      end;
    end;
    if Hits <> 1 then
    begin
      Result := -1;
    end;
  end;

  procedure AddRef(var C: TCond; AItem: Integer);
  var
    M: Integer;
  begin
    for M := 0 to High(C.Refs) do
    begin
      if C.Refs[M] = AItem then
      begin
        Exit;
      end;
    end;
    SetLength(C.Refs, Length(C.Refs) + 1);
    C.Refs[High(C.Refs)] := AItem;
  end;

  function IsTerminator(AIdx: Integer): Boolean;
  var
    X: string;
  begin
    X := TU(T, AIdx);
    Result := (X = 'GROUP') or (X = 'HAVING') or (X = 'ORDER') or (X = 'CONNECT') or
      ((X = 'START') and (TU(T, AIdx + 1) = 'WITH')) or (X = 'MODEL') or (X = 'FETCH') or
      (X = 'OFFSET') or ((X = 'FOR') and (TU(T, AIdx + 1) = 'UPDATE')) or (X = 'WINDOW');
  end;

  function Fail(const AWhy: string): Boolean;
  begin
    ANote := AWhy;
    Result := False;
  end;

begin
  Result := False;
  ANew := '';
  ANote := '';
  AFromPos := 0;
  AToPos := 0;
  B := Blocks[AB];
  // FROM and WHERE at the block's own level
  FromIdx := -1;
  WhereIdx := -1;
  RegionEnd := B.EndIdx;
  D := 0;
  for I := B.SelectIdx + 1 to B.EndIdx do
  begin
    if TU(T, I) = '(' then
    begin
      Inc(D);
    end
    else if TU(T, I) = ')' then
    begin
      Dec(D);
    end
    else if D = 0 then
    begin
      if (FromIdx < 0) and (TU(T, I) = 'FROM') then
      begin
        FromIdx := I;
      end
      else if (FromIdx >= 0) and (WhereIdx < 0) and (TU(T, I) = 'WHERE') then
      begin
        WhereIdx := I;
      end
      else if (FromIdx >= 0) and IsTerminator(I) then
      begin
        RegionEnd := I - 1;
        Break;
      end;
    end;
  end;
  if (FromIdx < 0) or (WhereIdx < 0) then
  begin
    Exit(Fail('no FROM ... WHERE to rewrite'));
  end;

  // SELECT *: reordering the tables would reorder the columns
  StarSelect := False;
  D := 0;
  for I := B.SelectIdx + 1 to FromIdx - 1 do
  begin
    if TU(T, I) = '(' then
    begin
      Inc(D);
    end
    else if TU(T, I) = ')' then
    begin
      Dec(D);
    end
    else if (D = 0) and (TU(T, I) = '*') then
    begin
      J := I - 1;
      while (J > B.SelectIdx) and IsCmt(T[J]) do
      begin
        Dec(J);
      end;
      if (J = B.SelectIdx) or (TU(T, J) = ',') or (TU(T, J) = 'DISTINCT') or (TU(T, J) = 'ALL') or
        (TU(T, J) = 'UNIQUE') or ((T[J].Kind = tkBlockComment)) then
      begin
        StarSelect := True;
      end;
    end;
  end;

  // the FROM items
  SetLength(Items, 0);
  Start := FromIdx + 1;
  D := 0;
  I := FromIdx + 1;
  while I <= WhereIdx do
  begin
    if (I < WhereIdx) and (TU(T, I) = '(') then
    begin
      Inc(D);
    end
    else if (I < WhereIdx) and (TU(T, I) = ')') then
    begin
      Dec(D);
    end
    else if (I < WhereIdx) and (D = 0) and ((TU(T, I) = 'JOIN') or (TU(T, I) = 'APPLY')) then
    begin
      Exit(Fail('this query already mixes ANSI JOIN with (+)'));
    end;
    if (I = WhereIdx) or ((D = 0) and (TU(T, I) = ',')) then
    begin
      N := Length(Items);
      SetLength(Items, N + 1);
      Items[N].FromTok := Start;
      Items[N].ToTok := I - 1;
      Items[N].Placed := False;
      // the significant tokens: table [AS] alias
      J := I - 1;
      while (J >= Start) and IsCmt(T[J]) do
      begin
        Dec(J);
      end;
      K := Start;
      while (K <= J) and IsCmt(T[K]) do
      begin
        Inc(K);
      end;
      if K > J then
      begin
        Exit(Fail('an empty FROM item'));
      end;
      Items[N].Table := '';
      Items[N].Full := '';
      if TU(T, K) <> '(' then
      begin
        // schema.table[@link]: the table's own name is the part after the last dot
        Next := K;
        while (Next + 2 <= J) and (TU(T, Next + 1) = '.') do
        begin
          Items[N].Full := Items[N].Full + NameKey(T[Next]) + '.';
          Next := Next + 2;
        end;
        Items[N].Table := NameKey(T[Next]);
        if Pos('@', Items[N].Table) > 0 then
        begin
          Items[N].Table := Copy(Items[N].Table, 1, Pos('@', Items[N].Table) - 1);
        end;
        // looked up where the SQL says it is: the database needn't search for it
        Items[N].Full := Items[N].Full + Items[N].Table;
        if (J > Next) and (T[J].Kind in [tkWord, tkQuoted]) and not IsSqlKeyword(T[J].Up) then
        begin
          Items[N].Name := NameKey(T[J]);
          Items[N].Disp := T[J].Text;
        end
        else
        begin
          Items[N].Name := Items[N].Table;
          Items[N].Disp := T[Next].Text;
        end;
      end
      else
      begin
        if (T[J].Kind in [tkWord, tkQuoted]) and not IsSqlKeyword(T[J].Up) then
        begin
          Items[N].Name := NameKey(T[J]);
          Items[N].Disp := T[J].Text;
        end
        else
        begin
          Items[N].Name := '';
          Items[N].Disp := '(subquery)';
        end;
      end;
      Start := I + 1;
    end;
    Inc(I);
  end;
  if Length(Items) < 2 then
  begin
    Exit(Fail('only one table in FROM'));
  end;

  // the WHERE conditions, split at AND (BETWEEN's AND aside)
  SetLength(Conds, 0);
  Start := WhereIdx + 1;
  D := 0;
  K := 0;   // BETWEENs waiting for their AND
  I := WhereIdx + 1;
  while I <= RegionEnd + 1 do
  begin
    if I <= RegionEnd then
    begin
      W := TU(T, I);
      if W = '(' then
      begin
        Inc(D);
      end
      else if W = ')' then
      begin
        Dec(D);
      end
      else if (D = 0) and (W = 'BETWEEN') then
      begin
        Inc(K);
      end;
    end
    else
    begin
      W := '';
    end;
    if (I > RegionEnd) or ((D = 0) and (W = 'AND') and (K = 0)) then
    begin
      N := Length(Conds);
      SetLength(Conds, N + 1);
      Conds[N].FromTok := Start;
      Conds[N].ToTok := I - 1;
      Conds[N].HasMark := False;
      Conds[N].OptItem := -1;
      SetLength(Conds[N].Refs, 0);
      Conds[N].HasSub := False;
      Conds[N].Problem := '';
      Conds[N].Target := -1;
      Start := I + 1;
    end
    else if (D = 0) and (W = 'AND') and (K > 0) then
    begin
      Dec(K);
    end;
    Inc(I);
  end;

  // each condition: its tables, its (+) marks
  for N := 0 to High(Conds) do
  begin
    I := Conds[N].FromTok;
    while I <= Conds[N].ToTok do
    begin
      if IsCmt(T[I]) then
      begin
        Inc(I);
        Continue;
      end;
      W := TU(T, I);
      if (W = 'SELECT') then
      begin
        Conds[N].HasSub := True;
      end;
      if T[I].Kind = tkOuterMark then
      begin
        if Owner(I) = AB then
        begin
          Conds[N].HasMark := True;
        end;
        Inc(I);
        Continue;
      end;
      if (T[I].Kind in [tkWord, tkQuoted]) and (Owner(I) = AB) and
        not ((I > 0) and (TU(T, I - 1) = '.')) then
      begin
        // a column: [qualifier.]name, or schema.table.name
        if (TU(T, I + 1) = '.') and (I + 2 <= Conds[N].ToTok) then
        begin
          J := I;
          while (TU(T, J + 1) = '.') and (J + 2 <= Conds[N].ToTok) do
          begin
            J := J + 2;
          end;
          // the qualifier is the part just before the column
          Q := NameKey(T[J - 2]);
          if TU(T, J + 1) = '(' then
          begin
            // pkg.function(...)
            I := J + 1;
            Continue;
          end;
          K := ItemOf(Q);
          if K >= 0 then
          begin
            AddRef(Conds[N], K);
            if (J + 1 <= Conds[N].ToTok) and (T[J + 1].Kind = tkOuterMark) then
            begin
              if (Conds[N].OptItem >= 0) and (Conds[N].OptItem <> K) then
              begin
                Conds[N].Problem := '(+) on two tables in one condition';
              end;
              Conds[N].OptItem := K;
            end;
          end
          else if (T[J + 1].Kind = tkOuterMark) or (Conds[N].Problem = '') then
          begin
            if not IsPseudo(UpperCase(T[J].Text)) and (UpperCase(T[J].Text) <> 'NEXTVAL') and
              (UpperCase(T[J].Text) <> 'CURRVAL') then
            begin
              Conds[N].Problem := 'refers to ' + T[J - 2].Text + ', which isn''t in this query''s FROM ' +
                '(a correlated condition)';
            end;
          end;
          I := J + 1;
          Continue;
        end;
        // unqualified: a column unless it's a keyword, a function or a constant
        if (T[I].Kind = tkWord) and (IsSqlKeyword(T[I].Up) or IsPseudo(T[I].Up) or
          (TU(T, I + 1) = '(') or (Copy(T[I].Text, 1, 1) = ':') or (Copy(T[I].Text, 1, 1) = '&')) then
        begin
          Inc(I);
          Continue;
        end;
        Col := NameKey(T[I]);
        K := ItemOfColumn(Col);
        if K >= 0 then
        begin
          AddRef(Conds[N], K);
          if (I + 1 <= Conds[N].ToTok) and (T[I + 1].Kind = tkOuterMark) then
          begin
            if (Conds[N].OptItem >= 0) and (Conds[N].OptItem <> K) then
            begin
              Conds[N].Problem := '(+) on two tables in one condition';
            end;
            Conds[N].OptItem := K;
          end;
        end
        else if Conds[N].Problem = '' then
        begin
          Conds[N].Problem := 'can''t tell which table ' + T[I].Text + ' belongs to (qualify it, ' +
            'e.g. ' + Items[0].Disp + '.' + T[I].Text + ')';
        end;
      end;
      Inc(I);
    end;
  end;

  // the conditions with (+): what Pagona can't rewrite faithfully
  for N := 0 to High(Conds) do
  begin
    if not Conds[N].HasMark then
    begin
      Continue;
    end;
    if Conds[N].Problem <> '' then
    begin
      Exit(Fail(Conds[N].Problem));
    end;
    if Conds[N].OptItem < 0 then
    begin
      Exit(Fail('a (+) that isn''t on a column of a table in FROM'));
    end;
    if Conds[N].HasSub then
    begin
      Exit(Fail('(+) in a condition with a subquery'));
    end;
    D := 0;
    for I := Conds[N].FromTok to Conds[N].ToTok do
    begin
      W := TU(T, I);
      if (W = 'OR') then
      begin
        Exit(Fail('(+) with OR'));
      end;
      if (W = 'IN') then
      begin
        Exit(Fail('(+) with IN'));
      end;
      if W = '(' then
      begin
        Inc(D);
      end
      else if W = ')' then
      begin
        Dec(D);
      end
      else if (T[I].Kind = tkOuterMark) and (D > 0) then
      begin
        Exit(Fail('(+) inside a function or parentheses'));
      end;
    end;
  end;

  // each outer-joined table and the one table it's joined to
  SetLength(Pres, Length(Items));
  for K := 0 to High(Items) do
  begin
    Pres[K] := -2;   // -2: not outer-joined
  end;
  for N := 0 to High(Conds) do
  begin
    if not Conds[N].HasMark then
    begin
      Continue;
    end;
    K := Conds[N].OptItem;
    if Pres[K] = -2 then
    begin
      Pres[K] := -1;
    end;
    for J := 0 to High(Conds[N].Refs) do
    begin
      if Conds[N].Refs[J] = K then
      begin
        Continue;
      end;
      if (Pres[K] >= 0) and (Pres[K] <> Conds[N].Refs[J]) then
      begin
        Exit(Fail(Items[K].Disp + ' is outer-joined to two tables (' + Items[Pres[K]].Disp + ' and ' +
          Items[Conds[N].Refs[J]].Disp + ')'));
      end;
      Pres[K] := Conds[N].Refs[J];
    end;
  end;
  for K := 0 to High(Items) do
  begin
    if Pres[K] = -1 then
    begin
      Exit(Fail(Items[K].Disp + ' has (+) only against constants, with no join condition'));
    end;
  end;

  // the order: FROM order, an outer-joined table after the one it joins to
  SetLength(Order, 0);
  while Length(Order) < Length(Items) do
  begin
    Found := False;
    for K := 0 to High(Items) do
    begin
      if Items[K].Placed then
      begin
        Continue;
      end;
      Ready := (Pres[K] < 0) or Items[Pres[K]].Placed;
      if Ready then
      begin
        Items[K].Placed := True;
        SetLength(Order, Length(Order) + 1);
        Order[High(Order)] := K;
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Exit(Fail('the outer joins go in a circle'));
    end;
  end;
  Moved := False;
  for K := 0 to High(Order) do
  begin
    if Order[K] <> K then
    begin
      Moved := True;
    end;
  end;
  if Moved and StarSelect then
  begin
    Exit(Fail('SELECT * with tables that would need reordering (the columns would change order)'));
  end;
  // an outer-joined table can't be the first: something must come before it
  if Pres[Order[0]] >= 0 then
  begin
    Exit(Fail('the first table is outer-joined'));
  end;

  // where each condition goes
  for N := 0 to High(Conds) do
  begin
    if Conds[N].HasMark then
    begin
      Conds[N].Target := Conds[N].OptItem;
      Continue;
    end;
    // a join between two inner tables: the ON of the later one
    if (Length(Conds[N].Refs) >= 2) and not Conds[N].HasSub and (Conds[N].Problem = '') then
    begin
      Found := True;
      for J := 0 to High(Conds[N].Refs) do
      begin
        if Pres[Conds[N].Refs[J]] >= 0 then
        begin
          Found := False;
        end;
      end;
      if Found then
      begin
        Next := -1;
        for K := 0 to High(Order) do
        begin
          for J := 0 to High(Conds[N].Refs) do
          begin
            if Order[K] = Conds[N].Refs[J] then
            begin
              Next := K;
            end;
          end;
        end;
        if Next > 0 then
        begin
          Conds[N].Target := Order[Next];
        end;
      end;
    end;
  end;

  // the new FROM ... WHERE
  First := Order[0];
  ANew := 'FROM ' + TokText(Items[First].FromTok, Items[First].ToTok, False);
  Names := Items[First].Disp;
  LeftJoins := 0;
  InnerJoins := 0;
  Crosses := 0;
  for K := 1 to High(Order) do
  begin
    J := Order[K];
    OnText := '';
    for N := 0 to High(Conds) do
    begin
      if Conds[N].Target = J then
      begin
        if OnText <> '' then
        begin
          OnText := OnText + ' AND ';
        end;
        OnText := OnText + TokText(Conds[N].FromTok, Conds[N].ToTok, True);
      end;
    end;
    if Pres[J] >= 0 then
    begin
      ANew := ANew + ' LEFT JOIN ' + TokText(Items[J].FromTok, Items[J].ToTok, False) + ' ON ' + OnText;
      Inc(LeftJoins);
    end
    else if OnText <> '' then
    begin
      ANew := ANew + ' JOIN ' + TokText(Items[J].FromTok, Items[J].ToTok, False) + ' ON ' + OnText;
      Inc(InnerJoins);
    end
    else
    begin
      ANew := ANew + ' CROSS JOIN ' + TokText(Items[J].FromTok, Items[J].ToTok, False);
      Inc(Crosses);
    end;
    Names := Names + ', ' + Items[J].Disp;
  end;
  WhereText := '';
  for N := 0 to High(Conds) do
  begin
    if Conds[N].Target < 0 then
    begin
      if WhereText <> '' then
      begin
        WhereText := WhereText + ' AND ';
      end;
      WhereText := WhereText + TokText(Conds[N].FromTok, Conds[N].ToTok, False);
    end;
  end;
  if WhereText <> '' then
  begin
    ANew := ANew + ' WHERE ' + WhereText;
  end;
  ANew := ANew + ' ';
  AFromPos := T[FromIdx].StartPos;
  AToPos := T[RegionEnd].EndPos;
  ANote := Names + ': ' + IntToStr(LeftJoins) + ' LEFT JOIN';
  if InnerJoins > 0 then
  begin
    ANote := ANote + ', ' + IntToStr(InnerJoins) + ' JOIN';
  end;
  if Crosses > 0 then
  begin
    ANote := ANote + ', ' + IntToStr(Crosses) + ' CROSS JOIN (nothing joined it to the others)';
  end;
  Result := True;
end;

function TConverter.Run(const AText: string; ANotes: TStrings; out AConverted, ASkipped: Integer): string;
var
  B, Pick, Guard, FromPos, ToPos, FromTok, I: Integer;
  NewText, Note, Lead: string;
  Found: TStringList;
begin
  AConverted := 0;
  ASkipped := 0;
  Text := AText;
  Guard := 0;
  Found := TStringList.Create;
  while Guard < 500 do
  begin
    Inc(Guard);
    T := Tokenize(Text, sdOracle);
    FindBlocks;
    // the deepest block (latest SELECT among the innermost) with its own (+)
    Pick := -1;
    for B := High(Blocks) downto 0 do
    begin
      if OwnMarks(B) and not HasTodo(B) then
      begin
        if (Pick < 0) or (Blocks[B].Depth > Blocks[Pick].Depth) then
        begin
          Pick := B;
        end;
      end;
    end;
    if Pick < 0 then
    begin
      Break;
    end;
    if TryBlock(Pick, NewText, FromPos, ToPos, Note) then
    begin
      Text := Copy(Text, 1, FromPos - 1) + NewText + Copy(Text, ToPos + 1, MaxInt);
      Found.AddObject(Format('%.9d', [T[Blocks[Pick].SelectIdx].StartPos]), TObject(PtrInt(1)));
      Found[Found.Count - 1] := Found[Found.Count - 1] + #1 + 'Converted: ' + Note;
      Inc(AConverted);
    end
    else
    begin
      // mark it, just before its FROM (or its SELECT)
      FromTok := Blocks[Pick].SelectIdx;
      for I := Blocks[Pick].SelectIdx to Blocks[Pick].EndIdx do
      begin
        if (TU(T, I) = 'FROM') and (Owner(I) = Pick) then
        begin
          FromTok := I;
          Break;
        end;
      end;
      Lead := LineEnding + TodoMark + StringReplace(Note, '*/', '* /', [rfReplaceAll]) + ' */' + LineEnding;
      Text := Copy(Text, 1, T[FromTok].StartPos - 1) + Lead + Copy(Text, T[FromTok].StartPos, MaxInt);
      Found.Add(Format('%.9d', [T[Blocks[Pick].SelectIdx].StartPos]) + #1 + 'Left as written: ' + Note);
      Inc(ASkipped);
    end;
  end;
  Result := Text;
  // the notes in the order the queries come in the text
  Found.Sort;
  for I := 0 to Found.Count - 1 do
  begin
    ANotes.Add(Copy(Found[I], Pos(#1, Found[I]) + 1, MaxInt));
  end;
  Found.Free;
end;

{ One statement at a time (a query block never runs past its statement's
  ; or /); the text between statements stays as it is. }
function ConvertOuterJoins(const AText: string; ALookup: TpgnColumnLookup; ANotes: TStrings;
  out AConverted, ASkipped: Integer): string;
var
  C: TConverter;
  Spans: TpgnStatementSpans;
  I, P, Conv, Skip: Integer;
  Stmt: string;
begin
  AConverted := 0;
  ASkipped := 0;
  Result := '';
  Spans := SplitStatements(AText, sdOracle);
  C := TConverter.Create(ALookup);
  try
    P := 1;
    for I := 0 to High(Spans) do
    begin
      Result := Result + Copy(AText, P, Spans[I].StartPos - P);
      Stmt := Copy(AText, Spans[I].StartPos, Spans[I].EndPos - Spans[I].StartPos + 1);
      if HasOuterJoinMarks(Stmt) then
      begin
        Stmt := C.Run(Stmt, ANotes, Conv, Skip);
        Inc(AConverted, Conv);
        Inc(ASkipped, Skip);
      end;
      Result := Result + Stmt;
      P := Spans[I].EndPos + 1;
    end;
    Result := Result + Copy(AText, P, MaxInt);
  finally
    C.Free;
  end;
end;

end.
