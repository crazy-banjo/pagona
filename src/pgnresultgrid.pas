// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnResultGrid;

{ A results grid drawn by Pagona, so it looks the same everywhere:

    #  | SPRIDEN_ID | LAST_NAME      <- header row: bold, shaded
    1  | H00012345  | Smith
    2  | H00023456  | (null)         <- NULL: gray italic, never plain text

  Rows are drawn on demand straight from the result set, so a large
  result costs no extra memory. The grid owns its result set.
  Ctrl+C copies the selected cells, tab-separated (with the column titles
  when whole rows are selected), ready to paste into a spreadsheet.
  Ctrl+Shift+C copies them with the titles always. The right-click menu
  has Copy As (CSV, INSERT statements, IN list, JSON, column names) and
  Save Results As. With a single cell selected, Copy As takes the whole
  result (the IN list: the whole column).

  Sort and filter, in the column titles: click a title to sort (again for
  descending, a third time for the order the database gave; Shift+click
  adds a column), the triangle at its right opens that column's filter
  (ticked values, or contains / equals / starts with / empty / greater /
  less). They work on the rows already fetched, stay when the query runs
  again (by column name), and the corner (or the right-click menu) clears
  them all. Copy takes the rows as shown. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Grids, Clipbrd, LCLType, Math, Menus, Dialogs, Forms,
  StdCtrls, ExtCtrls, CheckLst, pgnTypes, pgnTheme, pgnExport;

type
  TpgnFilterKind = (fkValues, fkContains, fkEquals, fkStarts, fkEmpty, fkNotEmpty, fkGreater, fkLess);

  TpgnColFilter = record
    Col: string;              // column name
    Kind: TpgnFilterKind;
    Text: string;
    Values: TpgnStringArray;  // fkValues: the values kept (NullMark for NULL)
  end;

  TpgnColSort = record
    Col: string;
    Desc: Boolean;
  end;

  TpgnResultGrid = class(TDrawGrid)
  private
    FData: TpgnResultSet;
    FView: array of Integer;      // the data rows shown, in order (when sorted or filtered)
    FSorts: array of TpgnColSort;
    FFilters: array of TpgnColFilter;
    FNumeric: array of Integer;   // per column: -1 unknown, 0 text, 1 numbers
    FDownX, FDownY: Integer;
    FDownShift: TShiftState;
    FOnViewChanged: TNotifyEvent;
    FMenu: TPopupMenu;
    FItemSave, FItemClear: TMenuItem;
    FDialect: TpgnDialect;
    FOnSaveResults: TNotifyEvent;
    procedure FitColumns;
    procedure BuildMenu;
    function AddItem(AParent: TMenuItem; const ACaption: string; AShortCut: TShortCut;
      AClick: TNotifyEvent): TMenuItem;
    function SelRange(AWholeIfOne: Boolean; AD: TpgnResultSet): TpgnCellRange;
    procedure SetSaveCaption(const AValue: string);
    procedure MenuPopup(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoCopyHeaders(Sender: TObject);
    procedure DoCopyCSV(Sender: TObject);
    procedure DoCopyInsert(Sender: TObject);
    procedure DoCopyInList(Sender: TObject);
    procedure DoCopyJSON(Sender: TObject);
    procedure DoCopyNames(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoSave(Sender: TObject);
    procedure SetClipText(const S: string);
    procedure DoClearView(Sender: TObject);
    procedure DrawHeaderMarks(C: Integer; const ARect: TRect);
    function DataRow(AGridRow: Integer): Integer;
    function ColIndex(const AName: string): Integer;
    function IsNumericCol(C: Integer): Boolean;
    function RowPasses(R: Integer): Boolean;
    function CompareRows(A, B: Integer): Integer;
    procedure RebuildView;
    function FilterOf(C: Integer): Integer;
    function SortOf(C: Integer): Integer;
    function GlyphWidth: Integer;
    { The rows shown, as a result set (the data itself when nothing is
      sorted or filtered); AOwned: the caller frees it. }
    function ShownSet(out AOwned: Boolean): TpgnResultSet;
  protected
    procedure DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure HeaderClick(IsColumn: Boolean; Index: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows a result set and takes ownership of it (nil = empty grid). }
    procedure ShowData(AData: TpgnResultSet);
    procedure CopySelection;
    procedure CopyWithHeaders;
    procedure SelectAllCells;
    { What a click on a column's title does (C: the column, from 0); AAdd:
      Shift held. }
    procedure ToggleSort(C: Integer; AAdd: Boolean);
    { What a click on a title's triangle does. }
    procedure EditFilter(C: Integer);
    { Clears every sort and filter. }
    procedure ClearView;
    function ViewActive: Boolean;
    function ShownCount: Integer;
    { e.g. "12 of 1,000 rows shown, sorted and filtered" ('' when neither) }
    function ViewText: string;
    property Data: TpgnResultSet read FData;
    { Fires when the sort or the filters change. }
    property OnViewChanged: TNotifyEvent read FOnViewChanged write FOnViewChanged;
    { how INSERT statements and IN lists quote names and text }
    property Dialect: TpgnDialect read FDialect write FDialect;
    { Save Results As... (Export Dataset... in Amphibian); shown in the
      menu only when OnSaveResults is set }
    property SaveCaption: string write SetSaveCaption;
    property OnSaveResults: TNotifyEvent read FOnSaveResults write FOnSaveResults;
  end;

implementation

const
  NullText = '(null)';
  NullMark = #1'null';      // a NULL in a filter's value list
  MaxFilterValues = 1000;   // distinct values listed in a filter
  MaxSampleRows = 200;     // rows measured when sizing columns
  MaxColWidth = 420;       // at 96 dpi

constructor TpgnResultGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FData := nil;
  FixedCols := 1;
  FixedRows := 1;
  ColCount := 1;
  RowCount := 1;
  DefaultRowHeight := Scale96ToScreen(22);
  Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine,
    goRangeSelect, goColSizing, goThumbTracking, goDrawFocusSelected, goTabs];
  Color := clPgnWork;
  FixedColor := clPgnGridFixed;
  GridLineColor := clPgnGridLines;
  FocusRectVisible := False;
  ColWidths[0] := Scale96ToScreen(44);
  FDialect := sdMySQL;
  FOnSaveResults := nil;
  BuildMenu;
end;

function TpgnResultGrid.AddItem(AParent: TMenuItem; const ACaption: string; AShortCut: TShortCut;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.ShortCut := AShortCut;
  Result.OnClick := AClick;
  AParent.Add(Result);
end;

procedure TpgnResultGrid.BuildMenu;
var
  Sub: TMenuItem;
begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;
  AddItem(FMenu.Items, '&Copy', ShortCut(VK_C, [ssCtrl]), @DoCopy);
  AddItem(FMenu.Items, 'Copy with &Headers', ShortCut(VK_C, [ssCtrl, ssShift]), @DoCopyHeaders);
  Sub := AddItem(FMenu.Items, 'Copy &As', 0, nil);
  AddItem(Sub, '&CSV', 0, @DoCopyCSV);
  AddItem(Sub, '&INSERT Statements...', 0, @DoCopyInsert);
  AddItem(Sub, 'I&N List', 0, @DoCopyInList);
  AddItem(Sub, '&JSON', 0, @DoCopyJSON);
  AddItem(Sub, 'Column &Names', 0, @DoCopyNames);
  AddItem(FMenu.Items, '-', 0, nil);
  AddItem(FMenu.Items, 'Select &All', ShortCut(VK_A, [ssCtrl]), @DoSelectAll);
  FItemClear := AddItem(FMenu.Items, 'C&lear Sort and Filters', 0, @DoClearView);
  AddItem(FMenu.Items, '-', 0, nil);
  FItemSave := AddItem(FMenu.Items, 'Save Results &As...', 0, @DoSave);
  PopupMenu := FMenu;
end;

procedure TpgnResultGrid.SetSaveCaption(const AValue: string);
begin
  FItemSave.Caption := AValue;
end;

procedure TpgnResultGrid.MenuPopup(Sender: TObject);
var
  I: Integer;
  Has: Boolean;
begin
  Has := (FData <> nil) and (FData.ColumnCount > 0);
  for I := 0 to FMenu.Items.Count - 1 do
  begin
    FMenu.Items[I].Enabled := Has;
  end;
  FItemClear.Enabled := ViewActive;
  FItemSave.Visible := Assigned(FOnSaveResults);
  FItemSave.Enabled := Has and (FData.RowCount > 0);
  // the line before Save goes with it
  FMenu.Items[FMenu.Items.IndexOf(FItemSave) - 1].Visible := FItemSave.Visible;
end;

{ The selection as result-set cells. One cell selected and AWholeIfOne:
  every cell. }
function TpgnResultGrid.SelRange(AWholeIfOne: Boolean; AD: TpgnResultSet): TpgnCellRange;
var
  Sel: TGridRect;
begin
  Sel := Selection;
  Result.R1 := Max(Sel.Top, 1) - 1;
  Result.R2 := Min(Sel.Bottom, RowCount - 1) - 1;
  Result.C1 := Max(Sel.Left, 1) - 1;
  Result.C2 := Min(Sel.Right, ColCount - 1) - 1;
  if AWholeIfOne and (Result.R1 = Result.R2) and (Result.C1 = Result.C2) then
  begin
    Result := WholeRange(AD);
  end;
end;

procedure TpgnResultGrid.SetClipText(const S: string);
begin
  Clipboard.AsText := TrimRight(S);
end;

procedure TpgnResultGrid.DoCopy(Sender: TObject);
begin
  CopySelection;
end;

procedure TpgnResultGrid.DoCopyHeaders(Sender: TObject);
begin
  CopyWithHeaders;
end;

procedure TpgnResultGrid.CopyWithHeaders;
var
  D: TpgnResultSet;
  Own: Boolean;
begin
  if (FData = nil) or (FData.ColumnCount = 0) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  D := ShownSet(Own);
  try
    SetClipText(CellsAsCSV(D, SelRange(False, D), #9, True, False));
  finally
    if Own then
    begin
      D.Free;
    end;
  end;
end;

procedure TpgnResultGrid.DoCopyCSV(Sender: TObject);
var
  D: TpgnResultSet;
  Own: Boolean;
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  D := ShownSet(Own);
  try
    SetClipText(CellsAsCSV(D, SelRange(True, D), ',', True, False));
  finally
    if Own then
    begin
      D.Free;
    end;
  end;
end;

procedure TpgnResultGrid.DoCopyInsert(Sender: TObject);
var
  Table: string;
  D: TpgnResultSet;
  Own: Boolean;
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  Table := GuessTableName(FData.SourceSQL);
  if not InputQuery('Copy As INSERT Statements', 'Table to insert into:', Table) then
  begin
    Exit;
  end;
  D := ShownSet(Own);
  try
    SetClipText(CellsAsInsert(D, SelRange(True, D), Table, FDialect));
  finally
    if Own then
    begin
      D.Free;
    end;
  end;
end;

procedure TpgnResultGrid.DoCopyInList(Sender: TObject);
var
  R: TpgnCellRange;
  D: TpgnResultSet;
  Own: Boolean;
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  D := ShownSet(Own);
  try
    R := SelRange(False, D);
    if R.R1 = R.R2 then
    begin
      // one cell (or one row): the whole column it's in
      R.R1 := 0;
      R.R2 := D.RowCount - 1;
    end;
    SetClipText(CellsAsInList(D, R, FDialect));
  finally
    if Own then
    begin
      D.Free;
    end;
  end;
end;

procedure TpgnResultGrid.DoCopyJSON(Sender: TObject);
var
  D: TpgnResultSet;
  Own: Boolean;
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  D := ShownSet(Own);
  try
    SetClipText(CellsAsJSON(D, SelRange(True, D)));
  finally
    if Own then
    begin
      D.Free;
    end;
  end;
end;

procedure TpgnResultGrid.DoCopyNames(Sender: TObject);
begin
  if (FData = nil) or (FData.ColumnCount = 0) then
  begin
    Exit;
  end;
  if FData.RowCount = 0 then
  begin
    SetClipText(ColumnNames(FData, WholeRange(FData)));
  end
  else
  begin
    SetClipText(ColumnNames(FData, SelRange(True, FData)));
  end;
end;

procedure TpgnResultGrid.DoSelectAll(Sender: TObject);
begin
  SelectAllCells;
end;

procedure TpgnResultGrid.SelectAllCells;
var
  Sel: TGridRect;
begin
  if (FData = nil) or (RowCount < 2) or (ColCount < 2) then
  begin
    Exit;
  end;
  Sel.Left := 1;
  Sel.Top := 1;
  Sel.Right := ColCount - 1;
  Sel.Bottom := RowCount - 1;
  Selection := Sel;
  Invalidate;
end;

procedure TpgnResultGrid.DoSave(Sender: TObject);
begin
  if Assigned(FOnSaveResults) then
  begin
    FOnSaveResults(Self);
  end;
end;

{ A right-click outside the selection selects the cell clicked first. }
procedure TpgnResultGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  C, R: Integer;
  Sel: TGridRect;
begin
  FDownX := X;
  FDownY := Y;
  FDownShift := Shift;
  if Button = mbRight then
  begin
    MouseToCell(X, Y, C, R);
    Sel := Selection;
    if (C >= 1) and (R >= 1) and
      ((C < Sel.Left) or (C > Sel.Right) or (R < Sel.Top) or (R > Sel.Bottom)) then
    begin
      Col := C;
      Row := R;
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

destructor TpgnResultGrid.Destroy;
begin
  FreeAndNil(FData);
  inherited Destroy;
end;

procedure TpgnResultGrid.ShowData(AData: TpgnResultSet);
var
  I: Integer;
  Keep: Boolean;
begin
  BeginUpdate;
  try
    FreeAndNil(FData);
    FData := AData;
    FNumeric := nil;
    if FData <> nil then
    begin
      SetLength(FNumeric, FData.ColumnCount);
      for I := 0 to High(FNumeric) do
      begin
        FNumeric[I] := -1;
      end;
    end;
    // the sort and filters stay when their columns are still there
    Keep := FData <> nil;
    for I := 0 to High(FSorts) do
    begin
      if Keep and (ColIndex(FSorts[I].Col) < 0) then
      begin
        Keep := False;
      end;
    end;
    for I := 0 to High(FFilters) do
    begin
      if Keep and (ColIndex(FFilters[I].Col) < 0) then
      begin
        Keep := False;
      end;
    end;
    if not Keep then
    begin
      FSorts := nil;
      FFilters := nil;
    end;
    FView := nil;
    if (FData = nil) or (FData.ColumnCount = 0) then
    begin
      ColCount := 1;
      RowCount := 1;
    end
    else
    begin
      ColCount := FData.ColumnCount + 1;
      RowCount := FData.RowCount + 1;
      FitColumns;
      if ViewActive then
      begin
        RebuildView;
      end;
    end;
    ColWidths[0] := Scale96ToScreen(44);
    if RowCount > 1 then
    begin
      Row := 1;
      Col := 1;
    end;
    TopRow := 1;
    LeftCol := 1;
  finally
    EndUpdate;
  end;
  Invalidate;
end;

{ Each column as wide as its title or its widest value in the first rows,
  within limits. }
procedure TpgnResultGrid.FitColumns;
var
  C, R, W, Best, Pad: Integer;
begin
  Pad := Scale96ToScreen(16);
  Canvas.Font.Assign(Font);
  for C := 0 to FData.ColumnCount - 1 do
  begin
    Canvas.Font.Style := [fsBold];
    Best := Canvas.TextWidth(FData.Columns[C]);
    Canvas.Font.Style := [];
    for R := 0 to Min(FData.RowCount, MaxSampleRows) - 1 do
    begin
      if FData.Rows[R].Nulls[C] then
      begin
        W := Canvas.TextWidth(NullText);
      end
      else
      begin
        W := Canvas.TextWidth(FData.Rows[R].Values[C]);
      end;
      if W > Best then
      begin
        Best := W;
      end;
    end;
    ColWidths[C + 1] := Min(Max(Best + Pad, Canvas.TextWidth(FData.Columns[C]) + Pad + GlyphWidth * 2),
      Scale96ToScreen(MaxColWidth));
  end;
  // the row-number column fits the largest row number
  ColWidths[0] := Max(Scale96ToScreen(44), Canvas.TextWidth(IntToStr(FData.RowCount)) + Pad);
end;

procedure TpgnResultGrid.DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
var
  S, M: string;
  IsNull: Boolean;
  TX, TY, Pad, K: Integer;
  TR: TRect;
begin
  TR := ARect;
  Pad := Scale96ToScreen(6);
  Canvas.Font.Assign(Font);
  IsNull := False;
  S := '';
  if FData = nil then
  begin
    // nothing to show: no header, no corner, just the empty area
    Canvas.Brush.Color := clPgnWork;
    Canvas.FillRect(ARect);
    Exit;
  end;

  if (ARow = 0) or (ACol = 0) then
  begin
    // header row and row numbers
    Canvas.Brush.Color := clPgnGridFixed;
    Canvas.FillRect(ARect);
    if (ARow = 0) and (ACol > 0) and (FData <> nil) and (ACol - 1 < FData.ColumnCount) then
    begin
      S := FData.Columns[ACol - 1];
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := clPgnText;
      DrawHeaderMarks(ACol - 1, ARect);
      TR.Right := TR.Right - GlyphWidth;
      K := SortOf(ACol - 1);
      if K >= 0 then
      begin
        // the direction, and the order when there's more than one
        if FSorts[K].Desc then
        begin
          M := ' ' + #$E2#$96#$BC;   // ▼
        end
        else
        begin
          M := ' ' + #$E2#$96#$B2;   // ▲
        end;
        if Length(FSorts) > 1 then
        begin
          M := M + IntToStr(K + 1);
        end;
        S := S + M;
      end;
    end
    else if (ARow = 0) and (ACol = 0) and ViewActive then
    begin
      // the corner clears the sort and filters
      S := #$E2#$9C#$95;   // ✕
      Canvas.Font.Color := clPgnText;
      Canvas.Font.Style := [fsBold];
    end
    else if (ARow > 0) and (ACol = 0) then
    begin
      S := IntToStr(ARow);
      Canvas.Font.Color := clPgnMuted;
    end;

  end
  else
  begin
    if (FData <> nil) and (ARow - 1 < ShownCount) and (ACol - 1 < FData.ColumnCount) then
    begin
      IsNull := FData.Rows[DataRow(ARow)].Nulls[ACol - 1];
      if IsNull then
      begin
        S := NullText;
      end
      else
      begin
        S := FData.Rows[DataRow(ARow)].Values[ACol - 1];
      end;
    end;
    if gdSelected in AState then
    begin
      Canvas.Brush.Color := clPgnSelection;
    end
    else
    begin
      Canvas.Brush.Color := clPgnWork;
    end;
    Canvas.FillRect(ARect);
    if IsNull then
    begin
      Canvas.Font.Style := [fsItalic];
      Canvas.Font.Color := clPgnMuted;
    end
    else
    begin
      Canvas.Font.Color := TColor($001A1A1A);
    end;
  end;

  if (ACol = 0) and (ARow = 0) and ViewActive then
  begin
    // the corner's ✕, centered
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut((ARect.Left + ARect.Right - Canvas.TextWidth(S)) div 2,
      (ARect.Top + ARect.Bottom - Canvas.TextHeight(S)) div 2, S);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  // one line per cell; line breaks inside a value show as spaces
  S := StringReplace(StringReplace(S, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Canvas.Brush.Style := bsClear;
  TY := (ARect.Top + ARect.Bottom - Canvas.TextHeight('Ag')) div 2;
  if (ACol = 0) and (ARow > 0) then
  begin
    TX := ARect.Right - Pad - Canvas.TextWidth(S);
  end
  else
  begin
    TX := ARect.Left + Pad;
  end;
  Canvas.TextRect(TR, TX, TY, S);
  Canvas.Brush.Style := bsSolid;

  // the cell's own right and bottom lines, dark enough to read the grid
  // by (drawn here: the cell is painted by hand, over the grid's lines)
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := clPgnGridLines;
  Canvas.Line(ARect.Right - 1, ARect.Top, ARect.Right - 1, ARect.Bottom);
  if ARow = 0 then
  begin
    // a firmer line under the titles
    Canvas.Pen.Color := clPgnGridHead;
  end;
  Canvas.Line(ARect.Left, ARect.Bottom - 1, ARect.Right, ARect.Bottom - 1);
end;

{ ------------------------------------------------- sort and filter }

function TpgnResultGrid.ViewActive: Boolean;
begin
  Result := (Length(FSorts) > 0) or (Length(FFilters) > 0);
end;

function TpgnResultGrid.ShownCount: Integer;
begin
  if FData = nil then
  begin
    Result := 0;
  end
  else if ViewActive then
  begin
    Result := Length(FView);
  end
  else
  begin
    Result := FData.RowCount;
  end;
end;

function TpgnResultGrid.DataRow(AGridRow: Integer): Integer;
begin
  if ViewActive then
  begin
    Result := FView[AGridRow - 1];
  end
  else
  begin
    Result := AGridRow - 1;
  end;
end;

function TpgnResultGrid.ColIndex(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if FData = nil then
  begin
    Exit;
  end;
  for I := 0 to FData.ColumnCount - 1 do
  begin
    if SameText(FData.Columns[I], AName) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnResultGrid.SortOf(C: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FSorts) do
  begin
    if SameText(FSorts[I].Col, FData.Columns[C]) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnResultGrid.FilterOf(C: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FFilters) do
  begin
    if SameText(FFilters[I].Col, FData.Columns[C]) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnResultGrid.GlyphWidth: Integer;
begin
  Result := Scale96ToScreen(18);
end;

var
  DotFormat: TFormatSettings;

function AsNumber(const S: string; out V: Double): Boolean;
begin
  Result := TryStrToFloat(Trim(S), V, DotFormat);
end;

{ A column sorts as numbers when every value in it is one. }
function TpgnResultGrid.IsNumericCol(C: Integer): Boolean;
var
  R: Integer;
  V: Double;
  Any: Boolean;
begin
  if FNumeric[C] < 0 then
  begin
    FNumeric[C] := 1;
    Any := False;
    for R := 0 to FData.RowCount - 1 do
    begin
      if FData.Rows[R].Nulls[C] or (FData.Rows[R].Values[C] = '') then
      begin
        Continue;
      end;
      Any := True;
      if not AsNumber(FData.Rows[R].Values[C], V) then
      begin
        FNumeric[C] := 0;
        Break;
      end;
    end;
    if not Any then
    begin
      FNumeric[C] := 0;
    end;
  end;
  Result := FNumeric[C] = 1;
end;

function CompareValues(const A, B: string; ANumeric: Boolean): Integer;
var
  X, Y: Double;
begin
  if ANumeric and AsNumber(A, X) and AsNumber(B, Y) then
  begin
    Result := CompareValue(X, Y);
  end
  else
  begin
    Result := AnsiCompareText(A, B);
    if Result = 0 then
    begin
      Result := AnsiCompareStr(A, B);
    end;
  end;
end;

function TpgnResultGrid.RowPasses(R: Integer): Boolean;
var
  I, C, K: Integer;
  V: string;
  IsNull: Boolean;
  F: TpgnColFilter;
begin
  Result := True;
  for I := 0 to High(FFilters) do
  begin
    F := FFilters[I];
    C := ColIndex(F.Col);
    if C < 0 then
    begin
      Continue;
    end;
    IsNull := FData.Rows[R].Nulls[C];
    V := FData.Rows[R].Values[C];
    case F.Kind of
      fkValues:
        begin
          Result := False;
          for K := 0 to High(F.Values) do
          begin
            if (IsNull and (F.Values[K] = NullMark)) or (not IsNull and (F.Values[K] = V)) then
            begin
              Result := True;
              Break;
            end;
          end;
        end;
      fkContains:
        begin
          Result := not IsNull and (Pos(AnsiLowerCase(F.Text), AnsiLowerCase(V)) > 0);
        end;
      fkEquals:
        begin
          Result := not IsNull and (CompareValues(V, F.Text, IsNumericCol(C)) = 0);
        end;
      fkStarts:
        begin
          Result := not IsNull and (Pos(AnsiLowerCase(F.Text), AnsiLowerCase(V)) = 1);
        end;
      fkEmpty:
        begin
          Result := IsNull or (Trim(V) = '');
        end;
      fkNotEmpty:
        begin
          Result := not IsNull and (Trim(V) <> '');
        end;
      fkGreater:
        begin
          Result := not IsNull and (CompareValues(V, F.Text, IsNumericCol(C)) > 0);
        end;
      fkLess:
        begin
          Result := not IsNull and (CompareValues(V, F.Text, IsNumericCol(C)) < 0);
        end;
    end;
    if not Result then
    begin
      Exit;
    end;
  end;
end;

{ NULLs last either way; ties keep the database's order. }
function TpgnResultGrid.CompareRows(A, B: Integer): Integer;
var
  I, C: Integer;
  NA, NB: Boolean;
begin
  Result := 0;
  for I := 0 to High(FSorts) do
  begin
    C := ColIndex(FSorts[I].Col);
    if C < 0 then
    begin
      Continue;
    end;
    NA := FData.Rows[A].Nulls[C];
    NB := FData.Rows[B].Nulls[C];
    if NA and NB then
    begin
      Continue;
    end;
    if NA then
    begin
      Result := 1;
      Exit;
    end;
    if NB then
    begin
      Result := -1;
      Exit;
    end;
    Result := CompareValues(FData.Rows[A].Values[C], FData.Rows[B].Values[C], IsNumericCol(C));
    if FSorts[I].Desc then
    begin
      Result := -Result;
    end;
    if Result <> 0 then
    begin
      Exit;
    end;
  end;
  Result := A - B;
end;

procedure TpgnResultGrid.RebuildView;
var
  R, N, W, I, L, M, H, K: Integer;
  Src, Tmp: array of Integer;
begin
  FView := nil;
  if (FData = nil) or not ViewActive then
  begin
    if FData <> nil then
    begin
      RowCount := FData.RowCount + 1;
    end;
    Invalidate;
    if Assigned(FOnViewChanged) then
    begin
      FOnViewChanged(Self);
    end;
    Exit;
  end;
  SetLength(Src, FData.RowCount);
  N := 0;
  for R := 0 to FData.RowCount - 1 do
  begin
    if RowPasses(R) then
    begin
      Src[N] := R;
      Inc(N);
    end;
  end;
  SetLength(Src, N);
  // a merge sort: stable, and fine on a few hundred thousand rows
  if Length(FSorts) > 0 then
  begin
    SetLength(Tmp, N);
    W := 1;
    while W < N do
    begin
      I := 0;
      while I < N do
      begin
        L := I;
        M := Min(I + W, N);
        H := Min(I + 2 * W, N);
        K := I;
        R := M;
        while (L < M) and (R < H) do
        begin
          if CompareRows(Src[L], Src[R]) <= 0 then
          begin
            Tmp[K] := Src[L];
            Inc(L);
          end
          else
          begin
            Tmp[K] := Src[R];
            Inc(R);
          end;
          Inc(K);
        end;
        while L < M do
        begin
          Tmp[K] := Src[L];
          Inc(L);
          Inc(K);
        end;
        while R < H do
        begin
          Tmp[K] := Src[R];
          Inc(R);
          Inc(K);
        end;
        Inc(I, 2 * W);
      end;
      for I := 0 to N - 1 do
      begin
        Src[I] := Tmp[I];
      end;
      W := W * 2;
    end;
  end;
  FView := Src;
  RowCount := Length(FView) + 1;
  if (RowCount > 1) and (Row < 1) then
  begin
    Row := 1;
  end;
  Invalidate;
  if Assigned(FOnViewChanged) then
  begin
    FOnViewChanged(Self);
  end;
end;

procedure TpgnResultGrid.ClearView;
begin
  FSorts := nil;
  FFilters := nil;
  RebuildView;
end;

procedure TpgnResultGrid.DoClearView(Sender: TObject);
begin
  ClearView;
end;

function TpgnResultGrid.ViewText: string;
var
  What: string;
begin
  Result := '';
  if (FData = nil) or not ViewActive then
  begin
    Exit;
  end;
  if (Length(FSorts) > 0) and (Length(FFilters) > 0) then
  begin
    What := 'sorted and filtered';
  end
  else if Length(FSorts) > 0 then
  begin
    What := 'sorted';
  end
  else
  begin
    What := 'filtered';
  end;
  Result := FormatFloat('#,##0', ShownCount) + ' of ' + FormatFloat('#,##0', FData.RowCount) + ' rows shown, ' +
    What;
  if FData.HasMoreRows then
  begin
    Result := Result + ' (within the first ' + FormatFloat('#,##0', FData.RowCount) + ' fetched)';
  end;
end;

{ Ascending, descending, then the database's order again. AAdd (Shift):
  another sort column; otherwise this one alone. }
procedure TpgnResultGrid.ToggleSort(C: Integer; AAdd: Boolean);
var
  K, I, N: Integer;
begin
  K := SortOf(C);
  if not AAdd then
  begin
    if K < 0 then
    begin
      SetLength(FSorts, 1);
      FSorts[0].Col := FData.Columns[C];
      FSorts[0].Desc := False;
    end
    else if not FSorts[K].Desc then
    begin
      SetLength(FSorts, 1);
      FSorts[0].Col := FData.Columns[C];
      FSorts[0].Desc := True;
    end
    else
    begin
      FSorts := nil;
    end;
  end
  else if K < 0 then
  begin
    N := Length(FSorts);
    SetLength(FSorts, N + 1);
    FSorts[N].Col := FData.Columns[C];
    FSorts[N].Desc := False;
  end
  else if not FSorts[K].Desc then
  begin
    FSorts[K].Desc := True;
  end
  else
  begin
    for I := K to High(FSorts) - 1 do
    begin
      FSorts[I] := FSorts[I + 1];
    end;
    SetLength(FSorts, Length(FSorts) - 1);
  end;
  RebuildView;
end;

{ The triangle at the right of a title: outline when the column has no
  filter, filled (and boxed) when it has one, so the shape says it too. }
procedure TpgnResultGrid.DrawHeaderMarks(C: Integer; const ARect: TRect);
var
  G: string;
  R: TRect;
begin
  R := ARect;
  R.Left := R.Right - GlyphWidth;
  if FilterOf(C) >= 0 then
  begin
    G := #$E2#$96#$BC;   // ▼
    Canvas.Brush.Color := clPgnSelection;
    Canvas.FillRect(Rect(R.Left + 1, R.Top + 2, R.Right - 2, R.Bottom - 2));
    Canvas.Pen.Color := clPgnText;
    Canvas.Frame(Rect(R.Left + 1, R.Top + 2, R.Right - 2, R.Bottom - 2));
    Canvas.Font.Color := clPgnText;
  end
  else
  begin
    G := #$E2#$96#$BD;   // ▽
    Canvas.Font.Color := clPgnMuted;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [];
  Canvas.TextOut((R.Left + R.Right - Canvas.TextWidth(G)) div 2, (R.Top + R.Bottom - Canvas.TextHeight(G)) div 2, G);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := clPgnText;
  Canvas.Brush.Color := clPgnGridFixed;
end;

procedure TpgnResultGrid.HeaderClick(IsColumn: Boolean; Index: Integer);
var
  R: TRect;
  X, Y: Integer;
begin
  inherited HeaderClick(IsColumn, Index);
  if not IsColumn or (FData = nil) or (FData.ColumnCount = 0) then
  begin
    Exit;
  end;
  if Index = 0 then
  begin
    if ViewActive then
    begin
      ClearView;   // the corner's ✕
    end;
    Exit;
  end;
  if Index - 1 >= FData.ColumnCount then
  begin
    Exit;
  end;
  // a drag on a column's edge resizes it: not a click
  X := ScreenToClient(Mouse.CursorPos).X;
  Y := ScreenToClient(Mouse.CursorPos).Y;
  if (Abs(X - FDownX) > 4) or (Abs(Y - FDownY) > 4) then
  begin
    Exit;
  end;
  R := CellRect(Index, 0);
  if (FDownX >= R.Right - Scale96ToScreen(4)) or (FDownX <= R.Left + Scale96ToScreen(3)) then
  begin
    Exit;
  end;
  if FDownX >= R.Right - GlyphWidth then
  begin
    EditFilter(Index - 1);
  end
  else
  begin
    ToggleSort(Index - 1, ssShift in FDownShift);
  end;
end;

type
  { The filter pop-up's buttons. }
  TFilterHelper = class
    List: TCheckListBox;
    Kind: TComboBox;
    Text: TEdit;
    procedure AllClick(Sender: TObject);
    procedure NoneClick(Sender: TObject);
    procedure KindChange(Sender: TObject);
  end;

procedure TFilterHelper.AllClick(Sender: TObject);
begin
  List.CheckAll(cbChecked);
end;

procedure TFilterHelper.NoneClick(Sender: TObject);
begin
  List.CheckAll(cbUnchecked);
end;

procedure TFilterHelper.KindChange(Sender: TObject);
begin
  List.Enabled := Kind.ItemIndex = 0;
  Text.Enabled := Kind.ItemIndex in [1, 2, 3, 6, 7];
end;

{ The filter for column C: ticked values, or a condition. }
procedure TpgnResultGrid.EditFilter(C: Integer);
var
  F: TForm;
  H: TFilterHelper;
  Vals: TStringList;
  R, K, N, M, W: Integer;
  HasNull, Cut: Boolean;
  P: TPoint;
  L: TLabel;
  B: TButton;
  Res: TModalResult;
  Old: TpgnColFilter;
  Keep: TpgnStringArray;
begin
  K := FilterOf(C);
  Vals := TStringList.Create;
  H := TFilterHelper.Create;
  F := TForm.CreateNew(nil);
  try
    Vals.Sorted := True;
    Vals.Duplicates := dupIgnore;
    Vals.CaseSensitive := True;
    HasNull := False;
    Cut := False;
    for R := 0 to FData.RowCount - 1 do
    begin
      if FData.Rows[R].Nulls[C] then
      begin
        HasNull := True;
      end
      else if Vals.Count < MaxFilterValues then
      begin
        Vals.Add(FData.Rows[R].Values[C]);
      end
      else if Vals.IndexOf(FData.Rows[R].Values[C]) < 0 then
      begin
        Cut := True;
      end;
    end;
    SmoothFont(F.Font);
    F.Caption := 'Filter: ' + FData.Columns[C];
    F.BorderStyle := bsDialog;
    M := Scale96ToScreen(8);
    W := Scale96ToScreen(300);
    F.ClientWidth := W + 2 * M;
    L := TLabel.Create(F);
    L.Parent := F;
    L.Caption := 'Show rows where ' + FData.Columns[C];
    L.SetBounds(M, M, W, L.Height);
    H.Kind := TComboBox.Create(F);
    H.Kind.Parent := F;
    H.Kind.Style := csDropDownList;
    H.Kind.Items.Add('is one of the ticked values');
    H.Kind.Items.Add('contains');
    H.Kind.Items.Add('equals');
    H.Kind.Items.Add('starts with');
    H.Kind.Items.Add('is empty (or NULL)');
    H.Kind.Items.Add('is not empty');
    H.Kind.Items.Add('is greater than');
    H.Kind.Items.Add('is less than');
    H.Kind.SetBounds(M, M + Scale96ToScreen(22), W, H.Kind.Height);
    H.Kind.Constraints.MinWidth := W;
    H.Kind.OnChange := @H.KindChange;
    H.Text := TEdit.Create(F);
    H.Text.Parent := F;
    H.Text.SetBounds(M, M + Scale96ToScreen(56), W, H.Text.Height);
    H.List := TCheckListBox.Create(F);
    H.List.Parent := F;
    H.List.SetBounds(M, M + Scale96ToScreen(90), W, Scale96ToScreen(220));
    // the list is filled before the window shows (GTK3 doesn't like a
    // list changing while it's on screen)
    if HasNull then
    begin
      H.List.Items.Add(NullText);
    end;
    for R := 0 to Vals.Count - 1 do
    begin
      H.List.Items.Add(Vals[R]);
    end;
    N := H.List.Items.Count;
    if (K >= 0) and (FFilters[K].Kind = fkValues) then
    begin
      for R := 0 to N - 1 do
      begin
        H.List.Checked[R] := False;
      end;
      for M := 0 to High(FFilters[K].Values) do
      begin
        if FFilters[K].Values[M] = NullMark then
        begin
          if HasNull then
          begin
            H.List.Checked[0] := True;
          end;
        end
        else
        begin
          R := H.List.Items.IndexOf(FFilters[K].Values[M]);
          if (R >= 0) and not (HasNull and (R = 0)) then
          begin
            H.List.Checked[R] := True;
          end;
        end;
      end;
    end
    else
    begin
      H.List.CheckAll(cbChecked);
    end;
    M := Scale96ToScreen(8);
    if K >= 0 then
    begin
      H.Kind.ItemIndex := Ord(FFilters[K].Kind);
      H.Text.Text := FFilters[K].Text;
    end
    else
    begin
      H.Kind.ItemIndex := 0;
    end;
    H.KindChange(nil);
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Tick All';
    B.SetBounds(M, M + Scale96ToScreen(316), Scale96ToScreen(90), Scale96ToScreen(26));
    B.OnClick := @H.AllClick;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Tick None';
    B.SetBounds(M + Scale96ToScreen(96), M + Scale96ToScreen(316), Scale96ToScreen(90), Scale96ToScreen(26));
    B.OnClick := @H.NoneClick;
    if Cut then
    begin
      L := TLabel.Create(F);
      L.Parent := F;
      L.Caption := 'The first ' + IntToStr(MaxFilterValues) + ' different values are listed.';
      L.Font.Color := clPgnMuted;
      L.SetBounds(M, M + Scale96ToScreen(346), W, L.Height);
    end;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Filter';
    B.Default := True;
    B.ModalResult := mrOK;
    B.SetBounds(M, M + Scale96ToScreen(370), Scale96ToScreen(84), Scale96ToScreen(28));
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Remove Filter';
    B.ModalResult := mrIgnore;
    B.SetBounds(M + Scale96ToScreen(90), M + Scale96ToScreen(370), Scale96ToScreen(124), Scale96ToScreen(28));
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Cancel';
    B.Cancel := True;
    B.ModalResult := mrCancel;
    B.SetBounds(M + Scale96ToScreen(220), M + Scale96ToScreen(370), Scale96ToScreen(80), Scale96ToScreen(28));
    F.ClientHeight := M + Scale96ToScreen(406);
    // under the column's title
    P := ClientToScreen(Point(CellRect(C + 1, 0).Left, CellRect(C + 1, 0).Bottom));
    F.Position := poDesigned;
    F.Left := Max(0, Min(P.X, Screen.Width - F.Width));
    F.Top := Max(0, Min(P.Y, Screen.Height - F.Height - Scale96ToScreen(40)));
    Res := F.ShowModal;
    if Res = mrCancel then
    begin
      Exit;
    end;
    // drop this column's old filter
    if K >= 0 then
    begin
      for R := K to High(FFilters) - 1 do
      begin
        FFilters[R] := FFilters[R + 1];
      end;
      SetLength(FFilters, Length(FFilters) - 1);
    end;
    if Res = mrOK then
    begin
      Old := Default(TpgnColFilter);
      Old.Col := FData.Columns[C];
      Old.Kind := TpgnFilterKind(Max(0, H.Kind.ItemIndex));
      Old.Text := H.Text.Text;
      if Old.Kind = fkValues then
      begin
        Keep := nil;
        for R := 0 to H.List.Items.Count - 1 do
        begin
          if H.List.Checked[R] then
          begin
            SetLength(Keep, Length(Keep) + 1);
            if HasNull and (R = 0) then
            begin
              Keep[High(Keep)] := NullMark;
            end
            else
            begin
              Keep[High(Keep)] := H.List.Items[R];
            end;
          end;
        end;
        Old.Values := Keep;
      end;
      // every value ticked (and none cut off) is no filter at all
      if not ((Old.Kind = fkValues) and (Length(Old.Values) = H.List.Items.Count) and not Cut) then
      begin
        SetLength(FFilters, Length(FFilters) + 1);
        FFilters[High(FFilters)] := Old;
      end;
    end;
    RebuildView;
  finally
    F.Free;
    H.Free;
    Vals.Free;
  end;
end;

function TpgnResultGrid.ShownSet(out AOwned: Boolean): TpgnResultSet;
var
  I: Integer;
begin
  if not ViewActive then
  begin
    AOwned := False;
    Result := FData;
    Exit;
  end;
  AOwned := True;
  Result := TpgnResultSet.Create;
  Result.Columns := Copy(FData.Columns, 0, Length(FData.Columns));
  Result.ReturnsRows := True;
  Result.SourceSQL := FData.SourceSQL;
  SetLength(Result.Rows, Length(FView));
  for I := 0 to High(FView) do
  begin
    Result.Rows[I] := FData.Rows[FView[I]];
  end;
end;

procedure TpgnResultGrid.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_C) and (Shift = [ssCtrl]) then
  begin
    CopySelection;
    Key := 0;
    Exit;
  end;
  if (Key = VK_C) and (Shift = [ssCtrl, ssShift]) then
  begin
    CopyWithHeaders;
    Key := 0;
    Exit;
  end;
  if (Key = VK_A) and (Shift = [ssCtrl]) then
  begin
    SelectAllCells;
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

{ Tab-separated text of the selected cells. Whole rows selected (all
  columns) also get the column titles as a first line. }
procedure TpgnResultGrid.CopySelection;
var
  Sel: TGridRect;
  R, C: Integer;
  Lines: TStringList;
  Line, V: string;
begin
  if (FData = nil) or (FData.ColumnCount = 0) then
  begin
    Exit;
  end;
  Sel := Selection;
  Lines := TStringList.Create;
  try
    if (Sel.Left <= 1) and (Sel.Right >= ColCount - 1) and (Sel.Bottom > Sel.Top) then
    begin
      Line := '';
      for C := 0 to FData.ColumnCount - 1 do
      begin
        if C > 0 then
        begin
          Line := Line + #9;
        end;
        Line := Line + FData.Columns[C];
      end;
      Lines.Add(Line);
    end;
    for R := Max(Sel.Top, 1) to Min(Sel.Bottom, RowCount - 1) do
    begin
      Line := '';
      for C := Max(Sel.Left, 1) to Min(Sel.Right, ColCount - 1) do
      begin
        if C > Max(Sel.Left, 1) then
        begin
          Line := Line + #9;
        end;
        if FData.Rows[DataRow(R)].Nulls[C - 1] then
        begin
          V := '';
        end
        else
        begin
          V := FData.Rows[DataRow(R)].Values[C - 1];
        end;
        Line := Line + V;
      end;
      Lines.Add(Line);
    end;
    Clipboard.AsText := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

initialization
  DotFormat := DefaultFormatSettings;
  DotFormat.DecimalSeparator := '.';
  DotFormat.ThousandSeparator := #0;

end.
