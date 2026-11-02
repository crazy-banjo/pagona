// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnWhoCanScreen;

{ DBA > Who Can Do What: pick an object, see everyone who can use it and
  how (granted directly, through a role, on the whole database or server,
  as owner or superuser). What PUBLIC (everyone) may do is called out on
  a line of its own, like the Everyone group on a Windows share.

  Changes go through the same path as Users and Roles: the statement is
  shown first, a confirmation names where it runs (default No), and it is
  written to the Pagona DBA log. Only direct grants can be revoked here;
  for the others the screen says where the access comes from. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Forms, Dialogs, Graphics, Clipbrd,
  pgnTypes, pgnAdapter, pgnUsersScreen;

type
  TpgnWhoCanPanel = class(TPanel)
  private
    FAdapter: TpgnAdapter;
    FInfo: TpgnConnectionInfo;
    FLog: TpgnLogProc;
    FMono: string;
    FKinds: TpgnStringArray;
    FAccounts: TpgnAccounts;
    FPublic: string;              // what PUBLIC may do, '' = nothing
    FFilling: Boolean;
    FOnOpenAccount: TpgnOpenAccountEvent;

    FBar: TPanel;
    FTitle: TLabel;
    FBtnRefresh: TButton;
    FOnLabel: TLabel;
    FKindCombo: TComboBox;
    FContainerCombo: TComboBox;
    FObjectCombo: TComboBox;
    FRolesCheck: TCheckBox;
    FOwnersCheck: TCheckBox;
    FSystemCheck: TCheckBox;

    FPublicPanel: TPanel;
    FPublicLabel: TLabel;
    FBtnRevokePublic: TButton;

    FGrid: TStringGrid;
    FButtons: TPanel;
    FBtnGrant: TButton;
    FBtnRevoke: TButton;
    FBtnOpen: TButton;
    FBtnCopy: TButton;
    FNote: TLabel;

    function NewButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent;
      AWidth: Integer): TButton;
    function NewCombo(AParent: TWinControl; AChange: TNotifyEvent): TComboBox;
    procedure LayoutBar(Sender: TObject);
    function Kind: string;
    function ObjectText: string;
    function HasTarget: Boolean;
    procedure FillContainers;
    procedure FillObjects;
    procedure KindChange(Sender: TObject);
    procedure ContainerChange(Sender: TObject);
    procedure TargetChange(Sender: TObject);
    procedure ShowPublic;
    function AccountKind(const AWho: string; out ASystem: Boolean): string;
    function RowValue(ARow, ACol: Integer): string;
    function Run(const AWhat: string; const ASQL: TpgnStringArray): Boolean;

    procedure RefreshClick(Sender: TObject);
    procedure GrantClick(Sender: TObject);
    procedure RevokeClick(Sender: TObject);
    procedure RevokePublicClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure GridDblClick(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; AAdapter: TpgnAdapter; const AInfo: TpgnConnectionInfo;
      ALog: TpgnLogProc; const AMonoFont: string);
    { Starts on this object (from the Explorer); '' leaves the first one. }
    procedure SetTarget(const AKind, AContainer, AName: string);
    procedure Reload;
    property OnOpenAccount: TpgnOpenAccountEvent read FOnOpenAccount write FOnOpenAccount;
  end;

implementation

uses
  Math, pgnTheme;

{ ------------------------------------------------------------ building }

constructor TpgnWhoCanPanel.CreateFor(AOwner: TComponent; AAdapter: TpgnAdapter;
  const AInfo: TpgnConnectionInfo; ALog: TpgnLogProc; const AMonoFont: string);
var
  All: TpgnStringArray;
  I: Integer;
