// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnStatusBar;

{ Pagona's status bar, drawn by Pagona so it looks the same everywhere.

    [PROD] dev9 · MySQL 8.0.36 | 2 uncommitted statements | 1,000 rows 0.4 s |  Ln 2, Col 9

  Segment 0 can start with an environment chip (the environment's short
  name on its color). Segment 1 can be marked as a warning: red text on a
  light red background, for uncommitted work. The last segment is right
  aligned. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types, Math, pgnTypes, pgnTheme;

type
  TpgnSegmentClickEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TpgnStatusBar = class(TCustomControl)
  private
    FOnSegmentClick: TpgnSegmentClickEvent;
    FTexts: array of string;
    FWidths: array of Integer;     // 96-dpi widths; 0 = take the rest
    FEnv: TpgnEnvironment;
    FWarn: Boolean;
    function GetText(AIndex: Integer): string;
    procedure SetText(AIndex: Integer; const AValue: string);
    procedure SetEnv(AValue: TpgnEnvironment);
    procedure SetWarn(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    { The segment under X, or -1. }
    function SegmentAt(X: Integer): Integer;
    property OnSegmentClick: TpgnSegmentClickEvent read FOnSegmentClick write FOnSegmentClick;
    constructor Create(AOwner: TComponent); override;
    { Defines the segments: widths at 96 dpi, 0 for the one that stretches. }
    procedure SetSegments(const AWidths: array of Integer);
    property Texts[AIndex: Integer]: string read GetText write SetText;
    property Env: TpgnEnvironment read FEnv write SetEnv;
    property Warn: Boolean read FWarn write SetWarn;
  end;

implementation

constructor TpgnStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnv := enNone;
  FWarn := False;
  Color := clPgnStatus;
  ParentColor := False;
  DoubleBuffered := True;
  Height := Scale96ToScreen(26);
end;

procedure TpgnStatusBar.SetSegments(const AWidths: array of Integer);
var
  I: Integer;
begin
  SetLength(FWidths, Length(AWidths));
  SetLength(FTexts, Length(AWidths));
  for I := 0 to High(AWidths) do
  begin
    FWidths[I] := AWidths[I];
    FTexts[I] := '';
  end;
  Invalidate;
end;

function TpgnStatusBar.GetText(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FTexts)) then
  begin
    Result := FTexts[AIndex];
  end;
end;

procedure TpgnStatusBar.SetText(AIndex: Integer; const AValue: string);
begin
  if (AIndex >= 0) and (AIndex <= High(FTexts)) and (FTexts[AIndex] <> AValue) then
  begin
    FTexts[AIndex] := AValue;
    Invalidate;
  end;
end;

procedure TpgnStatusBar.SetEnv(AValue: TpgnEnvironment);
begin
  if FEnv <> AValue then
  begin
    FEnv := AValue;
    Invalidate;
  end;
end;

procedure TpgnStatusBar.SetWarn(AValue: Boolean);
begin
  if FWarn <> AValue then
  begin
    FWarn := AValue;
    Invalidate;
  end;
end;

function TpgnStatusBar.SegmentAt(X: Integer): Integer;
var
  I, Fixed, Rest, SegLeft, W: Integer;
begin
  Result := -1;
  Fixed := 0;
  for I := 0 to High(FWidths) do
  begin
    Fixed := Fixed + Scale96ToScreen(FWidths[I]);
  end;
  Rest := Max(0, Width - Fixed);
  SegLeft := 0;
  for I := 0 to High(FWidths) do
  begin
    if FWidths[I] = 0 then
    begin
      W := Rest;
    end
    else
    begin
      W := Scale96ToScreen(FWidths[I]);
    end;
    if (X >= SegLeft) and (X < SegLeft + W) then
    begin
      Result := I;
      Exit;
    end;
    SegLeft := SegLeft + W;
  end;
end;

procedure TpgnStatusBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  I := SegmentAt(X);
  if (Button = mbLeft) and (I >= 0) and Assigned(FOnSegmentClick) then
  begin
    FOnSegmentClick(Self, I);
  end;
end;

procedure TpgnStatusBar.Paint;
var
  I, X, W, Fixed, Rest, TY, Pad: Integer;
  R, Chip: TRect;
  Look: TpgnEnvLook;
  S: string;
begin
  Canvas.Font.Assign(Font);
  Canvas.Brush.Color := clPgnStatus;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clPgnStatusLines;
  Canvas.Line(0, 0, Width, 0);
  Pad := Scale96ToScreen(8);
  TY := (Height - Canvas.TextHeight('Ag')) div 2;

  Fixed := 0;
  for I := 0 to High(FWidths) do
  begin
    Fixed := Fixed + Scale96ToScreen(FWidths[I]);
  end;
  Rest := Width - Fixed;
  if Rest < 0 then
  begin
    Rest := 0;
  end;

  X := 0;
  for I := 0 to High(FWidths) do
  begin
    if FWidths[I] = 0 then
    begin
      W := Rest;
    end
    else
    begin
      W := Scale96ToScreen(FWidths[I]);
    end;
    R := Rect(X, 1, X + W, Height);

    Canvas.Font.Style := [];
    Canvas.Font.Color := clPgnStatusText;
    if (I = 1) and FWarn then
    begin
      Canvas.Brush.Color := EnvironmentLook(enProduction).Back;
      Canvas.FillRect(R);
      Canvas.Font.Color := clPgnDanger;
      Canvas.Font.Style := [fsBold];
    end;

    Canvas.Brush.Style := bsClear;
    S := FTexts[I];
    if (I = 0) and (FEnv <> enNone) then
    begin
      Look := EnvironmentLook(FEnv);
      Canvas.Font.Style := [fsBold];
      Chip := Rect(R.Left + Pad, R.Top + Scale96ToScreen(4),
        R.Left + Pad + Canvas.TextWidth(EnvironmentShort[FEnv]) + Scale96ToScreen(8),
        R.Bottom - Scale96ToScreen(4));
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := Look.Back;
      Canvas.Pen.Color := Look.Border;
      Canvas.Rectangle(Chip);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := Look.Text;
      Canvas.TextOut(Chip.Left + Scale96ToScreen(4), TY, EnvironmentShort[FEnv]);
      Canvas.Font.Style := [];
      Canvas.Font.Color := clPgnStatusText;
      Canvas.TextRect(Rect(Chip.Right + Scale96ToScreen(6), R.Top, R.Right - Pad, R.Bottom),
        Chip.Right + Scale96ToScreen(6), TY, S);
    end
    else if I = High(FWidths) then
    begin
      // last segment: right aligned
      Canvas.TextOut(R.Right - Pad - Canvas.TextWidth(S), TY, S);
    end
    else
    begin
      Canvas.TextRect(Rect(R.Left + Pad, R.Top, R.Right - Pad, R.Bottom), R.Left + Pad, TY, S);
    end;
    Canvas.Brush.Style := bsSolid;

    // divider
    if I < High(FWidths) then
    begin
      Canvas.Pen.Color := clPgnStatusLines;
      Canvas.Line(R.Right - 1, Scale96ToScreen(5), R.Right - 1, Height - Scale96ToScreen(5));
    end;
    X := X + W;
  end;
end;

end.
