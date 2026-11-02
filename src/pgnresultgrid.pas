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
  result (the IN list: the whole column). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Grids, Clipbrd, LCLType, Math, Menus, Dialogs,
  pgnTypes, pgnTheme, pgnExport;

type
  TpgnResultGrid = class(TDrawGrid)
  private
    FData: TpgnResultSet;
    FMenu: TPopupMenu;
    FItemSave: TMenuItem;
    FDialect: TpgnDialect;
    FOnSaveResults: TNotifyEvent;
    procedure FitColumns;
    procedure BuildMenu;
    function AddItem(AParent: TMenuItem; const ACaption: string; AShortCut: TShortCut;
      AClick: TNotifyEvent): TMenuItem;
    function SelRange(AWholeIfOne: Boolean): TpgnCellRange;
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
  protected
    procedure DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows a result set and takes ownership of it (nil = empty grid). }
    procedure ShowData(AData: TpgnResultSet);
    procedure CopySelection;
    procedure CopyWithHeaders;
    procedure SelectAllCells;
    property Data: TpgnResultSet read FData;
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
  FItemSave.Visible := Assigned(FOnSaveResults);
  FItemSave.Enabled := Has and (FData.RowCount > 0);
  // the line before Save goes with it
  FMenu.Items[FMenu.Items.IndexOf(FItemSave) - 1].Visible := FItemSave.Visible;
end;

{ The selection as result-set cells. One cell selected and AWholeIfOne:
  every cell. }
function TpgnResultGrid.SelRange(AWholeIfOne: Boolean): TpgnCellRange;
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
    Result := WholeRange(FData);
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
begin
  if (FData = nil) or (FData.ColumnCount = 0) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  SetClipText(CellsAsCSV(FData, SelRange(False), #9, True, False));
end;

procedure TpgnResultGrid.DoCopyCSV(Sender: TObject);
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  SetClipText(CellsAsCSV(FData, SelRange(True), ',', True, False));
end;

procedure TpgnResultGrid.DoCopyInsert(Sender: TObject);
var
  Table: string;
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
  SetClipText(CellsAsInsert(FData, SelRange(True), Table, FDialect));
end;

procedure TpgnResultGrid.DoCopyInList(Sender: TObject);
var
  R: TpgnCellRange;
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  R := SelRange(False);
  if R.R1 = R.R2 then
  begin
    // one cell (or one row): the whole column it's in
    R.R1 := 0;
    R.R2 := FData.RowCount - 1;
  end;
  SetClipText(CellsAsInList(FData, R, FDialect));
end;

procedure TpgnResultGrid.DoCopyJSON(Sender: TObject);
begin
  if (FData = nil) or (FData.RowCount = 0) then
  begin
    Exit;
  end;
  SetClipText(CellsAsJSON(FData, SelRange(True)));
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
    SetClipText(ColumnNames(FData, SelRange(True)));
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
begin
  BeginUpdate;
  try
    FreeAndNil(FData);
    FData := AData;
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
    ColWidths[C + 1] := Min(Best + Pad, Scale96ToScreen(MaxColWidth));
  end;
  // the row-number column fits the largest row number
  ColWidths[0] := Max(Scale96ToScreen(44), Canvas.TextWidth(IntToStr(FData.RowCount)) + Pad);
end;

procedure TpgnResultGrid.DrawCell(ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
var
  S: string;
  IsNull: Boolean;
  TX, TY, Pad: Integer;
begin
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
    end
    else if (ARow > 0) and (ACol = 0) then
    begin
      S := IntToStr(ARow);
      Canvas.Font.Color := clPgnMuted;
    end;

  end
  else
  begin
    if (FData <> nil) and (ARow - 1 < FData.RowCount) and (ACol - 1 < FData.ColumnCount) then
    begin
      IsNull := FData.Rows[ARow - 1].Nulls[ACol - 1];
      if IsNull then
      begin
        S := NullText;
      end
      else
      begin
        S := FData.Rows[ARow - 1].Values[ACol - 1];
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
  Canvas.TextRect(ARect, TX, TY, S);
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
        if FData.Rows[R - 1].Nulls[C - 1] then
        begin
          V := '';
        end
        else
        begin
          V := FData.Rows[R - 1].Values[C - 1];
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

end.
