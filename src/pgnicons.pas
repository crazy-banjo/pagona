// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnIcons;

{ Pagona's small toolbar icons (Amphibian), drawn from simple shapes on a
  16 x 16 grid. Nothing is copied from another program.

  Two styles:
    Two-tone  ink outlines; the part that says what the button does is in
              its group's color (run green, session orange, DBA purple,
              cancel and rollback red, files and editor blue, text tools
              gray), lightly tinted where it is a shape.
    Bold      shapes filled white with a heavier outline; the action part
              solid color. Used for Run, Run as Script and Stop.
  Disabled icons are faded toward the background.

  Shapes carry the meaning; color only helps the eye.

  Icons are drawn four times larger and averaged down, so edges are smooth
  on every widget set, then kept in a cache. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Math, IntfGraphics, FPImage, GraphType;

type
  TpgnIcon = (icNone, icEditor, icSchema, icNewSession, icEndSession, icSessionBrowser,
    icCommit, icRollback, icUsers, icLocks, icOpen, icSave, icSaveAs, icRun, icScript,
    icStop, icExplain, icDescribe, icHistory, icComment, icUncomment, icUpper, icLower,
    icIndent, icOutdent, icFind,
    // Seattle (SSMS's arrangement)
    icNewQuery, icConnect, icChangeConn, icDisconnect, icRefresh, icFilter, icUndo, icRedo,
    icSaveAll, icActivity);

  TpgnIconStyle = (isTwoTone, isBold);

