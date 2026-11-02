// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnConnectWin;

{ Amphibian's New Connection window, as Toad's: every saved connection in a
  list (environment in words, name, user, database or TNS alias, engine,
  server). Connect (or double-click, or Enter) opens it; New, Edit and
  Delete change the saved list without leaving the window.

    +----------------------------------------------------------------+
    | Saved connections                                              |
    |  Environment  Name       User      Database / alias  Engine    |
    |  TEST         reports-db randy     banner_dw         PostgreSQL|
    |  DEV          DEVL       RMORROW   DEVL (TNS)        Oracle    |
    | [New...] [Edit...] [Delete...]              [Connect] [Cancel] |
    +----------------------------------------------------------------+ }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids, LCLType, Math,
  pgnTypes, pgnConnections, pgnResultGrid, pgnTheme;

type
  { Store index in, True if the saved list changed. }
  TpgnConnEditFunc = function(AStoreIndex: Integer): Boolean of object;
  TpgnConnNewFunc = function: Boolean of object;

  TpgnConnectWindow = class(TForm)
  private
    FStore: TpgnConnectionStore;
    FGrid: TpgnResultGrid;
    FNote: TLabel;
    FBtnNew, FBtnEdit, FBtnDelete, FBtnConnect, FBtnCancel: TButton;
    FOnNew: TpgnConnNewFunc;
    FOnEdit: TpgnConnEditFunc;
    FOnDelete: TpgnConnEditFunc;
    FChosen: Integer;
    procedure Fill(const ASelectId: string);
    function Current: Integer;
    procedure UpdateButtons;
    procedure GridSelect(Sender: TObject; aCol, aRow: Integer);
    procedure GridDblClick(Sender: TObject);
    procedure GridKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure NewClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure BarResize(Sender: TObject);
  public
    constructor CreateWin(AOwner: TComponent; AStore: TpgnConnectionStore; const ASelectId: string);
    { The store index picked, or -1 if the window was closed. }
    property Chosen: Integer read FChosen;
    property OnNewConnection: TpgnConnNewFunc read FOnNew write FOnNew;
    property OnEditConnection: TpgnConnEditFunc read FOnEdit write FOnEdit;
    property OnDeleteConnection: TpgnConnEditFunc read FOnDelete write FOnDelete;
  end;

implementation

constructor TpgnConnectWindow.CreateWin(AOwner: TComponent; AStore: TpgnConnectionStore;
  const ASelectId: string);
