// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnErrorPos;

{ Where in a statement an error happened, read from the database's message:

    PostgreSQL   LINE 3: ... and a ^ under the spot (exact)
    Oracle       ORA-06550: line 3, column 12 (PL/SQL; exact)
                 ORA-00904: "X": invalid identifier (the name is looked for)
    MySQL        ... near 'xyz' at line 3
    SQL Server   Line 3 / Incorrect syntax near 'xyz'

  The line and column are within the statement as it was sent; the caller
  adds where the statement starts in the editor. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils;

{ ALine / ACol (1-based) within AStatement; False when the message doesn't
  say (the caller then goes to the statement's start). }
function ErrorPosition(const AError, AStatement: string; out ALine, ACol: Integer): Boolean;

implementation

function LineOf(const S: string; AIndex: Integer): string;
var
  L: TStringList;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.Text := S;
    if (AIndex >= 1) and (AIndex <= L.Count) then
    begin
      Result := L[AIndex - 1];
    end;
  finally
    L.Free;
  end;
end;

{ The number after AWord (case-insensitive) in S, from APos on; 0 if none. }
function NumberAfter(const S, AWord: string; out AAt: Integer): Integer;
var
  P, K: Integer;
  Num: string;
begin
  Result := 0;
  AAt := 0;
  P := Pos(LowerCase(AWord), LowerCase(S));
  while P > 0 do
  begin
    K := P + Length(AWord);
    while (K <= Length(S)) and (S[K] = ' ') do
    begin
      Inc(K);
    end;
    Num := '';
    while (K <= Length(S)) and (S[K] in ['0'..'9']) do
    begin
      Num := Num + S[K];
      Inc(K);
    end;
    if Num <> '' then
    begin
      Result := StrToIntDef(Num, 0);
      AAt := P;
      Exit;
    end;
    P := PosEx(LowerCase(AWord), LowerCase(S), P + 1);
  end;
end;

{ The text between the first pair of AQuote after AAfter in S. }
function QuotedAfter(const S, AAfter: string; AQuote: Char): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos(LowerCase(AAfter), LowerCase(S));
  if P = 0 then
  begin
    Exit;
  end;
  P := PosEx(AQuote, S, P + Length(AAfter));
  if P = 0 then
  begin
    Exit;
  end;
  Q := PosEx(AQuote, S, P + 1);
  if Q > P + 1 then
  begin
    Result := Copy(S, P + 1, Q - P - 1);
  end;
end;

function Min(A, B: Integer): Integer;
begin
  if A < B then
  begin
    Result := A;
  end
  else
  begin
    Result := B;
  end;
end;

{ Finds AToken in the statement (on ALine when given, else anywhere); fills
  ALine / ACol. }
function FindToken(const AStatement, AToken: string; var ALine, ACol: Integer): Boolean;
var
  L: TStringList;
  I, P, First, Last: Integer;
  Tok: string;
begin
  Result := False;
  Tok := Trim(AToken);
  if Tok = '' then
  begin
    Exit;
  end;
  // MySQL quotes the rest of the statement from the spot: its first line
  if Pos(#10, Tok) > 0 then
  begin
    Tok := Trim(Copy(Tok, 1, Pos(#10, Tok) - 1));
  end;
  L := TStringList.Create;
  try
    L.Text := AStatement;
    if ALine > 0 then
    begin
      First := ALine;
      Last := ALine;
    end
    else
    begin
      First := 1;
      Last := L.Count;
    end;
    for I := First to Min(Last, L.Count) do
    begin
      P := Pos(LowerCase(Tok), LowerCase(L[I - 1]));
      if P > 0 then
      begin
        ALine := I;
        ACol := P;
        Result := True;
        Exit;
      end;
    end;
  finally
    L.Free;
  end;
end;

function ErrorPosition(const AError, AStatement: string; out ALine, ACol: Integer): Boolean;
var
  L: TStringList;
  I, At, P, Caret, Prefix: Integer;
  Snip, Real, Tok: string;
  Dots: Boolean;
begin
  Result := False;
  ALine := 0;
  ACol := 0;

  // PostgreSQL: "LINE 3: <the line>" then "        ^"
  L := TStringList.Create;
  try
    L.Text := AError;
    for I := 0 to L.Count - 1 do
    begin
      P := Pos('LINE ', L[I]);
      if (P > 0) and (NumberAfter(Copy(L[I], P, MaxInt), 'LINE', At) > 0) then
      begin
        ALine := NumberAfter(Copy(L[I], P, MaxInt), 'LINE', At);
        Prefix := Pos(':', Copy(L[I], P, MaxInt));
        if Prefix = 0 then
        begin
          Break;
        end;
        Prefix := P + Prefix;            // first character after "LINE n:"
        if (Prefix <= Length(L[I])) and (L[I][Prefix] = ' ') then
        begin
          Inc(Prefix);
        end;
        Snip := Copy(L[I], Prefix, MaxInt);
        ACol := 1;
        if (I + 1 < L.Count) and (Pos('^', L[I + 1]) > 0) then
        begin
          Caret := Pos('^', L[I + 1]) - Prefix + 1;   // within the snippet as shown
          // a long line is shown cut, with ... at the front
          Dots := Copy(Snip, 1, 3) = '...';
          if Dots then
          begin
            Snip := Copy(Snip, 4, MaxInt);
            Dec(Caret, 3);
          end;
          if Copy(Snip, Length(Snip) - 2, 3) = '...' then
          begin
            Snip := Copy(Snip, 1, Length(Snip) - 3);
          end;
          Real := LineOf(AStatement, ALine);
          P := Pos(Snip, Real);
          if (P > 0) and (Caret >= 1) then
          begin
            ACol := P + Caret - 1;
          end
          else if Caret >= 1 then
          begin
            ACol := Caret;
          end;
        end;
        Result := True;
        Exit;
      end;
    end;
  finally
    L.Free;
  end;

  // Oracle PL/SQL: "line 3, column 12"
  ALine := NumberAfter(AError, 'line ', At);
  if (ALine > 0) and (Pos('column', LowerCase(Copy(AError, At, 40))) > 0) then
  begin
    ACol := NumberAfter(Copy(AError, At, MaxInt), 'column', P);
    if ACol = 0 then
    begin
      ACol := 1;
    end;
    Result := True;
    Exit;
  end;

  // MySQL: "... near 'xyz' at line 3"
  if Pos('at line', LowerCase(AError)) > 0 then
  begin
    ALine := NumberAfter(AError, 'at line', At);
    Tok := QuotedAfter(AError, 'near ', '''');
    ACol := 1;
    if (ALine > 0) and (Tok <> '') then
    begin
      FindToken(AStatement, Tok, ALine, ACol);
    end;
    Result := ALine > 0;
    Exit;
  end;

  // SQL Server: "Line 3" (when the driver passes it) and "near 'xyz'"
  ALine := NumberAfter(AError, 'Line ', At);
  Tok := QuotedAfter(AError, 'near ', '''');
  if Tok = '' then
  begin
    Tok := QuotedAfter(AError, 'near ', '"');   // PostgreSQL without LINE
  end;
  if Tok = '' then
  begin
    // Oracle: ORA-00904: "X": invalid identifier, and other names in quotes
    // the whole quoted name, "S"."SPRIDEN_NAME": its last part
    P := Pos('ORA-', AError);
    if P > 0 then
    begin
      P := PosEx('"', AError, P);
      if P > 0 then
      begin
        Caret := PosEx('":', AError, P);
        if Caret = 0 then
        begin
          Caret := PosEx('"', AError, P + 1);
        end;
        if Caret > P then
        begin
          Tok := StringReplace(Copy(AError, P, Caret - P + 1), '"', '', [rfReplaceAll]);
          if Pos('.', Tok) > 0 then
          begin
            Tok := Copy(Tok, LastDelimiter('.', Tok) + 1, MaxInt);
          end;
        end;
      end;
    end;
  end;
  if Tok = '' then
  begin
    Tok := QuotedAfter(AError, 'column ', '"');   // PostgreSQL: column "x" does not exist
  end;
  if Tok = '' then
  begin
    Tok := QuotedAfter(AError, 'relation ', '"');
  end;
  if Tok = '' then
  begin
    Tok := QuotedAfter(AError, 'function ', '"');
  end;
  ACol := 1;
  if Tok <> '' then
  begin
    Result := FindToken(AStatement, Tok, ALine, ACol);
    if Result then
    begin
      Exit;
    end;
  end;
  Result := ALine > 0;
end;

end.
