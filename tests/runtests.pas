// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

program runtests;

{ Runs the test cases for Pagona's text engines: the Oracle/PostgreSQL
  converter, the formatter and statement splitting. No database and no
  window: text in, text out.

  A case is a text file under tests/convert, tests/format or tests/split
  (see tests/README.md):

    --@ test: NVL becomes COALESCE
    --@ rules: default
    SELECT NVL(a, 'N') FROM t
    --@ expect
    SELECT COALESCE(a, 'N') FROM t

    runtests            runs every case; exit code 1 when one fails
    runtests --update   writes what the code does now into each case's
                        expect part (then read the changes before keeping
                        them: git diff tests)

  A case with a "--@ known-issue: what's wrong" line holds the result it
  should give, not today's. It's listed, not failed, until a fix makes it
  pass; then the runner says to take the line out. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, TypInfo, pgnTypes, pgnSqlFormat, pgnSqlSplit, pgnOracleConvert;

const
  Mark = '--@ ';

type
  TCase = record
    FileName: string;
    Title: string;
    Settings: TStringList;   // name=value from the --@ lines before the input
    Input: string;
    Expect: string;
    HasNotes: Boolean;
    Notes: string;
  end;

  { A made-up data dictionary for a case's "columns:" line
    (PEOPLE.PERSONS=ID,NAME; GEO.ADDRESSES=PERSON_REF,CITY), which also
    keeps the names the converter asked for. }
  TFakeDictionary = class
    Tables: TStringList;   // NAME=COL,COL
    Asked: TStringList;
    constructor Create(const ASetting: string);
    destructor Destroy; override;
    function Columns(const ATable: string): TStrings;
  end;

var
  Update: Boolean;
  Passed, Failed, Updated, Known: Integer;

constructor TFakeDictionary.Create(const ASetting: string);
var
  Parts: TStringArray;
  I, P: Integer;
begin
  inherited Create;
  Tables := TStringList.Create;
  Asked := TStringList.Create;
  Parts := ASetting.Split([';'], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to High(Parts) do
  begin
    P := Pos('=', Parts[I]);
    if P > 0 then
    begin
      Tables.Add(UpperCase(Trim(Copy(Parts[I], 1, P - 1))) + '=' +
        UpperCase(StringReplace(Copy(Parts[I], P + 1, MaxInt), ' ', '', [rfReplaceAll])));
    end;
  end;
end;

destructor TFakeDictionary.Destroy;
begin
  Tables.Free;
  Asked.Free;
  inherited Destroy;
end;

function TFakeDictionary.Columns(const ATable: string): TStrings;
var
  K: Integer;
begin
  Result := nil;
  if Asked.IndexOf(ATable) < 0 then
  begin
    Asked.Add(ATable);
  end;
  K := Tables.IndexOfName(UpperCase(ATable));
  if K >= 0 then
  begin
    Result := TStringList.Create;
    Result.CommaText := Tables.ValueFromIndex[K];
  end;
end;

function TrimLines(const S: string): string;
var
  L: TStringList;
  I: Integer;
begin
  // line ends and trailing blanks aside: the same text on every system
  L := TStringList.Create;
  try
    L.Text := S;
    for I := 0 to L.Count - 1 do
    begin
      L[I] := TrimRight(L[I]);
    end;
    while (L.Count > 0) and (L[L.Count - 1] = '') do
    begin
      L.Delete(L.Count - 1);
    end;
    while (L.Count > 0) and (L[0] = '') do
    begin
      L.Delete(0);
    end;
    Result := '';
    for I := 0 to L.Count - 1 do
    begin
      if I > 0 then
      begin
        Result := Result + #10;
      end;
      Result := Result + L[I];
    end;
  finally
    L.Free;
  end;
end;

procedure LoadCase(const AFileName: string; out C: TCase);
var
  L: TStringList;
  I, Part, P: Integer;
  Line, Rest: string;
begin
  C.FileName := AFileName;
  C.Title := ExtractFileName(AFileName);
  C.Settings := TStringList.Create;
  C.Input := '';
  C.Expect := '';
  C.Notes := '';
  C.HasNotes := False;
  Part := 0;   // 0 input, 1 expect, 2 notes
  L := TStringList.Create;
  try
    L.LoadFromFile(AFileName);
    for I := 0 to L.Count - 1 do
    begin
      Line := L[I];
      if Copy(Line, 1, Length(Mark)) = Mark then
      begin
        Rest := Trim(Copy(Line, Length(Mark) + 1, MaxInt));
        if Rest = 'expect' then
        begin
          Part := 1;
        end
        else if Rest = 'notes' then
        begin
          Part := 2;
          C.HasNotes := True;
        end
        else
        begin
          P := Pos(':', Rest);
          if P > 0 then
          begin
            if Trim(Copy(Rest, 1, P - 1)) = 'test' then
            begin
              C.Title := Trim(Copy(Rest, P + 1, MaxInt));
            end
            else
            begin
              C.Settings.Values[Trim(Copy(Rest, 1, P - 1))] := Trim(Copy(Rest, P + 1, MaxInt));
            end;
          end;
        end;
        Continue;
      end;
      case Part of
        0:
          begin
            C.Input := C.Input + Line + #10;
          end;
        1:
          begin
            C.Expect := C.Expect + Line + #10;
          end;
      else
        begin
          C.Notes := C.Notes + Line + #10;
        end;
      end;
    end;
  finally
    L.Free;
  end;
  C.Input := TrimLines(C.Input);
  C.Expect := TrimLines(C.Expect);
  C.Notes := TrimLines(C.Notes);
end;

{ Writes the case back with what the code does now. }
procedure SaveCase(const C: TCase; const AActual, AActualNotes: string);
var
  L, Old: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  Old := TStringList.Create;
  try
    // the lines up to the expect part stay exactly as written
    Old.LoadFromFile(C.FileName);
    for I := 0 to Old.Count - 1 do
    begin
      if (Trim(Old[I]) = Mark + 'expect') or (Trim(Old[I]) = Trim(Mark) + ' expect') then
      begin
        Break;
      end;
      L.Add(Old[I]);
    end;
    while (L.Count > 0) and (Trim(L[L.Count - 1]) = '') do
    begin
      L.Delete(L.Count - 1);
    end;
    L.Add(Mark + 'expect');
    L.Add(AActual);
    if C.HasNotes then
    begin
      L.Add(Mark + 'notes');
      L.Add(AActualNotes);
    end;
    L.LineBreak := #10;
    L.SaveToFile(C.FileName);
  finally
    L.Free;
    Old.Free;
  end;
end;

function DialectOf(const AName: string): TpgnDialect;
begin
  if SameText(AName, 'postgresql') or SameText(AName, 'pg') then
  begin
    Result := sdPostgreSQL;
  end
  else if SameText(AName, 'mysql') then
  begin
    Result := sdMySQL;
  end
  else if SameText(AName, 'sqlserver') or SameText(AName, 'tsql') then
  begin
    Result := sdTSQL;
  end
  else
  begin
    Result := sdOracle;
  end;
end;

{ rules: default | all | none, then +rule and -rule (crNvl, rpDual, cfRowid ...). }
function RulesOf(const AText: string): TpgnConvRules;
var
  Words: TStringArray;
  I, V: Integer;
  W: string;
  R: TpgnConvRule;
begin
  Result := DefaultConvRules;
  Words := AText.Split([' ', ','], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to High(Words) do
  begin
    W := Words[I];
    if SameText(W, 'default') then
    begin
      Result := DefaultConvRules;
    end
    else if SameText(W, 'all') then
    begin
      Result := [Low(TpgnConvRule)..High(TpgnConvRule)];
    end
    else if SameText(W, 'none') then
    begin
      Result := [];
    end
    else if (W[1] = '+') or (W[1] = '-') then
    begin
      V := GetEnumValue(TypeInfo(TpgnConvRule), Copy(W, 2, MaxInt));
      if V < 0 then
      begin
        raise Exception.Create('no rule called ' + Copy(W, 2, MaxInt));
      end;
      R := TpgnConvRule(V);
      if W[1] = '+' then
      begin
        Include(Result, R);
      end
      else
      begin
        Exclude(Result, R);
      end;
    end
    else
    begin
      raise Exception.Create('rules: ' + W + '?');
    end;
  end;
end;

procedure RunConvert(const C: TCase; out AActual, ANotes: string);
var
  J: TpgnConvJob;
  Parts: TStringArray;
  I, P: Integer;
  Dict: TFakeDictionary;
begin
  Dict := nil;
  J := TpgnConvJob.Create;
  try
    J.Rules := RulesOf(C.Settings.Values['rules']);
    // schemas: SALES= ; HR=people   (remove SALES, rename HR)
    Parts := C.Settings.Values['schemas'].Split([';'], TStringSplitOptions.ExcludeEmpty);
    for I := 0 to High(Parts) do
    begin
      // spaces around the = aside; a new name may hold spaces ("Fin Data")
      P := Pos('=', Parts[I]);
      if P > 0 then
      begin
        J.SchemaMap.Add(Trim(Copy(Parts[I], 1, P - 1)) + '=' + Trim(Copy(Parts[I], P + 1, MaxInt)));
      end;
    end;
    Dict := nil;
    if C.Settings.IndexOfName('columns') >= 0 then
    begin
      Dict := TFakeDictionary.Create(C.Settings.Values['columns']);
      J.Columns := @Dict.Columns;
    end;
    AActual := TrimLines(ConvertOracleToAnsi(C.Input, J));
    ANotes := TrimLines(J.Notes.Text);
    if Dict <> nil then
    begin
      ANotes := TrimLines(ANotes + #10 + 'tables looked up: ' + Dict.Asked.CommaText);
    end;
  finally
    Dict.Free;
    J.Free;
  end;
end;

procedure RunFormat(const C: TCase; out AActual, ANotes: string);
var
  O: TpgnFormatOptions;
  Words: TStringArray;
  I, Skipped: Integer;
  W: string;
begin
  O := DefaultFormatOptions;
  // options: lower | astyped | indent2 | tabs | leadingcommas | packed | river | joinindented
  Words := C.Settings.Values['options'].Split([' ', ','], TStringSplitOptions.ExcludeEmpty);
  for I := 0 to High(Words) do
  begin
    W := LowerCase(Words[I]);
    if W = 'lower' then
    begin
      O.KeywordCase := kcLower;
    end
    else if W = 'astyped' then
    begin
      O.KeywordCase := kcAsTyped;
    end
    else if W = 'indent2' then
    begin
      O.IndentSize := 2;
    end
    else if W = 'tabs' then
    begin
      O.UseTabs := True;
    end
    else if W = 'leadingcommas' then
    begin
      O.LeadingCommas := True;
    end
    else if W = 'packed' then
    begin
      O.OneColumnPerLine := False;
    end
    else if W = 'river' then
    begin
      O.River := True;
    end
    else if W = 'joinindented' then
    begin
      O.JoinIndented := True;
    end
    else
    begin
      raise Exception.Create('options: ' + W + '?');
    end;
  end;
  AActual := TrimLines(FormatSql(C.Input, DialectOf(C.Settings.Values['dialect']), O, Skipped));
  ANotes := 'left alone: ' + IntToStr(Skipped);
end;

procedure RunSplit(const C: TCase; out AActual, ANotes: string);
var
  Spans: TpgnStatementSpans;
  I: Integer;
  Piece: string;
begin
  Spans := SplitStatements(C.Input, DialectOf(C.Settings.Values['dialect']));
  AActual := '';
  for I := 0 to High(Spans) do
  begin
    if I > 0 then
    begin
      AActual := AActual + #10 + '--@@ next statement' + #10;
    end;
    Piece := TrimLines(Copy(C.Input, Spans[I].StartPos, Spans[I].EndPos - Spans[I].StartPos + 1));
    if Piece = '' then
    begin
      Piece := '(empty)';   // Pagona skips these when it runs a script
    end;
    AActual := AActual + Piece;
  end;
  ANotes := 'statements: ' + IntToStr(Length(Spans));
end;

procedure ShowDifference(const AExpect, AActual: string);
var
  E, A: TStringList;
  I: Integer;
begin
  E := TStringList.Create;
  A := TStringList.Create;
  try
    E.Text := AExpect;
    A.Text := AActual;
    for I := 0 to Max(E.Count, A.Count) - 1 do
    begin
      if (I >= E.Count) or (I >= A.Count) or (E[I] <> A[I]) then
      begin
        Writeln('      first difference at line ', I + 1, ':');
        if I < E.Count then
        begin
          Writeln('        expected: ', E[I]);
        end
        else
        begin
          Writeln('        expected: (nothing more)');
        end;
        if I < A.Count then
        begin
          Writeln('        got:      ', A[I]);
        end
        else
        begin
          Writeln('        got:      (nothing more)');
        end;
        Break;
      end;
    end;
  finally
    E.Free;
    A.Free;
  end;
end;

procedure RunFile(const AKind, AFileName: string);
var
  C: TCase;
  Actual, Notes: string;
  Ok: Boolean;
begin
  LoadCase(AFileName, C);
  try
    try
      if AKind = 'convert' then
      begin
        RunConvert(C, Actual, Notes);
      end
      else if AKind = 'format' then
      begin
        RunFormat(C, Actual, Notes);
      end
      else
      begin
        RunSplit(C, Actual, Notes);
      end;
    except
      on E: Exception do
      begin
        Inc(Failed);
        Writeln('FAIL  ', AKind, '/', ExtractFileName(AFileName), ': ', C.Title);
        Writeln('      ', E.Message);
        Exit;
      end;
    end;
    Ok := (Actual = C.Expect) and (not C.HasNotes or (Notes = C.Notes));
    // known-issue: the expect part holds what it should give, not what it
    // gives today. Not a failure until it's fixed; then the line comes out.
    if C.Settings.Values['known-issue'] <> '' then
    begin
      if Ok then
      begin
        Inc(Failed);
        Writeln('FIXED ', AKind, '/', ExtractFileName(AFileName), ': ', C.Title);
        Writeln('      it passes now: take the known-issue line out of the case');
      end
      else
      begin
        Inc(Known);
        Writeln('known ', AKind, '/', ExtractFileName(AFileName), ': ', C.Settings.Values['known-issue']);
      end;
      Exit;
    end;
    if Ok then
    begin
      Inc(Passed);
    end
    else if Update then
    begin
      SaveCase(C, Actual, Notes);
      Inc(Updated);
      Writeln('wrote ', AKind, '/', ExtractFileName(AFileName), ': ', C.Title);
    end
    else
    begin
      Inc(Failed);
      Writeln('FAIL  ', AKind, '/', ExtractFileName(AFileName), ': ', C.Title);
      if Actual <> C.Expect then
      begin
        ShowDifference(C.Expect, Actual);
      end
      else
      begin
        Writeln('      the notes differ:');
        ShowDifference(C.Notes, Notes);
      end;
    end;
  finally
    C.Settings.Free;
  end;
end;

procedure RunFolder(const ARoot, AKind: string);
var
  Files: TStringList;
  SR: TSearchRec;
  I: Integer;
begin
  Files := TStringList.Create;
  try
    if FindFirst(ARoot + AKind + DirectorySeparator + '*.sql', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(ARoot + AKind + DirectorySeparator + SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    Files.Sort;
    for I := 0 to Files.Count - 1 do
    begin
      RunFile(AKind, Files[I]);
    end;
  finally
    Files.Free;
  end;
end;

var
  Root: string;
  I: Integer;
begin
  Update := False;
  Root := ExtractFilePath(ParamStr(0));
  for I := 1 to ParamCount do
  begin
    if ParamStr(I) = '--update' then
    begin
      Update := True;
    end
    else
    begin
      Root := IncludeTrailingPathDelimiter(ParamStr(I));
    end;
  end;
  RunFolder(Root, 'convert');
  RunFolder(Root, 'format');
  RunFolder(Root, 'split');
  Writeln;
  if Update then
  begin
    Writeln(Passed, ' unchanged, ', Updated, ' written. Read the changes (git diff tests) before keeping them.');
  end
  else
  begin
    Write(Passed, ' passed, ', Failed, ' failed');
    if Known > 0 then
    begin
      Write(', ', Known, ' known issue(s)');
    end;
    Writeln('.');
  end;
  if Failed > 0 then
  begin
    Halt(1);
  end;
end.
