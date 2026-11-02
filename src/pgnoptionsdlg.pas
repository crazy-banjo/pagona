// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnOptionsDlg;

{ Tools > Options, built in code. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  pgnSettings, pgnKeymap, pgnTheme;

function EditOptions(AOwner: TComponent; ASettings: TpgnSettings): Boolean;

implementation

function EditOptions(AOwner: TComponent; ASettings: TpgnSettings): Boolean;
var
  F: TForm;
  Y, I, Limit: Integer;
  ERowLimit: TLabeledEdit;
  LKeymap, LHint: TLabel;
  CKeymap: TComboBox;
  CConfirm, CLogAll, CAuto, CAutoSea, CDdl: TCheckBox;
  BOK, BCancel: TButton;
begin
  Result := False;
  F := TForm.CreateNew(AOwner);
  SmoothFont(F.Font);
  try
    F.Caption := 'Options';
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := 480;
    Y := 8;

    ERowLimit := TLabeledEdit.Create(F);
    ERowLimit.Parent := F;
    ERowLimit.LabelPosition := lpAbove;
    ERowLimit.EditLabel.Caption := 'Maximum rows to fetch per query';
    ERowLimit.Left := 16;
    ERowLimit.Top := Y + 18;
    ERowLimit.Width := 120;
    ERowLimit.Text := IntToStr(ASettings.RowLimit);
    Inc(Y, 50);

    LHint := TLabel.Create(F);
    LHint.Parent := F;
    LHint.Caption := '0 = no limit (very large results use a lot of memory)';
    LHint.Left := 16;
    LHint.Top := Y;
    Inc(Y, 30);

    CConfirm := TCheckBox.Create(F);
    CConfirm.Parent := F;
    CConfirm.Caption := 'Ask before running DELETE, TRUNCATE and DROP';
    CConfirm.Left := 16;
    CConfirm.Top := Y;
    CConfirm.Checked := ASettings.ConfirmDestructive;
    Inc(Y, 28);

    CDdl := TCheckBox.Create(F);
    CDdl.Parent := F;
    CDdl.Caption := 'Warn before DDL commits pending changes (Oracle, MySQL)';
    CDdl.Left := 16;
    CDdl.Top := Y;
    CDdl.Checked := ASettings.WarnDdlCommit;
    Inc(Y, 28);

    CLogAll := TCheckBox.Create(F);
    CLogAll.Parent := F;
    CLogAll.Caption := 'Show a message for every statement, even in long scripts';
    CLogAll.Left := 16;
    CLogAll.Top := Y;
    CLogAll.Checked := ASettings.LogEveryStatement;
    Inc(Y, 28);

    CAuto := TCheckBox.Create(F);
    CAuto.Parent := F;
    CAuto.Caption := 'New tabs start with auto-commit on (off: changes wait for Commit)';
    CAuto.Left := 16;
    CAuto.Top := Y;
    CAuto.Checked := ASettings.AutoCommitNewTabs;
    Inc(Y, 28);

    CAutoSea := TCheckBox.Create(F);
    CAutoSea.Parent := F;
    CAutoSea.Caption := 'Seattle tabs start with auto-commit on (as SSMS)';
    CAutoSea.Left := 16;
    CAutoSea.Top := Y;
    CAutoSea.Checked := ASettings.AutoCommitSeattle;
    Inc(Y, 34);

    LKeymap := TLabel.Create(F);
    LKeymap.Parent := F;
    LKeymap.Caption := 'Keymap (Match layout follows the chosen layout)';
    LKeymap.Left := 16;
    LKeymap.Top := Y;
    CKeymap := TComboBox.Create(F);
    CKeymap.Parent := F;
    CKeymap.Style := csDropDownList;
    CKeymap.Left := 16;
    CKeymap.Top := Y + 18;
    CKeymap.Width := 200;
    CKeymap.Items.Add(KeymapMatchLayout + ' (recommended)');
    CKeymap.ItemIndex := 0;
    for I := 0 to High(KeymapNames) do
    begin
      CKeymap.Items.Add(KeymapNames[I]);
      if SameText(KeymapNames[I], ASettings.Keymap) then
      begin
        CKeymap.ItemIndex := I + 1;
      end;
    end;
    Inc(Y, 56);

    BOK := TButton.Create(F);
    BOK.Parent := F;
    BOK.Caption := 'OK';
    BOK.ModalResult := mrOK;
    BOK.Default := True;
    BOK.Width := 90;
    BOK.Left := F.ClientWidth - 2 * (BOK.Width + 12);
    BOK.Top := Y;

    BCancel := TButton.Create(F);
    BCancel.Parent := F;
    BCancel.Caption := 'Cancel';
    BCancel.ModalResult := mrCancel;
    BCancel.Cancel := True;
    BCancel.Width := 90;
    BCancel.Left := F.ClientWidth - (BCancel.Width + 12);
    BCancel.Top := Y;

    F.ClientHeight := Y + BOK.Height + 16;

    if F.ShowModal = mrOK then
    begin
      Limit := StrToIntDef(Trim(ERowLimit.Text), -1);
      if Limit < 0 then
      begin
        MessageDlg('The row limit must be a whole number, 0 or more. It was not changed.',
          mtWarning, [mbOK], 0);
      end
      else
      begin
        ASettings.RowLimit := Limit;
      end;
      ASettings.ConfirmDestructive := CConfirm.Checked;
      ASettings.WarnDdlCommit := CDdl.Checked;
      ASettings.LogEveryStatement := CLogAll.Checked;
      ASettings.AutoCommitNewTabs := CAuto.Checked;
      ASettings.AutoCommitSeattle := CAutoSea.Checked;
      if CKeymap.ItemIndex = 0 then
      begin
        ASettings.Keymap := KeymapMatchLayout;
      end
      else if CKeymap.ItemIndex > 0 then
      begin
        ASettings.Keymap := KeymapNames[CKeymap.ItemIndex - 1];
      end;
      ASettings.Save;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

end.
