// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnFindCombo;

{ A drop-down you can type into to find a name: the list narrows to the
  names that contain what's typed (anywhere, any case). Up and Down move,
  Enter picks, Esc puts the old pick back. The arrow, Alt+Down or F4 shows
  the whole list.

  It stands in for a csDropDownList TComboBox where the lists get long
  (databases, schemas): Items, ItemIndex, OnChange and DroppedDown work the
  same, and OnChange fires only when a different name is picked.

  The list is drawn by Pagona and laid over the form (not a window of its
  own), so it behaves the same on Windows and Linux and never takes focus
  away from the box. (The LCL's GTK3 list box crashes when its items change
  while it's showing.) }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Forms, Graphics, LCLType, Math, Types;

type
  TpgnFindList = class;

  TpgnFindCombo = class(TCustomPanel)
  private
    FEdit: TEdit;
    FArrow: TPaintBox;
    FList: TpgnFindList;
    FItems: TStringList;
    FItemIndex: Integer;
    FSettingText: Boolean;
    FStyle: TComboBoxStyle;
    FOnChange: TNotifyEvent;
    procedure ItemsChanged(Sender: TObject);
    procedure SetItemIndex(AValue: Integer);
    function GetItems: TStrings;
    procedure ShowPicked;
    procedure EnsureList;
    procedure OpenList(AAll: Boolean);
    procedure CloseList;
    procedure Pick(AListIndex: Integer);
    procedure ListPicked(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure CheckFocus(AData: PtrInt);
    procedure ArrowPaint(Sender: TObject);
    procedure ArrowDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function GetDroppedDown: Boolean;
    function GetHintText: TTranslateString;
    procedure SetHintText(const AValue: TTranslateString);
    function GetText: string;
  protected
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetFocus; override;
    property Items: TStrings read GetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property DroppedDown: Boolean read GetDroppedDown;
    property Text: string read GetText;
    { Accepted so it can stand in for a TComboBox; it always behaves as a
      list you can type into. }
    property Style: TComboBoxStyle read FStyle write FStyle;
    property Hint: TTranslateString read GetHintText write SetHintText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { The open list: rows of names, the highlighted one picked by Enter or a
    click; the wheel scrolls, and a thin bar on the right shows where you
    are in a long list (click above or below it to page). }
  TpgnFindList = class(TCustomControl)
  private
    FNames: TStringList;      // Objects: the index in the combo's Items
    FIndex: Integer;
    FTop: Integer;
    FRowH: Integer;
    FRows: Integer;
    FHot: Integer;
    FOnPicked: TNotifyEvent;
    procedure SetIndex(AValue: Integer);
    function RowAt(Y: Integer): Integer;
    function BarRect: TRect;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure MakeVisible;
    property Names: TStringList read FNames;
    property Index: Integer read FIndex write SetIndex;
    property RowH: Integer read FRowH write FRowH;
    property Rows: Integer read FRows write FRows;
    property OnPicked: TNotifyEvent read FOnPicked write FOnPicked;
  end;

implementation

const
  MaxRows = 12;

{ ------------------------------------------------------------ the list }

constructor TpgnFindList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNames := TStringList.Create;
  FIndex := -1;
  FHot := -1;
  FRowH := 20;
  FRows := MaxRows;
  TabStop := False;
  Color := clWindow;
end;

destructor TpgnFindList.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TpgnFindList.SetIndex(AValue: Integer);
begin
  if FNames.Count = 0 then
  begin
    AValue := -1;
  end
  else
  begin
    AValue := EnsureRange(AValue, 0, FNames.Count - 1);
  end;
  FIndex := AValue;
  MakeVisible;
  Invalidate;
end;

{ Scrolls so the highlighted row is in view. }
procedure TpgnFindList.MakeVisible;
begin
  if FIndex < 0 then
  begin
    FTop := 0;
    Exit;
  end;
  if FIndex < FTop then
  begin
    FTop := FIndex;
  end
  else if FIndex >= FTop + FRows then
  begin
    FTop := FIndex - FRows + 1;
  end;
  FTop := EnsureRange(FTop, 0, Max(0, FNames.Count - FRows));
end;

function TpgnFindList.RowAt(Y: Integer): Integer;
begin
  Result := FTop + (Y - 1) div Max(FRowH, 1);
  if (Y < 1) or (Result >= FNames.Count) then
  begin
    Result := -1;
  end;
end;

function TpgnFindList.BarRect: TRect;
var
  TrackH, ThumbH, ThumbY: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if FNames.Count <= FRows then
  begin
    Exit;
  end;
  TrackH := ClientHeight - 2;
  ThumbH := Max(Scale96ToScreen(16), TrackH * FRows div FNames.Count);
  ThumbY := 1 + (TrackH - ThumbH) * FTop div Max(1, FNames.Count - FRows);
  Result := Rect(ClientWidth - Scale96ToScreen(6) - 1, ThumbY, ClientWidth - 2, ThumbY + ThumbH);
end;

procedure TpgnFindList.Paint;
var
  C: TCanvas;
  I, Y, Pad: Integer;
  R, Bar: TRect;
begin
  C := Canvas;
  C.Font.Assign(Font);
  C.Brush.Style := bsSolid;
  C.Brush.Color := clWindow;
  C.FillRect(ClientRect);
  Pad := Scale96ToScreen(6);
  Bar := BarRect;
  for I := FTop to Min(FNames.Count - 1, FTop + FRows - 1) do
  begin
    Y := 1 + (I - FTop) * FRowH;
    R := Rect(1, Y, ClientWidth - 1, Y + FRowH);
    if Bar.Right > 0 then
    begin
      R.Right := Bar.Left - 1;
    end;
    if I = FIndex then
    begin
      C.Brush.Color := clHighlight;
      C.Font.Color := clHighlightText;
      C.FillRect(R);
    end
    else if I = FHot then
    begin
      C.Brush.Color := clBtnFace;
      C.Font.Color := clWindowText;
      C.FillRect(R);
    end
    else
    begin
      C.Font.Color := clWindowText;
    end;
    C.Brush.Style := bsClear;
    C.TextOut(R.Left + Pad, Y + (FRowH - C.TextHeight('Wg')) div 2, FNames[I]);
    C.Brush.Style := bsSolid;
  end;
  if Bar.Right > 0 then
  begin
    C.Brush.Color := clBtnShadow;
    C.FillRect(Bar);
  end;
  C.Brush.Style := bsClear;
  C.Pen.Color := clBtnShadow;
  C.Rectangle(0, 0, ClientWidth, ClientHeight);
  C.Brush.Style := bsSolid;
end;

procedure TpgnFindList.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  R: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  R := RowAt(Y);
  if R <> FHot then
  begin
    FHot := R;
    Invalidate;
  end;
end;

procedure TpgnFindList.MouseLeave;
begin
  inherited MouseLeave;
  if FHot <> -1 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TpgnFindList.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  R: Integer;
  Bar: TRect;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    Exit;
  end;
  Bar := BarRect;
  if (Bar.Right > 0) and (X >= Bar.Left - Scale96ToScreen(4)) then
  begin
    // the bar: page up or down
    if Y < Bar.Top then
    begin
      FTop := Max(0, FTop - FRows);
    end
    else if Y > Bar.Bottom then
    begin
      FTop := Min(Max(0, FNames.Count - FRows), FTop + FRows);
    end;
    Invalidate;
    Exit;
  end;
  R := RowAt(Y);
  if R >= 0 then
  begin
    FIndex := R;
    Invalidate;
    if Assigned(FOnPicked) then
    begin
      FOnPicked(Self);
    end;
  end;
end;

function TpgnFindList.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then
  begin
    FTop := Max(0, FTop - 3);
  end
  else
  begin
    FTop := Min(Max(0, FNames.Count - FRows), FTop + 3);
  end;
  Invalidate;
end;

{ ------------------------------------------------------------- the box }

constructor TpgnFindCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FItemIndex := -1;
  FStyle := csDropDownList;
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.ParentFont := True;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;
  FEdit.OnExit := @EditExit;

  FArrow := TPaintBox.Create(Self);
  FArrow.Parent := Self;
  FArrow.Align := alRight;
  FArrow.Width := Scale96ToScreen(20);
  FArrow.OnPaint := @ArrowPaint;
  FArrow.OnMouseDown := @ArrowDown;

  Height := FEdit.Height;
  Width := Scale96ToScreen(160);
end;

destructor TpgnFindCombo.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FItems.Free;
  inherited Destroy;
end;

function TpgnFindCombo.GetItems: TStrings;
begin
  Result := FItems;
end;

function TpgnFindCombo.GetText: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
  begin
    Result := FItems[FItemIndex];
  end
  else
  begin
    Result := '';
  end;
end;

{ After the list changes, the pick stays if its name is still there. }
procedure TpgnFindCombo.ItemsChanged(Sender: TObject);
var
  Was: string;
begin
  CloseList;
  Was := FEdit.Text;
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) and (FItems[FItemIndex] = Was) then
  begin
    Exit;
  end;
  if Was <> '' then
  begin
    FItemIndex := FItems.IndexOf(Was);
  end
  else
  begin
    FItemIndex := -1;
  end;
  if FItemIndex < 0 then
  begin
    ShowPicked;
  end;
end;

procedure TpgnFindCombo.SetItemIndex(AValue: Integer);
begin
  if (AValue < -1) or (AValue >= FItems.Count) then
  begin
    AValue := -1;
  end;
  FItemIndex := AValue;
  ShowPicked;
end;

procedure TpgnFindCombo.ShowPicked;
begin
  FSettingText := True;
  try
    FEdit.Text := GetText;
  finally
    FSettingText := False;
  end;
end;

procedure TpgnFindCombo.EnsureList;
var
  F: TCustomForm;
begin
  F := GetParentForm(Self);
  if F = nil then
  begin
    Exit;
  end;
  if FList = nil then
  begin
    FList := TpgnFindList.Create(Self);
    FList.Visible := False;
    FList.OnPicked := @ListPicked;
  end;
  if FList.Parent <> F then
  begin
    FList.Parent := F;
  end;
  FList.Font.Assign(Font);
end;

{ Shows the names that contain the typed text (every name when AAll),
  under the box, or above it when there isn't room below. }
procedure TpgnFindCombo.OpenList(AAll: Boolean);
var
  F: TCustomForm;
  Find: string;
  I, RowH, H, W, Wide: Integer;
  P: TPoint;
  C: TCanvas;
begin
  EnsureList;
  if FList = nil then
  begin
    Exit;
  end;
  F := GetParentForm(Self);
  Find := LowerCase(Trim(FEdit.Text));
  if AAll or (Find = LowerCase(GetText)) then
  begin
    Find := '';
  end;
  FList.Names.Clear;
  for I := 0 to FItems.Count - 1 do
  begin
    if (Find = '') or (Pos(Find, LowerCase(FItems[I])) > 0) then
    begin
      FList.Names.AddObject(FItems[I], TObject(PtrInt(I)));
    end;
  end;
  if FList.Names.Count = 0 then
  begin
    CloseList;
    Exit;
  end;
  C := F.Canvas;
  C.Font.Assign(Font);
  RowH := Max(C.TextHeight('Wg') + Scale96ToScreen(6), Scale96ToScreen(20));
  Wide := Width;
  for I := 0 to FList.Names.Count - 1 do
  begin
    Wide := Max(Wide, C.TextWidth(FList.Names[I]) + Scale96ToScreen(28));
  end;
  P := F.ScreenToClient(ClientToScreen(Point(0, Height)));
  W := Min(Wide, Max(Width, F.ClientWidth - P.X - Scale96ToScreen(4)));
  FList.RowH := RowH;
  FList.Rows := Min(FList.Names.Count, MaxRows);
  H := FList.Rows * RowH + 2;
  if (P.Y + H > F.ClientHeight) and (P.Y - Height - H >= 0) then
  begin
    P.Y := P.Y - Height - H;
  end;
  // the current pick highlighted, else the first match
  FList.Index := 0;
  for I := 0 to FList.Names.Count - 1 do
  begin
    if PtrInt(FList.Names.Objects[I]) = FItemIndex then
    begin
      FList.Index := I;
      Break;
    end;
  end;
  FList.SetBounds(P.X, P.Y, W, H);
  FList.Visible := True;
  FList.BringToFront;
  FList.Invalidate;
  FArrow.Invalidate;
end;

procedure TpgnFindCombo.CloseList;
begin
  if (FList <> nil) and FList.Visible then
  begin
    FList.Visible := False;
    FArrow.Invalidate;
  end;
end;

function TpgnFindCombo.GetDroppedDown: Boolean;
begin
  Result := (FList <> nil) and FList.Visible;
end;

procedure TpgnFindCombo.Pick(AListIndex: Integer);
var
  Idx: Integer;
begin
  if (FList = nil) or (AListIndex < 0) or (AListIndex >= FList.Names.Count) then
  begin
    CloseList;
    ShowPicked;
    Exit;
  end;
  Idx := PtrInt(FList.Names.Objects[AListIndex]);
  CloseList;
  if Idx = FItemIndex then
  begin
    ShowPicked;
    FEdit.SelectAll;
    Exit;
  end;
  FItemIndex := Idx;
  ShowPicked;
  FEdit.SelectAll;
  if Assigned(FOnChange) then
  begin
    FOnChange(Self);
  end;
end;

procedure TpgnFindCombo.ListPicked(Sender: TObject);
begin
  Pick(FList.Index);
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
  end;
end;

procedure TpgnFindCombo.EditChange(Sender: TObject);
begin
  if FSettingText then
  begin
    Exit;
  end;
  OpenList(False);
end;

procedure TpgnFindCombo.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_DOWN) and (ssAlt in Shift)) or (Key = VK_F4) then
  begin
    if DroppedDown then
    begin
      CloseList;
    end
    else
    begin
      OpenList(True);
    end;
    Key := 0;
  end
  else if (Key = VK_DOWN) or (Key = VK_UP) or (Key = VK_NEXT) or (Key = VK_PRIOR) then
  begin
    if not DroppedDown then
    begin
      OpenList(True);
    end
    else if Key = VK_DOWN then
    begin
      FList.Index := FList.Index + 1;
    end
    else if Key = VK_UP then
    begin
      FList.Index := FList.Index - 1;
    end
    else if Key = VK_NEXT then
    begin
      FList.Index := FList.Index + MaxRows - 1;
    end
    else
    begin
      FList.Index := FList.Index - MaxRows + 1;
    end;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    if DroppedDown then
    begin
      Pick(FList.Index);
      Key := 0;
    end;
  end
  else if Key = VK_ESCAPE then
  begin
    if DroppedDown or (FEdit.Text <> GetText) then
    begin
      CloseList;
      ShowPicked;
      FEdit.SelectAll;
      Key := 0;
    end;
  end;
end;

{ Focus moving on: a typed name that matches one exactly is picked,
  anything else puts the old pick back. Checked a moment later, after a
  click in the list has been handled. }
procedure TpgnFindCombo.EditExit(Sender: TObject);
begin
  Application.QueueAsyncCall(@CheckFocus, 0);
end;

procedure TpgnFindCombo.CheckFocus(AData: PtrInt);
var
  I: Integer;
begin
  // a click in the list may take the focus for a moment; it gives it back
  if FEdit.Focused or ((FList <> nil) and FList.Focused) then
  begin
    Exit;
  end;
  if DroppedDown then
  begin
    for I := 0 to FList.Names.Count - 1 do
    begin
      if SameText(FList.Names[I], Trim(FEdit.Text)) then
      begin
        Pick(I);
        Exit;
      end;
    end;
  end;
  CloseList;
  ShowPicked;
end;

procedure TpgnFindCombo.ArrowDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if (Button <> mbLeft) or not Enabled then
  begin
    Exit;
  end;
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
  end;
  if DroppedDown then
  begin
    CloseList;
  end
  else
  begin
    OpenList(True);
  end;
end;

{ A small triangle: down, or up while the list is open. }
procedure TpgnFindCombo.ArrowPaint(Sender: TObject);
var
  C: TCanvas;
  CX, CY, D: Integer;
begin
  C := FArrow.Canvas;
  C.Brush.Color := Color;
  C.FillRect(0, 0, FArrow.Width, FArrow.Height);
  if Enabled then
  begin
    C.Brush.Color := clWindowText;
    C.Pen.Color := clWindowText;
  end
  else
  begin
    C.Brush.Color := clGrayText;
    C.Pen.Color := clGrayText;
  end;
  CX := FArrow.Width div 2;
  CY := FArrow.Height div 2;
  D := Scale96ToScreen(4);
  if DroppedDown then
  begin
    C.Polygon([Point(CX - D, CY + D div 2), Point(CX + D, CY + D div 2), Point(CX, CY - D div 2)]);
  end
  else
  begin
    C.Polygon([Point(CX - D, CY - D div 2), Point(CX + D, CY - D div 2), Point(CX, CY + D div 2)]);
  end;
end;

procedure TpgnFindCombo.EnabledChanged;
begin
  inherited EnabledChanged;
  FEdit.Enabled := Enabled;
  if not Enabled then
  begin
    CloseList;
  end;
  FArrow.Invalidate;
end;

procedure TpgnFindCombo.SetFocus;
begin
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
  end;
end;

function TpgnFindCombo.GetHintText: TTranslateString;
begin
  Result := inherited Hint;
end;

procedure TpgnFindCombo.SetHintText(const AValue: TTranslateString);
begin
  inherited Hint := AValue;
  FEdit.Hint := AValue;
  FEdit.ShowHint := AValue <> '';
end;

end.
