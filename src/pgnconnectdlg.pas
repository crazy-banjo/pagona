// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnConnectDlg;

{ Add/edit connection dialog, built in code. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, pgnTypes, pgnColors, pgnTns, pgnTheme;

function EditConnection(AOwner: TComponent; var AInfo: TpgnConnectionInfo): Boolean;

implementation

type
  { Keeps the port field on the chosen type's default, unless someone
    typed a port of their own. }
  TPortFollower = class
  public
    Engine: TComboBox;
    Port: TCustomEdit;
    Shown: TpgnEngine;
    // Oracle only: the TNS alias list, read from tnsnames.ora
    TnsAlias: TComboBox;
    TnsFile: TCustomEdit;
    Library_: TCustomEdit;
    TnsNote: TLabel;
    // SQL Server only: authentication and encryption, as SSMS's Connect dialog
    SqlAuth: TComboBox;
    SqlEncrypt: TComboBox;
    SqlTrust: TCheckBox;
    UseTls: TCheckBox;
    procedure EngineChange(Sender: TObject);
    procedure SqlFields;
    procedure TnsChange(Sender: TObject);
    procedure FillAliases;
  end;

procedure TPortFollower.FillAliases;
var
  F, Keep: string;
  List: TpgnStringArray;
  I: Integer;
  Oracle: Boolean;
begin
  Oracle := (Engine.ItemIndex >= 0) and (TpgnEngine(Engine.ItemIndex) = feOracle);
  TnsAlias.Enabled := Oracle;
  TnsFile.Enabled := Oracle;
  if not Oracle then
  begin
    TnsNote.Caption := 'TNS settings are for Oracle connections.';
    Exit;
  end;
  Keep := TnsAlias.Text;
  F := FindTnsFile(Trim(TnsFile.Text), Trim(Library_.Text));
  TnsAlias.Items.Clear;
  TnsAlias.Items.Add('');   // none: use host, port and service name
  if F = '' then
  begin
    TnsNote.Caption := 'No tnsnames.ora found: type an alias, or use host, port and service name.';
    TnsNote.Hint := 'Looked in TNS_ADMIN, the client library''s folder and ORACLE_HOME';
  end
  else
  begin
    List := TnsAliases(F);
    for I := 0 to High(List) do
    begin
      TnsAlias.Items.Add(List[I]);
    end;
    TnsNote.Caption := IntToStr(Length(List)) + ' aliases in ' + ExtractFileName(ExcludeTrailingPathDelimiter(
      ExtractFilePath(F))) + PathDelim + ExtractFileName(F) + ' (point at it for the full path)';
    TnsNote.Hint := F;
  end;
  TnsAlias.Text := Keep;
end;

procedure TPortFollower.SqlFields;
var
  Sql: Boolean;
begin
  Sql := (Engine.ItemIndex >= 0) and (TpgnEngine(Engine.ItemIndex) = feSQLServer);
  SqlAuth.Enabled := Sql;
  SqlEncrypt.Enabled := Sql;
  SqlTrust.Enabled := Sql;
  // SQL Server's Encrypt setting takes the place of Use TLS
  UseTls.Enabled := not Sql;
end;

procedure TPortFollower.TnsChange(Sender: TObject);
begin
  FillAliases;
end;

procedure TPortFollower.EngineChange(Sender: TObject);
var
  NewEngine: TpgnEngine;
begin
  if Engine.ItemIndex < 0 then
  begin
    Exit;
  end;
  NewEngine := TpgnEngine(Engine.ItemIndex);
  if StrToIntDef(Trim(Port.Text), -1) = EngineDefaultPort(Shown) then
  begin
    Port.Text := IntToStr(EngineDefaultPort(NewEngine));
  end;
  Shown := NewEngine;
  FillAliases;
  SqlFields;
end;

function EditConnection(AOwner: TComponent; var AInfo: TpgnConnectionInfo): Boolean;
var
  F: TForm;
  Y: Integer;
  EName, EHost, EPort, EUser, EDatabase, ELibrary, ECAFile, ETnsFile: TLabeledEdit;
  LEngine, LNote, LColor, LEnv, LTns, LTnsNote, LAuth, LEnc: TLabel;
  CEngine, CColor, CEnv, CTns, CAuth, CEnc: TComboBox;
  CTrust: TCheckBox;
  En: TpgnEnvironment;
  I: Integer;
  CTLS: TCheckBox;
  BOK, BCancel: TButton;
  E: TpgnEngine;
  Follower: TPortFollower;
  CX, ColW, LeftY: Integer;   // two columns: the connection, then the client and security

  function MakeEdit(const ACaption, AValue: string): TLabeledEdit;
  begin
    Result := TLabeledEdit.Create(F);
    Result.Parent := F;
    Result.LabelPosition := lpAbove;
    Result.EditLabel.Caption := ACaption;
    Result.Left := CX;
    Result.Top := Y + 18;
    Result.Width := ColW;
    Result.Text := AValue;
    Inc(Y, 52);
  end;

begin
  Result := False;
  Follower := nil;
  F := TForm.CreateNew(AOwner);
  SmoothFont(F.Font);
  try
    F.Caption := 'Connection';
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := 780;
    CX := 16;
    ColW := 360;
    Y := 8;

    LEngine := TLabel.Create(F);
    LEngine.Parent := F;
    LEngine.Caption := 'Database type';
    LEngine.Left := 16;
    LEngine.Top := Y;
    CEngine := TComboBox.Create(F);
    CEngine.Parent := F;
    CEngine.Style := csDropDownList;
    CEngine.Left := 16;
    CEngine.Top := Y + 18;
    CEngine.Width := 200;
    for E := Low(TpgnEngine) to High(TpgnEngine) do
    begin
      CEngine.Items.Add(EngineCaptions[E]);
    end;
    CEngine.ItemIndex := Ord(AInfo.Engine);
    Inc(Y, 52);

    EName := MakeEdit('Name', AInfo.Name);

    LEnv := TLabel.Create(F);
    LEnv.Parent := F;
    LEnv.Caption := 'Environment (shown as text on tabs and warnings)';
    LEnv.Left := 16;
    LEnv.Top := Y;
    CEnv := TComboBox.Create(F);
    CEnv.Parent := F;
    CEnv.Style := csDropDownList;
    CEnv.Left := 16;
    CEnv.Top := Y + 18;
    CEnv.Width := 200;
    for En := Low(TpgnEnvironment) to High(TpgnEnvironment) do
    begin
      CEnv.Items.Add(EnvironmentCaptions[En]);
    end;
    CEnv.ItemIndex := Ord(AInfo.Environment);
    Inc(Y, 52);

    LColor := TLabel.Create(F);
    LColor.Parent := F;
    LColor.Caption := 'Color (optional, personal preference)';
    LColor.Left := 16;
    LColor.Top := Y;
    CColor := TComboBox.Create(F);
    CColor.Parent := F;
    CColor.Style := csDropDownList;
    CColor.Left := 16;
    CColor.Top := Y + 18;
    CColor.Width := 200;
    for I := 0 to ColorPresetCount - 1 do
    begin
      CColor.Items.Add(ColorPreset(I).Name);
    end;
    if ColorPresetIndex(AInfo.Color) >= 0 then
    begin
      CColor.ItemIndex := ColorPresetIndex(AInfo.Color);
    end
    else
    begin
      // a color set outside the preset list: keep it selectable
      CColor.ItemIndex := CColor.Items.Add('Custom');
    end;
    Inc(Y, 52);

    EHost := MakeEdit('Host or server name (e.g. HOMEONE\SQLEXPRESS)', AInfo.Host);
    EPort := MakeEdit('Port', IntToStr(AInfo.Port));
    Follower := TPortFollower.Create;
    Follower.Engine := CEngine;
    Follower.Port := EPort;
    Follower.Shown := AInfo.Engine;
    CEngine.OnChange := @Follower.EngineChange;
    EUser := MakeEdit('User', AInfo.User);
    EDatabase := MakeEdit('Default database (Oracle: service name, if no alias)',
      AInfo.DefaultDatabase);
    // the second column
    LeftY := Y;
    Y := 8;
    CX := 404;
    {$IFDEF WINDOWS}
    ELibrary := MakeEdit('Client library or ODBC driver (optional)', AInfo.ClientLibrary);
    {$ELSE}
    ELibrary := MakeEdit('Client library or ODBC driver (optional)', AInfo.ClientLibrary);
    {$ENDIF}
    ELibrary.Hint := 'e.g. oci.dll, libpq.dll, or for SQL Server an ODBC driver name such as ' +
      '"ODBC Driver 18 for SQL Server" (empty: the first one installed)';
    ELibrary.ShowHint := True;

    // Oracle: a TNS alias from tnsnames.ora, as Toad uses
    LTns := TLabel.Create(F);
    LTns.Parent := F;
    LTns.Caption := 'TNS alias (Oracle; empty: host, port, service)';
    LTns.Left := CX;
    LTns.Top := Y;
    CTns := TComboBox.Create(F);
    CTns.Parent := F;
    CTns.Style := csDropDown;
    CTns.Left := CX;
    CTns.Top := Y + 18;
    CTns.Width := 260;
    CTns.Text := AInfo.TnsAlias;
    Inc(Y, 52);
    ETnsFile := MakeEdit('tnsnames.ora file or folder (Oracle, optional)',
      AInfo.TnsFile);
    LTnsNote := TLabel.Create(F);
    LTnsNote.Parent := F;
    LTnsNote.ShowHint := True;
    LTnsNote.Left := CX;
    LTnsNote.Top := Y - 2;
    Inc(Y, 24);
    Follower.TnsAlias := CTns;
    Follower.TnsFile := ETnsFile;
    Follower.Library_ := ELibrary;
    Follower.TnsNote := LTnsNote;
    ETnsFile.OnEditingDone := @Follower.TnsChange;
    ELibrary.OnEditingDone := @Follower.TnsChange;
    Follower.FillAliases;

    CTLS := TCheckBox.Create(F);
    CTLS.Parent := F;
    CTLS.Caption := 'Use TLS';
    CTLS.Left := CX;
    CTLS.Top := Y;
    CTLS.Checked := AInfo.UseTLS;
    Inc(Y, 28);

    ECAFile := MakeEdit('TLS CA certificate file (optional)', AInfo.TLSCAFile);

    // SQL Server, as SSMS's Connect to Server
    LAuth := TLabel.Create(F);
    LAuth.Parent := F;
    LAuth.Caption := 'Authentication (SQL Server)';
    LAuth.Left := CX;
    LAuth.Top := Y;
    CAuth := TComboBox.Create(F);
    CAuth.Parent := F;
    CAuth.Style := csDropDownList;
    CAuth.Left := CX;
    CAuth.Top := Y + 18;
    CAuth.Width := 230;
    CAuth.Items.Add('SQL Server Authentication');
    CAuth.Items.Add('Windows Authentication');
    if AInfo.WindowsAuth then
    begin
      CAuth.ItemIndex := 1;
    end
    else
    begin
      CAuth.ItemIndex := 0;
    end;
    LEnc := TLabel.Create(F);
    LEnc.Parent := F;
    LEnc.Caption := 'Encrypt';
    LEnc.Left := CX + 246;
    LEnc.Top := Y;
    CEnc := TComboBox.Create(F);
    CEnc.Parent := F;
    CEnc.Style := csDropDownList;
    CEnc.Left := CX + 246;
    CEnc.Top := Y + 18;
    CEnc.Width := 120;
    CEnc.Items.Add('Mandatory');
    CEnc.Items.Add('Optional');
    CEnc.Items.Add('Strict');
    CEnc.ItemIndex := CEnc.Items.IndexOf(AInfo.Encrypt);
    if CEnc.ItemIndex < 0 then
    begin
      CEnc.ItemIndex := 0;
    end;
    Inc(Y, 52);
    CTrust := TCheckBox.Create(F);
    CTrust.Parent := F;
    CTrust.Caption := 'Trust server certificate (SQL Server)';
    CTrust.Left := CX;
    CTrust.Top := Y;
    CTrust.Checked := AInfo.TrustServerCert;
    Inc(Y, 28);
    Follower.SqlAuth := CAuth;
    Follower.SqlEncrypt := CEnc;
    Follower.SqlTrust := CTrust;
    Follower.UseTls := CTLS;
    Follower.SqlFields;

    if LeftY > Y then
    begin
      Y := LeftY;
    end;
    CX := 16;
    LNote := TLabel.Create(F);
    LNote.Parent := F;
    LNote.Caption := 'The password is asked for when you connect and is never saved.';
    LNote.Left := CX;
    LNote.Top := Y;
    Inc(Y, 28);

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
      if CEngine.ItemIndex >= 0 then
      begin
        AInfo.Engine := TpgnEngine(CEngine.ItemIndex);
      end;
      AInfo.Host := Trim(EHost.Text);
      AInfo.Name := Trim(EName.Text);
      if (AInfo.Name = '') and (Trim(CTns.Text) <> '') then
      begin
        AInfo.Name := Trim(CTns.Text);
      end;
      if AInfo.Name = '' then
      begin
        AInfo.Name := AInfo.Host;
      end;
      AInfo.Port := StrToIntDef(Trim(EPort.Text), EngineDefaultPort(AInfo.Engine));
      AInfo.User := Trim(EUser.Text);
      AInfo.DefaultDatabase := Trim(EDatabase.Text);
      AInfo.ClientLibrary := Trim(ELibrary.Text);
      AInfo.UseTLS := CTLS.Checked;
      AInfo.TLSCAFile := Trim(ECAFile.Text);
      AInfo.TnsAlias := Trim(CTns.Text);
      AInfo.TnsFile := Trim(ETnsFile.Text);
      AInfo.WindowsAuth := CAuth.ItemIndex = 1;
      AInfo.Encrypt := CEnc.Text;
      AInfo.TrustServerCert := CTrust.Checked;
      if CEnv.ItemIndex >= 0 then
      begin
        AInfo.Environment := TpgnEnvironment(CEnv.ItemIndex);
      end;
      if (CColor.ItemIndex >= 0) and (CColor.ItemIndex < ColorPresetCount) then
      begin
        AInfo.Color := ColorPreset(CColor.ItemIndex).Color;
      end;
      Result := True;
    end;
  finally
    F.Free;
    Follower.Free;
  end;
end;

end.