begin
  inherited Create(AOwner);
  FAdapter := AAdapter;
  FInfo := AInfo;
  FLog := ALog;
  FMono := AMonoFont;
  BevelOuter := bvNone;
  Caption := '';
  Color := clPgnWork;

  // what can be looked at: everything that can be granted on, one object
  // at a time (not "all tables" or the whole server)
  All := FAdapter.GrantTargets;
  for I := 0 to High(All) do
  begin
    if (All[I] <> 'all tables') and (All[I] <> 'global') then
    begin
      SetLength(FKinds, Length(FKinds) + 1);
      FKinds[High(FKinds)] := All[I];
    end;
  end;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Height := Scale96ToScreen(72);
  FBar.BevelOuter := bvNone;
  FBar.Caption := '';
  FBar.Color := clPgnSurface;
  FBar.ParentColor := False;
  FBar.OnResize := @LayoutBar;

  FTitle := TLabel.Create(Self);
  FTitle.Parent := FBar;
  FTitle.Caption := 'Who Can Do What';
  FTitle.ParentFont := False;
  FTitle.Font.Style := [fsBold];

  FBtnRefresh := NewButton(FBar, 'Refresh', @RefreshClick, 90);

  FOnLabel := TLabel.Create(Self);
  FOnLabel.Parent := FBar;
  FOnLabel.Caption := 'On:';

  FKindCombo := NewCombo(FBar, @KindChange);
  for I := 0 to High(FKinds) do
  begin
    FKindCombo.Items.Add(FAdapter.GrantTargetCaption(FKinds[I]));
  end;
  FContainerCombo := NewCombo(FBar, @ContainerChange);
  FObjectCombo := NewCombo(FBar, @TargetChange);

  FRolesCheck := TCheckBox.Create(Self);
  FRolesCheck.Parent := FBar;
  FRolesCheck.Caption := 'Include access through roles';
  FRolesCheck.Checked := True;
  FRolesCheck.OnChange := @RefreshClick;

  FOwnersCheck := TCheckBox.Create(Self);
  FOwnersCheck.Parent := FBar;
  FOwnersCheck.Caption := 'Show owners and superusers';
  FOwnersCheck.Checked := False;
  FOwnersCheck.OnChange := @RefreshClick;
  if not FAdapter.HasSchemas then
  begin
    // MySQL has no owners or superusers; *.* grants show as "whole server"
    FOwnersCheck.Enabled := False;
    FOwnersCheck.Hint := 'MySQL has no object owners or superusers; whole-server grants are listed anyway';
    FOwnersCheck.ShowHint := True;
  end;

  FSystemCheck := TCheckBox.Create(Self);
  FSystemCheck.Parent := FBar;
  FSystemCheck.Caption := 'Show system accounts';
  FSystemCheck.Checked := False;
  FSystemCheck.OnChange := @RefreshClick;

  // what everyone may do; 0 tall when nothing (GTK3 shows hidden panels
  // again, so it's flattened rather than hidden)
  FPublicPanel := TPanel.Create(Self);
  FPublicPanel.Parent := Self;
  FPublicPanel.Align := alTop;
  FPublicPanel.Top := FBar.Top + FBar.Height + 1;
  FPublicPanel.Height := 0;
  FPublicPanel.BevelOuter := bvNone;
  FPublicPanel.Caption := '';
  FPublicPanel.Color := clPgnShade;
  FPublicPanel.ParentColor := False;

  FPublicLabel := TLabel.Create(Self);
  FPublicLabel.Parent := FPublicPanel;
  FPublicLabel.ParentFont := False;
  FPublicLabel.Font.Style := [fsBold];
  FPublicLabel.Font.Color := clPgnCaution;

  FBtnRevokePublic := NewButton(FPublicPanel, 'Revoke from PUBLIC...', @RevokePublicClick, 180);

  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Height := Scale96ToScreen(40);
  FButtons.BevelOuter := bvNone;
  FButtons.Caption := '';

  FBtnGrant := NewButton(FButtons, 'Grant...', @GrantClick, 110);
  FBtnRevoke := NewButton(FButtons, 'Revoke Selected...', @RevokeClick, 150);
  FBtnOpen := NewButton(FButtons, 'Open Account', @OpenClick, 120);
  FBtnCopy := NewButton(FButtons, 'Copy', @CopyClick, 80);
  FBtnGrant.SetBounds(Scale96ToScreen(6), Scale96ToScreen(4), FBtnGrant.Width, Scale96ToScreen(32));
  FBtnRevoke.SetBounds(FBtnGrant.Left + FBtnGrant.Width + Scale96ToScreen(6), Scale96ToScreen(4),
    FBtnRevoke.Width, Scale96ToScreen(32));
  FBtnOpen.SetBounds(FBtnRevoke.Left + FBtnRevoke.Width + Scale96ToScreen(6), Scale96ToScreen(4),
    FBtnOpen.Width, Scale96ToScreen(32));
  FBtnCopy.SetBounds(FBtnOpen.Left + FBtnOpen.Width + Scale96ToScreen(6), Scale96ToScreen(4),
    FBtnCopy.Width, Scale96ToScreen(32));

  FNote := TLabel.Create(Self);
  FNote.Parent := FButtons;
  FNote.ParentFont := False;
  FNote.Font.Color := clPgnMuted;
  FNote.SetBounds(FBtnCopy.Left + FBtnCopy.Width + Scale96ToScreen(16), Scale96ToScreen(12),
    Scale96ToScreen(600), FNote.Height);

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.RowCount := 1;
  FGrid.ColCount := 5;
  FGrid.Options := FGrid.Options + [goRowSelect, goColSizing, goThumbTracking, goRangeSelect] - [goEditing];
  FGrid.DefaultRowHeight := Scale96ToScreen(24);
  FGrid.BorderStyle := bsNone;
  FGrid.OnDblClick := @GridDblClick;

  if FKindCombo.Items.Count > 0 then
  begin
    FKindCombo.ItemIndex := 0;
  end;
  FFilling := True;
  try
    FillContainers;
  finally
    FFilling := False;
  end;
