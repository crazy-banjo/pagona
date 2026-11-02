// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAboutDlg;

{ Help > About Pagona: the peahen, the version, the copyright, the license
  (GPL 3 or later, no warranty) and where the source is. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  IntfGraphics, FPImage, FPReadPNG, GraphType, pgnTypes, pgnTheme;

procedure ShowAbout(AOwner: TComponent);

implementation

{$I pgnaboutlogo.inc}

{ The built-in peahen PNG as a bitmap APixels square, its transparent
  corners blended onto ABack. Decoded and scaled here (each pixel the
  average of the PNG pixels it covers) rather than by the widget set, so it
  looks the same everywhere. }
{ True when colors written into a bitmap's image data come back with red
  and blue swapped (the LCL's GTK3 widget set reports the wrong byte order;
  Windows doesn't). Tested on one pixel rather than assumed per platform. }
function SwapsRedBlue: Boolean;
var
  Img: TLazIntfImage;
  Bmp: TBitmap;
  Col: TFPColor;
begin
  Img := TLazIntfImage.Create(0, 0);
  Bmp := TBitmap.Create;
  try
    Img.DataDescription := GetDescriptionFromDevice(0, 1, 1);
    Img.SetSize(1, 1);
    Col.Red := $FFFF;
    Col.Green := 0;
    Col.Blue := 0;
    Col.Alpha := alphaOpaque;
    Img.Colors[0, 0] := Col;
    Bmp.LoadFromIntfImage(Img);
    Result := Blue(ColorToRGB(Bmp.Canvas.Pixels[0, 0])) > Red(ColorToRGB(Bmp.Canvas.Pixels[0, 0]));
  finally
    Bmp.Free;
    Img.Free;
  end;
end;

function LogoBitmap(APixels: Integer; ABack: TColor): TBitmap;
var
  Swap: Boolean;
  T: Word;
  Src, Dst: TLazIntfImage;
  Reader: TFPReaderPNG;
  Stream: TMemoryStream;
  X, Y, SX, SY, X0, X1, Y0, Y1, N: Integer;
  R, G, B, A, BR, BG, BB: Double;
  Col: TFPColor;
  Back: TColor;
begin
  Back := ColorToRGB(ABack);
  BR := Red(Back) * 257;
  BG := Green(Back) * 257;
  BB := Blue(Back) * 257;
  Src := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
  Dst := TLazIntfImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(AboutLogoPNG[0], Length(AboutLogoPNG));
    Stream.Position := 0;
    Src.LoadFromStream(Stream, Reader);
    Swap := SwapsRedBlue;
    Dst.DataDescription := GetDescriptionFromDevice(0, APixels, APixels);
    Dst.SetSize(APixels, APixels);
    for Y := 0 to APixels - 1 do
    begin
      Y0 := Y * Src.Height div APixels;
      Y1 := (Y + 1) * Src.Height div APixels;
      if Y1 <= Y0 then
      begin
        Y1 := Y0 + 1;
      end;
      for X := 0 to APixels - 1 do
      begin
        X0 := X * Src.Width div APixels;
        X1 := (X + 1) * Src.Width div APixels;
        if X1 <= X0 then
        begin
          X1 := X0 + 1;
        end;
        R := 0;
        G := 0;
        B := 0;
        N := 0;
        for SY := Y0 to Y1 - 1 do
        begin
          for SX := X0 to X1 - 1 do
          begin
            Col := Src.Colors[SX, SY];
            A := Col.Alpha / 65535;
            R := R + Col.Red * A + BR * (1 - A);
            G := G + Col.Green * A + BG * (1 - A);
            B := B + Col.Blue * A + BB * (1 - A);
            Inc(N);
          end;
        end;
        Col.Red := Round(R / N);
        Col.Green := Round(G / N);
        Col.Blue := Round(B / N);
        Col.Alpha := alphaOpaque;
        if Swap then
        begin
          T := Col.Red;
          Col.Red := Col.Blue;
          Col.Blue := T;
        end;
        Dst.Colors[X, Y] := Col;
      end;
    end;
    Result := TBitmap.Create;
    Result.LoadFromIntfImage(Dst);
  finally
    Stream.Free;
    Reader.Free;
    Dst.Free;
    Src.Free;
  end;
end;

type
  TAboutHelper = class
    procedure LinkClick(Sender: TObject);
  end;

procedure TAboutHelper.LinkClick(Sender: TObject);
begin
  OpenURL(PagonaSourceURL);
end;

procedure ShowAbout(AOwner: TComponent);
var
  F: TForm;
  Img: TImage;
  LName, LVer, LWhat, LCopy, LLicense, LLink: TLabel;
  BOK: TButton;
  Helper: TAboutHelper;
  X, Y, W: Integer;
  Logo: TBitmap;
begin
  Helper := TAboutHelper.Create;
  F := TForm.CreateNew(AOwner);
  try
    SmoothFont(F.Font);
    F.Caption := 'About Pagona';
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := F.Scale96ToScreen(600);
    F.Color := clPgnWork;

    // the app icon's largest picture: the peahen on blue
    Img := TImage.Create(F);
    Img.Parent := F;
    Img.SetBounds(F.Scale96ToScreen(24), F.Scale96ToScreen(24), F.Scale96ToScreen(128), F.Scale96ToScreen(128));
    try
      // the 256-pixel PNG built into the program, not the app icon
      Logo := LogoBitmap(Img.Width, F.Color);
      try
        Img.Picture.Assign(Logo);
      finally
        Logo.Free;
      end;
    except
      on E: Exception do
      begin
        // no picture: the words are enough
      end;
    end;

    X := F.Scale96ToScreen(176);
    W := F.ClientWidth - X - F.Scale96ToScreen(24);
    Y := F.Scale96ToScreen(24);
    LName := TLabel.Create(F);
    LName.Parent := F;
    LName.Caption := 'Pagona';
    LName.Font.Size := 20;
    LName.Font.Style := [fsBold];
    LName.Font.Color := clPgnText;
    LName.SetBounds(X, Y, W, F.Scale96ToScreen(36));
    Inc(Y, F.Scale96ToScreen(40));
    LVer := TLabel.Create(F);
    LVer.Parent := F;
    LVer.Caption := 'Version ' + PagonaVersion;
    LVer.Font.Color := clPgnText;
    LVer.SetBounds(X, Y, W, F.Scale96ToScreen(20));
    Inc(Y, F.Scale96ToScreen(24));
    LWhat := TLabel.Create(F);
    LWhat.Parent := F;
    LWhat.WordWrap := True;
    LWhat.AutoSize := False;
    LWhat.Caption := 'A database client for MySQL, PostgreSQL, Oracle and SQL Server. ' +
      'The name means peahen.';
    LWhat.Font.Color := clPgnText;
    LWhat.SetBounds(X, Y, W, F.Scale96ToScreen(40));
    Inc(Y, F.Scale96ToScreen(46));
    LCopy := TLabel.Create(F);
    LCopy.Parent := F;
    LCopy.Caption := PagonaCopyright;
    LCopy.Font.Color := clPgnText;
    LCopy.SetBounds(X, Y, W, F.Scale96ToScreen(20));
    Inc(Y, F.Scale96ToScreen(28));
    LLicense := TLabel.Create(F);
    LLicense.Parent := F;
    LLicense.WordWrap := True;
    LLicense.AutoSize := False;
    LLicense.Caption := 'This program is free software: you can redistribute it and/or modify it ' +
      'under the terms of the GNU General Public License as published by the Free Software ' +
      'Foundation, either version 3 of the License, or (at your option) any later version.' +
      LineEnding + LineEnding +
      'It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file installed with Pagona, and ' +
      'THIRD-PARTY-NOTICES.md for the libraries it uses.';
    LLicense.Font.Color := clPgnText;
    LLicense.SetBounds(X, Y, W, F.Scale96ToScreen(176));
    Inc(Y, F.Scale96ToScreen(182));
    LLink := TLabel.Create(F);
    LLink.Parent := F;
    LLink.Caption := 'Source code: ' + PagonaSourceURL;
    LLink.Font.Color := clPgnAccent;
    LLink.Font.Style := [fsUnderline];
    LLink.Cursor := crHandPoint;
    LLink.OnClick := @Helper.LinkClick;
    LLink.SetBounds(X, Y, W, F.Scale96ToScreen(20));
    Inc(Y, F.Scale96ToScreen(40));

    BOK := TButton.Create(F);
    BOK.Parent := F;
    BOK.Caption := 'OK';
    BOK.Default := True;
    BOK.Cancel := True;
    BOK.ModalResult := mrOK;
    BOK.SetBounds(F.ClientWidth - F.Scale96ToScreen(24) - F.Scale96ToScreen(90), Y, F.Scale96ToScreen(90),
      F.Scale96ToScreen(30));
    F.ClientHeight := Y + F.Scale96ToScreen(46);
    F.ShowModal;
  finally
    F.Free;
    Helper.Free;
  end;
end;

end.