var
  Bar: TPanel;
  L: TLabel;

  function Btn(const ACaption: string; AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Bar;
    Result.Caption := ACaption;
    Result.Width := Scale96ToScreen(96);
    Result.OnClick := AHandler;
  end;

begin
  inherited CreateNew(AOwner);
  SmoothFont(Font);
  FStore := AStore;
  FChosen := -1;
  Caption := 'New Connection';
  Position := poOwnerFormCenter;
  BorderStyle := bsSizeable;
  Width := Scale96ToScreen(820);
  Height := Scale96ToScreen(440);
  KeyPreview := True;

  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Align := alTop;
  L.Caption := 'Saved connections';
  L.Font.Style := [fsBold];
  // fixed sizes: labels that size themselves can make the layout loop
  L.AutoSize := False;
  L.Height := Scale96ToScreen(30);
  L.Layout := tlCenter;
  L.BorderSpacing.Left := Scale96ToScreen(8);

  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alBottom;
  Bar.Height := Scale96ToScreen(46);
  Bar.BevelOuter := bvNone;
  Bar.Caption := '';
  Bar.OnResize := @BarResize;

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alBottom;
  FNote.Caption := 'Double-click a connection, or press Enter, to connect. Passwords are asked ' +
    'once and kept only until Pagona closes.';
  FNote.Font.Color := clPgnMuted;
  FNote.AutoSize := False;
  FNote.Height := Scale96ToScreen(26);
  FNote.Layout := tlCenter;
  FNote.BorderSpacing.Left := Scale96ToScreen(8);

  FGrid := TpgnResultGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.BorderSpacing.Left := Scale96ToScreen(8);
  FGrid.BorderSpacing.Right := Scale96ToScreen(8);
  FGrid.Options := FGrid.Options + [goRowSelect];
  FGrid.OnSelection := @GridSelect;
  FGrid.OnDblClick := @GridDblClick;
  FGrid.OnKeyDown := @GridKeyDown;

  FBtnNew := Btn('New...', @NewClick);
  FBtnEdit := Btn('Edit...', @EditClick);
  FBtnDelete := Btn('Delete...', @DeleteClick);
  FBtnConnect := Btn('Connect', @ConnectClick);
  FBtnConnect.Default := True;
  FBtnCancel := Btn('Cancel', nil);
  FBtnCancel.ModalResult := mrCancel;
  FBtnCancel.Cancel := True;

  Fill(ASelectId);
  ActiveControl := FGrid;
end;

procedure TpgnConnectWindow.BarResize(Sender: TObject);
var
  P: TWinControl;
  Y, Gap: Integer;
begin
  P := FBtnNew.Parent;
  Gap := Scale96ToScreen(8);
  Y := (P.ClientHeight - FBtnNew.Height) div 2;
  FBtnNew.SetBounds(Gap, Y, FBtnNew.Width, FBtnNew.Height);
  FBtnEdit.SetBounds(FBtnNew.Left + FBtnNew.Width + Gap, Y, FBtnEdit.Width, FBtnEdit.Height);
  FBtnDelete.SetBounds(FBtnEdit.Left + FBtnEdit.Width + Gap, Y, FBtnDelete.Width, FBtnDelete.Height);
  FBtnCancel.SetBounds(P.ClientWidth - FBtnCancel.Width - Gap, Y, FBtnCancel.Width, FBtnCancel.Height);
  FBtnConnect.SetBounds(FBtnCancel.Left - FBtnConnect.Width - Gap, Y, FBtnConnect.Width,
    FBtnConnect.Height);
end;

procedure TpgnConnectWindow.Fill(const ASelectId: string);
var
  R: TpgnResultSet;
  I, Pick: Integer;
  Info: TpgnConnectionInfo;

  procedure SetCell(ARow, ACol: Integer; const AText: string);
  begin
    R.Rows[ARow].Values[ACol] := AText;
  end;

begin
  R := TpgnResultSet.Create;
  R.ReturnsRows := True;
  SetLength(R.Columns, 6);
  R.Columns[0] := 'Environment';
  R.Columns[1] := 'Name';
  R.Columns[2] := 'User';
  R.Columns[3] := 'Database / alias';
  R.Columns[4] := 'Engine';
  R.Columns[5] := 'Server';
  SetLength(R.Rows, FStore.Count);
  Pick := 0;
  for I := 0 to FStore.Count - 1 do
  begin
    Info := FStore.Items[I];
    SetLength(R.Rows[I].Values, 6);
    SetLength(R.Rows[I].Nulls, 6);
    if Info.Environment = enNone then
    begin
      SetCell(I, 0, '(none)');
    end
    else
    begin
      SetCell(I, 0, EnvironmentLong[Info.Environment]);
    end;
    SetCell(I, 1, Info.Name);
    if (Info.Engine = feSQLServer) and Info.WindowsAuth then
    begin
      SetCell(I, 2, '(Windows Authentication)');
    end
    else
    begin
      SetCell(I, 2, Info.User);
    end;
    if Info.TnsAlias <> '' then
    begin
      SetCell(I, 3, Info.TnsAlias + ' (TNS)');
    end
    else
    begin
      SetCell(I, 3, Info.DefaultDatabase);
    end;
    SetCell(I, 4, EngineCaptions[Info.Engine]);
    if Info.Host <> '' then
    begin
      SetCell(I, 5, Info.Host + ':' + IntToStr(Info.Port));
    end
    else
    begin
      SetCell(I, 5, '');
    end;
    if Info.Id = ASelectId then
    begin
      Pick := I;
    end;
  end;
  FGrid.ShowData(R);   // the grid keeps it
  if FStore.Count > 0 then
  begin
    FGrid.Row := Pick + 1;
  end;
  UpdateButtons;
end;

function TpgnConnectWindow.Current: Integer;
begin
  Result := FGrid.Row - 1;
  if (FStore.Count = 0) or (Result < 0) or (Result >= FStore.Count) then
  begin
    Result := -1;
  end;
end;

procedure TpgnConnectWindow.UpdateButtons;
var
  Has: Boolean;
begin
  Has := Current >= 0;
  FBtnEdit.Enabled := Has;
  FBtnDelete.Enabled := Has;
  FBtnConnect.Enabled := Has;
  if FStore.Count = 0 then
  begin
    FNote.Caption := 'No saved connections yet: New... adds one.';
  end;
end;

procedure TpgnConnectWindow.GridSelect(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtons;
end;

procedure TpgnConnectWindow.GridDblClick(Sender: TObject);
begin
  ConnectClick(nil);
end;

procedure TpgnConnectWindow.GridKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    ConnectClick(nil);
  end
  else if Key = VK_DELETE then
  begin
    Key := 0;
    DeleteClick(nil);
  end;
end;

procedure TpgnConnectWindow.NewClick(Sender: TObject);
var
  Before: Integer;
begin
  Before := FStore.Count;
  if Assigned(FOnNew) and FOnNew() then
  begin
    Fill('');
    if FStore.Count > Before then
    begin
      FGrid.Row := FStore.Count;   // the new one
    end;
    UpdateButtons;
  end;
end;

procedure TpgnConnectWindow.EditClick(Sender: TObject);
var
  I: Integer;
  Id: string;
begin
  I := Current;
  if (I < 0) or not Assigned(FOnEdit) then
  begin
    Exit;
  end;
  Id := FStore.Items[I].Id;
  if FOnEdit(I) then
  begin
    Fill(Id);
  end;
end;

procedure TpgnConnectWindow.DeleteClick(Sender: TObject);
var
  I: Integer;
begin
  I := Current;
  if (I < 0) or not Assigned(FOnDelete) then
  begin
    Exit;
  end;
  if FOnDelete(I) then
  begin
    Fill('');
  end;
end;

procedure TpgnConnectWindow.ConnectClick(Sender: TObject);
begin
  if Current < 0 then
  begin
    Exit;
  end;
  FChosen := Current;
  ModalResult := mrOK;
end;

end.