end;

function TpgnWhoCanPanel.NewButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent;
  AWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := Scale96ToScreen(AWidth);
end;

function TpgnWhoCanPanel.NewCombo(AParent: TWinControl; AChange: TNotifyEvent): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.Style := csDropDownList;
  Result.AutoSize := False;
  Result.Height := Scale96ToScreen(30);
  Result.OnChange := AChange;
end;

procedure TpgnWhoCanPanel.LayoutBar(Sender: TObject);
var
  X, H, Y: Integer;

  procedure Place(C: TControl; AWidth, AGap: Integer);
  var
    W: Integer;
  begin
    if AWidth > 0 then
    begin
      W := Scale96ToScreen(AWidth);
    end
    else
    begin
      W := C.Width;
    end;
    C.SetBounds(X, Y + (H - C.Height) div 2, W, C.Height);
    X := X + W + Scale96ToScreen(AGap);
  end;

begin
  H := Scale96ToScreen(36);
  Y := 0;
  X := Scale96ToScreen(10);
  Place(FTitle, 0, 18);
  Place(FBtnRefresh, 90, 18);
  Place(FOnLabel, 0, 6);
  Place(FKindCombo, 310, 6);
  Place(FContainerCombo, 160, 6);
  Place(FObjectCombo, 240, 0);
  Y := H;
  X := FOnLabel.Left;
  Place(FRolesCheck, 0, 18);
  Place(FOwnersCheck, 0, 18);
  Place(FSystemCheck, 0, 0);
  if FPublicPanel.Height = 0 then
  begin
    // out of sight: a flattened panel still lets GTK3 draw its children
    FPublicLabel.SetBounds(Scale96ToScreen(12), -Scale96ToScreen(200), FPublicLabel.Width, FPublicLabel.Height);
    FBtnRevokePublic.SetBounds(0, -Scale96ToScreen(200), FBtnRevokePublic.Width, Scale96ToScreen(30));
  end
  else
  begin
    FPublicLabel.SetBounds(Scale96ToScreen(12), (FPublicPanel.Height - FPublicLabel.Height) div 2,
      FPublicLabel.Width, FPublicLabel.Height);
    FBtnRevokePublic.SetBounds(FPublicLabel.Left + FPublicLabel.Width + Scale96ToScreen(16),
      Max(0, (FPublicPanel.Height - Scale96ToScreen(30)) div 2), FBtnRevokePublic.Width, Scale96ToScreen(30));
  end;
  Invalidate;