{ The icon drawn APixels square on ABack; owned by the cache, don't free. }
function IconBitmap(AIcon: TpgnIcon; AStyle: TpgnIconStyle; AEnabled: Boolean;
  ABack: TColor; APixels: Integer): TBitmap;

{ Draws the icon, APixels square, centered in ARect. }
procedure DrawIcon(ACanvas: TCanvas; const ARect: TRect; AIcon: TpgnIcon;
  AStyle: TpgnIconStyle; AEnabled: Boolean; ABack: TColor; APixels: Integer);

implementation

const
  Ss = 4;   // supersampling

type
  TPrimKind = (pkOpen, pkClosed, pkRect, pkCircle);

  TPt = record
    X, Y: Single;
  end;

  TPrim = record
    Kind: TPrimKind;
    Pts: array of TPt;      // pkRect: [top-left, size]; pkCircle: [center, (r, r)]
    Accent: Boolean;
    Fill: Boolean;          // closed shapes: filled (tinted / solid / white)
  end;

  TPrims = array of TPrim;

var
  Cache: TStringList = nil;

function Pt(X, Y: Single): TPt;
begin
  Result.X := X;
  Result.Y := Y;
end;

function Hex(const AValue: string): TColor;
var
  V: LongInt;
begin
  V := StrToInt('$' + AValue);
  Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

function Mix(A, B: TColor; AWeightA: Integer): TColor;
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

function GroupColor(AIcon: TpgnIcon): TColor;
begin
  case AIcon of
    icRun, icScript, icCommit:
      begin
        Result := Hex('2E7D32');
      end;
    icNewSession, icConnect, icChangeConn:
      begin
        Result := Hex('C26A00');
      end;
    icEndSession, icRollback, icStop, icDisconnect:
      begin
        Result := Hex('B3261E');
      end;
    icSessionBrowser, icUsers, icLocks, icActivity:
      begin
        Result := Hex('6A3FA0');
      end;
    icOpen:
      begin
        Result := Hex('B07D00');
      end;
    icExplain, icHistory:
      begin
        Result := Hex('00796B');
      end;
    icComment, icUncomment, icUpper, icLower, icIndent, icOutdent, icFind, icFilter, icUndo, icRedo:
      begin
        Result := Hex('5D6B7A');
      end;
  else
    begin
      Result := Hex('1D5FA8');
    end;
  end;
end;

{ ------------------------------------------------------------- shapes }

procedure Add(var P: TPrims; AKind: TPrimKind; const APts: array of TPt; AAccent, AFill: Boolean);
var
  N, I: Integer;
begin
  N := Length(P);
  SetLength(P, N + 1);
  P[N].Kind := AKind;
  SetLength(P[N].Pts, Length(APts));
  for I := 0 to High(APts) do
  begin
    P[N].Pts[I] := APts[I];
  end;
  P[N].Accent := AAccent;
  P[N].Fill := AFill;
end;

procedure Line(var P: TPrims; X1, Y1, X2, Y2: Single; AAccent: Boolean);
begin
  Add(P, pkOpen, [Pt(X1, Y1), Pt(X2, Y2)], AAccent, False);
end;

procedure Box(var P: TPrims; X, Y, W, H: Single; AAccent, AFill: Boolean);
begin
  Add(P, pkRect, [Pt(X, Y), Pt(W, H)], AAccent, AFill);
end;

procedure Circle(var P: TPrims; CX, CY, R: Single; AAccent, AFill: Boolean);
begin
  Add(P, pkCircle, [Pt(CX, CY), Pt(R, R)], AAccent, AFill);
end;

{ Points along an arc, angles in degrees (0 = right, 90 = down). }
procedure ArcPts(var AList: TPrim; CX, CY, RX, RY, A0, A1: Single);
var
  I, N, K: Integer;
  A: Single;
begin
  N := 12;
  K := Length(AList.Pts);
  SetLength(AList.Pts, K + N + 1);
  for I := 0 to N do
  begin
    A := DegToRad(A0 + (A1 - A0) * I / N);
    AList.Pts[K + I] := Pt(CX + RX * Cos(A), CY + RY * Sin(A));
  end;
end;

procedure AddPts(var AList: TPrim; const APts: array of TPt);
var
  K, I: Integer;
begin
  K := Length(AList.Pts);
  SetLength(AList.Pts, K + Length(APts));
  for I := 0 to High(APts) do
  begin
    AList.Pts[K + I] := APts[I];
  end;
end;

procedure AddPrim(var P: TPrims; const APrim: TPrim);
begin
  SetLength(P, Length(P) + 1);
  P[High(P)] := APrim;
end;

function NewPrim(AKind: TPrimKind; AAccent, AFill: Boolean): TPrim;
begin
  Result.Kind := AKind;
  Result.Pts := nil;
  Result.Accent := AAccent;
  Result.Fill := AFill;
end;

{ A database: a cylinder, drawn in base ink. }
procedure Cylinder(var P: TPrims);
var
  Q: TPrim;
begin
  Q := NewPrim(pkClosed, False, True);
  ArcPts(Q, 7, 3.5, 5, 2, 180, 360);
  ArcPts(Q, 7, 12.5, 5, 2, 0, 180);
  AddPrim(P, Q);
  Q := NewPrim(pkOpen, False, False);
  ArcPts(Q, 7, 3.5, 5, 2, 0, 180);
  AddPrim(P, Q);
end;

function Shapes(AIcon: TpgnIcon): TPrims;
var
  P: TPrims;
  Q: TPrim;
begin
  P := nil;
  case AIcon of
    icEditor:
      begin
        Box(P, 2.5, 1.5, 9, 13, False, True);
        Line(P, 5, 5, 9, 5, False);
        Line(P, 5, 8, 9, 8, False);
        Line(P, 5, 11, 7, 11, False);
        Add(P, pkClosed, [Pt(9, 13), Pt(14, 8), Pt(15.5, 9.5), Pt(10.5, 14.5), Pt(9, 14.5)], True, True);
      end;
    icSchema:
      begin
        Box(P, 1.5, 2.5, 13, 11, False, True);
        Box(P, 1.5, 2.5, 13, 3.5, True, True);
        Line(P, 6, 6, 6, 13.5, False);
        Line(P, 10, 6, 10, 13.5, False);
      end;
    icNewSession:
      begin
        Cylinder(P);
        Line(P, 12.5, 9, 12.5, 15, True);
        Line(P, 9.5, 12, 15.5, 12, True);
      end;
    icEndSession:
      begin
        Cylinder(P);
        Line(P, 10, 9.5, 15, 14.5, True);
        Line(P, 15, 9.5, 10, 14.5, True);
      end;
    icSessionBrowser:
      begin
        Box(P, 1.5, 2.5, 13, 9, False, True);
        Line(P, 5, 14, 11, 14, False);
        Line(P, 8, 11.5, 8, 14, False);
        Line(P, 4, 5.5, 7, 5.5, True);
        Line(P, 4, 8.5, 9, 8.5, True);
        Circle(P, 11, 6.5, 1.6, True, True);
      end;
    icCommit:
      begin
        Circle(P, 8, 8, 6.5, False, True);
        Add(P, pkOpen, [Pt(4.8, 8.2), Pt(7, 10.5), Pt(11.2, 5.9)], True, False);
      end;
    icRollback:
      begin
        Q := NewPrim(pkOpen, False, False);
        AddPts(Q, [Pt(4, 6)]);
        ArcPts(Q, 10, 9.5, 3.5, 3.5, -90, 90);
        AddPts(Q, [Pt(6, 13)]);
        AddPrim(P, Q);
        Add(P, pkOpen, [Pt(6.5, 3.5), Pt(4, 6), Pt(6.5, 8.5)], True, False);
      end;
    icUsers:
      begin
        Circle(P, 8, 5, 3, False, True);
        Q := NewPrim(pkClosed, True, True);
        ArcPts(Q, 8, 14.5, 5.5, 5, 180, 360);
        AddPrim(P, Q);
      end;
    icLocks:
      begin
        Q := NewPrim(pkOpen, False, False);
        AddPts(Q, [Pt(5, 7.5)]);
        ArcPts(Q, 8, 5, 3, 3, 180, 360);
        AddPts(Q, [Pt(11, 7.5)]);
        AddPrim(P, Q);
        Box(P, 3, 7.5, 10, 7, True, True);
        Line(P, 8, 10.5, 8, 12, False);
      end;
    icOpen:
      begin
        Add(P, pkOpen, [Pt(1.5, 13.5), Pt(1.5, 3), Pt(5.5, 3), Pt(7, 4.5), Pt(14, 4.5), Pt(14, 6.5)],
          False, False);
        Add(P, pkClosed, [Pt(1.5, 13.5), Pt(3.5, 7), Pt(15, 7), Pt(13, 13.5)], True, True);
      end;
    icSave:
      begin
        Add(P, pkClosed, [Pt(2, 2), Pt(12, 2), Pt(14, 4), Pt(14, 14), Pt(2, 14)], False, True);
        Box(P, 4.5, 2, 6, 4, True, True);
        Box(P, 4, 9, 8, 5, False, False);
      end;
    icSaveAs:
      begin
        Add(P, pkOpen, [Pt(8, 14), Pt(2, 14), Pt(2, 2), Pt(12, 2), Pt(14, 4), Pt(14, 8)], False, False);
        Box(P, 4.5, 2, 6, 4, True, True);
        Add(P, pkClosed, [Pt(9, 15), Pt(10, 12), Pt(14, 8), Pt(16, 10), Pt(12, 14)], True, True);
      end;
    icRun:
      begin
        Add(P, pkClosed, [Pt(4, 2.5), Pt(14, 8), Pt(4, 13.5)], True, True);
      end;
    icScript:
      begin
        Add(P, pkClosed, [Pt(1.5, 2.5), Pt(8.5, 8), Pt(1.5, 13.5)], True, True);
        Line(P, 9.5, 3.5, 14.5, 3.5, False);
        Line(P, 11, 8, 14.5, 8, False);
        Line(P, 9.5, 12.5, 14.5, 12.5, False);
      end;
    icStop:
      begin
        Box(P, 3, 3, 10, 10, True, True);
      end;
    icExplain:
      begin
        Box(P, 1.5, 1.5, 5, 3.5, True, True);
        Box(P, 9.5, 6.5, 5, 3.5, False, True);
        Box(P, 9.5, 11.5, 5, 3.5, False, True);
        Add(P, pkOpen, [Pt(4, 5), Pt(4, 13.25), Pt(9.5, 13.25)], False, False);
        Line(P, 4, 8.25, 9.5, 8.25, False);
      end;
    icDescribe:
      begin
        Circle(P, 8, 8, 6.5, False, True);
        Line(P, 8, 7, 8, 11.5, True);
        Circle(P, 8, 4.7, 0.9, True, True);
      end;
    icHistory:
      begin
        Circle(P, 8, 8, 6.5, False, True);
        Add(P, pkOpen, [Pt(8, 4), Pt(8, 8), Pt(11, 10)], True, False);
      end;
    icComment:
      begin
        Line(P, 6, 4, 14, 4, False);
        Line(P, 6, 8, 14, 8, False);
        Line(P, 6, 12, 11, 12, False);
        Line(P, 1.5, 4, 3.5, 4, True);
        Line(P, 1.5, 8, 3.5, 8, True);
        Line(P, 1.5, 12, 3.5, 12, True);
      end;
    icUncomment:
      begin
        Line(P, 6, 4, 14, 4, False);
        Line(P, 6, 8, 14, 8, False);
        Line(P, 6, 12, 11, 12, False);
        Line(P, 1.5, 13.5, 4.5, 2.5, True);
      end;
    icUpper:
      begin
        Add(P, pkOpen, [Pt(1.5, 13), Pt(4.5, 3), Pt(7.5, 13)], False, False);
        Line(P, 2.6, 9.5, 6.4, 9.5, False);
        Add(P, pkOpen, [Pt(9, 13), Pt(11.75, 4), Pt(14.5, 13)], True, False);
        Line(P, 10, 10, 13.5, 10, True);
      end;
    icLower:
      begin
        Add(P, pkOpen, [Pt(1.5, 13), Pt(4.5, 3), Pt(7.5, 13)], False, False);
        Line(P, 2.6, 9.5, 6.4, 9.5, False);
        Circle(P, 11.5, 10.5, 2.5, True, False);
        Line(P, 14, 7.5, 14, 13, True);
      end;
    icIndent:
      begin
        Line(P, 7, 3, 14, 3, False);
        Line(P, 7, 8, 14, 8, False);
        Line(P, 7, 13, 14, 13, False);
        Add(P, pkOpen, [Pt(2, 5.5), Pt(4.5, 8), Pt(2, 10.5)], True, False);
      end;
    icOutdent:
      begin
        Line(P, 7, 3, 14, 3, False);
        Line(P, 7, 8, 14, 8, False);
        Line(P, 7, 13, 14, 13, False);
        Add(P, pkOpen, [Pt(4.5, 5.5), Pt(2, 8), Pt(4.5, 10.5)], True, False);
      end;
    icFind:
      begin
        Circle(P, 6.5, 6.5, 4.5, False, True);
        Line(P, 10, 10, 14.5, 14.5, True);
      end;
    icNewQuery:
      begin
        // a page with lines, and a plus
        Add(P, pkClosed, [Pt(2.5, 1.5), Pt(9, 1.5), Pt(11.5, 4), Pt(11.5, 14.5), Pt(2.5, 14.5)], False, True);
        Line(P, 4.5, 6, 9, 6, False);
        Line(P, 4.5, 9, 7, 9, False);
        Line(P, 12.5, 9, 12.5, 15.5, True);
        Line(P, 9.5, 12.25, 15.5, 12.25, True);
      end;
    icConnect:
      begin
        // a plug: body, two prongs, and the cord
        Box(P, 4.5, 6, 7, 5, True, True);
        Line(P, 6.5, 2, 6.5, 6, False);
        Line(P, 9.5, 2, 9.5, 6, False);
        Add(P, pkOpen, [Pt(8, 11), Pt(8, 13.5), Pt(5, 15)], False, False);
      end;
    icChangeConn:
      begin
        Box(P, 1.5, 6, 6, 4.5, True, True);
        Line(P, 3.25, 2.5, 3.25, 6, False);
        Line(P, 5.75, 2.5, 5.75, 6, False);
        Line(P, 4.5, 10.5, 4.5, 14.5, False);
        Add(P, pkOpen, [Pt(9.5, 5), Pt(15, 5)], True, False);
        Add(P, pkOpen, [Pt(13, 3), Pt(15, 5), Pt(13, 7)], True, False);
        Add(P, pkOpen, [Pt(15, 11), Pt(9.5, 11)], True, False);
        Add(P, pkOpen, [Pt(11.5, 9), Pt(9.5, 11), Pt(11.5, 13)], True, False);
      end;
    icDisconnect:
      begin
        Box(P, 2, 6, 6.5, 5, False, True);
        Line(P, 3.75, 2, 3.75, 6, False);
        Line(P, 6.75, 2, 6.75, 6, False);
        Line(P, 5.25, 11, 5.25, 15, False);
        Line(P, 10, 9, 15, 14, True);
        Line(P, 15, 9, 10, 14, True);
      end;
    icRefresh:
      begin
        Q := NewPrim(pkOpen, True, False);
        ArcPts(Q, 8, 8.5, 5.5, 5.5, -60, 250);
        AddPrim(P, Q);
        Add(P, pkOpen, [Pt(10, 2), Pt(11, 4.2), Pt(8.6, 5.2)], True, False);
      end;
    icFilter:
      begin
        Add(P, pkClosed, [Pt(1.5, 2.5), Pt(14.5, 2.5), Pt(9.5, 8.5), Pt(9.5, 14), Pt(6.5, 12.5), Pt(6.5, 8.5)],
          True, True);
      end;
    icUndo:
      begin
        Q := NewPrim(pkOpen, True, False);
        AddPts(Q, [Pt(3, 6.5)]);
        ArcPts(Q, 9, 10, 5, 3.5, -90, 90);
        AddPts(Q, [Pt(6, 13.5)]);
        AddPrim(P, Q);
        Add(P, pkOpen, [Pt(5.5, 4), Pt(3, 6.5), Pt(5.5, 9)], True, False);
      end;
    icRedo:
      begin
        Q := NewPrim(pkOpen, True, False);
        AddPts(Q, [Pt(13, 6.5)]);
        ArcPts(Q, 7, 10, 5, 3.5, -90, -270);
        AddPts(Q, [Pt(10, 13.5)]);
        AddPrim(P, Q);
        Add(P, pkOpen, [Pt(10.5, 4), Pt(13, 6.5), Pt(10.5, 9)], True, False);
      end;
    icSaveAll:
      begin
        Add(P, pkOpen, [Pt(1.5, 11), Pt(1.5, 1.5), Pt(10, 1.5)], False, False);
        Add(P, pkClosed, [Pt(4, 4), Pt(12.5, 4), Pt(14.5, 6), Pt(14.5, 14.5), Pt(4, 14.5)], False, True);
        Box(P, 6, 4, 5, 3.5, True, True);
        Box(P, 6, 10, 6.5, 4.5, False, False);
      end;
    icActivity:
      begin
        Box(P, 1.5, 2.5, 13, 11, False, True);
        Add(P, pkOpen, [Pt(3, 9), Pt(5.5, 9), Pt(7, 5), Pt(9, 12), Pt(10.5, 8), Pt(13, 8)], True, False);
      end;
  end;
  Result := P;
end;

{ ------------------------------------------------------------ drawing }

procedure Render(ACanvas: TCanvas; const P: TPrims; AIcon: TpgnIcon; AStyle: TpgnIconStyle;
  AEnabled: Boolean; ABack: TColor; ASize: Integer);
var
  F: Single;
  I, J: Integer;
  Ink, Grp, Stroke, Fill: TColor;
  W: Single;
  Pts: array of TPoint;
  HasFill: Boolean;

  function C(A: TColor): TColor;
  begin
    if AEnabled then
    begin
      Result := A;
    end
    else
    begin
      Result := Mix(A, ABack, 35);
    end;
  end;

  function X(V: Single): Integer;
  begin
    Result := Round(V * F);
  end;

begin
  F := ASize / 16;
  Ink := C(Hex('2B3440'));
  Grp := C(GroupColor(AIcon));
  ACanvas.Pen.EndCap := pecRound;
  ACanvas.Pen.JoinStyle := pjsRound;
  for I := 0 to High(P) do
  begin
    // colors for this part
    Stroke := Ink;
    HasFill := False;
    Fill := ABack;
    W := 1.3;
    if AStyle = isTwoTone then
    begin
      if P[I].Accent then
      begin
        Stroke := Grp;
        W := 1.6;
        if P[I].Fill then
        begin
          HasFill := True;
          Fill := Mix(Grp, ABack, 22);
        end;
      end;
    end
    else
    begin
      W := 1.5;
      if P[I].Accent then
      begin
        Stroke := Grp;
        W := 1.3;
        if P[I].Fill then
        begin
          HasFill := True;
          Fill := Grp;
        end;
      end
      else if P[I].Fill then
      begin
        HasFill := True;
        Fill := C(clWhite);
      end;
    end;
    ACanvas.Pen.Color := Stroke;
    ACanvas.Pen.Width := Max(1, Round(W * F));
    if HasFill then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := Fill;
    end
    else
    begin
      ACanvas.Brush.Style := bsClear;
    end;
    case P[I].Kind of
      pkRect:
        begin
          ACanvas.Rectangle(X(P[I].Pts[0].X), X(P[I].Pts[0].Y), X(P[I].Pts[0].X + P[I].Pts[1].X),
            X(P[I].Pts[0].Y + P[I].Pts[1].Y));
        end;
      pkCircle:
        begin
          ACanvas.Ellipse(X(P[I].Pts[0].X - P[I].Pts[1].X), X(P[I].Pts[0].Y - P[I].Pts[1].X),
            X(P[I].Pts[0].X + P[I].Pts[1].X), X(P[I].Pts[0].Y + P[I].Pts[1].X));
        end;
    else
      begin
        SetLength(Pts, Length(P[I].Pts));
        for J := 0 to High(Pts) do
        begin
          Pts[J] := Point(X(P[I].Pts[J].X), X(P[I].Pts[J].Y));
        end;
        if P[I].Kind = pkClosed then
        begin
          ACanvas.Polygon(Pts);
        end
        else
        begin
          ACanvas.Polyline(Pts);
        end;
      end;
    end;
  end;
  ACanvas.Brush.Style := bsSolid;
end;

function MakeIcon(AIcon: TpgnIcon; AStyle: TpgnIconStyle; AEnabled: Boolean; ABack: TColor;
  APixels: Integer): TBitmap;
var
  Big: TBitmap;
  Src, Dst: TLazIntfImage;
  X, Y, I, J, N: Integer;
  R, G, B: Cardinal;
  Col: TFPColor;
begin
  Big := TBitmap.Create;
  try
    Big.PixelFormat := pf24bit;
    Big.SetSize(APixels * Ss, APixels * Ss);
    Big.Canvas.Brush.Color := ABack;
    Big.Canvas.FillRect(0, 0, Big.Width, Big.Height);
    Render(Big.Canvas, Shapes(AIcon), AIcon, AStyle, AEnabled, ABack, APixels * Ss);
    Src := Big.CreateIntfImage;
    Dst := TLazIntfImage.Create(0, 0);
    try
      Dst.DataDescription := GetDescriptionFromDevice(0, APixels, APixels);
      Dst.SetSize(APixels, APixels);
      N := Ss * Ss;
      for Y := 0 to APixels - 1 do
      begin
        for X := 0 to APixels - 1 do
        begin
          R := 0;
          G := 0;
          B := 0;
          for J := 0 to Ss - 1 do
          begin
            for I := 0 to Ss - 1 do
            begin
              Col := Src.Colors[X * Ss + I, Y * Ss + J];
              R := R + Col.Red;
              G := G + Col.Green;
              B := B + Col.Blue;
            end;
          end;
          Col.Red := R div Cardinal(N);
          Col.Green := G div Cardinal(N);
          Col.Blue := B div Cardinal(N);
          Col.Alpha := alphaOpaque;
          Dst.Colors[X, Y] := Col;
        end;
      end;
      Result := TBitmap.Create;
      Result.LoadFromIntfImage(Dst);
    finally
      Dst.Free;
      Src.Free;
    end;
  finally
    Big.Free;
  end;
end;

function IconBitmap(AIcon: TpgnIcon; AStyle: TpgnIconStyle; AEnabled: Boolean;
  ABack: TColor; APixels: Integer): TBitmap;
var
  Key: string;
  Idx: Integer;
begin
  if Cache = nil then
  begin
    Cache := TStringList.Create;
    Cache.Sorted := True;
    Cache.OwnsObjects := True;
  end;
  Key := Format('%d|%d|%d|%x|%d', [Ord(AIcon), Ord(AStyle), Ord(AEnabled), ColorToRGB(ABack), APixels]);
  Idx := Cache.IndexOf(Key);
  if Idx >= 0 then
  begin
    Result := TBitmap(Cache.Objects[Idx]);
  end
  else
  begin
    Result := MakeIcon(AIcon, AStyle, AEnabled, ABack, APixels);
    Cache.AddObject(Key, Result);
  end;
end;

procedure DrawIcon(ACanvas: TCanvas; const ARect: TRect; AIcon: TpgnIcon;
  AStyle: TpgnIconStyle; AEnabled: Boolean; ABack: TColor; APixels: Integer);
var
  B: TBitmap;
  Px: Integer;
begin
  if AIcon = icNone then
  begin
    Exit;
  end;
  Px := Min(Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), APixels);
  B := IconBitmap(AIcon, AStyle, AEnabled, ABack, Px);
  ACanvas.Draw((ARect.Left + ARect.Right - Px) div 2, (ARect.Top + ARect.Bottom - Px) div 2, B);
end;

finalization
  FreeAndNil(Cache);
end.
