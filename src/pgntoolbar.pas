// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnToolbar;

{ Pagona's toolbar, drawn by Pagona so it looks the same everywhere.

    [+ New Tab] | [> Run] [= Run Script] [# Cancel] | [v Commit] ...

  Flat buttons with a small symbol and a word (the word is always there).
  One button can be "primary" (filled with the accent) and some "outlined"
  (they change data). Each button runs a TAction, so it is enabled and
  disabled with its action.

  People can rearrange it: drag a button to move it; right-click to
  remove a button, add one back, add a separator, or reset to the layout's
  default. The arrangement is a plain string ("newtab,|,run,script") that
  the main window saves per layout. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ActnList, Menus, Forms, LCLType,
  LCLIntf, LCLProc, Types, Math, pgnTheme, pgnIcons;

type
  TpgnGlyph = (glNone, glPlus, glRun, glScript, glStop, glCommit, glRollback,
    glExplain, glDescribe, glComment, glUncomment, glSessions, glLock, glUsers);

  TpgnButtonStyle = (bsFlat, bsPrimary, bsOutline);

  { One kind of button the toolbar can show. }
  TpgnToolDef = class
  public
    Id: string;
    Caption: string;
    Action: TCustomAction;
    Glyph: TpgnGlyph;
    Style: TpgnButtonStyle;
    Icon: TpgnIcon;              // icon-only bars (Amphibian)
    IconStyle: TpgnIconStyle;
    DropMenu: TPopupMenu;        // a drop arrow beside the button opens it
    Labelled: Boolean;           // icon bars: the caption shown beside the icon (Seattle's Execute)
  end;

  { A button or separator as placed on the bar. }
  TpgnToolSlot = record
    Def: TpgnToolDef;    // nil = separator
    R: TRect;
  end;

  TpgnToolbar = class(TCustomControl)
  private
    FDefs: TList;                      // of TpgnToolDef, owned
    FSlots: array of TpgnToolSlot;
    FDefault: string;
    FHot: Integer;
    FDown: Integer;
    FDownX: Integer;
    FDragging: Boolean;
    FDropAt: Integer;                  // slot index the dragged one goes before
    FMenu: TPopupMenu;
    FMenuSlot: Integer;
    FOnChanged: TNotifyEvent;
    FIconOnly: Boolean;
    function S(AValue: Integer): Integer;
    function FindDef(const AId: string): TpgnToolDef;
    function SlotAt(X, Y: Integer): Integer;
    function DropIndexAt(X: Integer): Integer;
    function SlotEnabled(AIndex: Integer): Boolean;
    function DropWidth(ADef: TpgnToolDef): Integer;
    procedure Layout;
    procedure DrawGlyph(AGlyph: TpgnGlyph; const R: TRect; AColor: TColor);
    procedure DrawDrop(AIndex: Integer; AEnabled: Boolean);
    procedure Changed;
    procedure FillRounded(const R: TRect);
    procedure MenuPopup(Sender: TObject);
    procedure MenuRemove(Sender: TObject);
    procedure MenuAdd(Sender: TObject);
    procedure MenuAddSeparator(Sender: TObject);
    procedure MenuReset(Sender: TObject);
    procedure MoveSlot(AFrom, ABefore: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure AddDef(const AId, ACaption: string; AAction: TCustomAction;
      AGlyph: TpgnGlyph; AStyle: TpgnButtonStyle);
    { A button for an icon-only bar; its caption is the tooltip. }
    procedure AddIconDef(const AId, ACaption: string; AAction: TCustomAction;
      AIcon: TpgnIcon; AIconStyle: TpgnIconStyle; ALabelled: Boolean = False);
    { A small arrow beside the button that opens AMenu (as Toad's Commit). }
    procedure SetDropMenu(const AId: string; AMenu: TPopupMenu);
    { "id,id,|,id". Unknown ids are skipped. }
    procedure SetArrangement(const AValue: string);
    function Arrangement: string;
    { The layout's own arrangement, used by "Reset to Layout Default". }
    property DefaultArrangement: string read FDefault write FDefault;
    { Raised after the person rearranges the bar. }
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    { Small square buttons with icons only, names in the tooltips (Amphibian). }
    property IconOnly: Boolean read FIconOnly write FIconOnly;
  end;

implementation

const
  SeparatorId = '|';

function Blend(A, B: TColor; AWeightA: Integer): TColor;
var
  CA, CB: LongInt;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    (Red(CA) * AWeightA + Red(CB) * (100 - AWeightA)) div 100,
    (Green(CA) * AWeightA + Green(CB) * (100 - AWeightA)) div 100,
    (Blue(CA) * AWeightA + Blue(CB) * (100 - AWeightA)) div 100);
end;

function CleanCaption(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '', [rfReplaceAll]);
  Result := StringReplace(Result, '...', '', [rfReplaceAll]);
end;

constructor TpgnToolbar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDefs := TList.Create;
  FHot := -1;
  FDown := -1;
  FDropAt := -1;
  FMenuSlot := -1;
  Color := clPgnBar;
  ParentColor := False;
  DoubleBuffered := True;
  ShowHint := True;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;
  PopupMenu := FMenu;
end;

destructor TpgnToolbar.Destroy;
var
  I: Integer;
begin
  for I := 0 to FDefs.Count - 1 do
  begin
    TpgnToolDef(FDefs[I]).Free;
  end;
  FDefs.Free;
  inherited Destroy;
end;

function TpgnToolbar.S(AValue: Integer): Integer;
begin
  Result := Scale96ToScreen(AValue);
end;

procedure TpgnToolbar.AddDef(const AId, ACaption: string; AAction: TCustomAction;
  AGlyph: TpgnGlyph; AStyle: TpgnButtonStyle);
var
  D: TpgnToolDef;
begin
  D := TpgnToolDef.Create;
  D.Id := AId;
  D.Caption := ACaption;
  D.Action := AAction;
  D.Glyph := AGlyph;
  D.Style := AStyle;
  D.Icon := icNone;
  D.IconStyle := isTwoTone;
  FDefs.Add(D);
end;

procedure TpgnToolbar.SetDropMenu(const AId: string; AMenu: TPopupMenu);
var
  D: TpgnToolDef;
begin
  D := FindDef(AId);
  if D <> nil then
  begin
    D.DropMenu := AMenu;
  end;
  Layout;
  Invalidate;
end;

function TpgnToolbar.DropWidth(ADef: TpgnToolDef): Integer;
begin
  Result := 0;
  if (ADef <> nil) and (ADef.DropMenu <> nil) then
  begin
    Result := S(14);
  end;
end;

procedure TpgnToolbar.AddIconDef(const AId, ACaption: string; AAction: TCustomAction;
  AIcon: TpgnIcon; AIconStyle: TpgnIconStyle; ALabelled: Boolean);
begin
  AddDef(AId, ACaption, AAction, glNone, bsFlat);
  TpgnToolDef(FDefs[FDefs.Count - 1]).Icon := AIcon;
  TpgnToolDef(FDefs[FDefs.Count - 1]).IconStyle := AIconStyle;
  TpgnToolDef(FDefs[FDefs.Count - 1]).Labelled := ALabelled;
end;

function TpgnToolbar.FindDef(const AId: string): TpgnToolDef;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FDefs.Count - 1 do
  begin
    if SameText(TpgnToolDef(FDefs[I]).Id, AId) then
    begin
      Result := TpgnToolDef(FDefs[I]);
      Exit;
    end;
  end;
end;

procedure TpgnToolbar.SetArrangement(const AValue: string);
var
  Parts: TStringList;
  I, N: Integer;
  D: TpgnToolDef;
  Id: string;
  Used: TList;
begin
  Parts := TStringList.Create;
  Used := TList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := AValue;
    SetLength(FSlots, Parts.Count);
    N := 0;
    for I := 0 to Parts.Count - 1 do
    begin
      Id := Trim(Parts[I]);
      if Id = SeparatorId then
      begin
        // no separator first, and never two in a row
        if (N > 0) and (FSlots[N - 1].Def <> nil) then
        begin
          FSlots[N].Def := nil;
          Inc(N);
        end;
      end
      else
      begin
        D := FindDef(Id);
        if (D <> nil) and (Used.IndexOf(D) < 0) then
        begin
          FSlots[N].Def := D;
          Used.Add(D);
          Inc(N);
        end;
      end;
    end;
    // no separator last
    if (N > 0) and (FSlots[N - 1].Def = nil) then
    begin
      Dec(N);
    end;
    SetLength(FSlots, N);
  finally
    Used.Free;
    Parts.Free;
  end;
  FHot := -1;
  FDown := -1;
  Layout;
  Invalidate;
end;

function TpgnToolbar.Arrangement: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FSlots) do
  begin
    if I > 0 then
    begin
      Result := Result + ',';
    end;
    if FSlots[I].Def = nil then
    begin
      Result := Result + SeparatorId;
    end
    else
    begin
      Result := Result + FSlots[I].Def.Id;
    end;
  end;
end;

procedure TpgnToolbar.Layout;
var
  I, X, W, H, Y0: Integer;
begin
  Canvas.Font.Assign(Font);
  X := S(8);
  Y0 := S(5);
  if FIconOnly then
  begin
    X := S(4);
    Y0 := S(3);
  end;
  H := Height - 2 * Y0 - 1;
  for I := 0 to High(FSlots) do
  begin
    // a button whose command is hidden (DBA Mode off) takes no room
    if (FSlots[I].Def <> nil) and (FSlots[I].Def.Action <> nil) and
      not FSlots[I].Def.Action.Visible then
    begin
      FSlots[I].R := Rect(X, Y0, X, Y0 + H);
      Continue;
    end;
    if FSlots[I].Def = nil then
    begin
      W := S(13);
      if FIconOnly then
      begin
        W := S(9);
      end;
    end
    else if FIconOnly and (FSlots[I].Def.Icon <> icNone) and FSlots[I].Def.Labelled then
    begin
      Canvas.Font.Style := [];
      W := S(26) + Canvas.TextWidth(FSlots[I].Def.Caption) + S(6);
    end
    else if FIconOnly and (FSlots[I].Def.Icon <> icNone) then
    begin
      W := S(26);
    end
    else if FIconOnly then
    begin
      Canvas.Font.Style := [];
      W := S(8) + Canvas.TextWidth(FSlots[I].Def.Caption) + S(8);
    end
    else
    begin
      Canvas.Font.Style := [];
      if FSlots[I].Def.Style = bsPrimary then
      begin
        Canvas.Font.Style := [fsBold];
      end;
      W := S(10) + Canvas.TextWidth(FSlots[I].Def.Caption) + S(10);
      if FSlots[I].Def.Glyph <> glNone then
      begin
        W := W + S(14) + S(6);
      end;
    end;
    W := W + DropWidth(FSlots[I].Def);
    FSlots[I].R := Rect(X, Y0, X + W, Y0 + H);
    if FIconOnly then
    begin
      X := X + W + S(1);
    end
    else
    begin
      X := X + W + S(3);
    end;
  end;
end;

procedure TpgnToolbar.Resize;
begin
  inherited Resize;
  Layout;
end;

function TpgnToolbar.SlotEnabled(AIndex: Integer): Boolean;
var
  D: TpgnToolDef;
begin
  D := FSlots[AIndex].Def;
  Result := (D <> nil) and (D.Action <> nil) and D.Action.Enabled and D.Action.Visible;
end;

procedure TpgnToolbar.DrawGlyph(AGlyph: TpgnGlyph; const R: TRect; AColor: TColor);
var
  C: TCanvas;
  CX, CY, U: Integer;
  P: array[0..2] of TPoint;
begin
  C := Canvas;
  CX := (R.Left + R.Right) div 2;
  CY := (R.Top + R.Bottom) div 2;
  U := S(1);
  C.Pen.Color := AColor;
  C.Pen.Width := Max(1, S(2));
  C.Brush.Color := AColor;
  C.Brush.Style := bsSolid;
  case AGlyph of
    glPlus:
      begin
        C.Line(CX - 5 * U, CY, CX + 5 * U + 1, CY);
        C.Line(CX, CY - 5 * U, CX, CY + 5 * U + 1);
      end;
    glRun:
      begin
        C.Pen.Width := 1;
        P[0] := Point(CX - 4 * U, CY - 6 * U);
        P[1] := Point(CX + 6 * U, CY);
        P[2] := Point(CX - 4 * U, CY + 6 * U);
        C.Polygon(P);
      end;
    glScript:
      begin
        C.Line(CX - 6 * U, CY - 4 * U, CX + 6 * U, CY - 4 * U);
        C.Line(CX - 6 * U, CY, CX + 6 * U, CY);
        C.Line(CX - 6 * U, CY + 4 * U, CX + 3 * U, CY + 4 * U);
      end;
    glStop:
      begin
        C.Pen.Width := 1;
        C.Rectangle(CX - 5 * U, CY - 5 * U, CX + 5 * U, CY + 5 * U);
      end;
    glCommit:
      begin
        C.Line(CX - 6 * U, CY, CX - 2 * U, CY + 4 * U);
        C.Line(CX - 2 * U, CY + 4 * U, CX + 6 * U, CY - 5 * U);
      end;
    glRollback:
      begin
        // a hooked arrow pointing back
        C.Brush.Style := bsClear;
        C.Arc(CX - 5 * U, CY - 4 * U, CX + 7 * U, CY + 7 * U, 90 * 16, -180 * 16);
        C.Line(CX + U, CY - 4 * U, CX - 5 * U, CY - 4 * U);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        P[0] := Point(CX - 7 * U, CY - 4 * U);
        P[1] := Point(CX - 3 * U, CY - 8 * U);
        P[2] := Point(CX - 3 * U, CY);
        C.Polygon(P);
      end;
    glExplain:
      begin
        C.Line(CX - 6 * U, CY - 5 * U, CX + 2 * U, CY - 5 * U);
        C.Line(CX - 3 * U, CY, CX + 5 * U, CY);
        C.Line(CX, CY + 5 * U, CX + 7 * U, CY + 5 * U);
      end;
    glDescribe:
      begin
        C.Brush.Style := bsClear;
        C.Pen.Width := Max(1, S(1));
        C.Ellipse(CX - 7 * U, CY - 7 * U, CX + 7 * U, CY + 7 * U);
        C.Pen.Width := Max(1, S(2));
        C.Line(CX, CY - 1 * U, CX, CY + 4 * U);
        C.Line(CX, CY - 4 * U, CX, CY - 3 * U);
      end;
    glSessions:
      begin
        // two people: heads and shoulders
        C.Pen.Width := 1;
        C.Ellipse(CX - 7 * U, CY - 6 * U, CX - 2 * U, CY - U);
        C.Ellipse(CX + 2 * U, CY - 6 * U, CX + 7 * U, CY - U);
        C.Pie(CX - 9 * U, CY + U, CX, CY + 10 * U, CX, CY + 5 * U, CX - 9 * U, CY + 5 * U);
        C.Pie(CX, CY + U, CX + 9 * U, CY + 10 * U, CX + 9 * U, CY + 5 * U, CX, CY + 5 * U);
      end;
    glUsers:
      begin
        // an ID card: a head and shoulders beside two lines
        C.Brush.Style := bsClear;
        C.Pen.Width := Max(1, S(1));
        C.Rectangle(CX - 9 * U, CY - 6 * U, CX + 9 * U, CY + 7 * U);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        C.Ellipse(CX - 6 * U, CY - 4 * U, CX - U, CY + U);
        C.Pie(CX - 7 * U, CY + 2 * U, CX, CY + 12 * U, CX, CY + 7 * U, CX - 7 * U, CY + 7 * U);
        C.Line(CX + 2 * U, CY - 2 * U, CX + 7 * U, CY - 2 * U);
        C.Line(CX + 2 * U, CY + 2 * U, CX + 6 * U, CY + 2 * U);
      end;
    glLock:
      begin
        // a padlock: shackle and body
        C.Brush.Style := bsClear;
        C.Pen.Width := Max(1, S(2));
        C.Arc(CX - 4 * U, CY - 8 * U, CX + 4 * U, CY + 2 * U, 0, 180 * 16);
        C.Line(CX - 4 * U, CY - 3 * U, CX - 4 * U, CY);
        C.Line(CX + 4 * U, CY - 3 * U, CX + 4 * U, CY);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        C.Rectangle(CX - 6 * U, CY, CX + 6 * U, CY + 7 * U);
      end;
    glComment, glUncomment:
      begin
        C.Line(CX - 7 * U, CY, CX - 2 * U, CY);
        C.Line(CX + 2 * U, CY, CX + 7 * U, CY);
        if AGlyph = glUncomment then
        begin
          C.Pen.Width := Max(1, S(1));
          C.Line(CX - 6 * U, CY + 6 * U, CX + 6 * U, CY - 6 * U);
        end;
      end;
  end;
  C.Brush.Style := bsSolid;
  C.Pen.Width := 1;
end;

function GlyphColor(AGlyph: TpgnGlyph): TColor;
begin
  case AGlyph of
    glScript, glExplain, glDescribe:
      begin
        Result := clPgnAccent;
      end;
    glStop, glRollback:
      begin
        Result := clPgnDanger;
      end;
    glCommit:
      begin
        Result := clPgnSafe;
      end;
  else
    begin
      Result := clPgnText;
    end;
  end;
end;

{ A rectangle with softened corners, from a polygon (rounded-rectangle
  drawing differs between widget sets). Uses the canvas's pen and brush. }
procedure TpgnToolbar.FillRounded(const R: TRect);
var
  P: array[0..7] of TPoint;
  C: Integer;
begin
  C := S(3);
  P[0] := Point(R.Left + C, R.Top);
  P[1] := Point(R.Right - 1 - C, R.Top);
  P[2] := Point(R.Right - 1, R.Top + C);
  P[3] := Point(R.Right - 1, R.Bottom - 1 - C);
  P[4] := Point(R.Right - 1 - C, R.Bottom - 1);
  P[5] := Point(R.Left + C, R.Bottom - 1);
  P[6] := Point(R.Left, R.Bottom - 1 - C);
  P[7] := Point(R.Left, R.Top + C);
  Canvas.Polygon(P);
end;

{ The drop arrow of a button with a menu: a thin divider and a small
  triangle at its right end. }
procedure TpgnToolbar.DrawDrop(AIndex: Integer; AEnabled: Boolean);
var
  R: TRect;
  D: TpgnToolDef;
  X, CY, W: Integer;
  P: array[0..2] of TPoint;
begin
  D := FSlots[AIndex].Def;
  W := DropWidth(D);
  if W = 0 then
  begin
    Exit;
  end;
  R := FSlots[AIndex].R;
  X := R.Right - W;
  Canvas.Pen.Color := clPgnLines;
  Canvas.Line(X, R.Top + S(5), X, R.Bottom - S(5));
  CY := (R.Top + R.Bottom) div 2;
  if AEnabled then
  begin
    Canvas.Pen.Color := clPgnText;
    Canvas.Brush.Color := clPgnText;
  end
  else
  begin
    Canvas.Pen.Color := clPgnMuted;
    Canvas.Brush.Color := clPgnMuted;
  end;
  P[0] := Point(X + S(4), CY - S(2));
  P[1] := Point(X + W - S(4), CY - S(2));
  P[2] := Point(X + W div 2, CY + S(2));
  Canvas.Polygon(P);
end;

procedure TpgnToolbar.Paint;
var
  I, TX, TY: Integer;
  R, GR: TRect;
  D: TpgnToolDef;
  En: Boolean;
  Fore, Glyph, Back, Edge: TColor;
begin
  Layout;   // cheap, and always matches the current size and font
  Canvas.Brush.Color := clPgnBar;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clPgnLines;
  Canvas.Line(0, Height - 1, Width, Height - 1);
  Canvas.Font.Assign(Font);

  for I := 0 to High(FSlots) do
  begin
    R := FSlots[I].R;
    D := FSlots[I].Def;
    if R.Right <= R.Left then
    begin
      Continue;   // hidden
    end;
    if D = nil then
    begin
      Canvas.Pen.Color := clPgnLines;
      Canvas.Line((R.Left + R.Right) div 2, R.Top + S(3), (R.Left + R.Right) div 2, R.Bottom - S(3));
      Continue;
    end;

    En := SlotEnabled(I);
    if FIconOnly then
    begin
      Back := clPgnBar;
      if En and ((I = FHot) or (I = FDown)) then
      begin
        Back := clPgnHover;
        Canvas.Brush.Color := Back;
        Canvas.Pen.Color := Blend(clPgnAccent, clPgnBar, 45);
        FillRounded(R);
      end;
      if (D.Icon <> icNone) and D.Labelled then
      begin
        DrawIcon(Canvas, Rect(R.Left, R.Top, R.Left + S(26), R.Bottom), D.Icon, D.IconStyle,
          En, Back, S(16));
        Canvas.Font.Style := [];
        if En then
        begin
          Canvas.Font.Color := clPgnText;
        end
        else
        begin
          Canvas.Font.Color := clPgnMuted;
        end;
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(R.Left + S(26), (R.Top + R.Bottom - Canvas.TextHeight(D.Caption)) div 2, D.Caption);
        Canvas.Brush.Style := bsSolid;
        DrawDrop(I, En);
      end
      else if D.Icon <> icNone then
      begin
        DrawIcon(Canvas, Rect(R.Left, R.Top, R.Right - DropWidth(D), R.Bottom), D.Icon, D.IconStyle,
          En, Back, S(16));
        DrawDrop(I, En);
      end
      else
      begin
        Canvas.Font.Style := [];
        if En then
        begin
          Canvas.Font.Color := clPgnText;
        end
        else
        begin
          Canvas.Font.Color := clPgnMuted;
        end;
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(R.Left + S(8), (R.Top + R.Bottom - Canvas.TextHeight(D.Caption)) div 2, D.Caption);
        Canvas.Brush.Style := bsSolid;
        DrawDrop(I, En);
      end;
      Continue;
    end;
    Fore := clPgnText;
    Glyph := GlyphColor(D.Glyph);
    Back := clNone;
    Edge := clNone;
    case D.Style of
      bsPrimary:
        begin
          Back := clPgnAccent;
          Fore := clWhite;
          Glyph := clWhite;
          if not En then
          begin
            Back := Blend(clPgnAccent, clPgnBar, 40);
          end;
        end;
      bsOutline:
        begin
          Back := clWhite;
          Edge := TColor($00D8CCC4);          // #C4CCD8
        end;
    end;
    if En and (I = FHot) and (D.Style <> bsPrimary) then
    begin
      Back := clPgnHover;
    end;
    if En and (I = FHot) and (D.Style = bsPrimary) then
    begin
      Back := Blend(clPgnAccent, clBlack, 85);
    end;
    if not En and (D.Style <> bsPrimary) then
    begin
      Fore := clPgnMuted;
      Glyph := Blend(Glyph, clPgnBar, 40);
    end;

    if Back <> clNone then
    begin
      Canvas.Brush.Color := Back;
      if Edge <> clNone then
      begin
        Canvas.Pen.Color := Edge;
      end
      else
      begin
        Canvas.Pen.Color := Back;
      end;
      FillRounded(R);
    end;

    TX := R.Left + S(10);
    if D.Glyph <> glNone then
    begin
      GR := Rect(TX, R.Top, TX + S(14), R.Bottom);
      DrawGlyph(D.Glyph, GR, Glyph);
      TX := TX + S(14) + S(6);
    end;
    Canvas.Font.Color := Fore;
    if D.Style = bsPrimary then
    begin
      Canvas.Font.Style := [fsBold];
    end
    else
    begin
      Canvas.Font.Style := [];
    end;
    Canvas.Brush.Style := bsClear;
    TY := (R.Top + R.Bottom - Canvas.TextHeight(D.Caption)) div 2;
    Canvas.TextOut(TX, TY, D.Caption);
    Canvas.Brush.Style := bsSolid;
    DrawDrop(I, En);
  end;

  // where a dragged button will land
  if FDragging and (FDropAt >= 0) then
  begin
    if FDropAt <= High(FSlots) then
    begin
      TX := FSlots[FDropAt].R.Left - S(2);
    end
    else if Length(FSlots) > 0 then
    begin
      TX := FSlots[High(FSlots)].R.Right + S(1);
    end
    else
    begin
      TX := S(8);
    end;
    Canvas.Brush.Color := clPgnAccent;
    Canvas.FillRect(TX - S(1), S(4), TX + S(2), Height - S(5));
  end;
end;

function TpgnToolbar.SlotAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FSlots) do
  begin
    if PtInRect(FSlots[I].R, Point(X, Y)) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnToolbar.DropIndexAt(X: Integer): Integer;
var
  I: Integer;
begin
  Result := Length(FSlots);
  for I := 0 to High(FSlots) do
  begin
    if X < (FSlots[I].R.Left + FSlots[I].R.Right) div 2 then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TpgnToolbar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := SlotAt(X, Y);
    FDownX := X;
    FDragging := False;
    FDropAt := -1;
  end;
end;

procedure TpgnToolbar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: Integer;
  D: TpgnToolDef;
  Tip: string;
begin
  inherited MouseMove(Shift, X, Y);
  if (FDown >= 0) and (ssLeft in Shift) then
  begin
    if (not FDragging) and (Abs(X - FDownX) > S(5)) then
    begin
      FDragging := True;
      Cursor := crDrag;
    end;
    if FDragging then
    begin
      FDropAt := DropIndexAt(X);
      Invalidate;
      Exit;
    end;
  end;

  Hot := SlotAt(X, Y);
  if Hot <> FHot then
  begin
    FHot := Hot;
    Tip := '';
    if FHot >= 0 then
    begin
      D := FSlots[FHot].Def;
      if (D <> nil) and (D.Action <> nil) then
      begin
        Tip := CleanCaption(D.Action.Caption);
        if D.Action.ShortCut <> 0 then
        begin
          Tip := Tip + ' (' + ShortCutToText(D.Action.ShortCut) + ')';
        end;
      end;
    end;
    Application.CancelHint;
    Hint := Tip;
    Invalidate;
  end;
end;

procedure TpgnToolbar.MoveSlot(AFrom, ABefore: Integer);
var
  Item: TpgnToolSlot;
  I, Dest: Integer;
begin
  if (AFrom < 0) or (AFrom > High(FSlots)) then
  begin
    Exit;
  end;
  Dest := ABefore;
  if Dest > AFrom then
  begin
    Dec(Dest);
  end;
  if Dest = AFrom then
  begin
    Exit;
  end;
  Item := FSlots[AFrom];
  for I := AFrom to High(FSlots) - 1 do
  begin
    FSlots[I] := FSlots[I + 1];
  end;
  for I := High(FSlots) downto Dest + 1 do
  begin
    FSlots[I] := FSlots[I - 1];
  end;
  FSlots[Dest] := Item;
  // tidy separators (none first, last, or doubled) via the string form
  SetArrangement(Arrangement);
  Changed;
end;

procedure TpgnToolbar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Slot: Integer;
  D: TpgnToolDef;
  P: TPoint;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    Exit;
  end;
  if FDragging then
  begin
    FDragging := False;
    Cursor := crDefault;
    MoveSlot(FDown, FDropAt);
    FDown := -1;
    FDropAt := -1;
    Invalidate;
    Exit;
  end;
  Slot := SlotAt(X, Y);
  if (Slot >= 0) and (Slot = FDown) and SlotEnabled(Slot) then
  begin
    D := FSlots[Slot].Def;
    FDown := -1;
    if (D.DropMenu <> nil) and (X >= FSlots[Slot].R.Right - DropWidth(D)) then
    begin
      // the arrow: the button's menu
      P := ClientToScreen(Point(FSlots[Slot].R.Left, FSlots[Slot].R.Bottom));
      D.DropMenu.PopUp(P.X, P.Y);
    end
    else
    begin
      D.Action.Execute;
    end;
  end;
  FDown := -1;
end;

procedure TpgnToolbar.MouseLeave;
begin
  inherited MouseLeave;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TpgnToolbar.Changed;
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

{ ---------------------------------------------------- right-click menu }

procedure TpgnToolbar.MenuPopup(Sender: TObject);
var
  P: TPoint;
  Item, AddItem: TMenuItem;
  I, J: Integer;
  D: TpgnToolDef;
  Shown: Boolean;
begin
  FMenu.Items.Clear;
  P := ScreenToClient(Mouse.CursorPos);
  FMenuSlot := SlotAt(P.X, P.Y);

  if (FMenuSlot >= 0) then
  begin
    Item := TMenuItem.Create(FMenu);
    if FSlots[FMenuSlot].Def = nil then
    begin
      Item.Caption := 'Remove Separator';
    end
    else
    begin
      Item.Caption := 'Remove "' + FSlots[FMenuSlot].Def.Caption + '"';
    end;
    Item.OnClick := @MenuRemove;
    FMenu.Items.Add(Item);
  end;

  AddItem := TMenuItem.Create(FMenu);
  AddItem.Caption := 'Add Button';
  FMenu.Items.Add(AddItem);
  for I := 0 to FDefs.Count - 1 do
  begin
    D := TpgnToolDef(FDefs[I]);
    Shown := False;
    for J := 0 to High(FSlots) do
    begin
      if FSlots[J].Def = D then
      begin
        Shown := True;
      end;
    end;
    if (D.Action <> nil) and not D.Action.Visible then
    begin
      Shown := True;   // not on offer while its command is hidden
    end;
    if not Shown then
    begin
      Item := TMenuItem.Create(FMenu);
      Item.Caption := D.Caption;
      Item.Tag := I;
      Item.OnClick := @MenuAdd;
      AddItem.Add(Item);
    end;
  end;
  AddItem.Enabled := AddItem.Count > 0;

  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Add Separator';
  Item.OnClick := @MenuAddSeparator;
  FMenu.Items.Add(Item);

  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  FMenu.Items.Add(Item);

  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Drag a button to move it';
  Item.Enabled := False;
  FMenu.Items.Add(Item);

  Item := TMenuItem.Create(FMenu);
  Item.Caption := 'Reset to Layout Default';
  Item.OnClick := @MenuReset;
  FMenu.Items.Add(Item);
end;

procedure TpgnToolbar.MenuRemove(Sender: TObject);
var
  I: Integer;
begin
  if (FMenuSlot < 0) or (FMenuSlot > High(FSlots)) then
  begin
    Exit;
  end;
  for I := FMenuSlot to High(FSlots) - 1 do
  begin
    FSlots[I] := FSlots[I + 1];
  end;
  SetLength(FSlots, Length(FSlots) - 1);
  SetArrangement(Arrangement);
  Changed;
end;

{ New buttons go where the menu was opened: after the button clicked on,
  or at the end. }
procedure TpgnToolbar.MenuAdd(Sender: TObject);
var
  A, Id: string;
  Parts: TStringList;
begin
  Id := TpgnToolDef(FDefs[(Sender as TMenuItem).Tag]).Id;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Arrangement;
    if (FMenuSlot >= 0) and (FMenuSlot < Parts.Count) then
    begin
      Parts.Insert(FMenuSlot + 1, Id);
    end
    else
    begin
      Parts.Add(Id);
    end;
    A := Parts.DelimitedText;
  finally
    Parts.Free;
  end;
  SetArrangement(A);
  Changed;
end;

procedure TpgnToolbar.MenuAddSeparator(Sender: TObject);
var
  A: string;
  Parts: TStringList;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Arrangement;
    if (FMenuSlot >= 0) and (FMenuSlot < Parts.Count) then
    begin
      Parts.Insert(FMenuSlot + 1, SeparatorId);
    end
    else
    begin
      Parts.Add(SeparatorId);
    end;
    A := Parts.DelimitedText;
  finally
    Parts.Free;
  end;
  SetArrangement(A);
  Changed;
end;

procedure TpgnToolbar.MenuReset(Sender: TObject);
begin
  SetArrangement(FDefault);
  Changed;
end;

end.