end;

{ ------------------------------------------------------------ the target }

function TpgnWhoCanPanel.Kind: string;
begin
  Result := '';
  if (FKindCombo.ItemIndex >= 0) and (FKindCombo.ItemIndex <= High(FKinds)) then
  begin
    Result := FKinds[FKindCombo.ItemIndex];
  end;
end;

function TpgnWhoCanPanel.ObjectText: string;
begin
  Result := FAdapter.GrantObjectText(Kind, FContainerCombo.Text, FObjectCombo.Text);
end;

function TpgnWhoCanPanel.HasTarget: Boolean;
begin
  Result := (Kind <> '') and (FContainerCombo.Text <> '') and
    (not FAdapter.GrantNeedsObject(Kind) or (FObjectCombo.Text <> ''));
end;

procedure TpgnWhoCanPanel.FillContainers;
var
  List: TpgnStringArray;
  I: Integer;
begin
  FContainerCombo.Items.Clear;
  try
    List := FAdapter.GrantContainers(Kind);
  except
    on E: Exception do
    begin
      List := nil;
      FLog('ERROR: could not list them: ' + E.Message);
    end;
  end;
  for I := 0 to High(List) do
  begin
    FContainerCombo.Items.Add(List[I]);
  end;
  if FContainerCombo.Items.Count > 0 then
  begin
    FContainerCombo.ItemIndex := 0;
  end;
  FillObjects;
end;

procedure TpgnWhoCanPanel.FillObjects;
var
  List: TpgnStringArray;
  I: Integer;
begin
  FObjectCombo.Items.Clear;
  FObjectCombo.Enabled := FAdapter.GrantNeedsObject(Kind);
  if FObjectCombo.Enabled and (FContainerCombo.Text <> '') then
  begin
    try
      List := FAdapter.GrantObjects(Kind, FContainerCombo.Text);
    except
      on E: Exception do
      begin
        List := nil;
        FLog('ERROR: could not list them: ' + E.Message);
      end;
    end;
    for I := 0 to High(List) do
    begin
      FObjectCombo.Items.Add(List[I]);
    end;
    if FObjectCombo.Items.Count > 0 then
    begin
      FObjectCombo.ItemIndex := 0;
    end;
  end;
end;

