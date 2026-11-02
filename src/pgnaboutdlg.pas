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
  pgnTypes, pgnTheme;

procedure ShowAbout(AOwner: TComponent);

implementation

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
    Img.Stretch := True;
    Img.Proportional := True;
    try
      Application.Icon.Current := Application.Icon.GetBestIndexForSize(Size(256, 256));
      Img.Picture.Icon.Assign(Application.Icon);
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
