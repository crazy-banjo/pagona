// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnConvertWin;

{ The Oracle/PostgreSQL Compatibility window:

    [rules found]  | Before          | After (converted and formatted)
    ------------------------------------------------------------------
    What was done (log)
    [Export HTML...] [Export CSV...]
    Oracle (from): [connection v] PROD   PostgreSQL (to): [connection v] TEST   [Run Both and Compare]
    SAME: 5 rows from each, the same rows.
    [Oracle grid, first 100 rows]   |   [PostgreSQL grid, first 100 rows]
    [Copy] [Save As...]                                              [Close]

  Ticks start fresh each time and re-make the After side. Run Both and
  Compare runs the original on Oracle and the converted SQL on PostgreSQL
  (SELECT only) and compares the rows, ignoring their order and leveling
  what the two engines show differently (numbers by value, dates and times
  in one form, empty text as NULL, trailing spaces). A row with no match on
  the other side is marked ≠. Without an Oracle connection the converted
  SQL still runs on PostgreSQL. The editor is never changed: Copy, or Save
  As a new file (never over the file the tab has open). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs, Math, LCLType, StrUtils, Clipbrd,
  SynEdit, SynHighlighterSQL, pgnTypes, pgnAdapter, pgnQueryThread, pgnTheme, pgnSqlSplit, pgnResultGrid,
  pgnOracleConvert, pgnConvertReport, pgnSqlFormat, pgnFormatProfiles, pgnFormatDlg;

type
  { Converts the reviewed SQL as AJob says: the text to show (formatted). }
  TpgnConvertFunc = function(AJob: TpgnConvJob): string of object;

  TpgnBusyFunc = function: Boolean of object;

  { Sets the format profile the converted SQL is laid out with. }
  TpgnSetFormatProc = procedure(const AOpt: TpgnFormatOptions) of object;

  { A connection the compare can run on. }
  TpgnCompareTarget = record
    Caption: string;
    Env: TpgnEnvironment;
    Adapter: TpgnAdapter;
    IsBusy: TpgnBusyFunc;   // its tab is running a query (nil: never)
  end;
  TpgnCompareTargets = array of TpgnCompareTarget;

  TpgnReviewSetup = record
    Before: string;
    Source: string;              // 'the selection' / 'the editor', for the report
    OrigFile: string;            // the file the tab has open ('' = none): never saved over
    Convert: TpgnConvertFunc;
    FromTargets: TpgnCompareTargets;   // Oracle sessions (the original runs there)
    ToTargets: TpgnCompareTargets;     // PostgreSQL sessions (the converted SQL runs there)
    DefaultFrom, DefaultTo: Integer;
    LookupFrom: string;          // where functions are looked up ('' = nowhere)
    RowLimit, FontSize: Integer;
    Theme: string;
    Profiles: TpgnFormatProfiles;   // the format profiles, as in the Format window
    ProfileIndex: Integer;          // the one used last (the window starts on it)
    SetFormat: TpgnSetFormatProc;   // nil: no Format drop-down
  end;

{ Shows the window. ASaved: the file the converted SQL was saved to ('' if
  it wasn't). }
procedure ReviewConversion(AOwner: TComponent; const ASetup: TpgnReviewSetup; out ASaved, ASummary: string);

implementation

const
  ShownRows = 100;
  RemoveName = 'Remove the name';
  SchemaWhy = 'Without its schema name PostgreSQL finds a table or function through search_path, so it ' +
    'could read a different one. Tick to remove the name, or pick or type a PostgreSQL schema to put in its ' +
    'place. Packages and PL/SQL blocks are left alone.';

type
  TConvertWindow = class(TForm)
  private
    FSetup: TpgnReviewSetup;
    FJob: TpgnConvJob;
    FBeforeText, FAfterText, FSummaryText, FSaved: string;
    FChecks: array[TpgnConvRule] of TCheckBox;
    FSchemaChecks: array of TCheckBox;
    FSchemaNames: TStringList;
    // schema names to remove or rename: a box and a drop-down per schema
    FNameChecks: array of TCheckBox;
    FNameCombos: array of TComboBox;
    FNameList: TStringList;
    FFormatCombo: TComboBox;
    // the PostgreSQL (to) connection's schemas and search_path, read once per connection
    FToInfoFor: Integer;
    FToSchemas, FToPath: TpgnStringArray;
    FToWhyNot: string;
    FFillingNames: Boolean;   // the drop-downs are being refilled: not a pick
    FSummary: TLabel;
    FFromCombo, FToCombo: TComboBox;
    FFromBadge, FToBadge: TLabel;
    FBefore, FAfter: TSynEdit;
    FHlBefore, FHlAfter: TSynSQLSyn;
    FNotes: TMemo;
    FCompare, FCompareAll, FStop: TButton;
    FResult: TLabel;
    FGridA, FGridB: TpgnResultGrid;
    FGridALabel, FGridBLabel: TLabel;
    FGridsP, FGridAP: TPanel;
    FGridShare: Double;   // the Oracle grid's share of the width
    FCopyBtn, FSaveBtn, FCloseBtn: TButton;
    FRowLimit: Integer;
    FRunBefore, FRunAfter: string;   // the two statements compared (no ; or /)
    FLimitUsed: Integer;
    FRunning: Boolean;
    FPhase: Integer;
    FFromAdapter, FToAdapter: TpgnAdapter;
    FResA, FResB: TpgnResultSet;
    FErr: string;
    procedure GridsResize(Sender: TObject);
    procedure GridSplitMoved(Sender: TObject);
    procedure CompareClick(Sender: TObject);
    procedure CompareAllClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure StartRun(ALimit: Integer);
    procedure RunDone(Sender: TObject);
    procedure ShowComparison;
    procedure SetRunning(AValue: Boolean);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure Recompute;
    procedure RuleClick(Sender: TObject);
    procedure ConnChange(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ExportHtmlClick(Sender: TObject);
    procedure ExportCsvClick(Sender: TObject);
    procedure SaveReport(const AText, AExt, AFilter: string);
    procedure ShowBadges;
    procedure CompareState;
    function FromTarget: Integer;
    function ToTarget: Integer;
    procedure BuildRules(AParent: TWinControl; AFound: TpgnConvJob);
    function MakeEditor(AParent: TWinControl; const ACaption: string; out AHl: TSynSQLSyn;
      AFontSize: Integer; const ATheme: string; out AHead: TPanel): TSynEdit;
    procedure FormatChange(Sender: TObject);
    procedure NameSelected(Sender: TObject);
    procedure NameEdited(Sender: TObject);
    procedure NameChanged(Sender: TObject);
    procedure ReadToInfo;
    procedure FillNameCombos;
    function NameTarget(AIndex: Integer): string;
    procedure AddSchemaChecks(ALines: TStrings);
  public
    destructor Destroy; override;
  end;

destructor TConvertWindow.Destroy;
begin
  FResA.Free;
  FResB.Free;
  FJob.Free;
  FSchemaNames.Free;
  FNameList.Free;
  inherited Destroy;
end;

function TConvertWindow.MakeEditor(AParent: TWinControl; const ACaption: string; out AHl: TSynSQLSyn;
  AFontSize: Integer; const ATheme: string; out AHead: TPanel): TSynEdit;
var
  L: TLabel;
begin
  // the caption, on a strip that can take more (the Format drop-down)
  AHead := TPanel.Create(Self);
  AHead.Parent := AParent;
  AHead.Align := alTop;
  AHead.BevelOuter := bvNone;
  AHead.Caption := '';
  AHead.Height := Scale96ToScreen(30);
  L := TLabel.Create(Self);
  L.Parent := AHead;
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  L.Font.Style := [fsBold];
  L.BorderSpacing.Left := Scale96ToScreen(4);
  L.BorderSpacing.Right := Scale96ToScreen(8);
  AHl := TSynSQLSyn.Create(Self);
  AHl.SQLDialect := sqlOracle;
  ApplyEditorTheme(AHl, ATheme);
  Result := TSynEdit.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.Highlighter := AHl;
  Result.ReadOnly := True;
  Result.RightEdge := -1;
  {$IFDEF WINDOWS}
  Result.Font.Name := 'Consolas';
  {$ELSE}
  Result.Font.Name := 'Monospace';
  {$ENDIF}
  Result.Font.Size := AFontSize;
  SmoothFont(Result.Font);
  Result.Color := clPgnWork;
  Result.Gutter.Color := TColor($00FAF8F7);
end;

function TConvertWindow.FromTarget: Integer;
begin
  Result := -1;
  if (FFromCombo <> nil) and (FFromCombo.ItemIndex >= 0) and (FFromCombo.ItemIndex <= High(FSetup.FromTargets)) then
  begin
    Result := FFromCombo.ItemIndex;
  end;
end;

function TConvertWindow.ToTarget: Integer;
begin
  Result := -1;
  if (FToCombo <> nil) and (FToCombo.ItemIndex >= 0) and (FToCombo.ItemIndex <= High(FSetup.ToTargets)) then
  begin
    Result := FToCombo.ItemIndex;
  end;
end;

procedure TConvertWindow.SetRunning(AValue: Boolean);
begin
  FRunning := AValue;
  FCompare.Enabled := not AValue;
  FCompareAll.Enabled := not AValue;
  FStop.Visible := AValue;
  FCloseBtn.Enabled := not AValue;
  FFromCombo.Enabled := not AValue and (Length(FSetup.FromTargets) > 0);
  FToCombo.Enabled := not AValue and (Length(FSetup.ToTargets) > 0);
  if AValue then
  begin
    Screen.Cursor := crHourGlass;
  end
  else
  begin
    Screen.Cursor := crDefault;
    CompareState;
  end;
end;

procedure TConvertWindow.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // the queries report back to this window: it stays until they're done
  CanClose := not FRunning;
end;

procedure TConvertWindow.CompareClick(Sender: TObject);
begin
  StartRun(FRowLimit);
end;

procedure TConvertWindow.CompareAllClick(Sender: TObject);
begin
  StartRun(0);
end;

procedure TConvertWindow.StopClick(Sender: TObject);
begin
  try
    if FPhase = 1 then
    begin
      FFromAdapter.CancelCurrent;
    end
    else
    begin
      FToAdapter.CancelCurrent;
    end;
  except
    on E: Exception do
    begin
      // it stops when it stops
    end;
  end;
end;

function ConfirmProduction(const T: TpgnCompareTarget): Boolean;
begin
  // a tab's session can't take a second query while its own runs
  if Assigned(T.IsBusy) and T.IsBusy() then
  begin
    MessageDlg('Run Both and Compare', T.Caption + ' is running a query. Wait for it to finish (or stop it), ' +
      'then run again.', mtInformation, [mbOK], 0);
    Result := False;
    Exit;
  end;
  Result := True;
  if T.Env = enProduction then
  begin
    Result := QuestionDlg('Run on production', 'Run on ' + T.Caption + '?' + LineEnding +
      'It''s a production connection. The query only reads (SELECT), but it does run there.', mtWarning,
      [mrYes, 'Run on Production', mrNo, 'Don''t Run', 'IsDefault'], 0) = mrYes;
  end;
end;

procedure TConvertWindow.StartRun(ALimit: Integer);
var
  Stmts: TpgnStringArray;
begin
  if ToTarget < 0 then
  begin
    Exit;
  end;
  FFromAdapter := nil;
  if FromTarget >= 0 then
  begin
    if not ConfirmProduction(FSetup.FromTargets[FromTarget]) then
    begin
      Exit;
    end;
    FFromAdapter := FSetup.FromTargets[FromTarget].Adapter;
  end;
  if not ConfirmProduction(FSetup.ToTargets[ToTarget]) then
  begin
    Exit;
  end;
  FToAdapter := FSetup.ToTargets[ToTarget].Adapter;
  FreeAndNil(FResA);
  FreeAndNil(FResB);
  FGridA.ShowData(nil);
  FGridB.ShowData(nil);
  FErr := '';
  FLimitUsed := ALimit;
  SetRunning(True);
  SetLength(Stmts, 1);
  if FFromAdapter <> nil then
  begin
    FPhase := 1;
    FResult.Caption := 'Running the original on Oracle...';
    Stmts[0] := FRunBefore;
    TpgnQueryThread.Create(FFromAdapter, Stmts, ALimit, @RunDone).Start;
  end
  else
  begin
    FPhase := 2;
    FResult.Caption := 'Running the converted SQL on PostgreSQL...';
    Stmts[0] := FRunAfter;
    TpgnQueryThread.Create(FToAdapter, Stmts, ALimit, @RunDone).Start;
  end;
end;

procedure TConvertWindow.RunDone(Sender: TObject);
var
  T: TpgnQueryThread;
  L: TFPList;
  I: Integer;
  R: TpgnResultSet;
  Stmts: TpgnStringArray;
begin
  T := Sender as TpgnQueryThread;
  R := nil;
  L := T.TakeResults;
  try
    for I := 0 to L.Count - 1 do
    begin
      if (R = nil) and TpgnResultSet(L[I]).ReturnsRows then
      begin
        R := TpgnResultSet(L[I]);
      end
      else
      begin
        TpgnResultSet(L[I]).Free;
      end;
    end;
  finally
    L.Free;
  end;
  if T.ErrorText <> '' then
  begin
    R.Free;
    if FPhase = 1 then
    begin
      FErr := 'The original failed on Oracle: ' + T.ErrorText;
    end
    else
    begin
      FErr := 'The converted SQL failed on PostgreSQL: ' + T.ErrorText;
    end;
    SetRunning(False);
    ShowComparison;
    Exit;
  end;
  if T.Stopped then
  begin
    R.Free;
    FErr := 'Stopped.';
    SetRunning(False);
    ShowComparison;
    Exit;
  end;
  if FPhase = 1 then
  begin
    FResA := R;
    FPhase := 2;
    FResult.Caption := 'Running the converted SQL on PostgreSQL...';
    SetLength(Stmts, 1);
    Stmts[0] := FRunAfter;
    TpgnQueryThread.Create(FToAdapter, Stmts, FLimitUsed, @RunDone).Start;
    Exit;
  end;
  FResB := R;
  SetRunning(False);
  ShowComparison;
end;

var
  DotFormat: TFormatSettings;

{ A value as the comparison sees it: what the two engines show differently
  made the same. NULL and empty text are one (Oracle can't store ''). }
function Level(const V: string; AIsNull: Boolean): string;
var
  X: Double;
  S, D, T: string;
  K: Integer;
begin
  S := TrimRight(V);
  if AIsNull or (S = '') then
  begin
    Result := #0'NULL';
    Exit;
  end;
  // numbers by value: 1.5 = 1.50, -0 = 0
  if TryStrToFloat(Trim(S), X, DotFormat) and (Pos(' ', Trim(S)) = 0) then
  begin
    if X = 0 then
    begin
      X := 0;
    end;
    Result := FloatToStrF(X, ffGeneral, 15, 0, DotFormat);
    Exit;
  end;
  // dates and times: YYYY-MM-DD[ HH:MM:SS[.fff]] with midnight and zero fractions dropped
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    D := Copy(S, 1, 10);
    T := '';
    if (Length(S) > 11) and (S[11] in [' ', 'T']) then
    begin
      T := Copy(S, 12, MaxInt);
      // a time zone or fraction: keep digits, drop trailing zeros of the fraction
      K := Pos('.', T);
      if K > 0 then
      begin
        while (Length(T) > K) and (T[Length(T)] = '0') do
        begin
          Delete(T, Length(T), 1);
        end;
        if T[Length(T)] = '.' then
        begin
          Delete(T, Length(T), 1);
        end;
      end;
      if T = '00:00:00' then
      begin
        T := '';
      end;
    end;
    if T <> '' then
    begin
      Result := D + ' ' + T;
    end
    else
    begin
      Result := D;
    end;
    Exit;
  end;
  Result := S;
end;

function RowKey(R: TpgnResultSet; ARow: Integer): string;
var
  C: Integer;
begin
  Result := '';
  for C := 0 to High(R.Rows[ARow].Values) do
  begin
    if C > 0 then
    begin
      Result := Result + #9;
    end;
    Result := Result + Level(R.Rows[ARow].Values[C], (C <= High(R.Rows[ARow].Nulls)) and R.Rows[ARow].Nulls[C]);
  end;
end;

{ Which of A's rows have no match in B (each B row matches once). }
function Unmatched(A, B: TpgnResultSet): TpgnBoolArray;
var
  Counts: TStringList;
  I, K: Integer;
  Key: string;
begin
  Result := nil;
  SetLength(Result, A.RowCount);
  Counts := TStringList.Create;
  try
    Counts.Sorted := True;
    Counts.CaseSensitive := True;
    Counts.Duplicates := dupIgnore;
    if B <> nil then
    begin
      for I := 0 to B.RowCount - 1 do
      begin
        Key := RowKey(B, I);
        K := Counts.IndexOf(Key);
        if K < 0 then
        begin
          K := Counts.AddObject(Key, TObject(PtrInt(0)));
        end;
        Counts.Objects[K] := TObject(PtrInt(Counts.Objects[K]) + 1);
      end;
    end;
    for I := 0 to A.RowCount - 1 do
    begin
      K := Counts.IndexOf(RowKey(A, I));
      if (K >= 0) and (PtrInt(Counts.Objects[K]) > 0) then
      begin
        Counts.Objects[K] := TObject(PtrInt(Counts.Objects[K]) - 1);
        Result[I] := False;
      end
      else
      begin
        Result[I] := True;
      end;
    end;
  finally
    Counts.Free;
  end;
end;

{ The first rows of R, with a ≠ column in front for rows without a match. }
function ShownSet(R: TpgnResultSet; const AMarks: TpgnBoolArray): TpgnResultSet;
var
  I, C, N: Integer;
begin
  Result := TpgnResultSet.Create;
  Result.ReturnsRows := True;
  SetLength(Result.Columns, R.ColumnCount + 1);
  Result.Columns[0] := #$E2#$89#$A0;   // ≠
  for C := 0 to R.ColumnCount - 1 do
  begin
    Result.Columns[C + 1] := R.Columns[C];
  end;
  N := Min(R.RowCount, ShownRows);
  SetLength(Result.Rows, N);
  for I := 0 to N - 1 do
  begin
    SetLength(Result.Rows[I].Values, R.ColumnCount + 1);
    SetLength(Result.Rows[I].Nulls, R.ColumnCount + 1);
    if (I <= High(AMarks)) and AMarks[I] then
    begin
      Result.Rows[I].Values[0] := #$E2#$89#$A0;
    end
    else
    begin
      Result.Rows[I].Values[0] := '';
    end;
    Result.Rows[I].Nulls[0] := False;
    for C := 0 to R.ColumnCount - 1 do
    begin
      Result.Rows[I].Values[C + 1] := R.Rows[I].Values[C];
      Result.Rows[I].Nulls[C + 1] := (C <= High(R.Rows[I].Nulls)) and R.Rows[I].Nulls[C];
    end;
  end;
end;

procedure TConvertWindow.ShowComparison;
var
  MA, MB: TpgnBoolArray;
  OnlyA, OnlyB, I: Integer;
  Msg, Limited, Of100: string;
  Partial: Boolean;
begin
  FCompareAll.Visible := False;
  if FResA <> nil then
  begin
    MB := Unmatched(FResB, FResA);
  end;
  if FResB <> nil then
  begin
    if FResA <> nil then
    begin
      MA := Unmatched(FResA, FResB);
    end;
  end;
  if FResA <> nil then
  begin
    FGridA.ShowData(ShownSet(FResA, MA));
  end;
  if FResB <> nil then
  begin
    FGridB.ShowData(ShownSet(FResB, MB));
  end;
  FResult.Hint := '';
  if FErr <> '' then
  begin
    // the first line; the whole message (PostgreSQL's LINE and ^) on hover
    FResult.Caption := Trim(Copy(FErr + LineEnding, 1, Pos(#10, FErr + #10) - 1));
    FResult.Hint := FErr;
    FResult.ShowHint := True;
    Exit;
  end;
  if FResB = nil then
  begin
    FResult.Caption := 'The converted SQL returned no rows to show.';
    Exit;
  end;
  Of100 := '';
  if (FResB.RowCount > ShownRows) or ((FResA <> nil) and (FResA.RowCount > ShownRows)) then
  begin
    Of100 := ' The grids show the first ' + IntToStr(ShownRows) + ' rows of each.';
  end;
  if FResA = nil then
  begin
    FResult.Caption := 'PostgreSQL: ' + FormatFloat('#,##0', FResB.RowCount) + ' rows. No Oracle connection, so ' +
      'there''s nothing to compare with.' + Of100;
    Exit;
  end;
  OnlyA := 0;
  OnlyB := 0;
  for I := 0 to High(MA) do
  begin
    if MA[I] then
    begin
      Inc(OnlyA);
    end;
  end;
  for I := 0 to High(MB) do
  begin
    if MB[I] then
    begin
      Inc(OnlyB);
    end;
  end;
  Partial := (FLimitUsed > 0) and (FResA.HasMoreRows or FResB.HasMoreRows or
    (FResA.RowCount >= FLimitUsed) or (FResB.RowCount >= FLimitUsed));
  Limited := '';
  if Partial then
  begin
    Limited := ' (the first ' + FormatFloat('#,##0', FLimitUsed) + ' rows of each: the row limit)';
    FCompareAll.Visible := True;
  end;
  if FResA.ColumnCount <> FResB.ColumnCount then
  begin
    Msg := 'Different: Oracle returns ' + IntToStr(FResA.ColumnCount) + ' columns, PostgreSQL ' +
      IntToStr(FResB.ColumnCount) + '.';
  end
  else if (OnlyA = 0) and (OnlyB = 0) then
  begin
    Msg := 'Same rows: ' + FormatFloat('#,##0', FResA.RowCount) + ' from each' + Limited + '.';
  end
  else
  begin
    Msg := 'Different: ' + FormatFloat('#,##0', OnlyA) + ' row(s) only in Oracle, ' + FormatFloat('#,##0', OnlyB) +
      ' only in PostgreSQL, marked ' + #$E2#$89#$A0 + ' (Oracle ' + FormatFloat('#,##0', FResA.RowCount) +
      ' rows, PostgreSQL ' + FormatFloat('#,##0', FResB.RowCount) + ')' + Limited + '.';
    if Partial then
    begin
      Msg := Msg + ' With a row limit the first rows can simply be different ones: Compare All Rows.';
    end;
  end;
  FResult.Caption := Msg + Of100 + ' Order is ignored; numbers, dates and empty text are compared by meaning.';
end;

procedure TConvertWindow.BuildRules(AParent: TWinControl; AFound: TpgnConvJob);
var
  Box: TScrollBox;
  G: TpgnConvGroup;
  R: TpgnConvRule;
  Y, M, K, N: Integer;
  L: TLabel;
  Any: Boolean;
  Info: TpgnRuleInfo;
  Defaults: TpgnConvRules;
  Sch: TStringList;
  C: TCheckBox;
  Cb: TComboBox;
  Cap: string;
const
  Heads: array[TpgnConvGroup] of string = ('Same meaning, runs on both', 'Could change what a query returns',
    'PostgreSQL only (won''t run on Oracle 19c)', 'Notes only: TODO PG comments');

  procedure Head(const ACaption: string);
  begin
    L := TLabel.Create(Self);
    L.Parent := Box;
    L.Caption := ACaption;
    L.Font.Style := [fsBold];
    L.SetBounds(M, Y, Scale96ToScreen(330), L.Height);
    Inc(Y, Scale96ToScreen(22));
  end;

  function Check(const ACaption, AHint: string; AChecked: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := Box;
    Result.Caption := ACaption;
    Result.Hint := AHint;
    Result.ShowHint := AHint <> '';
    Result.Checked := AChecked;
    Result.SetBounds(M, Y, Scale96ToScreen(340), Result.Height);
    Result.OnClick := @RuleClick;
    Inc(Y, Scale96ToScreen(26));
  end;

begin
  Defaults := DefaultConvRules;
  Box := TScrollBox.Create(Self);
  Box.Parent := AParent;
  Box.Align := alClient;
  Box.BorderStyle := bsNone;
  Box.HorzScrollBar.Visible := False;
  M := Scale96ToScreen(8);
  Y := M;
  FSchemaNames := TStringList.Create;
  FNameList := TStringList.Create;
  for G := Low(TpgnConvGroup) to High(TpgnConvGroup) do
  begin
    Any := False;
    for R := Low(TpgnConvRule) to High(TpgnConvRule) do
    begin
      Info := RuleInfo(R);
      if (Info.Group <> G) or (AFound.Counts[R] = 0) or (R = cfFunctions) then
      begin
        Continue;
      end;
      if not Any then
      begin
        Head(Heads[G]);
        Any := True;
      end;
      FChecks[R] := Check(Info.Caption + '  (' + IntToStr(AFound.Counts[R]) + ')', Info.Why, R in Defaults);
    end;
    // stored functions: one box per schema, with the notes
    if (G = cgFlag) and (Length(AFound.Funcs) > 0) then
    begin
      if not Any then
      begin
        Head(Heads[G]);
        Any := True;
      end;
      Sch := AFound.SchemaCalls;
      try
        for K := 0 to Sch.Count - 1 do
        begin
          if Sch[K] = '' then
          begin
            Cap := 'Mark functions, schema unknown';
          end
          else
          begin
            Cap := 'Mark ' + Sch[K] + ' functions';
          end;
          N := PtrInt(Sch.Objects[K]);
          C := Check(Cap + '  (' + IntToStr(N) + ' call(s))', RuleInfo(cfFunctions).Why, True);
          SetLength(FSchemaChecks, Length(FSchemaChecks) + 1);
          FSchemaChecks[High(FSchemaChecks)] := C;
          FSchemaNames.Add(Sch[K]);
        end;
      finally
        Sch.Free;
      end;
    end;
    if Any then
    begin
      Inc(Y, Scale96ToScreen(8));
    end;
    // schema names: after the other rules that could change what a query returns
    if (G = cgChanges) and (Length(AFound.Schemas) > 0) then
    begin
      Head('Schema names (could change what a query returns)');
      for K := 0 to High(AFound.Schemas) do
      begin
        C := Check(AFound.Schemas[K].Name + '.  (' + SchemaCountText(AFound.Schemas[K]) + ')', SchemaWhy, False);
        Cb := TComboBox.Create(Self);
        Cb.Parent := Box;
        Cb.Style := csDropDown;
        Cb.Items.Add(RemoveName);
        Cb.ItemIndex := 0;
        Cb.Hint := 'Remove the name, or pick or type the PostgreSQL schema to use instead';
        Cb.ShowHint := True;
        Cb.SetBounds(M + Scale96ToScreen(22), Y - Scale96ToScreen(2), Scale96ToScreen(250), Cb.Height);
        Cb.OnSelect := @NameSelected;
        Cb.OnChange := @NameChanged;
        Cb.OnEditingDone := @NameEdited;
        Inc(Y, Cb.Height + Scale96ToScreen(6));
        SetLength(FNameChecks, Length(FNameChecks) + 1);
        FNameChecks[High(FNameChecks)] := C;
        SetLength(FNameCombos, Length(FNameCombos) + 1);
        FNameCombos[High(FNameCombos)] := Cb;
        FNameList.Add(AFound.Schemas[K].Name);
      end;
      Inc(Y, Scale96ToScreen(8));
    end;
  end;
  if Y = M then
  begin
    L := TLabel.Create(Self);
    L.Parent := Box;
    L.Caption := 'Nothing Oracle-only found.';
    L.SetBounds(M, Y, Scale96ToScreen(300), L.Height);
  end;
end;

procedure TConvertWindow.RuleClick(Sender: TObject);
begin
  if not FRunning then
  begin
    Recompute;
  end;
end;

procedure TConvertWindow.FormatChange(Sender: TObject);
var
  K: Integer;
begin
  K := FFormatCombo.ItemIndex;
  if (K < 0) or (K > High(FSetup.Profiles)) or not Assigned(FSetup.SetFormat) then
  begin
    Exit;
  end;
  FSetup.SetFormat(FSetup.Profiles[K].Opt);
  if not FRunning then
  begin
    Recompute;
  end;
end;

{ Picking from a schema's drop-down ticks its box (which converts again). }
procedure TConvertWindow.NameSelected(Sender: TObject);
var
  I: Integer;
begin
  if FFillingNames then
  begin
    Exit;
  end;
  for I := 0 to High(FNameCombos) do
  begin
    if FNameCombos[I] = Sender then
    begin
      if not FNameChecks[I].Checked then
      begin
        FNameChecks[I].Checked := True;   // its OnClick converts again
      end
      else if not FRunning then
      begin
        Recompute;
      end;
    end;
  end;
end;

{ GTK doesn't always say Select for a pick from the list: a change to one
  of the list's items counts as a pick (typing waits for Enter or leaving). }
procedure TConvertWindow.NameChanged(Sender: TObject);
begin
  if not FFillingNames and ((Sender as TComboBox).Items.IndexOf((Sender as TComboBox).Text) >= 0) then
  begin
    NameSelected(Sender);
  end;
end;

{ A name typed in: used when the box is ticked. }
procedure TConvertWindow.NameEdited(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FNameCombos) do
  begin
    if (FNameCombos[I] = Sender) and FNameChecks[I].Checked and not FRunning then
    begin
      Recompute;
    end;
  end;
end;

{ Reads the PostgreSQL (to) connection's schemas and search_path, once per
  connection picked (not while its tab runs a query). }
procedure TConvertWindow.ReadToInfo;
var
  K: Integer;
  Tg: TpgnCompareTarget;
begin
  K := ToTarget;
  if K = FToInfoFor then
  begin
    Exit;
  end;
  FToInfoFor := K;
  FToSchemas := nil;
  FToPath := nil;
  FToWhyNot := '';
  if K < 0 then
  begin
    FToWhyNot := 'no PostgreSQL connection to check them on';
    Exit;
  end;
  Tg := FSetup.ToTargets[K];
  if Assigned(Tg.IsBusy) and Tg.IsBusy() then
  begin
    FToWhyNot := Tg.Caption + ' is running a query, so it wasn''t checked';
    FToInfoFor := -2;   // asked again next time
    Exit;
  end;
  try
    FToSchemas := Tg.Adapter.ListSchemas(False);
    FToPath := Tg.Adapter.SearchPath;
  except
    on E: Exception do
    begin
      FToWhyNot := 'couldn''t check ' + Tg.Caption + ': ' + E.Message;
    end;
  end;
end;

{ Each schema's drop-down: Remove, then the PostgreSQL connection's schemas
  (what was typed stays). }
procedure TConvertWindow.FillNameCombos;
var
  I, K: Integer;
  Txt: string;
begin
  if Length(FNameCombos) = 0 then
  begin
    Exit;
  end;
  ReadToInfo;
  FFillingNames := True;
  try
    for I := 0 to High(FNameCombos) do
    begin
      Txt := FNameCombos[I].Text;
      FNameCombos[I].Items.BeginUpdate;
      try
        FNameCombos[I].Items.Clear;
        FNameCombos[I].Items.Add(RemoveName);
        for K := 0 to High(FToSchemas) do
        begin
          FNameCombos[I].Items.Add(FToSchemas[K]);
        end;
      finally
        FNameCombos[I].Items.EndUpdate;
      end;
      FNameCombos[I].Text := Txt;
    end;
  finally
    FFillingNames := False;
  end;
end;

function FindName(const AList: TpgnStringArray; const AName: string): Integer;
var
  K: Integer;
begin
  // an exact match first (PostgreSQL names are case-sensitive), then any case
  for K := 0 to High(AList) do
  begin
    if AList[K] = AName then
    begin
      Result := K;
      Exit;
    end;
  end;
  for K := 0 to High(AList) do
  begin
    if SameText(AList[K], AName) then
    begin
      Result := K;
      Exit;
    end;
  end;
  Result := -1;
end;

{ What a ticked schema becomes: '' removes it; a name typed in a different
  case from a schema on the connection takes the connection's spelling. }
function TConvertWindow.NameTarget(AIndex: Integer): string;
var
  K: Integer;
begin
  Result := Trim(FNameCombos[AIndex].Text);
  if (Result = '') or SameText(Result, RemoveName) then
  begin
    Result := '';
    Exit;
  end;
  K := FindName(FToSchemas, Result);
  if K >= 0 then
  begin
    Result := FToSchemas[K];
  end;
end;

{ For each schema removed or renamed: what the PostgreSQL connection has. }
procedure TConvertWindow.AddSchemaChecks(ALines: TStrings);
var
  I, K, P: Integer;
  Nm, Tgt, Cap, Path, Line: string;
  Any: Boolean;
begin
  Any := False;
  for I := 0 to High(FNameChecks) do
  begin
    if not FNameChecks[I].Checked then
    begin
      Continue;
    end;
    if not Any then
    begin
      ReadToInfo;
      if FToWhyNot <> '' then
      begin
        ALines.Add('Schema names: ' + FToWhyNot + '.');
        Exit;
      end;
      Cap := FSetup.ToTargets[ToTarget].Caption;
      ALines.Add('Schema names, checked on ' + Cap + ':');
      Path := '';
      for K := 0 to High(FToPath) do
      begin
        if Path <> '' then
        begin
          Path := Path + ', ';
        end;
        Path := Path + FToPath[K];
      end;
      if Path = '' then
      begin
        Path := 'empty';
      end;
      Any := True;
    end;
    Nm := FNameList[I];
    Tgt := NameTarget(I);
    if Tgt = '' then
    begin
      K := FindName(FToSchemas, Nm);
      Line := '  ' + Nm + ' removed: ';
      if K < 0 then
      begin
        Line := Line + 'there''s no ' + LowerCase(Nm) + ' schema there, so the names are looked up in ' +
          'its search_path (' + Path + ').';
      end
      else
      begin
        P := FindName(FToPath, FToSchemas[K]);
        if P < 0 then
        begin
          Line := Line + FToSchemas[K] + ' is there but not in its search_path, so the names would be ' +
            'looked up in ' + Path + ' instead. Keep the name, or add ' + FToSchemas[K] + ' to search_path.';
        end
        else if P = 0 then
        begin
          Line := Line + FToSchemas[K] + ' is there and first in its search_path (' + Path + '), so ' +
            'PostgreSQL finds the names there.';
        end
        else
        begin
          Line := Line + FToSchemas[K] + ' is there and in its search_path (' + Path + '), but a table or ' +
            'function of the same name earlier in the path would be used first.';
        end;
      end;
    end
    else
    begin
      Line := '  ' + Nm + ' changed to ' + SchemaPrefixText(Tgt) + ': ';
      if FindName(FToSchemas, Tgt) >= 0 then
      begin
        Line := Line + 'there''s a ' + Tgt + ' schema there.';
      end
      else
      begin
        Line := Line + 'there''s no ' + Tgt + ' schema there.';
      end;
    end;
    ALines.Add(Line);
  end;
end;

procedure SetBadge(ABadge: TLabel; const ATargets: TpgnCompareTargets; AIndex: Integer);
var
  E: TpgnEnvironment;
  Look: TpgnEnvLook;
begin
  if (AIndex < 0) or (AIndex > High(ATargets)) then
  begin
    ABadge.Visible := False;
    Exit;
  end;
  E := ATargets[AIndex].Env;
  // the word, not only the color
  ABadge.Visible := E <> enNone;
  Look := EnvironmentLook(E);
  ABadge.Caption := ' ' + EnvironmentShort[E] + ' ';
  ABadge.Color := Look.Back;
  ABadge.Font.Color := Look.Text;
end;

procedure TConvertWindow.ShowBadges;
begin
  SetBadge(FFromBadge, FSetup.FromTargets, FromTarget);
  SetBadge(FToBadge, FSetup.ToTargets, ToTarget);
end;

procedure TConvertWindow.ConnChange(Sender: TObject);
var
  I: Integer;
begin
  ShowBadges;
  FCompareAll.Visible := False;
  FillNameCombos;
  // the schema checks are against the PostgreSQL connection: say them again
  for I := 0 to High(FNameChecks) do
  begin
    if FNameChecks[I].Checked and not FRunning then
    begin
      Recompute;
      Exit;
    end;
  end;
  CompareState;
end;

{ What Run Both and Compare can run now, and why not when it can't. }
procedure TConvertWindow.CompareState;
var
  Why: string;
  Before, After: TpgnStringArray;
begin
  Why := '';
  FRunBefore := '';
  FRunAfter := '';
  if ToTarget < 0 then
  begin
    Why := 'choose a PostgreSQL connection to test on (connect a tab, or one in the Explorer, to PostgreSQL).';
  end
  else
  begin
    Before := StatementList(FBeforeText, sdOracle);
    After := StatementList(FAfterText, sdOracle);
    if (Length(Before) <> 1) or (Length(After) <> 1) then
    begin
      Why := 'it compares one query at a time: select a single SELECT statement and convert that.';
    end
    else if not StatementOnlyReads(Before[0]) or not StatementOnlyReads(After[0]) or
      (FirstKeyword(Before[0]) <> 'SELECT') then
    begin
      Why := 'only a SELECT is run.';
    end
    else
    begin
      FRunBefore := Before[0];
      FRunAfter := After[0];
    end;
  end;
  FCompare.Enabled := (Why = '') and not FRunning;
  if FRunning then
  begin
    Exit;
  end;
  if Why <> '' then
  begin
    FResult.Caption := 'Run Both and Compare isn''t available: ' + Why;
  end
  else if FromTarget < 0 then
  begin
    FResult.Caption := 'Runs the converted SQL on PostgreSQL (no Oracle connection open, so the original ' +
      'isn''t run). SELECT only; the first ' + IntToStr(ShownRows) + ' rows are shown.';
  end
  else
  begin
    FResult.Caption := 'Runs the original on Oracle and the converted SQL on PostgreSQL (SELECT only) and ' +
      'compares the rows, ignoring their order. Respects the row limit (' + FormatFloat('#,##0', FRowLimit) +
      '); the first ' + IntToStr(ShownRows) + ' rows of each are shown.';
  end;
end;

{ Converts with the ticked rules and refreshes everything that depends on
  the result: the After side, notes, summary, what Compare runs. }
procedure TConvertWindow.Recompute;
var
  R: TpgnConvRule;
  Lines: TStringList;
  Changes, Marks, PgOnly, I: Integer;
  F: TpgnConvFunc;
begin
  FJob.Rules := [cfFunctions];
  for R := Low(TpgnConvRule) to High(TpgnConvRule) do
  begin
    if (FChecks[R] <> nil) and FChecks[R].Checked then
    begin
      Include(FJob.Rules, R);
    end;
  end;
  FJob.SkipSchemas.Clear;
  for I := 0 to High(FSchemaChecks) do
  begin
    if not FSchemaChecks[I].Checked then
    begin
      FJob.SkipSchemas.Add(FSchemaNames[I]);
    end;
  end;
  FJob.SchemaMap.Clear;
  for I := 0 to High(FNameChecks) do
  begin
    if FNameChecks[I].Checked then
    begin
      FJob.SchemaMap.Add(FNameList[I] + '=' + NameTarget(I));
    end;
  end;
  Screen.Cursor := crHourGlass;
  try
    FAfterText := FSetup.Convert(FJob);
  finally
    Screen.Cursor := crDefault;
  end;
  // what the PostgreSQL connection has, in the log and the report
  AddSchemaChecks(FJob.Notes);
  Changes := FJob.AppliedIn(cgSame) + FJob.AppliedIn(cgChanges) + FJob.SchemaChanges;
  PgOnly := FJob.AppliedIn(cgPgOnly);
  Marks := FJob.AppliedIn(cgFlag);
  Lines := TStringList.Create;
  try
    Lines.AddStrings(FJob.Notes);
    if Lines.Count = 0 then
    begin
      Lines.Add('Nothing changed: tick a rule on the left.');
    end;
    if Length(FJob.Funcs) > 0 then
    begin
      Lines.Add('');
      if FSetup.LookupFrom <> '' then
      begin
        Lines.Add('Stored functions (from ' + FSetup.LookupFrom + '; data dictionary only, never source code):');
      end
      else
      begin
        Lines.Add('Stored functions (no Oracle connection: not looked up):');
      end;
      for I := 0 to High(FJob.Funcs) do
      begin
        F := FJob.Funcs[I];
        if F.Info.Found then
        begin
          Lines.Add('  ' + F.Name + ' (' + IntToStr(F.Calls) + ' call(s)): ' + LowerCase(F.Info.Kind) +
            IfThen(F.Info.PackageName <> '', ' in package ' + F.Info.Owner + '.' + F.Info.PackageName, ' in ' +
            F.Info.Owner) + IfThen(F.Info.ReturnType <> '', ', returns ' + F.Info.ReturnType, '') + '; (' +
            F.Info.Params + ')' + IfThen(F.Info.Overloads > 1, '; ' + IntToStr(F.Info.Overloads) + ' versions', '') +
            '; ' + F.Info.Status + ', changed ' + F.Info.LastChanged + '; reads ' + F.Info.Reads +
            IfThen(F.Info.Note <> '', '. ' + F.Info.Note, ''));
        end
        else
        begin
          Lines.Add('  ' + F.Name + ' (' + IntToStr(F.Calls) + ' call(s))' +
            IfThen(F.Info.Note <> '', ': ' + F.Info.Note, ''));
        end;
      end;
    end;
    FNotes.Lines.Assign(Lines);
  finally
    Lines.Free;
  end;
  FAfter.Text := FAfterText;
  FSummaryText := IntToStr(Changes) + ' change(s), ' + IntToStr(Marks) + ' marked TODO PG';
  if PgOnly > 0 then
  begin
    FSummaryText := FSummaryText + ', ' + IntToStr(PgOnly) + ' PostgreSQL only';
  end;
  FSummary.Caption := FSummaryText + ' (search for "TODO PG" to find them). Ticks apply to this SQL only. ' +
    'Your editor isn''t changed: Copy or Save As takes the result.';
  FCompareAll.Visible := False;
  CompareState;
end;

{ The two grids keep their share of the width as the window changes size. }
procedure TConvertWindow.GridsResize(Sender: TObject);
begin
  if FGridShare <= 0 then
  begin
    FGridShare := 0.5;
  end;
  FGridAP.Width := Max(Scale96ToScreen(80), Round((FGridsP.ClientWidth - Scale96ToScreen(24)) * FGridShare));
end;

procedure TConvertWindow.GridSplitMoved(Sender: TObject);
begin
  if FGridsP.ClientWidth > 0 then
  begin
    FGridShare := FGridAP.Width / Max(1, FGridsP.ClientWidth - Scale96ToScreen(24));
  end;
end;

procedure TConvertWindow.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := FAfterText;
  FSummary.Caption := 'Copied the converted SQL. ' + FSummaryText + '.';
end;

{ Always a new file: the tab's own file is never written over. }
procedure TConvertWindow.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
  L: TStringList;
  Target: string;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Save the Converted SQL As';
    D.Filter := 'SQL files (*.sql)|*.sql|All files|*';
    D.DefaultExt := 'sql';
    D.Options := D.Options + [ofOverwritePrompt];
    if FSetup.OrigFile <> '' then
    begin
      D.InitialDir := ExtractFileDir(FSetup.OrigFile);
      D.FileName := ChangeFileExt(ExtractFileName(FSetup.OrigFile), '') + '_pg.sql';
    end
    else
    begin
      D.FileName := 'converted_pg.sql';
    end;
    repeat
      if not D.Execute then
      begin
        Exit;
      end;
      Target := D.FileName;
      if (FSetup.OrigFile <> '') and SameText(ExpandFileName(Target), ExpandFileName(FSetup.OrigFile)) then
      begin
        MessageDlg('Save As', 'That''s the original file. Pagona never saves over it: choose another name.',
          mtInformation, [mbOK], 0);
        Target := '';
      end;
    until Target <> '';
    L := TStringList.Create;
    try
      L.Text := FAfterText;
      L.WriteBOM := False;
      L.SaveToFile(Target, TEncoding.UTF8);
    finally
      L.Free;
    end;
    FSaved := Target;
    FSummary.Caption := 'Saved to ' + Target + '. ' + FSummaryText + '.';
  finally
    D.Free;
  end;
end;

procedure TConvertWindow.SaveReport(const AText, AExt, AFilter: string);
var
  D: TSaveDialog;
  L: TStringList;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Export Report';
    D.Filter := AFilter;
    D.DefaultExt := AExt;
    D.FileName := 'oracle-postgresql-compatibility.' + AExt;
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then
    begin
      Exit;
    end;
    L := TStringList.Create;
    try
      L.Text := AText;
      L.WriteBOM := False;
      L.SaveToFile(D.FileName, TEncoding.UTF8);
    finally
      L.Free;
    end;
  finally
    D.Free;
  end;
end;

function ReportInfoOf(F: TConvertWindow): TpgnReportInfo;
begin
  Result.Source := F.FSetup.Source;
  Result.Connection := F.FSetup.LookupFrom;
  Result.Converted := F.FAfterText;
end;

procedure TConvertWindow.ExportHtmlClick(Sender: TObject);
begin
  SaveReport(ConvertReportHtml(FJob, ReportInfoOf(Self)), 'html', 'Web page (*.html)|*.html|All files|*');
end;

procedure TConvertWindow.ExportCsvClick(Sender: TObject);
begin
  SaveReport(ConvertReportCsv(FJob, ReportInfoOf(Self)), 'csv', 'CSV (*.csv)|*.csv|All files|*');
end;

procedure ReviewConversion(AOwner: TComponent; const ASetup: TpgnReviewSetup; out ASaved, ASummary: string);
var
  F: TConvertWindow;
  Top, Mid, LeftP, RightP, Bottom, CmpP, NotesP, ExportP, GridsP, GA, GB, Host, RulesP, HeadP: TPanel;
  Split, HostSplit, GridSplit: TSplitter;
  NotesL, RulesL, L, FmtL: TLabel;
  M, I, X, BH, CmpH, NotesH, ExportH, GridsH: Integer;
  Found: TpgnConvJob;
  B: TButton;

  function Combo(AParent: TWinControl; AX, AW: Integer; const ATargets: TpgnCompareTargets; ADefault: Integer;
    const ANone: string): TComboBox;
  var
    K: Integer;
  begin
    Result := TComboBox.Create(F);
    Result.Parent := AParent;
    Result.Style := csDropDownList;
    for K := 0 to High(ATargets) do
    begin
      Result.Items.Add(ATargets[K].Caption);
    end;
    Result.SetBounds(AX, F.Scale96ToScreen(6), AW, Result.Height);
    Result.Constraints.MinWidth := AW;
    Result.OnChange := @F.ConnChange;
    if Length(ATargets) = 0 then
    begin
      Result.Items.Add(ANone);
      Result.ItemIndex := 0;
      Result.Enabled := False;
    end
    else
    begin
      Result.ItemIndex := Max(0, Min(ADefault, High(ATargets)));
    end;
  end;

  function Badge(AParent: TWinControl; AX: Integer): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := AParent;
    Result.AutoSize := True;
    Result.Transparent := False;
    Result.Font.Style := [fsBold];
    Result.Left := AX;
    Result.Top := F.Scale96ToScreen(12);
  end;

  function GridSide(AParent: TWinControl; const ACaption: string; out ALabel: TLabel): TpgnResultGrid;
  begin
    ALabel := TLabel.Create(F);
    ALabel.Parent := AParent;
    ALabel.Align := alTop;
    ALabel.Caption := ACaption;
    ALabel.Font.Style := [fsBold];
    ALabel.BorderSpacing.Around := F.Scale96ToScreen(3);
    Result := TpgnResultGrid.Create(F);
    Result.Parent := AParent;
    Result.Align := alClient;
    Result.Dialect := sdOracle;
  end;

begin
  ASaved := '';
  ASummary := '';
  F := TConvertWindow.CreateNew(AOwner);
  try
    SmoothFont(F.Font);
    F.Caption := 'Oracle/PostgreSQL Compatibility: makes Oracle SQL that also runs on PostgreSQL';
    F.FSetup := ASetup;
    F.FBeforeText := ASetup.Before;
    F.FJob := TpgnConvJob.Create;
    F.Position := poOwnerFormCenter;
    F.Width := F.Scale96ToScreen(1320);
    F.Height := Min(F.Scale96ToScreen(960), Screen.WorkAreaHeight - F.Scale96ToScreen(20));
    F.Color := clPgnSurface;
    F.OnCloseQuery := @F.FormCloseQuery;
    F.FRowLimit := ASetup.RowLimit;
    M := F.Scale96ToScreen(8);

    Top := TPanel.Create(F);
    Top.Parent := F;
    Top.Align := alTop;
    Top.BevelOuter := bvNone;
    Top.Caption := '';
    Top.Height := F.Scale96ToScreen(40);
    F.FSummary := TLabel.Create(F);
    F.FSummary.Parent := Top;
    F.FSummary.Align := alClient;
    F.FSummary.Layout := tlCenter;
    F.FSummary.BorderSpacing.Left := M;
    F.FSummary.WordWrap := True;

    // the lower half, laid out by hand: notes, export, connections and
    // result line, the two grids, the buttons
    NotesH := F.Scale96ToScreen(110);
    ExportH := F.Scale96ToScreen(38);
    CmpH := F.Scale96ToScreen(84);
    GridsH := F.Scale96ToScreen(230);
    BH := F.Scale96ToScreen(46);
    Host := TPanel.Create(F);
    Host.Parent := F;
    Host.Align := alBottom;
    Host.BevelOuter := bvNone;
    Host.Caption := '';
    Host.Height := NotesH + ExportH + CmpH + GridsH + BH;
    Host.Constraints.MinHeight := NotesH + ExportH + CmpH + F.Scale96ToScreen(120) + BH;
    HostSplit := TSplitter.Create(F);
    HostSplit.Parent := F;
    HostSplit.Align := alBottom;
    HostSplit.Top := 0;

    NotesP := TPanel.Create(F);
    NotesP.Parent := Host;
    NotesP.BevelOuter := bvNone;
    NotesP.Caption := '';
    NotesP.SetBounds(0, 0, Host.ClientWidth, NotesH);
    NotesP.Anchors := [akLeft, akTop, akRight];
    NotesL := TLabel.Create(F);
    NotesL.Parent := NotesP;
    NotesL.Align := alTop;
    NotesL.Caption := 'What was done';
    NotesL.Font.Style := [fsBold];
    NotesL.BorderSpacing.Around := F.Scale96ToScreen(4);
    F.FNotes := TMemo.Create(F);
    F.FNotes.Parent := NotesP;
    F.FNotes.Align := alClient;
    F.FNotes.ReadOnly := True;
    F.FNotes.ScrollBars := ssAutoBoth;
    F.FNotes.WordWrap := False;
    F.FNotes.BorderSpacing.Left := M;
    F.FNotes.BorderSpacing.Right := M;

    // export, right under the log
    ExportP := TPanel.Create(F);
    ExportP.Parent := Host;
    ExportP.BevelOuter := bvNone;
    ExportP.Caption := '';
    ExportP.SetBounds(0, NotesH, Host.ClientWidth, ExportH);
    ExportP.Anchors := [akLeft, akTop, akRight];
    B := TButton.Create(F);
    B.Parent := ExportP;
    B.Caption := 'Export HTML...';
    B.Hint := 'One web page to read, print or send: what was done, every TODO PG, the functions called';
    B.ShowHint := True;
    B.SetBounds(M, F.Scale96ToScreen(5), F.Scale96ToScreen(130), F.Scale96ToScreen(28));
    B.OnClick := @F.ExportHtmlClick;
    B := TButton.Create(F);
    B.Parent := ExportP;
    B.Caption := 'Export CSV...';
    B.Hint := 'One row per finding, for a spreadsheet';
    B.ShowHint := True;
    B.SetBounds(M + F.Scale96ToScreen(138), F.Scale96ToScreen(5), F.Scale96ToScreen(130), F.Scale96ToScreen(28));
    B.OnClick := @F.ExportCsvClick;

    // the connections, Run Both and Compare, and what it found
    CmpP := TPanel.Create(F);
    CmpP.Parent := Host;
    CmpP.BevelOuter := bvNone;
    CmpP.Caption := '';
    CmpP.SetBounds(0, NotesH + ExportH, Host.ClientWidth, CmpH);
    CmpP.Anchors := [akLeft, akTop, akRight];
    X := M;
    L := TLabel.Create(F);
    L.Parent := CmpP;
    L.Caption := 'Oracle (from):';
    L.SetBounds(X, F.Scale96ToScreen(12), F.Scale96ToScreen(90), L.Height);
    Inc(X, F.Scale96ToScreen(94));
    F.FFromCombo := Combo(CmpP, X, F.Scale96ToScreen(300), ASetup.FromTargets, ASetup.DefaultFrom,
      '(no Oracle connection open)');
    Inc(X, F.Scale96ToScreen(306));
    F.FFromBadge := Badge(CmpP, X);
    Inc(X, F.Scale96ToScreen(56));
    L := TLabel.Create(F);
    L.Parent := CmpP;
    L.Caption := 'PostgreSQL (to):';
    L.SetBounds(X, F.Scale96ToScreen(12), F.Scale96ToScreen(104), L.Height);
    Inc(X, F.Scale96ToScreen(108));
    F.FToCombo := Combo(CmpP, X, F.Scale96ToScreen(300), ASetup.ToTargets, ASetup.DefaultTo,
      '(no PostgreSQL connection open)');
    Inc(X, F.Scale96ToScreen(306));
    F.FToBadge := Badge(CmpP, X);
    Inc(X, F.Scale96ToScreen(56));
    F.FCompare := TButton.Create(F);
    F.FCompare.Parent := CmpP;
    F.FCompare.Caption := 'Run Both and Compare';
    F.FCompare.SetBounds(X, F.Scale96ToScreen(4), F.Scale96ToScreen(170), F.Scale96ToScreen(28));
    F.FCompare.OnClick := @F.CompareClick;
    F.FCompareAll := TButton.Create(F);
    F.FCompareAll.Parent := CmpP;
    F.FCompareAll.Caption := 'Compare All Rows';
    F.FCompareAll.SetBounds(X + F.Scale96ToScreen(176), F.Scale96ToScreen(4), F.Scale96ToScreen(140),
      F.Scale96ToScreen(28));
    F.FCompareAll.OnClick := @F.CompareAllClick;
    F.FCompareAll.Visible := False;
    F.FStop := TButton.Create(F);
    F.FStop.Parent := CmpP;
    F.FStop.Caption := 'Stop';
    F.FStop.SetBounds(X + F.Scale96ToScreen(176), F.Scale96ToScreen(4), F.Scale96ToScreen(80), F.Scale96ToScreen(28));
    F.FStop.OnClick := @F.StopClick;
    F.FStop.Visible := False;
    F.FResult := TLabel.Create(F);
    F.FResult.Parent := CmpP;
    F.FResult.AutoSize := False;
    F.FResult.WordWrap := True;
    F.FResult.Anchors := [akLeft, akTop, akRight];
    F.FResult.SetBounds(M, F.Scale96ToScreen(40), CmpP.ClientWidth - 2 * M, CmpH - F.Scale96ToScreen(42));

    // the two results, side by side
    GridsP := TPanel.Create(F);
    GridsP.Parent := Host;
    GridsP.BevelOuter := bvNone;
    GridsP.Caption := '';
    GridsP.SetBounds(0, NotesH + ExportH + CmpH, Host.ClientWidth, GridsH);
    GridsP.Anchors := [akLeft, akTop, akRight, akBottom];
    GA := TPanel.Create(F);
    GA.Parent := GridsP;
    GA.Align := alLeft;
    GA.Width := Host.ClientWidth div 2;
    GA.BevelOuter := bvNone;
    GA.Caption := '';
    GA.BorderSpacing.Left := M;
    GridSplit := TSplitter.Create(F);
    GridSplit.Parent := GridsP;
    GridSplit.Align := alLeft;
    GridSplit.Left := GA.Width + M + 1;
    GridSplit.OnMoved := @F.GridSplitMoved;
    F.FGridsP := GridsP;
    F.FGridAP := GA;
    F.FGridShare := 0.5;
    GridsP.OnResize := @F.GridsResize;
    GB := TPanel.Create(F);
    GB.Parent := GridsP;
    GB.Align := alClient;
    GB.BevelOuter := bvNone;
    GB.Caption := '';
    GB.BorderSpacing.Right := M;
    F.FGridA := GridSide(GA, 'Oracle: the original (first ' + IntToStr(ShownRows) + ' rows)', F.FGridALabel);
    F.FGridB := GridSide(GB, 'PostgreSQL: the converted SQL (first ' + IntToStr(ShownRows) + ' rows)', F.FGridBLabel);

    Bottom := TPanel.Create(F);
    Bottom.Parent := Host;
    Bottom.BevelOuter := bvNone;
    Bottom.Caption := '';
    Bottom.SetBounds(0, NotesH + ExportH + CmpH + GridsH, Host.ClientWidth, BH);
    Bottom.Anchors := [akLeft, akRight, akBottom];
    F.FCopyBtn := TButton.Create(F);
    F.FCopyBtn.Parent := Bottom;
    F.FCopyBtn.Caption := 'Copy';
    F.FCopyBtn.Hint := 'Copies the converted SQL';
    F.FCopyBtn.ShowHint := True;
    F.FCopyBtn.SetBounds(M, F.Scale96ToScreen(9), F.Scale96ToScreen(100), F.Scale96ToScreen(28));
    F.FCopyBtn.OnClick := @F.CopyClick;
    F.FSaveBtn := TButton.Create(F);
    F.FSaveBtn.Parent := Bottom;
    F.FSaveBtn.Caption := 'Save As...';
    F.FSaveBtn.Hint := 'Saves the converted SQL to a new file (never over the original)';
    F.FSaveBtn.ShowHint := True;
    F.FSaveBtn.SetBounds(M + F.Scale96ToScreen(108), F.Scale96ToScreen(9), F.Scale96ToScreen(110),
      F.Scale96ToScreen(28));
    F.FSaveBtn.OnClick := @F.SaveAsClick;
    F.FCloseBtn := TButton.Create(F);
    F.FCloseBtn.Parent := Bottom;
    F.FCloseBtn.Caption := 'Close';
    F.FCloseBtn.ModalResult := mrClose;
    F.FCloseBtn.Cancel := True;
    F.FCloseBtn.Anchors := [akTop, akRight];
    F.FCloseBtn.SetBounds(Bottom.ClientWidth - F.Scale96ToScreen(100) - M, F.Scale96ToScreen(9),
      F.Scale96ToScreen(100), F.Scale96ToScreen(28));

    // the rules found, on the left
    RulesP := TPanel.Create(F);
    RulesP.Parent := F;
    RulesP.Align := alLeft;
    RulesP.Width := F.Scale96ToScreen(370);
    RulesP.BevelOuter := bvNone;
    RulesP.Caption := '';
    RulesL := TLabel.Create(F);
    RulesL.Parent := RulesP;
    RulesL.Align := alTop;
    RulesL.Caption := 'Rules found in this SQL';
    RulesL.Font.Style := [fsBold];
    RulesL.BorderSpacing.Around := F.Scale96ToScreen(4);
    // what each rule finds, with every rule on
    Found := TpgnConvJob.Create;
    try
      Found.Rules := [Low(TpgnConvRule)..High(TpgnConvRule)];
      ASetup.Convert(Found);
      F.BuildRules(RulesP, Found);
    finally
      Found.Free;
    end;

    // before | after
    Mid := TPanel.Create(F);
    Mid.Parent := F;
    Mid.Align := alClient;
    Mid.BevelOuter := bvNone;
    Mid.Caption := '';
    LeftP := TPanel.Create(F);
    LeftP.Parent := Mid;
    LeftP.Align := alLeft;
    LeftP.Width := F.Scale96ToScreen(460);
    LeftP.BevelOuter := bvNone;
    LeftP.Caption := '';
    Split := TSplitter.Create(F);
    Split.Parent := Mid;
    Split.Align := alLeft;
    Split.Left := LeftP.Width + 1;
    RightP := TPanel.Create(F);
    RightP.Parent := Mid;
    RightP.Align := alClient;
    RightP.BevelOuter := bvNone;
    RightP.Caption := '';
    F.FBefore := F.MakeEditor(LeftP, 'Before', F.FHlBefore, ASetup.FontSize, ASetup.Theme, HeadP);
    F.FAfter := F.MakeEditor(RightP, 'After (converted and formatted)', F.FHlAfter,
      ASetup.FontSize, ASetup.Theme, HeadP);
    F.FAfter.ReadOnly := True;
    // the format profile After is laid out with: the same list as the Format window
    if Assigned(ASetup.SetFormat) and (Length(ASetup.Profiles) > 0) then
    begin
      FmtL := TLabel.Create(F);
      FmtL.Parent := HeadP;
      FmtL.Align := alLeft;
      FmtL.Layout := tlCenter;
      FmtL.Caption := 'Format:';
      FmtL.Left := F.Scale96ToScreen(2000);   // after the caption
      FmtL.BorderSpacing.Right := F.Scale96ToScreen(4);
      F.FFormatCombo := TComboBox.Create(F);
      F.FFormatCombo.Parent := HeadP;
      F.FFormatCombo.Style := csDropDownList;
      for I := 0 to High(ASetup.Profiles) do
      begin
        F.FFormatCombo.Items.Add(ProfileCaption(ASetup.Profiles[I]));
      end;
      F.FFormatCombo.ItemIndex := Max(0, Min(ASetup.ProfileIndex, High(ASetup.Profiles)));
      F.FFormatCombo.Hint := 'The format profile the converted SQL is laid out with (this window only)';
      F.FFormatCombo.ShowHint := True;
      F.FFormatCombo.Width := F.Scale96ToScreen(220);
      F.FFormatCombo.Align := alLeft;
      F.FFormatCombo.Left := F.Scale96ToScreen(3000);
      F.FFormatCombo.BorderSpacing.Top := F.Scale96ToScreen(3);
      F.FFormatCombo.BorderSpacing.Bottom := F.Scale96ToScreen(3);
      F.FFormatCombo.OnChange := @F.FormatChange;
    end;
    F.FBefore.Text := ASetup.Before;
    F.ShowBadges;
    F.FToInfoFor := -2;
    F.FillNameCombos;
    F.Recompute;

    F.ShowModal;
    ASaved := F.FSaved;
    ASummary := F.FSummaryText;
  finally
    F.Free;
  end;
end;

initialization
  DotFormat := DefaultFormatSettings;
  DotFormat.DecimalSeparator := '.';
  DotFormat.ThousandSeparator := #0;

end.