procedure TpgnWhoCanPanel.KindChange(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  FFilling := True;
  try
    FillContainers;
  finally
    FFilling := False;
  end;
  Reload;
end;

procedure TpgnWhoCanPanel.ContainerChange(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  FFilling := True;
  try
    FillObjects;
  finally
    FFilling := False;
  end;
  Reload;
end;

procedure TpgnWhoCanPanel.TargetChange(Sender: TObject);
begin
  if not FFilling then
  begin
    Reload;
  end;
end;

procedure TpgnWhoCanPanel.SetTarget(const AKind, AContainer, AName: string);
var
  I: Integer;
begin
  FFilling := True;
  try
    for I := 0 to High(FKinds) do
    begin
      if FKinds[I] = AKind then
      begin
        FKindCombo.ItemIndex := I;
      end;
    end;
    FillContainers;
    if AContainer <> '' then
    begin
      if FContainerCombo.Items.IndexOf(AContainer) < 0 then
      begin
        FContainerCombo.Items.Add(AContainer);
      end;
      FContainerCombo.ItemIndex := FContainerCombo.Items.IndexOf(AContainer);
      FillObjects;
    end;
    if (AName <> '') and FObjectCombo.Enabled then
    begin
      if FObjectCombo.Items.IndexOf(AName) < 0 then
      begin
        FObjectCombo.Items.Add(AName);
      end;
      FObjectCombo.ItemIndex := FObjectCombo.Items.IndexOf(AName);
    end;
  finally
    FFilling := False;
  end;
end;

{ ------------------------------------------------------------ the list }

function TpgnWhoCanPanel.AccountKind(const AWho: string; out ASystem: Boolean): string;
var
  I: Integer;
begin
  Result := '';
  ASystem := False;
  for I := 0 to High(FAccounts) do
  begin
    if FAdapter.AccountText(FAccounts[I]) = AWho then
    begin
      ASystem := FAccounts[I].IsSystem;
      if FAccounts[I].IsRole then
      begin
        Result := 'role';
      end
      else
      begin
        Result := 'user';
      end;
      Exit;
    end;
  end;
end;

procedure TpgnWhoCanPanel.Reload;
var
  R: TpgnResultSet;
  I, C, N, Who: Integer;
  K: string;
  Sys: Boolean;
  Seen: TStringList;
begin
  FGrid.RowCount := 1;
  FGrid.ColCount := 5;
  FGrid.Cells[0, 0] := 'Who';
  FGrid.Cells[1, 0] := 'Kind';
  FGrid.Cells[2, 0] := 'Can do';
  FGrid.Cells[3, 0] := 'How';
  FGrid.Cells[4, 0] := 'Can grant';
  FPublic := '';
  ShowPublic;
  if not HasTarget then
  begin
    FNote.Caption := 'Nothing of that kind to pick here.';
    FBtnGrant.Enabled := False;
    FBtnRevoke.Enabled := False;
    FBtnOpen.Enabled := False;
    Exit;
  end;
  try
    FAccounts := FAdapter.ListAccounts(True);
  except
    on E: Exception do
    begin
      FAccounts := nil;   // the Kind column stays as the server gave it
    end;
  end;
  try
    R := FAdapter.ObjectAccess(Kind, FContainerCombo.Text, FObjectCombo.Text, FRolesCheck.Checked,
      FOwnersCheck.Checked, FSystemCheck.Checked);
  except
    on E: Exception do
    begin
      FLog('ERROR: could not read who can use ' + ObjectText + ': ' + E.Message);
      FNote.Caption := 'Could not read the grants (Messages says why).';
      FNote.Font.Color := clPgnDanger;
      Exit;
    end;
  end;
  FNote.Font.Color := clPgnMuted;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    N := 0;
    FGrid.RowCount := R.RowCount + 1;
    for I := 0 to R.RowCount - 1 do
    begin
      K := R.Rows[I].Values[1];
      if K = '' then
      begin
        K := AccountKind(R.Rows[I].Values[0], Sys);
      end
      else
      begin
        AccountKind(R.Rows[I].Values[0], Sys);
      end;
      if Sys and not FSystemCheck.Checked then
      begin
        Continue;
      end;
      Inc(N);
      for C := 0 to 4 do
      begin
        FGrid.Cells[C, N] := R.Rows[I].Values[C];
      end;
      FGrid.Cells[1, N] := K;
      Seen.Add(R.Rows[I].Values[0]);
    end;
    FGrid.RowCount := N + 1;
    Who := Seen.Count;
  finally
    Seen.Free;
    R.Free;
  end;
  FitColumns(FGrid);
  if Who = 1 then
  begin
    FNote.Caption := '1 account can use ' + ObjectText;
  end
  else
  begin
    FNote.Caption := IntToStr(Who) + ' accounts can use ' + ObjectText;
  end;
  try
    FPublic := FAdapter.PublicAccess(Kind, FContainerCombo.Text, FObjectCombo.Text);
  except
    on E: Exception do
    begin
      FPublic := '';
    end;
  end;
  if FPublic <> '' then
  begin
    FNote.Caption := FNote.Caption + ', and everyone through PUBLIC';
  end;
  ShowPublic;
  FBtnGrant.Enabled := FAdapter.MissingRight('accounts') = '';
  FBtnRevoke.Enabled := N > 0;
  FBtnOpen.Enabled := N > 0;
end;

procedure TpgnWhoCanPanel.ShowPublic;
begin
  if FPublic = '' then
  begin
    FPublicPanel.Height := 0;
  end
  else
  begin
    FPublicLabel.Caption := 'Everyone can ' + FPublic + ' this (granted to PUBLIC)';
    FPublicPanel.Height := Scale96ToScreen(40);
  end;
  LayoutBar(nil);
end;

function TpgnWhoCanPanel.RowValue(ARow, ACol: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow < FGrid.RowCount) then
  begin
    Result := FGrid.Cells[ACol, ARow];
  end;
end;

{ ------------------------------------------------------------ actions }

function TpgnWhoCanPanel.Run(const AWhat: string; const ASQL: TpgnStringArray): Boolean;
var
  Tried: Boolean;
begin
  Result := RunAdminStatements(FAdapter, FInfo, FLog, AWhat, ASQL, ASQL, False, Tried);
  if Tried then
  begin
    Reload;
  end;
end;

procedure TpgnWhoCanPanel.RefreshClick(Sender: TObject);
begin
  Reload;
end;

{ Only grants made on this object to that account can be taken back here;
  for the rest, say where the access comes from. }
procedure TpgnWhoCanPanel.RevokeClick(Sender: TObject);
var
  R, First, Last: Integer;
  SQL: TpgnStringArray;
  How, Why: string;
begin
  First := FGrid.Selection.Top;
  Last := FGrid.Selection.Bottom;
  if First < 1 then
  begin
    First := FGrid.Row;
    Last := FGrid.Row;
  end;
  SQL := nil;
  Why := '';
  for R := First to Last do
  begin
    How := RowValue(R, 3);
    if How = 'direct' then
    begin
      SetLength(SQL, Length(SQL) + 1);
      SQL[High(SQL)] := FAdapter.RevokePrivilegeSQL(FAdapter.AccountFromText(RowValue(R, 0)), ObjectText, Kind,
        RowValue(R, 2));
    end
    else if Why = '' then
    begin
      if Pos('through role ', How) = 1 then
      begin
        Why := RowValue(R, 0) + ' has this ' + How + '. Revoke it from ' + Copy(How, 14, MaxInt) +
          ' (its own row here), or take ' + RowValue(R, 0) + ' out of that role in Users and Roles.';
      end
      else if (How = 'owner') or (How = 'superuser') then
      begin
        Why := RowValue(R, 0) + ' is the ' + How + ': that access is built in and no grant controls it.';
      end
      else
      begin
        Why := RowValue(R, 0) + ' has this from a grant on the ' + How +
          '. Change it in Users and Roles > Privileges.';
      end;
    end;
  end;
  if Length(SQL) = 0 then
  begin
    if Why <> '' then
    begin
      MessageDlg(Why, mtInformation, [mbOK], 0);
    end;
    Exit;
  end;
  if Why <> '' then
  begin
    FLog('Not revoked here: ' + Why);
  end;
  Run('Revoke access to ' + ObjectText, SQL);
end;

procedure TpgnWhoCanPanel.RevokePublicClick(Sender: TObject);
begin
  if FPublic = '' then
  begin
    Exit;
  end;
  Run('Revoke PUBLIC''s access to ' + ObjectText,
    One(FAdapter.RevokePublicSQL(Kind, FContainerCombo.Text, FObjectCombo.Text, FPublic)));
end;

procedure TpgnWhoCanPanel.OpenClick(Sender: TObject);
var
  Who: string;
begin
  Who := RowValue(FGrid.Row, 0);
  if (Who <> '') and Assigned(FOnOpenAccount) then
  begin
    FOnOpenAccount(Who);
  end;
end;

procedure TpgnWhoCanPanel.GridDblClick(Sender: TObject);
begin
  OpenClick(Sender);
end;

procedure TpgnWhoCanPanel.CopyClick(Sender: TObject);
var
  S: string;
  R, C: Integer;
begin
  S := 'Who can use ' + ObjectText + ' on ' + ConnectionLongLabel(FInfo) + LineEnding;
  if FPublic <> '' then
  begin
    S := S + 'Everyone (PUBLIC) can ' + FPublic + LineEnding;
  end;
  for R := 0 to FGrid.RowCount - 1 do
  begin
    for C := 0 to FGrid.ColCount - 1 do
    begin
      if C > 0 then
      begin
        S := S + #9;
      end;
      S := S + FGrid.Cells[C, R];
    end;
    S := S + LineEnding;
  end;
  Clipboard.AsText := S;
  FLog('Copied who can use ' + ObjectText + ' to the clipboard.');
end;

type
  { The Grant dialog here: the object is fixed; pick who and what. }
  TpgnWhoGrantHelper = class
  public
    Adapter: TpgnAdapter;
    Kind, ObjectText: string;
    Dlg: TpgnAccountDialog;
    WhoCombo: TComboBox;
    Checks: array of TCheckBox;
    GrantOption: TCheckBox;
    function Privileges: string;
    function Statement: string;
    procedure Preview(Sender: TObject);
  end;

function TpgnWhoGrantHelper.Privileges: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Checks) do
  begin
    if Checks[I].Checked then
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + Checks[I].Caption;
    end;
  end;
end;

function TpgnWhoGrantHelper.Statement: string;
begin
  Result := Adapter.GrantPrivilegeSQL(Adapter.AccountFromText(WhoCombo.Text), ObjectText, Kind, Privileges,
    GrantOption.Checked);
end;

procedure TpgnWhoGrantHelper.Preview(Sender: TObject);
begin
  if WhoCombo.ItemIndex < 1 then
  begin
    Dlg.Preview.Lines.Text := '-- choose who gets it';
    Dlg.BtnOK.Enabled := False;
  end
  else if Privileges = '' then
  begin
    Dlg.Preview.Lines.Text := '-- tick at least one privilege';
    Dlg.BtnOK.Enabled := False;
  end
  else
  begin
    Dlg.Preview.Lines.Text := Statement + ';';
    Dlg.BtnOK.Enabled := True;
  end;
end;

procedure TpgnWhoCanPanel.GrantClick(Sender: TObject);
var
  H: TpgnWhoGrantHelper;
  Items: TStringList;
  List: TpgnStringArray;
  P: TPanel;
  I, Cols, ColW, RowH: Integer;
  SQL: string;
begin
  if not HasTarget then
  begin
    Exit;
  end;
  H := TpgnWhoGrantHelper.Create;
  try
    H.Adapter := FAdapter;
    H.Kind := Kind;
    H.ObjectText := ObjectText;
    H.Dlg := TpgnAccountDialog.CreateDlg('Grant access to ' + ObjectText + ' (' + ConnectionLongLabel(FInfo) + ')',
      'Grant...', 680, FMono);
    try
      Items := TStringList.Create;
      try
        Items.Add('(choose)');
        for I := 0 to High(FAccounts) do
        begin
          if not FAccounts[I].IsSystem then
          begin
            Items.Add(FAdapter.AccountText(FAccounts[I]));
          end;
        end;
        H.WhoCombo := H.Dlg.AddCombo('To', Items, 320);
      finally
        Items.Free;
      end;
      H.Dlg.AddLabel('Privileges:');
      List := FAdapter.GrantPrivileges(Kind);
      Cols := 3;
      RowH := Scale96ToScreen(24);
      P := H.Dlg.AddPanel(((Length(List) + Cols - 1) div Cols) * 24 + 4);
      ColW := (P.Width - Scale96ToScreen(8)) div Cols;
      SetLength(H.Checks, Length(List));
      for I := 0 to High(List) do
      begin
        H.Checks[I] := TCheckBox.Create(P);
        H.Checks[I].Parent := P;
        H.Checks[I].Caption := List[I];
        H.Checks[I].SetBounds(Scale96ToScreen(4) + (I mod Cols) * ColW, (I div Cols) * RowH,
          ColW - Scale96ToScreen(4), RowH);
        H.Checks[I].OnChange := @H.Preview;
      end;
      H.GrantOption := H.Dlg.AddCheck('Let them grant these to others (WITH GRANT OPTION)', True);
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(100);
      if H.Dlg.ShowModal <> mrOK then
      begin
        Exit;
      end;
      SQL := H.Statement;
    finally
      H.Dlg.Free;
    end;
  finally
    H.Free;
  end;
  Run('Grant access to ' + ObjectText, One(SQL));
end;

end.
