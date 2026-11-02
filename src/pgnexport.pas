// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnExport;

{ Getting rows out of a result grid: the text for Copy As (CSV, INSERT
  statements, IN list, JSON, column names), the Save Results As dialog
  and file, and SSMS's Results to Text layout:

    id          last_name
    ----------- ----------
    1           Smith
    2           NULL

    (2 rows affected)

  Values are text in Pagona's result sets, so INSERT statements and IN
  lists quote every value but NULL; the databases convert '42' into a
  number column on their own. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Math,
  pgnTypes, pgnTheme;

type
  TpgnExportFormat = (efCSV, efTab, efJSON, efInsert);

  { Which cells: rows R1..R2 and columns C1..C2 of the result set (0-based,
    inclusive). }
  TpgnCellRange = record
    R1, R2, C1, C2: Integer;
  end;

  TpgnExportOptions = record
    Format: TpgnExportFormat;
    Header: Boolean;         // CSV, tab: column names first
    NullAsWord: Boolean;     // CSV, tab: NULL written as NULL (else empty)
    Bom: Boolean;
    TableName: string;       // INSERT statements
    FileName: string;
    AllRows: Boolean;        // run the query again with no row limit
  end;

const
  ExportFormatCaptions: array[TpgnExportFormat] of string =
    ('CSV (comma-separated)', 'Tab-delimited', 'JSON', 'INSERT statements');
  ExportFormatExt: array[TpgnExportFormat] of string = ('csv', 'txt', 'json', 'sql');

{ The whole result set as a range. }
function WholeRange(AData: TpgnResultSet): TpgnCellRange;

function CellsAsCSV(AData: TpgnResultSet; const R: TpgnCellRange; ASep: Char;
  AHeader, ANullAsWord: Boolean): string;
function CellsAsJSON(AData: TpgnResultSet; const R: TpgnCellRange): string;
function CellsAsInsert(AData: TpgnResultSet; const R: TpgnCellRange; const ATable: string;
  ADialect: TpgnDialect): string;
{ ('a', 'b', 'c') from column C1 of the range, each value once. }
function CellsAsInList(AData: TpgnResultSet; const R: TpgnCellRange; ADialect: TpgnDialect): string;
function ColumnNames(AData: TpgnResultSet; const R: TpgnCellRange): string;

{ The text a format makes for a range. }
function CellsAs(AData: TpgnResultSet; const R: TpgnCellRange; const AOpt: TpgnExportOptions;
  ADialect: TpgnDialect): string;

{ SSMS's Results to Text: each result set as fixed-width columns. }
function ResultsAsText(AList: TFPList): string;

{ Writes the text to a file, UTF-8, with a byte-order mark if asked. }
procedure WriteTextFile(const AFileName, AText: string; ABom: Boolean);

{ The table a query reads from (the name after its first FROM), for the
  INSERT statements' table name; '' if there isn't one. }
function GuessTableName(const ASQL: string): string;

{ True if the text has a word that changes something (INSERT, UPDATE,
  DELETE, EXEC, CREATE, ...): such a query isn't run a second time. }
function SqlMayChangeData(const ASQL: string): Boolean;

{ The Save Results As dialog. ARowsNote says why "All rows" isn't offered
  ('' = it is). False if canceled. }
function AskExport(AOwner: TComponent; const ATitle: string; AShown: Integer; AMoreRows: Boolean;
  const ARowsNote, ATableGuess, AInitialDir: string; var AOpt: TpgnExportOptions): Boolean;

implementation

function WholeRange(AData: TpgnResultSet): TpgnCellRange;
begin
  Result.R1 := 0;
  Result.C1 := 0;
  Result.R2 := AData.RowCount - 1;
  Result.C2 := AData.ColumnCount - 1;
end;

function CsvField(const S: string; ASep: Char): string;
begin
  if (Pos(ASep, S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) or
    ((S <> '') and ((S[1] = ' ') or (S[Length(S)] = ' '))) then
  begin
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  end
  else
  begin
    Result := S;
  end;
end;

{ Tab-delimited can't quote: tabs and line breaks inside values become spaces. }
function TabField(const S: string): string;
begin
  Result := StringReplace(S, #9, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function CellsAsCSV(AData: TpgnResultSet; const R: TpgnCellRange; ASep: Char;
  AHeader, ANullAsWord: Boolean): string;
var
  SB: TStringList;
  Row, C: Integer;
  Line, V: string;
begin
  SB := TStringList.Create;
  try
    if AHeader then
    begin
      Line := '';
      for C := R.C1 to R.C2 do
      begin
        if C > R.C1 then
        begin
          Line := Line + ASep;
        end;
        if ASep = #9 then
        begin
          Line := Line + TabField(AData.Columns[C]);
        end
        else
        begin
          Line := Line + CsvField(AData.Columns[C], ASep);
        end;
      end;
      SB.Add(Line);
    end;
    for Row := R.R1 to R.R2 do
    begin
      Line := '';
      for C := R.C1 to R.C2 do
      begin
        if C > R.C1 then
        begin
          Line := Line + ASep;
        end;
        if AData.Rows[Row].Nulls[C] then
        begin
          if ANullAsWord then
          begin
            V := 'NULL';
          end
          else
          begin
            V := '';
          end;
        end
        else if ASep = #9 then
        begin
          V := TabField(AData.Rows[Row].Values[C]);
        end
        else
        begin
          V := CsvField(AData.Rows[Row].Values[C], ASep);
        end;
        Line := Line + V;
      end;
      SB.Add(Line);
    end;
    SB.LineBreak := LineEnding;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function JsonString(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    case Ch of
      '"':
        begin
          Result := Result + '\"';
        end;
      '\':
        begin
          Result := Result + '\\';
        end;
      #8:
        begin
          Result := Result + '\b';
        end;
      #9:
        begin
          Result := Result + '\t';
        end;
      #10:
        begin
          Result := Result + '\n';
        end;
      #12:
        begin
          Result := Result + '\f';
        end;
      #13:
        begin
          Result := Result + '\r';
        end;
    else
      begin
        if Ord(Ch) < 32 then
        begin
          Result := Result + '\u' + IntToHex(Ord(Ch), 4);
        end
        else
        begin
          Result := Result + Ch;   // UTF-8 passes through as it is
        end;
      end;
    end;
  end;
  Result := Result + '"';
end;

function CellsAsJSON(AData: TpgnResultSet; const R: TpgnCellRange): string;
var
  SB: TStringList;
  Row, C: Integer;
  Line: string;
begin
  SB := TStringList.Create;
  try
    SB.Add('[');
    for Row := R.R1 to R.R2 do
    begin
      SB.Add('  {');
      for C := R.C1 to R.C2 do
      begin
        Line := '    ' + JsonString(AData.Columns[C]) + ': ';
        if AData.Rows[Row].Nulls[C] then
        begin
          Line := Line + 'null';
        end
        else
        begin
          Line := Line + JsonString(AData.Rows[Row].Values[C]);
        end;
        if C < R.C2 then
        begin
          Line := Line + ',';
        end;
        SB.Add(Line);
      end;
      if Row < R.R2 then
      begin
        SB.Add('  },');
      end
      else
      begin
        SB.Add('  }');
      end;
    end;
    SB.Add(']');
    SB.LineBreak := LineEnding;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function PlainName(const S: string): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and (S[1] in ['A'..'Z', 'a'..'z', '_']);
  if not Result then
  begin
    Exit;
  end;
  for I := 2 to Length(S) do
  begin
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function QuoteName(const S: string; ADialect: TpgnDialect): string;
begin
  if PlainName(S) then
  begin
    Result := S;
  end
  else
  begin
    case ADialect of
      sdMySQL:
        begin
          Result := '`' + StringReplace(S, '`', '``', [rfReplaceAll]) + '`';
        end;
      sdTSQL:
        begin
          Result := '[' + StringReplace(S, ']', ']]', [rfReplaceAll]) + ']';
        end;
    else
      begin
        Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
      end;
    end;
  end;
end;

function HasNonAscii(const S: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
  begin
    if Ord(S[I]) > 127 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function SqlLiteral(const S: string; ADialect: TpgnDialect): string;
begin
  Result := StringReplace(S, '''', '''''', [rfReplaceAll]);
  if ADialect = sdMySQL then
  begin
    Result := StringReplace(Result, '\', '\\', [rfReplaceAll]);
  end;
  Result := '''' + Result + '''';
  if (ADialect = sdTSQL) and HasNonAscii(S) then
  begin
    Result := 'N' + Result;   // nvarchar, so accents survive
  end;
end;

{ A table name as typed stays as typed (it may be schema.table). }
function CellsAsInsert(AData: TpgnResultSet; const R: TpgnCellRange; const ATable: string;
  ADialect: TpgnDialect): string;
var
  SB: TStringList;
  Row, C: Integer;
  Cols, Vals, Table: string;
begin
  Table := Trim(ATable);
  if Table = '' then
  begin
    Table := 'table_name';
  end;
  Cols := '';
  for C := R.C1 to R.C2 do
  begin
    if C > R.C1 then
    begin
      Cols := Cols + ', ';
    end;
    Cols := Cols + QuoteName(AData.Columns[C], ADialect);
  end;
  SB := TStringList.Create;
  try
    for Row := R.R1 to R.R2 do
    begin
      Vals := '';
      for C := R.C1 to R.C2 do
      begin
        if C > R.C1 then
        begin
          Vals := Vals + ', ';
        end;
        if AData.Rows[Row].Nulls[C] then
        begin
          Vals := Vals + 'NULL';
        end
        else
        begin
          Vals := Vals + SqlLiteral(AData.Rows[Row].Values[C], ADialect);
        end;
      end;
      SB.Add('INSERT INTO ' + Table + ' (' + Cols + ') VALUES (' + Vals + ');');
    end;
    SB.LineBreak := LineEnding;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function CellsAsInList(AData: TpgnResultSet; const R: TpgnCellRange; ADialect: TpgnDialect): string;
var
  Seen: TStringList;
  Row: Integer;
  V: string;
begin
  Result := '';
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.CaseSensitive := True;
    Seen.Duplicates := dupIgnore;
    for Row := R.R1 to R.R2 do
    begin
      if AData.Rows[Row].Nulls[R.C1] then
      begin
        Continue;   // NULL never matches IN
      end;
      V := AData.Rows[Row].Values[R.C1];
      if Seen.IndexOf(V) >= 0 then
      begin
        Continue;
      end;
      Seen.Add(V);
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + SqlLiteral(V, ADialect);
    end;
  finally
    Seen.Free;
  end;
  Result := '(' + Result + ')';
end;

function ColumnNames(AData: TpgnResultSet; const R: TpgnCellRange): string;
var
  C: Integer;
begin
  Result := '';
  for C := R.C1 to R.C2 do
  begin
    if C > R.C1 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + AData.Columns[C];
  end;
end;

function CellsAs(AData: TpgnResultSet; const R: TpgnCellRange; const AOpt: TpgnExportOptions;
  ADialect: TpgnDialect): string;
begin
  case AOpt.Format of
    efCSV:
      begin
        Result := CellsAsCSV(AData, R, ',', AOpt.Header, AOpt.NullAsWord);
      end;
    efTab:
      begin
        Result := CellsAsCSV(AData, R, #9, AOpt.Header, AOpt.NullAsWord);
      end;
    efJSON:
      begin
        Result := CellsAsJSON(AData, R);
      end;
  else
    begin
      Result := CellsAsInsert(AData, R, AOpt.TableName, ADialect);
    end;
  end;
end;

{ ------------------------------------------------------ results to text }

function TextLen(const S: string): Integer;
begin
  Result := Length(UTF8Decode(S));
end;

function PadText(const S: string; AWidth: Integer): string;
var
  U: UnicodeString;
begin
  U := UTF8Decode(S);
  if Length(U) > AWidth then
  begin
    U := Copy(U, 1, AWidth);
  end;
  Result := UTF8Encode(U) + StringOfChar(' ', AWidth - Length(U));
end;

const
  MaxTextCol = 256;   // SSMS's default most characters per column

function OneLine(const S: string): string;
begin
  Result := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
end;

function ResultsAsText(AList: TFPList): string;
var
  SB: TStringList;
  K, C, Row: Integer;
  D: TpgnResultSet;
  W: array of Integer;
  Line, V: string;
begin
  SB := TStringList.Create;
  try
    for K := 0 to AList.Count - 1 do
    begin
      D := TpgnResultSet(AList[K]);
      if D.ColumnCount = 0 then
      begin
        Continue;
      end;
      SetLength(W, D.ColumnCount);
      for C := 0 to D.ColumnCount - 1 do
      begin
        W[C] := Max(TextLen(D.Columns[C]), 4);   // room for NULL
        for Row := 0 to D.RowCount - 1 do
        begin
          if not D.Rows[Row].Nulls[C] then
          begin
            W[C] := Max(W[C], TextLen(OneLine(D.Rows[Row].Values[C])));
          end;
        end;
        W[C] := Min(W[C], MaxTextCol);
      end;
      Line := '';
      for C := 0 to D.ColumnCount - 1 do
      begin
        if C > 0 then
        begin
          Line := Line + ' ';
        end;
        Line := Line + PadText(D.Columns[C], W[C]);
      end;
      SB.Add(TrimRight(Line));
      Line := '';
      for C := 0 to D.ColumnCount - 1 do
      begin
        if C > 0 then
        begin
          Line := Line + ' ';
        end;
        Line := Line + StringOfChar('-', W[C]);
      end;
      SB.Add(Line);
      for Row := 0 to D.RowCount - 1 do
      begin
        Line := '';
        for C := 0 to D.ColumnCount - 1 do
        begin
          if C > 0 then
          begin
            Line := Line + ' ';
          end;
          if D.Rows[Row].Nulls[C] then
          begin
            V := 'NULL';
          end
          else
          begin
            V := OneLine(D.Rows[Row].Values[C]);
          end;
          Line := Line + PadText(V, W[C]);
        end;
        SB.Add(TrimRight(Line));
      end;
      SB.Add('');
      if D.HasMoreRows then
      begin
        SB.Add(Format('(first %d rows; the row limit was reached)', [D.RowCount]));
      end
      else if D.RowCount = 1 then
      begin
        SB.Add('(1 row affected)');
      end
      else
      begin
        SB.Add(Format('(%d rows affected)', [D.RowCount]));
      end;
      SB.Add('');
    end;
    SB.LineBreak := LineEnding;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

procedure WriteTextFile(const AFileName, AText: string; ABom: Boolean);
const
  Bom: array[0..2] of Byte = ($EF, $BB, $BF);
var
  F: TFileStream;
begin
  F := TFileStream.Create(AFileName, fmCreate);
  try
    if ABom then
    begin
      F.WriteBuffer(Bom, 3);
    end;
    if AText <> '' then
    begin
      F.WriteBuffer(AText[1], Length(AText));
    end;
  finally
    F.Free;
  end;
end;

{ --------------------------------------------------------- SQL guesses }

{ The SQL with comments and string contents blanked, upper-cased. }
function CodeOnly(const ASQL: string): string;
var
  I, N: Integer;
  State: Char;
begin
  Result := UpperCase(ASQL);
  N := Length(Result);
  State := 'N';
  I := 1;
  while I <= N do
  begin
    case State of
      'N':
        begin
          if Result[I] = '''' then
          begin
            State := 'S';
          end
          else if (Result[I] = '-') and (I < N) and (Result[I + 1] = '-') then
          begin
            State := 'L';
            Result[I] := ' ';
          end
          else if (Result[I] = '/') and (I < N) and (Result[I + 1] = '*') then
          begin
            State := 'C';
            Result[I] := ' ';
          end;
        end;
      'S':
        begin
          if Result[I] = '''' then
          begin
            State := 'N';
          end
          else
          begin
            Result[I] := ' ';
          end;
        end;
      'L':
        begin
          if Result[I] = #10 then
          begin
            State := 'N';
          end
          else
          begin
            Result[I] := ' ';
          end;
        end;
      'C':
        begin
          if (Result[I] = '*') and (I < N) and (Result[I + 1] = '/') then
          begin
            Result[I] := ' ';
            Result[I + 1] := ' ';
            Inc(I);
            State := 'N';
          end
          else
          begin
            Result[I] := ' ';
          end;
        end;
    end;
    Inc(I);
  end;
end;

function IsWordChar(Ch: Char): Boolean;
begin
  Result := Ch in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#', '@'];
end;

{ Position of a whole word in upper-cased code, 0 if none. }
function WordPos(const AWord, ACode: string): Integer;
var
  P, From: Integer;
begin
  Result := 0;
  From := 1;
  repeat
    P := Pos(AWord, Copy(ACode, From, MaxInt));
    if P = 0 then
    begin
      Exit;
    end;
    P := P + From - 1;
    if ((P = 1) or not IsWordChar(ACode[P - 1])) and
      ((P + Length(AWord) > Length(ACode)) or not IsWordChar(ACode[P + Length(AWord)])) then
    begin
      Result := P;
      Exit;
    end;
    From := P + 1;
  until False;
end;

function SqlMayChangeData(const ASQL: string): Boolean;
const
  Words: array[0..17] of string = ('INSERT', 'UPDATE', 'DELETE', 'MERGE', 'REPLACE', 'CALL',
    'EXEC', 'EXECUTE', 'CREATE', 'ALTER', 'DROP', 'TRUNCATE', 'RENAME', 'GRANT', 'REVOKE',
    'BEGIN', 'INTO', 'LOCK');
var
  Code: string;
  I: Integer;
begin
  Code := CodeOnly(ASQL);
  Result := False;
  for I := 0 to High(Words) do
  begin
    if WordPos(Words[I], Code) > 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function GuessTableName(const ASQL: string): string;
var
  Code: string;
  P, Q: Integer;
begin
  Result := '';
  Code := CodeOnly(ASQL);
  P := WordPos('FROM', Code);
  if P = 0 then
  begin
    Exit;
  end;
  P := P + 4;
  while (P <= Length(ASQL)) and (ASQL[P] in [' ', #9, #10, #13]) do
  begin
    Inc(P);
  end;
  if (P > Length(ASQL)) or (ASQL[P] = '(') then
  begin
    Exit;   // a subquery: no single table
  end;
  Q := P;
  while (Q <= Length(ASQL)) and (IsWordChar(ASQL[Q]) or (ASQL[Q] in ['.', '"', '`', '[', ']'])) do
  begin
    Inc(Q);
  end;
  Result := Copy(ASQL, P, Q - P);
end;

{ ------------------------------------------------------------- dialog }

type
  TpgnExportForm = class(TForm)
  public
    CFormat: TComboBox;
    ETable: TEdit;
    LTable: TLabel;
    RShown, RAll: TRadioButton;
    CHeader, CBom: TCheckBox;
    LNull: TLabel;
    CNull: TComboBox;
    EFile: TEdit;
    InitialDir: string;
    Confirmed: string;      // a name the save dialog already asked about
    procedure FormatChange(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
  end;

procedure TpgnExportForm.FormatChange(Sender: TObject);
var
  Fmt: TpgnExportFormat;
  F: string;
begin
  Fmt := TpgnExportFormat(Max(CFormat.ItemIndex, 0));
  ETable.Enabled := Fmt = efInsert;
  LTable.Enabled := ETable.Enabled;
  CHeader.Enabled := Fmt in [efCSV, efTab];
  CNull.Enabled := Fmt in [efCSV, efTab];
  LNull.Enabled := CNull.Enabled;
  // the file's extension follows the format
  F := EFile.Text;
  if F <> '' then
  begin
    EFile.Text := ChangeFileExt(F, '.' + ExportFormatExt[Fmt]);
  end;
end;

procedure TpgnExportForm.BrowseClick(Sender: TObject);
var
  D: TSaveDialog;
  Fmt: TpgnExportFormat;
begin
  Fmt := TpgnExportFormat(Max(CFormat.ItemIndex, 0));
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Save Results As';
    case Fmt of
      efCSV:
        begin
          D.Filter := 'CSV files (*.csv)|*.csv|All files|*';
        end;
      efTab:
        begin
          D.Filter := 'Text files (*.txt;*.tsv)|*.txt;*.tsv|All files|*';
        end;
      efJSON:
        begin
          D.Filter := 'JSON files (*.json)|*.json|All files|*';
        end;
    else
      begin
        D.Filter := 'SQL files (*.sql)|*.sql|All files|*';
      end;
    end;
    D.DefaultExt := ExportFormatExt[Fmt];
    D.Options := D.Options + [ofOverwritePrompt];
    if EFile.Text <> '' then
    begin
      D.InitialDir := ExtractFileDir(EFile.Text);
      D.FileName := ExtractFileName(EFile.Text);
    end
    else
    begin
      D.InitialDir := InitialDir;
    end;
    if D.Execute then
    begin
      EFile.Text := D.FileName;
      Confirmed := D.FileName;
    end;
  finally
    D.Free;
  end;
end;

procedure TpgnExportForm.SaveClick(Sender: TObject);
begin
  if Trim(EFile.Text) = '' then
  begin
    BrowseClick(nil);
    if Trim(EFile.Text) = '' then
    begin
      Exit;
    end;
  end;
  if FileExists(EFile.Text) and (EFile.Text <> Confirmed) and (MessageDlg(EFile.Text + ' already exists. Replace it?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  ModalResult := mrOk;
end;

function AskExport(AOwner: TComponent; const ATitle: string; AShown: Integer; AMoreRows: Boolean;
  const ARowsNote, ATableGuess, AInitialDir: string; var AOpt: TpgnExportOptions): Boolean;
var
  F: TpgnExportForm;
  Y, X, W: Integer;
  Fmt: TpgnExportFormat;
  L, LNote: TLabel;
  BBrowse, BSave, BCancel: TButton;
  Grp: TPanel;
begin
  Result := False;
  F := TpgnExportForm.CreateNew(AOwner);
  SmoothFont(F.Font);
  try
    F.Caption := ATitle;
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := 520;
    F.InitialDir := AInitialDir;
    X := 16;
    W := F.ClientWidth - 2 * X;
    Y := 12;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Caption := 'Format';
    L.SetBounds(X, Y + 4, 110, 20);
    F.CFormat := TComboBox.Create(F);
    F.CFormat.Parent := F;
    F.CFormat.Style := csDropDownList;
    for Fmt := Low(TpgnExportFormat) to High(TpgnExportFormat) do
    begin
      F.CFormat.Items.Add(ExportFormatCaptions[Fmt]);
    end;
    F.CFormat.ItemIndex := Ord(AOpt.Format);
    F.CFormat.SetBounds(X + 120, Y, 240, 28);
    Inc(Y, 36);

    F.LTable := TLabel.Create(F);
    F.LTable.Parent := F;
    F.LTable.Caption := 'Table name';
    F.LTable.SetBounds(X, Y + 4, 110, 20);
    F.ETable := TEdit.Create(F);
    F.ETable.Parent := F;
    F.ETable.Text := ATableGuess;
    F.ETable.SetBounds(X + 120, Y, W - 120, 28);
    F.ETable.Hint := 'The table the INSERT statements go into, as you would type it (schema.table works)';
    F.ETable.ShowHint := True;
    Inc(Y, 40);

    L := TLabel.Create(F);
    L.Parent := F;
    L.Caption := 'Rows';
    L.SetBounds(X, Y + 2, 110, 20);
    // the two choices in a panel of their own, so they're one radio group
    Grp := TPanel.Create(F);
    Grp.Parent := F;
    Grp.BevelOuter := bvNone;
    Grp.Caption := '';
    Grp.SetBounds(X + 120, Y, W - 120, 56);
    F.RShown := TRadioButton.Create(F);
    F.RShown.Parent := Grp;
    if AMoreRows then
    begin
      F.RShown.Caption := Format('The rows shown (%s)', [FormatFloat('#,##0', AShown)]);
    end
    else
    begin
      F.RShown.Caption := Format('All %s rows (every row is shown)', [FormatFloat('#,##0', AShown)]);
    end;
    F.RShown.SetBounds(0, 0, Grp.Width, 24);
    F.RAll := TRadioButton.Create(F);
    F.RAll.Parent := Grp;
    F.RAll.Caption := 'All rows (runs the query again with no row limit)';
    F.RAll.SetBounds(0, 28, Grp.Width, 24);
    F.RAll.Enabled := AMoreRows and (ARowsNote = '');
    if F.RAll.Enabled and AOpt.AllRows then
    begin
      F.RAll.Checked := True;
    end
    else
    begin
      F.RShown.Checked := True;
    end;
    Inc(Y, 58);
    if AMoreRows and (ARowsNote <> '') then
    begin
      LNote := TLabel.Create(F);
      LNote.Parent := F;
      LNote.WordWrap := True;
      LNote.AutoSize := False;
      LNote.Caption := ARowsNote;
      LNote.Font.Color := clPgnMuted;
      LNote.SetBounds(X + 120, Y, W - 120, 36);
      Inc(Y, 40);
    end;

    F.CHeader := TCheckBox.Create(F);
    F.CHeader.Parent := F;
    F.CHeader.Caption := 'Column names in the first row';
    F.CHeader.Checked := AOpt.Header;
    F.CHeader.SetBounds(X + 120, Y, W - 120, 24);
    Inc(Y, 32);

    F.LNull := TLabel.Create(F);
    F.LNull.Parent := F;
    F.LNull.Caption := 'Write NULL as';
    F.LNull.SetBounds(X, Y + 4, 110, 20);
    F.CNull := TComboBox.Create(F);
    F.CNull.Parent := F;
    F.CNull.Style := csDropDownList;
    F.CNull.Items.Add('Nothing (an empty field)');
    F.CNull.Items.Add('The word NULL');
    if AOpt.NullAsWord then
    begin
      F.CNull.ItemIndex := 1;
    end
    else
    begin
      F.CNull.ItemIndex := 0;
    end;
    F.CNull.SetBounds(X + 120, Y, 240, 28);
    Inc(Y, 36);

    F.CBom := TCheckBox.Create(F);
    F.CBom.Parent := F;
    F.CBom.Caption := 'UTF-8 with BOM (so Excel reads accented letters right)';
    F.CBom.Checked := AOpt.Bom;
    F.CBom.SetBounds(X + 120, Y, W - 120, 24);
    Inc(Y, 36);

    L := TLabel.Create(F);
    L.Parent := F;
    L.Caption := 'File';
    L.SetBounds(X, Y + 4, 110, 20);
    F.EFile := TEdit.Create(F);
    F.EFile.Parent := F;
    F.EFile.Text := AOpt.FileName;
    F.EFile.SetBounds(X + 120, Y, W - 120 - 96, 28);
    BBrowse := TButton.Create(F);
    BBrowse.Parent := F;
    BBrowse.Caption := 'Browse...';
    BBrowse.SetBounds(X + W - 88, Y, 88, 28);
    BBrowse.OnClick := @F.BrowseClick;
    Inc(Y, 48);

    BSave := TButton.Create(F);
    BSave.Parent := F;
    BSave.Caption := 'Save';
    BSave.Default := True;
    BSave.SetBounds(F.ClientWidth - X - 188, Y, 90, 30);
    BSave.OnClick := @F.SaveClick;
    BCancel := TButton.Create(F);
    BCancel.Parent := F;
    BCancel.Caption := 'Cancel';
    BCancel.Cancel := True;
    BCancel.ModalResult := mrCancel;
    BCancel.SetBounds(F.ClientWidth - X - 90, Y, 90, 30);
    F.ClientHeight := Y + 44;

    F.CFormat.OnChange := @F.FormatChange;
    F.FormatChange(nil);

    if F.ShowModal = mrOk then
    begin
      AOpt.Format := TpgnExportFormat(Max(F.CFormat.ItemIndex, 0));
      AOpt.TableName := Trim(F.ETable.Text);
      AOpt.AllRows := F.RAll.Checked;
      AOpt.Header := F.CHeader.Checked;
      AOpt.NullAsWord := F.CNull.ItemIndex = 1;
      AOpt.Bom := F.CBom.Checked;
      AOpt.FileName := Trim(F.EFile.Text);
      if ExtractFileExt(AOpt.FileName) = '' then
      begin
        AOpt.FileName := AOpt.FileName + '.' + ExportFormatExt[AOpt.Format];
      end;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

end.
