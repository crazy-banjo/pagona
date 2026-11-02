// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnUsersScreen;

{ DBA > Users and Roles: the accounts on a server, and for the one picked
  its settings, the roles it has, who has it, what it may do, and the SQL
  to make it again.

  Nothing changes until Apply (or a dialog's button): the statements are
  shown first, a confirmation names where they run, and each one is
  written to the Pagona DBA log. Passwords never reach the log or the
  screen: the statements shown and logged carry '****'.

  The adapter decides what an account has (TpgnAccountAttr), so MySQL,
  PostgreSQL and later Oracle each show their own settings here. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, ComCtrls, Grids, Forms, Dialogs,
  Graphics, Clipbrd, LCLType, Math,
  pgnTypes, pgnAdapter;

type
  TpgnLogProc = procedure(const AText: string) of object;
  TpgnOpenAccountEvent = procedure(const AAccount: string) of object;

  { A small dialog: rows of fields, a "Will run:" box, OK and Cancel. }
  TLabelPair = array[0..1] of TLabel;

  TpgnAccountDialog = class(TForm)
  private
    FY: Integer;
    FLabels: TLabelPair;
    FOnPreview: TNotifyEvent;
    procedure Remember(ALabel: TLabel);
    procedure Changed(Sender: TObject);
  public
    Preview: TMemo;
    BtnOK: TButton;
    BtnCancel: TButton;
    constructor CreateDlg(const ACaption, AOK: string; AWidth: Integer; const AMono: string);
    function AddLabel(const AText: string; AMuted: Boolean = False): TLabel;
    function AddEdit(const ACaption: string; APassword: Boolean = False): TEdit;
    function AddCombo(const ACaption: string; AItems: TStrings; AWidth: Integer = 0): TComboBox;
    function AddCheck(const ACaption: string; AAtLeft: Boolean = False): TCheckBox;
    function AddGrid(AHeight: Integer): TStringGrid;
    function AddPanel(AHeight: Integer): TPanel;
    { Makes AControl ANewHeight tall; what's below it moves and the window
      grows or shrinks with it. }
    procedure ResizePart(AControl: TControl; ANewHeight: Integer);
    { The caption labels of the last two AddCombo / AddEdit calls, newest last. }
    function LastLabels: TLabelPair;
    procedure Finish(APreviewHeight: Integer);
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
  end;


  TpgnUsersPanel = class(TPanel)
  private
    FAdapter: TpgnAdapter;
    FInfo: TpgnConnectionInfo;
    FLog: TpgnLogProc;
    FMono: string;

    FAccounts: TpgnAccounts;      // as read, system accounts per the checkbox
    FShown: array of Integer;     // list row - 1 -> index in FAccounts
    FCurrent: TpgnAccount;
    FHasCurrent: Boolean;
    FAttrs: TpgnAccountAttrs;     // as read
    FEdited: TpgnAccountAttrs;    // as on screen
    FAttrControls: array of TControl;
    FFilling: Boolean;            // controls being filled, not edited
    FPending: TpgnStringArray;    // what Apply would run
    FDDLLoaded: Boolean;
    FAcctRight: string;           // '' or what the login lacks to change accounts

    // bar
    FBar: TPanel;
    FTitle: TLabel;
    FBtnRefresh: TButton;
    FShowCombo: TComboBox;
    FSystemCheck: TCheckBox;
    FFilterLabel: TLabel;
    FFilter: TEdit;
    FBarNote: TLabel;

    // left: the accounts
    FLeft: TPanel;
    FList: TStringGrid;
    FLeftButtons: TPanel;
    FBtnNewUser: TButton;
    FBtnNewRole: TButton;
    FSplitter: TSplitter;

    // right: the account picked
    FRight: TPanel;
    FHead: TPanel;
    FHeader: TLabel;
    FBtnPassword: TButton;
    FBtnDrop: TButton;
    FStrip: TTabControl;
    FPages: array[0..4] of TPanel;

    FAttrBox: TScrollBox;
    FApplyPanel: TPanel;
    FWillRunLabel: TLabel;
    FWillRun: TMemo;
    FBtnUndo: TButton;
    FBtnApply: TButton;

    FMemberOfGrid: TStringGrid;
    FBtnGrantRole: TButton;
    FBtnRevokeRole: TButton;
    FMemberOfNote: TLabel;

    FMembersGrid: TStringGrid;
    FBtnAddMember: TButton;
    FBtnRemoveMember: TButton;
    FMembersNote: TLabel;

    FPrivGrid: TStringGrid;
    FBtnGrantPriv: TButton;
    FBtnRevokePriv: TButton;
    FPrivNote: TLabel;

    FDDL: TMemo;
    FBtnCopyDDL: TButton;

    function NewButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function NewGrid(AParent: TWinControl): TStringGrid;
    function NewPage: TPanel;
    procedure GridResize(Sender: TObject);
    function ButtonRow(AParent: TWinControl): TPanel;
    procedure ShowPage(AIndex: Integer);
    procedure StripChange(Sender: TObject);
    procedure LayoutBar(Sender: TObject);
    procedure LayoutHead(Sender: TObject);

    procedure ReadAccounts;
    procedure FillList(const AKeep: string);
    function AccountKind(const AAccount: TpgnAccount): string;
    procedure ListSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
    procedure SelectRow(ARow: Integer);
    procedure LoadAccount;
    procedure ClearAccount;
    procedure BuildAttrRows;
    procedure AttrChanged(Sender: TObject);
    procedure UpdatePending;
    procedure ApplyRight;
    function HasPending: Boolean;
    procedure LoadDDL;
    procedure FillGrid(AGrid: TStringGrid; AData: TpgnResultSet);
    function GridValue(AGrid: TStringGrid; ARow, ACol: Integer): string;
    function OtherAccounts(AIncludeSelf: Boolean): TStringList;

    function RunStatements(const AWhat: string; const ASQL, AShown: TpgnStringArray;
      AWarn: Boolean): Boolean;

    procedure RefreshClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure NewUserClick(Sender: TObject);
    procedure NewRoleClick(Sender: TObject);
    procedure NewAccount(AIsRole: Boolean);
    procedure PasswordClick(Sender: TObject);
    procedure DropClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure GrantRoleClick(Sender: TObject);
    procedure RevokeRoleClick(Sender: TObject);
    procedure AddMemberClick(Sender: TObject);
    procedure RemoveMemberClick(Sender: TObject);
    procedure RoleDialog(AAddMember: Boolean);
    procedure GrantPrivClick(Sender: TObject);
    procedure RevokePrivClick(Sender: TObject);
    procedure CopyDDLClick(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; AAdapter: TpgnAdapter; const AInfo: TpgnConnectionInfo;
      ALog: TpgnLogProc; const AMonoFont: string);
    { Reads the accounts again; the one picked stays picked. }
    procedure Reload;
    { False when Apply has something waiting and the user wants to keep it. }
    function CanLeave: Boolean;
    { Picks the account written as AText ("reports@10.%" / "reports"). }
    procedure SelectAccount(const AText: string);
  end;

{ Columns as wide as their text plus room; the last one takes what's left. }
procedure FitColumns(AGrid: TStringGrid);
{ Statements one per line, each ending in ';'. }
function JoinStatements(const AList: TpgnStringArray): string;
function One(const AStatement: string): TpgnStringArray;
{ Asks (default No), runs each statement on the metadata session, logs
  each to Messages and the DBA log with what it was for. AShown is ASQL
  with passwords as ****. A list that starts with BEGIN is rolled back
  when a statement fails. False when not run or failed; ATried says
  whether the user said Yes (something may have changed). }
function RunAdminStatements(AAdapter: TpgnAdapter; const AInfo: TpgnConnectionInfo; ALog: TpgnLogProc;
  const AWhat: string; const ASQL, AShown: TpgnStringArray; AWarn: Boolean; out ATried: Boolean): Boolean;

implementation

uses
  pgnTheme, pgnDbaLog;

const
  PageNames: array[0..4] of string = ('General', 'Member Of', 'Members', 'Privileges', 'SQL');
  Masked = '****';
  NobodyText = '(nobody)';

{ Columns as wide as their text plus room; the last one takes what's left. }
procedure FitColumns(AGrid: TStringGrid);
var
  C, Total: Integer;
begin
  AGrid.AutoSizeColumns;
  Total := 0;
  for C := 0 to AGrid.ColCount - 1 do
  begin
    AGrid.ColWidths[C] := AGrid.ColWidths[C] + AGrid.Scale96ToScreen(12);
    Total := Total + AGrid.ColWidths[C];
  end;
  C := AGrid.ColCount - 1;
  if Total < AGrid.ClientWidth then
  begin
    AGrid.ColWidths[C] := AGrid.ColWidths[C] + AGrid.ClientWidth - Total;
  end;
end;

function JoinStatements(const AList: TpgnStringArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AList) do
  begin
    Result := Result + AList[I] + ';' + LineEnding;
  end;
end;

procedure AddTo(var AList: TpgnStringArray; const AMore: TpgnStringArray);
var
  I: Integer;
begin
  for I := 0 to High(AMore) do
  begin
    SetLength(AList, Length(AList) + 1);
    AList[High(AList)] := AMore[I];
  end;
end;

function One(const AStatement: string): TpgnStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := AStatement;
end;

{ ------------------------------------------------------------ dialogs }

constructor TpgnAccountDialog.CreateDlg(const ACaption, AOK: string; AWidth: Integer; const AMono: string);
begin
  inherited CreateNew(nil);
  SmoothFont(Font);
  Caption := ACaption;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := Scale96ToScreen(AWidth);
  FY := Scale96ToScreen(12);
  Preview := TMemo.Create(Self);
  Preview.ReadOnly := True;
  Preview.ScrollBars := ssAutoBoth;
  Preview.WordWrap := False;
  Preview.Font.Name := AMono;
  Preview.Color := clPgnShade;
  BtnOK := TButton.Create(Self);
  BtnOK.Caption := AOK;
  BtnOK.ModalResult := mrOK;
  BtnOK.Default := True;
  BtnCancel := TButton.Create(Self);
  BtnCancel.Caption := 'Cancel';
  BtnCancel.ModalResult := mrCancel;
  BtnCancel.Cancel := True;
end;

procedure TpgnAccountDialog.Remember(ALabel: TLabel);
begin
  FLabels[0] := FLabels[1];
  FLabels[1] := ALabel;
end;

function TpgnAccountDialog.LastLabels: TLabelPair;
begin
  Result := FLabels;
end;

function TpgnAccountDialog.AddPanel(AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.SetBounds(Scale96ToScreen(12), FY, ClientWidth - Scale96ToScreen(24), Scale96ToScreen(AHeight));
  FY := FY + Result.Height + Scale96ToScreen(8);
end;

procedure TpgnAccountDialog.ResizePart(AControl: TControl; ANewHeight: Integer);
var
  Delta, I: Integer;
begin
  Delta := ANewHeight - AControl.Height;
  if Delta = 0 then
  begin
    Exit;
  end;
  for I := 0 to ControlCount - 1 do
  begin
    if Controls[I].Top > AControl.Top then
    begin
      Controls[I].Top := Controls[I].Top + Delta;
    end;
  end;
  AControl.Height := ANewHeight;
  ClientHeight := ClientHeight + Delta;
end;

procedure TpgnAccountDialog.Changed(Sender: TObject);
begin
  if Assigned(FOnPreview) then
  begin
    FOnPreview(Self);
  end;
end;

{ How many lines AText takes at AWidth pixels, wrapped at spaces. }
function WrappedLines(ACanvas: TCanvas; const AText: string; AWidth: Integer): Integer;
var
  Words: TStringArray;
  Line: string;
  I: Integer;
begin
  Result := 1;
  Line := '';
  Words := AText.Split([' ']);
  for I := 0 to High(Words) do
  begin
    if (Line <> '') and (ACanvas.TextWidth(Line + ' ' + Words[I]) > AWidth) then
    begin
      Inc(Result);
      Line := Words[I];
    end
    else if Line = '' then
    begin
      Line := Words[I];
    end
    else
    begin
      Line := Line + ' ' + Words[I];
    end;
  end;
end;

function TpgnAccountDialog.AddLabel(const AText: string; AMuted: Boolean): TLabel;
var
  B: TBitmap;
  W, N: Integer;
begin
  W := ClientWidth - Scale96ToScreen(24);
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Caption := AText;
  if AMuted then
  begin
    Result.ParentFont := False;
    Result.Font.Color := clPgnMuted;
  end;
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(Result.Font);
    N := WrappedLines(B.Canvas, AText, W - Scale96ToScreen(8));
    Result.SetBounds(Scale96ToScreen(12), FY, W, N * (B.Canvas.TextHeight('Ag') + Scale96ToScreen(2)) +
      Scale96ToScreen(4));
  finally
    B.Free;
  end;
  FY := FY + Result.Height + Scale96ToScreen(8);
end;

function TpgnAccountDialog.AddEdit(const ACaption: string; APassword: Boolean): TEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Caption := ACaption;
  L.SetBounds(Scale96ToScreen(12), FY + Scale96ToScreen(5), Scale96ToScreen(160), L.Height);
  Remember(L);
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(Scale96ToScreen(180), FY, ClientWidth - Scale96ToScreen(192), Result.Height);
  if APassword then
  begin
    Result.PasswordChar := '*';
  end;
  Result.OnChange := @Changed;
  FY := FY + Result.Height + Scale96ToScreen(8);
end;

function TpgnAccountDialog.AddCombo(const ACaption: string; AItems: TStrings; AWidth: Integer): TComboBox;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Caption := ACaption;
  L.SetBounds(Scale96ToScreen(12), FY + Scale96ToScreen(5), Scale96ToScreen(160), L.Height);
  Remember(L);
  Result := TComboBox.Create(Self);
  Result.Parent := Self;
  Result.Style := csDropDownList;
  Result.AutoSize := False;
  Result.Items.Assign(AItems);
  if AWidth > 0 then
  begin
    Result.SetBounds(Scale96ToScreen(180), FY, Scale96ToScreen(AWidth), Scale96ToScreen(30));
  end
  else
  begin
    Result.SetBounds(Scale96ToScreen(180), FY, ClientWidth - Scale96ToScreen(192), Scale96ToScreen(30));
  end;
  if Result.Items.Count > 0 then
  begin
    Result.ItemIndex := 0;
  end;
  Result.OnChange := @Changed;
  FY := FY + Scale96ToScreen(38);
end;

function TpgnAccountDialog.AddCheck(const ACaption: string; AAtLeft: Boolean): TCheckBox;
var
  X: Integer;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  if AAtLeft then
  begin
    X := Scale96ToScreen(16);   // under the boxes above it
  end
  else
  begin
    X := Scale96ToScreen(180);
  end;
  Result.SetBounds(X, FY, ClientWidth - X - Scale96ToScreen(12), Result.Height);
  Result.OnChange := @Changed;
  FY := FY + Result.Height + Scale96ToScreen(8);
end;

function TpgnAccountDialog.AddGrid(AHeight: Integer): TStringGrid;
begin
  Result := TStringGrid.Create(Self);
  Result.Parent := Self;
  Result.FixedCols := 0;
  Result.RowCount := 1;
  Result.Options := Result.Options + [goRowSelect, goColSizing] - [goRangeSelect];
  Result.SetBounds(Scale96ToScreen(12), FY, ClientWidth - Scale96ToScreen(24), Scale96ToScreen(AHeight));
  FY := FY + Result.Height + Scale96ToScreen(8);
end;

procedure TpgnAccountDialog.Finish(APreviewHeight: Integer);
var
  L: TLabel;
  BW, BH: Integer;
begin
  L := TLabel.Create(Self);
  L.Parent := Self;
  L.Caption := 'Will run:';
  L.SetBounds(Scale96ToScreen(12), FY, Scale96ToScreen(200), L.Height);
  FY := FY + L.Height + Scale96ToScreen(4);
  Preview.Parent := Self;
  Preview.SetBounds(Scale96ToScreen(12), FY, ClientWidth - Scale96ToScreen(24), Scale96ToScreen(APreviewHeight));
  FY := FY + Preview.Height + Scale96ToScreen(12);
  BW := Scale96ToScreen(110);
  BH := Scale96ToScreen(32);
  BtnCancel.Parent := Self;
  BtnCancel.SetBounds(ClientWidth - Scale96ToScreen(12) - BW, FY, BW, BH);
  BtnOK.Parent := Self;
  BtnOK.SetBounds(BtnCancel.Left - Scale96ToScreen(8) - BW, FY, BW, BH);
  ClientHeight := FY + BH + Scale96ToScreen(12);
  Changed(nil);
end;

{ ------------------------------------------------------------ the panel }

constructor TpgnUsersPanel.CreateFor(AOwner: TComponent; AAdapter: TpgnAdapter;
  const AInfo: TpgnConnectionInfo; ALog: TpgnLogProc; const AMonoFont: string);
var
  I: Integer;
  P, Row: TPanel;
begin
  inherited Create(AOwner);
  FAdapter := AAdapter;
  FInfo := AInfo;
  FLog := ALog;
  FMono := AMonoFont;
  BevelOuter := bvNone;
  Caption := '';
  Color := clPgnWork;

  // the bar
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Height := Scale96ToScreen(36);
  FBar.BevelOuter := bvNone;
  FBar.Caption := '';
  FBar.Color := clPgnSurface;
  FBar.ParentColor := False;
  FBar.OnResize := @LayoutBar;

  FTitle := TLabel.Create(Self);
  FTitle.Parent := FBar;
  FTitle.Caption := 'Users and Roles';
  FTitle.ParentFont := False;
  FTitle.Font.Style := [fsBold];

  FBtnRefresh := NewButton(FBar, 'Refresh', @RefreshClick);

  FShowCombo := TComboBox.Create(Self);
  FShowCombo.Parent := FBar;
  FShowCombo.Style := csDropDownList;
  FShowCombo.AutoSize := False;
  FShowCombo.Items.Add('Users and roles');
  FShowCombo.Items.Add('Users only');
  FShowCombo.Items.Add('Roles only');
  FShowCombo.ItemIndex := 0;
  FShowCombo.OnChange := @FilterChange;

  FSystemCheck := TCheckBox.Create(Self);
  FSystemCheck.Parent := FBar;
  FSystemCheck.Caption := 'Show system accounts';
  FSystemCheck.Checked := False;
  FSystemCheck.OnChange := @RefreshClick;

  FFilterLabel := TLabel.Create(Self);
  FFilterLabel.Parent := FBar;
  FFilterLabel.Caption := 'Filter:';

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FBar;
  FFilter.OnChange := @FilterChange;

  FBarNote := TLabel.Create(Self);
  FBarNote.Parent := FBar;
  FBarNote.ParentFont := False;
  FBarNote.Font.Color := clPgnMuted;

  // left: the accounts and the buttons that make new ones
  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self;
  FLeft.Align := alLeft;
  FLeft.Width := Scale96ToScreen(320);
  FLeft.BevelOuter := bvNone;
  FLeft.Caption := '';

  FLeftButtons := ButtonRow(FLeft);
  FBtnNewUser := NewButton(FLeftButtons, 'New User...', @NewUserClick);
  FBtnNewRole := NewButton(FLeftButtons, 'New Role...', @NewRoleClick);

  FList := NewGrid(FLeft);
  FList.Align := alClient;
  FList.OnSelectCell := @ListSelectCell;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alLeft;
  FSplitter.Left := FLeft.Left + FLeft.Width + 1;
  FSplitter.Width := Scale96ToScreen(5);

  // right: the account picked
  FRight := TPanel.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alClient;
  FRight.BevelOuter := bvNone;
  FRight.Caption := '';

  FHead := TPanel.Create(Self);
  FHead.Parent := FRight;
  FHead.Align := alTop;
  FHead.Height := Scale96ToScreen(40);
  FHead.BevelOuter := bvNone;
  FHead.Caption := '';
  FHead.OnResize := @LayoutHead;

  FHeader := TLabel.Create(Self);
  FHeader.Parent := FHead;
  FHeader.ParentFont := False;
  FHeader.Font.Style := [fsBold];
  FHeader.Font.Height := -Scale96ToScreen(16);

  FBtnPassword := NewButton(FHead, 'Change Password...', @PasswordClick);
  FBtnDrop := NewButton(FHead, 'Drop...', @DropClick);

  FStrip := TTabControl.Create(Self);
  FStrip.Parent := FRight;
  FStrip.Align := alTop;
  FStrip.Top := FHead.Top + FHead.Height + 1;
  FStrip.Height := Scale96ToScreen(32);
  for I := 0 to High(PageNames) do
  begin
    FStrip.Tabs.Add(PageNames[I]);
  end;
  FStrip.OnChange := @StripChange;

  for I := 0 to High(FPages) do
  begin
    FPages[I] := NewPage;
  end;

  // General
  P := FPages[0];
  FApplyPanel := TPanel.Create(Self);
  FApplyPanel.Parent := P;
  FApplyPanel.Align := alBottom;
  FApplyPanel.Height := Scale96ToScreen(140);
  FApplyPanel.BevelOuter := bvNone;
  FApplyPanel.Caption := '';
  Row := ButtonRow(FApplyPanel);
  FBtnApply := NewButton(Row, 'Apply...', @ApplyClick);
  FBtnUndo := NewButton(Row, 'Undo Changes', @UndoClick);
  FBtnUndo.Align := alRight;
  FBtnUndo.Left := 20000;
  FBtnApply.Align := alRight;
  FBtnApply.Left := 30000;
  FWillRunLabel := TLabel.Create(Self);
  FWillRunLabel.Parent := FApplyPanel;
  FWillRunLabel.Align := alTop;
  FWillRunLabel.Caption := 'Will run:';
  FWillRunLabel.BorderSpacing.Around := Scale96ToScreen(6);
  FWillRun := TMemo.Create(Self);
  FWillRun.Parent := FApplyPanel;
  FWillRun.Align := alClient;
  FWillRun.ReadOnly := True;
  FWillRun.ScrollBars := ssAutoBoth;
  FWillRun.WordWrap := False;
  FWillRun.Font.Name := FMono;
  FWillRun.Color := clPgnShade;
  FWillRun.BorderSpacing.Left := Scale96ToScreen(6);
  FWillRun.BorderSpacing.Right := Scale96ToScreen(6);
  FAttrBox := TScrollBox.Create(Self);
  FAttrBox.Parent := P;
  FAttrBox.Align := alClient;
  FAttrBox.BorderStyle := bsNone;
  FAttrBox.HorzScrollBar.Visible := False;

  // Member Of
  P := FPages[1];
  Row := ButtonRow(P);
  FBtnGrantRole := NewButton(Row, 'Grant Role...', @GrantRoleClick);
  FBtnRevokeRole := NewButton(Row, 'Revoke...', @RevokeRoleClick);
  FMemberOfNote := TLabel.Create(Self);
  FMemberOfNote.Parent := Row;
  FMemberOfNote.Align := alClient;
  FMemberOfNote.Layout := tlCenter;
  FMemberOfNote.BorderSpacing.Left := Scale96ToScreen(10);
  FMemberOfNote.ParentFont := False;
  FMemberOfNote.Font.Color := clPgnMuted;
  FMemberOfGrid := NewGrid(P);
  FMemberOfGrid.Align := alClient;

  // Members
  P := FPages[2];
  Row := ButtonRow(P);
  FBtnAddMember := NewButton(Row, 'Add Member...', @AddMemberClick);
  FBtnRemoveMember := NewButton(Row, 'Remove...', @RemoveMemberClick);
  FMembersNote := TLabel.Create(Self);
  FMembersNote.Parent := Row;
  FMembersNote.Align := alClient;
  FMembersNote.Layout := tlCenter;
  FMembersNote.BorderSpacing.Left := Scale96ToScreen(10);
  FMembersNote.ParentFont := False;
  FMembersNote.Font.Color := clPgnMuted;
  FMembersGrid := NewGrid(P);
  FMembersGrid.Align := alClient;

  // Privileges
  P := FPages[3];
  Row := ButtonRow(P);
  FBtnGrantPriv := NewButton(Row, 'Grant...', @GrantPrivClick);
  FBtnRevokePriv := NewButton(Row, 'Revoke Selected...', @RevokePrivClick);
  FBtnRevokePriv.Width := Scale96ToScreen(150);
  FPrivNote := TLabel.Create(Self);
  FPrivNote.Parent := Row;
  FPrivNote.Align := alClient;
  FPrivNote.Layout := tlCenter;
  FPrivNote.BorderSpacing.Left := Scale96ToScreen(10);
  FPrivNote.ParentFont := False;
  FPrivNote.Font.Color := clPgnMuted;
  FPrivGrid := NewGrid(P);
  FPrivGrid.Align := alClient;
  FPrivGrid.Options := FPrivGrid.Options + [goRangeSelect];

  // SQL
  P := FPages[4];
  Row := ButtonRow(P);
  FBtnCopyDDL := NewButton(Row, 'Copy', @CopyDDLClick);
  FDDL := TMemo.Create(Self);
  FDDL.Parent := P;
  FDDL.Align := alClient;
  FDDL.ReadOnly := True;
  FDDL.ScrollBars := ssAutoBoth;
  FDDL.WordWrap := False;
  FDDL.Font.Name := FMono;

  ShowPage(0);
  ClearAccount;
end;

function TpgnUsersPanel.NewButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := Scale96ToScreen(130);
  if AParent is TPanel then
  begin
    if TPanel(AParent).Tag = 1 then
    begin
      // a button row: left to right
      Result.Align := alLeft;
      Result.Left := 10000 + AParent.ControlCount * 500;   // in the order made
      Result.BorderSpacing.Around := Scale96ToScreen(4);
    end;
  end;
end;

function TpgnUsersPanel.NewGrid(AParent: TWinControl): TStringGrid;
begin
  Result := TStringGrid.Create(Self);
  Result.Parent := AParent;
  Result.FixedCols := 0;
  Result.RowCount := 1;
  Result.ColCount := 1;
  Result.Options := Result.Options + [goRowSelect, goColSizing, goThumbTracking] -
    [goRangeSelect, goEditing];
  Result.DefaultRowHeight := Scale96ToScreen(24);
  Result.BorderStyle := bsNone;
  Result.OnResize := @GridResize;
end;

procedure TpgnUsersPanel.GridResize(Sender: TObject);
begin
  FitColumns(TStringGrid(Sender));
end;

function TpgnUsersPanel.NewPage: TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := FRight;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Align := alNone;
  Result.SetBounds(-10000, 0, 100, 100);
end;

function TpgnUsersPanel.ButtonRow(AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.Align := alBottom;
  Result.Height := Scale96ToScreen(40);
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Tag := 1;
end;

{ GTK3 shows hidden children again, so the pages not in use are moved out
  of sight rather than hidden. }
procedure TpgnUsersPanel.ShowPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
  begin
    if I <> AIndex then
    begin
      FPages[I].Align := alNone;
      FPages[I].SetBounds(-10000, 0, 100, 100);
    end;
  end;
  FPages[AIndex].Align := alClient;
  FStrip.TabIndex := AIndex;
  // grids filled while out of sight get their last column widened now
  case AIndex of
    1:
      begin
        FitColumns(FMemberOfGrid);
      end;
    2:
      begin
        FitColumns(FMembersGrid);
      end;
    3:
      begin
        FitColumns(FPrivGrid);
      end;
  end;
  if (AIndex = 4) and FHasCurrent and not FDDLLoaded then
  begin
    LoadDDL;
  end;
end;

procedure TpgnUsersPanel.StripChange(Sender: TObject);
begin
  ShowPage(FStrip.TabIndex);
end;

procedure TpgnUsersPanel.LayoutBar(Sender: TObject);
var
  X, H: Integer;

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
    C.SetBounds(X, (H - C.Height) div 2, W, C.Height);
    X := X + W + Scale96ToScreen(AGap);
  end;

begin
  H := FBar.ClientHeight;
  X := Scale96ToScreen(10);
  Place(FTitle, 0, 18);
  Place(FBtnRefresh, 90, 12);
  FShowCombo.Height := Scale96ToScreen(30);
  Place(FShowCombo, 150, 12);
  Place(FSystemCheck, 0, 18);
  Place(FFilterLabel, 0, 6);
  Place(FFilter, 160, 16);
  Place(FBarNote, 0, 0);
end;

procedure TpgnUsersPanel.LayoutHead(Sender: TObject);
var
  H, X, BW: Integer;
begin
  H := FHead.ClientHeight;
  BW := Scale96ToScreen(150);
  X := FHead.ClientWidth - Scale96ToScreen(8);
  FBtnDrop.SetBounds(X - Scale96ToScreen(90), (H - FBtnDrop.Height) div 2, Scale96ToScreen(90), FBtnDrop.Height);
  X := FBtnDrop.Left - Scale96ToScreen(6);
  FBtnPassword.SetBounds(X - BW, (H - FBtnPassword.Height) div 2, BW, FBtnPassword.Height);
  FHeader.SetBounds(Scale96ToScreen(10), (H - FHeader.Height) div 2,
    Max(10, FBtnPassword.Left - Scale96ToScreen(20)), FHeader.Height);
end;

{ ------------------------------------------------------------ the list }

function TpgnUsersPanel.AccountKind(const AAccount: TpgnAccount): string;
begin
  if AAccount.IsRole then
  begin
    Result := 'role';
  end
  else
  begin
    Result := 'user';
  end;
  if AAccount.IsSystem then
  begin
    Result := Result + ' (system)';
  end;
end;

procedure TpgnUsersPanel.ReadAccounts;
begin
  FAccounts := FAdapter.ListAccounts(FSystemCheck.Checked);
end;

procedure TpgnUsersPanel.FillList(const AKeep: string);
var
  I, N, KeepRow, Users, Roles: Integer;
  F: string;
  Wanted: Boolean;
  Host: Boolean;
  Old: TOnSelectCellEvent;
begin
  Host := FAdapter.AccountsHaveHost;
  F := LowerCase(Trim(FFilter.Text));
  SetLength(FShown, Length(FAccounts));
  N := 0;
  Users := 0;
  Roles := 0;
  for I := 0 to High(FAccounts) do
  begin
    Wanted := True;
    if (FShowCombo.ItemIndex = 1) and FAccounts[I].IsRole then
    begin
      Wanted := False;
    end;
    if (FShowCombo.ItemIndex = 2) and not FAccounts[I].IsRole then
    begin
      Wanted := False;
    end;
    if (F <> '') and (Pos(F, LowerCase(FAdapter.AccountText(FAccounts[I]))) = 0) then
    begin
      Wanted := False;
    end;
    if Wanted then
    begin
      FShown[N] := I;
      Inc(N);
      if FAccounts[I].IsRole then
      begin
        Inc(Roles);
      end
      else
      begin
        Inc(Users);
      end;
    end;
  end;
  SetLength(FShown, N);

  Old := FList.OnSelectCell;
  FList.OnSelectCell := nil;
  try
    if Host then
    begin
      FList.ColCount := 3;
      FList.Cells[0, 0] := 'Name';
      FList.Cells[1, 0] := 'Host';
      FList.Cells[2, 0] := 'Kind';
    end
    else
    begin
      FList.ColCount := 2;
      FList.Cells[0, 0] := 'Name';
      FList.Cells[1, 0] := 'Kind';
    end;
    FList.RowCount := N + 1;
    KeepRow := -1;
    for I := 0 to N - 1 do
    begin
      FList.Cells[0, I + 1] := FAccounts[FShown[I]].Name;
      if Host then
      begin
        FList.Cells[1, I + 1] := FAccounts[FShown[I]].Host;
        FList.Cells[2, I + 1] := AccountKind(FAccounts[FShown[I]]);
      end
      else
      begin
        FList.Cells[1, I + 1] := AccountKind(FAccounts[FShown[I]]);
      end;
      if FAdapter.AccountText(FAccounts[FShown[I]]) = AKeep then
      begin
        KeepRow := I + 1;
      end;
    end;
    FitColumns(FList);
    if (KeepRow < 0) and (N > 0) then
    begin
      KeepRow := 1;   // the first account, so the right side isn't empty
    end;
    if KeepRow > 0 then
    begin
      FList.Row := KeepRow;
    end;
  finally
    FList.OnSelectCell := Old;
  end;
  FBarNote.Caption := IntToStr(Users) + ' users, ' + IntToStr(Roles) + ' roles';
  if FAcctRight <> '' then
  begin
    FBarNote.Caption := FBarNote.Caption + '  ' + #$C2#$B7 + '  look only: ' + FAcctRight;
  end;
  FBarNote.Hint := FBarNote.Caption;
  FBarNote.ShowHint := True;
  LayoutBar(nil);
  if KeepRow > 0 then
  begin
    SelectRow(KeepRow);
  end
  else
  begin
    ClearAccount;
  end;
end;

procedure TpgnUsersPanel.Reload;
var
  Keep: string;
begin
  Keep := '';
  if FHasCurrent then
  begin
    Keep := FAdapter.AccountText(FCurrent);
  end;
  try
    ReadAccounts;
  except
    on E: Exception do
    begin
      FAccounts := nil;
      FLog('ERROR: could not read the accounts: ' + E.Message);
      FillList('');
      FBarNote.Caption := 'Could not read the accounts (Messages says why; your login may lack the right).';
      FBarNote.Font.Color := clPgnDanger;
      LayoutBar(nil);
      Exit;
    end;
  end;
  FBarNote.Font.Color := clPgnMuted;
  FAcctRight := FAdapter.MissingRight('accounts');
  FillList(Keep);
  ApplyRight;
end;

{ Look, but don't touch: without the right, everything stays readable and
  the buttons that change things are grayed, saying what's missing. }
procedure TpgnUsersPanel.ApplyRight;
var
  I: Integer;
  B: array[0..10] of TButton;
begin
  if FAcctRight = '' then
  begin
    Exit;
  end;
  B[0] := FBtnNewUser;
  B[1] := FBtnNewRole;
  B[2] := FBtnPassword;
  B[3] := FBtnDrop;
  B[4] := FBtnApply;
  B[5] := FBtnGrantRole;
  B[6] := FBtnRevokeRole;
  B[7] := FBtnAddMember;
  B[8] := FBtnRemoveMember;
  B[9] := FBtnGrantPriv;
  B[10] := FBtnRevokePriv;
  for I := 0 to High(B) do
  begin
    B[I].Enabled := False;
    B[I].Hint := FAcctRight;
    B[I].ShowHint := True;
  end;
end;

procedure TpgnUsersPanel.SelectAccount(const AText: string);
begin
  FFilter.Text := '';
  FShowCombo.ItemIndex := 0;
  FillList(AText);
end;

function TpgnUsersPanel.CanLeave: Boolean;
begin
  Result := True;
  if HasPending then
  begin
    Result := MessageDlg('Changes to ' + FAdapter.AccountText(FCurrent) + ' have not been applied.' +
      LineEnding + LineEnding + 'Leave them unapplied?', mtConfirmation, [mbYes, mbNo], 0, mbNo) = mrYes;
  end;
end;

procedure TpgnUsersPanel.ListSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  if ((aRow = FList.Row) and FHasCurrent) or (aRow < 1) then
  begin
    Exit;
  end;
  if not CanLeave then
  begin
    CanSelect := False;
    Exit;
  end;
  SelectRow(aRow);
end;

procedure TpgnUsersPanel.SelectRow(ARow: Integer);
begin
  if (ARow < 1) or (ARow > Length(FShown)) then
  begin
    ClearAccount;
    Exit;
  end;
  FCurrent := FAccounts[FShown[ARow - 1]];
  FHasCurrent := True;
  LoadAccount;
end;

{ ------------------------------------------------------------ one account }

procedure TpgnUsersPanel.ClearAccount;
var
  I: Integer;
begin
  FHasCurrent := False;
  FAttrs := nil;
  FEdited := nil;
  FPending := nil;
  for I := FAttrBox.ControlCount - 1 downto 0 do
  begin
    FAttrBox.Controls[I].Free;
  end;
  FAttrControls := nil;
  FHeader.Caption := 'Pick an account on the left';
  FWillRun.Lines.Text := '';
  FillGrid(FMemberOfGrid, nil);
  FillGrid(FMembersGrid, nil);
  FillGrid(FPrivGrid, nil);
  FDDL.Lines.Text := '';
  FDDLLoaded := False;
  FBtnPassword.Enabled := False;
  FBtnDrop.Enabled := False;
  FBtnApply.Enabled := False;
  FBtnUndo.Enabled := False;
  FBtnGrantRole.Enabled := False;
  FBtnRevokeRole.Enabled := False;
  FBtnAddMember.Enabled := False;
  FBtnRemoveMember.Enabled := False;
  FBtnRevokePriv.Enabled := False;
  FBtnGrantPriv.Enabled := False;
  FBtnCopyDDL.Enabled := False;
  FMemberOfNote.Caption := '';
  FMembersNote.Caption := '';
  FPrivNote.Caption := '';
end;

procedure TpgnUsersPanel.LoadAccount;
var
  R: TpgnResultSet;
  Roles: Boolean;
begin
  FHeader.Caption := FAdapter.AccountText(FCurrent) + '  ' + #$C2#$B7 + '  ' + AccountKind(FCurrent);
  FBtnPassword.Enabled := not FCurrent.IsRole;
  FBtnDrop.Enabled := True;
  FBtnCopyDDL.Enabled := True;
  Roles := FAdapter.HasRoles;

  // General
  try
    FAttrs := FAdapter.AccountAttrs(FCurrent);
  except
    on E: Exception do
    begin
      FAttrs := nil;
      FLog('ERROR: could not read ' + FAdapter.AccountText(FCurrent) + ': ' + E.Message);
    end;
  end;
  FEdited := Copy(FAttrs);
  BuildAttrRows;
  UpdatePending;

  // Member Of / Members
  FBtnGrantRole.Enabled := Roles;
  FBtnAddMember.Enabled := Roles;
  if not Roles then
  begin
    FMemberOfNote.Caption := 'This server has no roles to grant (MySQL has them from 8.0).';
    FMembersNote.Caption := FMemberOfNote.Caption;
    FillGrid(FMemberOfGrid, nil);
    FillGrid(FMembersGrid, nil);
    FBtnRevokeRole.Enabled := False;
    FBtnRemoveMember.Enabled := False;
  end
  else
  begin
    FMemberOfNote.Caption := '';
    FMembersNote.Caption := '';
    try
      R := FAdapter.AccountMemberOf(FCurrent);
      try
        FillGrid(FMemberOfGrid, R);
        FBtnRevokeRole.Enabled := (R <> nil) and (R.RowCount > 0);
        if (R <> nil) and (R.RowCount = 0) then
        begin
          FMemberOfNote.Caption := 'Not a member of any role.';
        end;
      finally
        R.Free;
      end;
    except
      on E: Exception do
      begin
        FillGrid(FMemberOfGrid, nil);
        FMemberOfNote.Caption := 'Could not read the roles: ' + E.Message;
      end;
    end;
    try
      R := FAdapter.AccountMembers(FCurrent);
      try
        FillGrid(FMembersGrid, R);
        FBtnRemoveMember.Enabled := (R <> nil) and (R.RowCount > 0);
        if (R <> nil) and (R.RowCount = 0) then
        begin
          FMembersNote.Caption := 'Nobody has been granted ' + FAdapter.AccountText(FCurrent) + '.';
        end;
      finally
        R.Free;
      end;
    except
      on E: Exception do
      begin
        FillGrid(FMembersGrid, nil);
        FMembersNote.Caption := 'Could not read the members: ' + E.Message;
      end;
    end;
  end;

  // Privileges
  FBtnGrantPriv.Enabled := Length(FAdapter.GrantTargets) > 0;
  try
    R := FAdapter.AccountPrivileges(FCurrent);
    try
      FillGrid(FPrivGrid, R);
      FBtnRevokePriv.Enabled := (R <> nil) and (R.RowCount > 0);
      if (R = nil) or (R.RowCount = 0) then
      begin
        FPrivNote.Caption := 'No privileges granted directly (roles may give more).';
      end
      else if FInfo.Engine = fePostgreSQL then
      begin
        FPrivNote.Caption := IntToStr(R.RowCount) + ' grants, in database ' + FAdapter.CurrentDatabase +
          ' (each database keeps its own)';
      end
      else
      begin
        FPrivNote.Caption := IntToStr(R.RowCount) + ' grants';
      end;
    finally
      R.Free;
    end;
  except
    on E: Exception do
    begin
      FillGrid(FPrivGrid, nil);
      FBtnRevokePriv.Enabled := False;
      FPrivNote.Caption := 'Could not read the privileges: ' + E.Message;
    end;
  end;

  ApplyRight;

  // SQL: read when its page is shown
  FDDLLoaded := False;
  FDDL.Lines.Text := '';
  if FStrip.TabIndex = 4 then
  begin
    LoadDDL;
  end;
end;

procedure TpgnUsersPanel.LoadDDL;
begin
  try
    FDDL.Lines.Text := FAdapter.AccountDDL(FCurrent);
  except
    on E: Exception do
    begin
      FDDL.Lines.Text := '-- Could not write the SQL for this account:' + LineEnding + '-- ' + E.Message;
    end;
  end;
  FDDLLoaded := True;
end;

procedure TpgnUsersPanel.BuildAttrRows;
var
  I, Y, RowH, CX: Integer;
  L, HintLabel: TLabel;
  C: TControl;
  E: TEdit;
  K: TCheckBox;
  B: TComboBox;
begin
  FFilling := True;
  try
    for I := FAttrBox.ControlCount - 1 downto 0 do
    begin
      FAttrBox.Controls[I].Free;
    end;
    SetLength(FAttrControls, Length(FEdited));
    RowH := Scale96ToScreen(31);
    CX := Scale96ToScreen(290);
    Y := Scale96ToScreen(10);
    if Length(FEdited) = 0 then
    begin
      L := TLabel.Create(FAttrBox);
      L.Parent := FAttrBox;
      L.Caption := 'No settings to show for this account.';
      L.SetBounds(Scale96ToScreen(12), Y, Scale96ToScreen(400), L.Height);
    end;
    for I := 0 to High(FEdited) do
    begin
      L := TLabel.Create(FAttrBox);
      L.Parent := FAttrBox;
      L.Caption := FEdited[I].Caption;
      L.SetBounds(Scale96ToScreen(12), Y + Scale96ToScreen(6), CX - Scale96ToScreen(20), L.Height);
      case FEdited[I].Kind of
        akBool:
          begin
            K := TCheckBox.Create(FAttrBox);
            K.Parent := FAttrBox;
            K.Caption := '';
            K.Checked := FEdited[I].Value = '1';
            K.OnChange := @AttrChanged;
            K.SetBounds(CX, Y + Scale96ToScreen(4), Scale96ToScreen(24), K.Height);
            C := K;
          end;
        akChoice:
          begin
            B := TComboBox.Create(FAttrBox);
            B.Parent := FAttrBox;
            B.Style := csDropDownList;
            B.AutoSize := False;
            B.Items.AddStrings(FEdited[I].Choices);
            if B.Items.IndexOf(FEdited[I].Value) < 0 then
            begin
              B.Items.Add(FEdited[I].Value);
            end;
            B.ItemIndex := B.Items.IndexOf(FEdited[I].Value);
            B.OnChange := @AttrChanged;
            B.SetBounds(CX, Y, Scale96ToScreen(280), Scale96ToScreen(30));
            C := B;
          end;
      else
        begin
          E := TEdit.Create(FAttrBox);
          E.Parent := FAttrBox;
          E.Text := FEdited[I].Value;
          E.OnChange := @AttrChanged;
          if FEdited[I].Kind = akInt then
          begin
            E.SetBounds(CX, Y, Scale96ToScreen(100), E.Height);
          end
          else
          begin
            E.SetBounds(CX, Y, Scale96ToScreen(180), E.Height);
          end;
          C := E;
        end;
      end;
      C.Tag := I;
      C.Enabled := not FEdited[I].ReadOnly;
      FAttrControls[I] := C;
      if FEdited[I].Hint <> '' then
      begin
        HintLabel := TLabel.Create(FAttrBox);
        HintLabel.Parent := FAttrBox;
        HintLabel.ParentFont := False;
        HintLabel.Font.Color := clPgnMuted;
        HintLabel.Caption := FEdited[I].Hint;
        HintLabel.SetBounds(C.Left + C.Width + Scale96ToScreen(12), Y + Scale96ToScreen(6),
          Scale96ToScreen(420), HintLabel.Height);
      end;
      Y := Y + RowH;
    end;
  finally
    FFilling := False;
  end;
end;

procedure TpgnUsersPanel.AttrChanged(Sender: TObject);
var
  I: Integer;
  C: TControl;
begin
  if FFilling then
  begin
    Exit;
  end;
  for I := 0 to High(FAttrControls) do
  begin
    C := FAttrControls[I];
    if C is TCheckBox then
    begin
      if TCheckBox(C).Checked then
      begin
        FEdited[I].Value := '1';
      end
      else
      begin
        FEdited[I].Value := '0';
      end;
    end
    else if C is TComboBox then
    begin
      FEdited[I].Value := TComboBox(C).Text;
    end
    else if C is TEdit then
    begin
      FEdited[I].Value := TEdit(C).Text;
    end;
  end;
  UpdatePending;
end;

procedure TpgnUsersPanel.UpdatePending;
var
  Problem: string;
begin
  FPending := nil;
  Problem := '';
  if FHasCurrent then
  begin
    try
      FPending := FAdapter.AlterAccountSQL(FCurrent, FAttrs, FEdited);
    except
      on E: Exception do
      begin
        FPending := nil;
        Problem := E.Message;
      end;
    end;
  end;
  if Problem <> '' then
  begin
    FWillRun.Lines.Text := '-- ' + Problem;
  end
  else if Length(FPending) = 0 then
  begin
    FWillRun.Lines.Text := '-- nothing changed yet';
  end
  else
  begin
    FWillRun.Lines.Text := JoinStatements(FPending);
  end;
  FBtnApply.Enabled := (Length(FPending) > 0) and (FAcctRight = '');
  FBtnUndo.Enabled := FHasCurrent and ((Length(FPending) > 0) or (Problem <> ''));
end;

function TpgnUsersPanel.HasPending: Boolean;
begin
  Result := FHasCurrent and FBtnUndo.Enabled;
end;

procedure TpgnUsersPanel.FillGrid(AGrid: TStringGrid; AData: TpgnResultSet);
var
  R, C: Integer;
begin
  if (AData = nil) or (AData.ColumnCount = 0) then
  begin
    AGrid.ColCount := 1;
    AGrid.RowCount := 1;
    AGrid.Cells[0, 0] := '';
    Exit;
  end;
  AGrid.ColCount := AData.ColumnCount;
  AGrid.RowCount := AData.RowCount + 1;
  for C := 0 to AData.ColumnCount - 1 do
  begin
    AGrid.Cells[C, 0] := AData.Columns[C];
  end;
  for R := 0 to AData.RowCount - 1 do
  begin
    for C := 0 to AData.ColumnCount - 1 do
    begin
      AGrid.Cells[C, R + 1] := AData.Rows[R].Values[C];
    end;
  end;
  FitColumns(AGrid);
end;

function TpgnUsersPanel.GridValue(AGrid: TStringGrid; ARow, ACol: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow < AGrid.RowCount) and (ACol < AGrid.ColCount) then
  begin
    Result := AGrid.Cells[ACol, ARow];
  end;
end;

{ Account texts to pick from (not the system ones, not the current one). }
function TpgnUsersPanel.OtherAccounts(AIncludeSelf: Boolean): TStringList;
var
  I: Integer;
  Same: Boolean;
begin
  Result := TStringList.Create;
  for I := 0 to High(FAccounts) do
  begin
    Same := FHasCurrent and (FAdapter.AccountText(FAccounts[I]) = FAdapter.AccountText(FCurrent));
    if (AIncludeSelf or not Same) and not FAccounts[I].IsSystem then
    begin
      Result.Add(FAdapter.AccountText(FAccounts[I]));
    end;
  end;
end;

{ ------------------------------------------------------------ running }

{ Asks (default No), runs each statement, logs each with what it was for.
  AShown is ASQL with passwords as ****. A list that starts with BEGIN is
  rolled back when a statement fails. }
function RunAdminStatements(AAdapter: TpgnAdapter; const AInfo: TpgnConnectionInfo; ALog: TpgnLogProc;
  const AWhat: string; const ASQL, AShown: TpgnStringArray; AWarn: Boolean; out ATried: Boolean): Boolean;
var
  I: Integer;
  Kind: TMsgDlgType;
  InTx: Boolean;
begin
  Result := False;
  ATried := False;
  if Length(ASQL) = 0 then
  begin
    Exit;
  end;
  if AWarn then
  begin
    Kind := mtWarning;
  end
  else
  begin
    Kind := mtConfirmation;
  end;
  if MessageDlg(AWhat + ' on ' + ConnectionLongLabel(AInfo) + '?' + LineEnding + LineEnding +
    JoinStatements(AShown), Kind, [mbYes, mbNo], 0, mbNo) <> mrYes then
  begin
    Exit;
  end;
  ATried := True;
  InTx := UpperCase(ASQL[0]) = 'BEGIN';
  for I := 0 to High(ASQL) do
  begin
    try
      AAdapter.RunAdmin(ASQL[I]);
      if (UpperCase(ASQL[I]) <> 'BEGIN') and (UpperCase(ASQL[I]) <> 'COMMIT') then
      begin
        DbaLog(AInfo, AWhat, AShown[I]);
        ALog(AWhat + ': ' + AShown[I]);
      end;
    except
      on E: Exception do
      begin
        if InTx then
        begin
          try
            AAdapter.RunAdmin('ROLLBACK');
          except
            on E2: Exception do
            begin
              // the session may already have ended the transaction
            end;
          end;
          ALog('ERROR: ' + AWhat + ' failed; nothing was changed: ' + E.Message);
          MessageDlg(AWhat + ' failed, and nothing was changed.' + LineEnding + LineEnding +
            AShown[I] + LineEnding + LineEnding + E.Message, mtError, [mbOK], 0);
        end
        else
        begin
          ALog('ERROR: ' + AShown[I] + ': ' + E.Message);
          if I > 0 then
          begin
            MessageDlg(AWhat + ' stopped at:' + LineEnding + LineEnding + AShown[I] + LineEnding +
              LineEnding + E.Message + LineEnding + LineEnding +
              'The statements before it did run (Messages lists them).', mtError, [mbOK], 0);
          end
          else
          begin
            MessageDlg(AWhat + ' failed.' + LineEnding + LineEnding + AShown[I] + LineEnding +
              LineEnding + E.Message, mtError, [mbOK], 0);
          end;
        end;
        Exit;
      end;
    end;
  end;
  Result := True;
end;


function TpgnUsersPanel.RunStatements(const AWhat: string; const ASQL, AShown: TpgnStringArray;
  AWarn: Boolean): Boolean;
var
  Tried: Boolean;
begin
  Result := RunAdminStatements(FAdapter, FInfo, FLog, AWhat, ASQL, AShown, AWarn, Tried);
  if Tried then
  begin
    Reload;
  end;
end;

{ ------------------------------------------------------------ actions }

procedure TpgnUsersPanel.RefreshClick(Sender: TObject);
begin
  if CanLeave then
  begin
    Reload;
  end;
end;

procedure TpgnUsersPanel.FilterChange(Sender: TObject);
var
  Keep: string;
begin
  Keep := '';
  if FHasCurrent then
  begin
    Keep := FAdapter.AccountText(FCurrent);
  end;
  FillList(Keep);
end;

procedure TpgnUsersPanel.NewUserClick(Sender: TObject);
begin
  NewAccount(False);
end;

procedure TpgnUsersPanel.NewRoleClick(Sender: TObject);
begin
  NewAccount(True);
end;

type
  { Keeps the New User dialog's preview up to date. }
  TpgnNewAccountHelper = class
  public
    Adapter: TpgnAdapter;
    IsRole: Boolean;
    Dlg: TpgnAccountDialog;
    NameEdit, HostEdit, Pass1, Pass2: TEdit;
    CopyCombo: TComboBox;
    CopyFrom: string;            // the source the copy statements were read for
    CopyStatements: TpgnStringArray;
    CopyProblem: string;
    function Account: TpgnAccount;
    procedure Preview(Sender: TObject);
    function Statements(AMasked: Boolean): TpgnStringArray;
  end;

function TpgnNewAccountHelper.Account: TpgnAccount;
begin
  Result := Default(TpgnAccount);
  Result.Name := Trim(NameEdit.Text);
  if HostEdit <> nil then
  begin
    Result.Host := Trim(HostEdit.Text);
    if Result.Host = '' then
    begin
      Result.Host := '%';
    end;
  end;
  Result.IsRole := IsRole;
end;

function TpgnNewAccountHelper.Statements(AMasked: Boolean): TpgnStringArray;
var
  P, S: string;
  I: Integer;
  Src, Dst: TpgnAccount;
begin
  P := '';
  if Pass1 <> nil then
  begin
    P := Pass1.Text;
    if AMasked and (P <> '') then
    begin
      P := Masked;
    end;
  end;
  Result := Adapter.CreateAccountSQL(Account, P);
  if (CopyCombo <> nil) and (CopyCombo.ItemIndex > 0) then
  begin
    if CopyFrom <> CopyCombo.Text then
    begin
      // read the source's access once per choice; the new name goes in below
      CopyFrom := CopyCombo.Text;
      CopyProblem := '';
      CopyStatements := nil;
      try
        Src := Adapter.AccountFromText(CopyFrom);
        Dst := Default(TpgnAccount);
        Dst.Name := #1'NEW'#1;
        Dst.Host := #1'HOST'#1;
        CopyStatements := Adapter.CopyAccessSQL(Src, Dst);
      except
        on E: Exception do
        begin
          CopyProblem := E.Message;
        end;
      end;
    end;
    // the placeholder name, quoted as the adapter quotes it, becomes the
    // real one quoted the same way
    Dst := Account;
    for I := 0 to High(CopyStatements) do
    begin
      S := CopyStatements[I];
      S := StringReplace(S, Adapter.QuoteIdent(#1'NEW'#1), Adapter.QuoteIdent(Dst.Name), [rfReplaceAll]);
      S := StringReplace(S, Adapter.QuoteLiteral(#1'NEW'#1), Adapter.QuoteLiteral(Dst.Name), [rfReplaceAll]);
      S := StringReplace(S, Adapter.QuoteLiteral(#1'HOST'#1), Adapter.QuoteLiteral(Dst.Host), [rfReplaceAll]);
      S := StringReplace(S, #1'NEW'#1, Dst.Name, [rfReplaceAll]);
      S := StringReplace(S, #1'HOST'#1, Dst.Host, [rfReplaceAll]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
  end;
end;

procedure TpgnNewAccountHelper.Preview(Sender: TObject);
var
  S: string;
  OK: Boolean;
begin
  OK := Trim(NameEdit.Text) <> '';
  if not OK then
  begin
    S := '-- type a name';
  end
  else if (Pass1 <> nil) and (Pass1.Text <> Pass2.Text) then
  begin
    S := '-- the two passwords are not the same';
    OK := False;
  end
  else
  begin
    try
      S := JoinStatements(Statements(True));
      if CopyProblem <> '' then
      begin
        S := S + '-- could not read the access to copy: ' + CopyProblem + LineEnding;
      end;
    except
      on E: Exception do
      begin
        S := '-- ' + E.Message;
        OK := False;
      end;
    end;
  end;
  Dlg.Preview.Lines.Text := S;
  Dlg.BtnOK.Enabled := OK;
end;

procedure TpgnUsersPanel.NewAccount(AIsRole: Boolean);
var
  H: TpgnNewAccountHelper;
  Items: TStringList;
  What: string;
  A: TpgnAccount;
begin
  H := TpgnNewAccountHelper.Create;
  try
    H.Adapter := FAdapter;
    H.IsRole := AIsRole;
    if AIsRole then
    begin
      What := 'New Role';
    end
    else
    begin
      What := 'New User';
    end;
    H.Dlg := TpgnAccountDialog.CreateDlg(What + ' on ' + ConnectionLongLabel(FInfo), 'Create...', 560, FMono);
    try
      H.NameEdit := H.Dlg.AddEdit('Name');
      if FAdapter.AccountsHaveHost then
      begin
        H.HostEdit := H.Dlg.AddEdit('Host (% = anywhere)');
        H.HostEdit.Text := '%';
      end;
      if not AIsRole then
      begin
        H.Pass1 := H.Dlg.AddEdit('Password', True);
        H.Pass2 := H.Dlg.AddEdit('Password again', True);
      end;
      Items := OtherAccounts(True);
      try
        Items.Insert(0, NobodyText);
        H.CopyCombo := H.Dlg.AddCombo('Copy access from', Items);
      finally
        Items.Free;
      end;
      H.Dlg.AddLabel('Copying gives the new account the same roles and object grants as the one ' +
        'picked; its settings and password are not copied.', True);
      if not AIsRole then
      begin
        H.Dlg.AddLabel('The password travels inside the statement: the server''s own statement log, ' +
          'if it keeps one, can record it. Pagona shows and logs it as ****.', True);
      end;
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(150);
      H.Dlg.ActiveControl := H.NameEdit;
      if H.Dlg.ShowModal <> mrOK then
      begin
        Exit;
      end;
      A := H.Account;
      if RunStatements(What + ' ' + FAdapter.AccountText(A), H.Statements(False), H.Statements(True), False) then
      begin
        // show the new account
        FFilter.Text := '';
        FillList(FAdapter.AccountText(A));
      end;
    finally
      H.Dlg.Free;
    end;
  finally
    H.Free;
  end;
end;

type
  TpgnPasswordHelper = class
  public
    Adapter: TpgnAdapter;
    Account: TpgnAccount;
    Dlg: TpgnAccountDialog;
    P1, P2: TEdit;
    procedure Preview(Sender: TObject);
  end;

procedure TpgnPasswordHelper.Preview(Sender: TObject);
begin
  if P1.Text = '' then
  begin
    Dlg.Preview.Lines.Text := '-- type the new password';
    Dlg.BtnOK.Enabled := False;
  end
  else if P1.Text <> P2.Text then
  begin
    Dlg.Preview.Lines.Text := '-- the two passwords are not the same';
    Dlg.BtnOK.Enabled := False;
  end
  else
  begin
    Dlg.Preview.Lines.Text := Adapter.PasswordSQL(Account, Masked) + ';';
    Dlg.BtnOK.Enabled := True;
  end;
end;

procedure TpgnUsersPanel.PasswordClick(Sender: TObject);
var
  H: TpgnPasswordHelper;
  Pass: string;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  H := TpgnPasswordHelper.Create;
  try
    H.Adapter := FAdapter;
    H.Account := FCurrent;
    H.Dlg := TpgnAccountDialog.CreateDlg('Change Password of ' + FAdapter.AccountText(FCurrent) + ' on ' +
      ConnectionLongLabel(FInfo), 'Change...', 560, FMono);
    try
      H.P1 := H.Dlg.AddEdit('New password', True);
      H.P2 := H.Dlg.AddEdit('New password again', True);
      H.Dlg.AddLabel('The password travels inside the statement: the server''s own statement log, ' +
        'if it keeps one, can record it. Pagona shows and logs it as ****.', True);
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(60);
      H.Dlg.ActiveControl := H.P1;
      if H.Dlg.ShowModal <> mrOK then
      begin
        Exit;
      end;
      Pass := H.P1.Text;
    finally
      H.Dlg.Free;
    end;
  finally
    H.Free;
  end;
  RunStatements('Change password of ' + FAdapter.AccountText(FCurrent),
    One(FAdapter.PasswordSQL(FCurrent, Pass)), One(FAdapter.PasswordSQL(FCurrent, Masked)), False);
end;

type
  { Keeps the Drop dialog's preview up to date. }
  TpgnDropHelper = class
  public
    Adapter: TpgnAdapter;
    Account: TpgnAccount;
    Owns: Integer;
    Dlg: TpgnAccountDialog;
    ToCombo: TComboBox;
    DeleteCheck: TCheckBox;
    function ReassignTo: string;
    function Statements: TpgnStringArray;
    procedure Preview(Sender: TObject);
  end;

function TpgnDropHelper.ReassignTo: string;
begin
  Result := '';
  if (ToCombo <> nil) and (ToCombo.ItemIndex > 0) then
  begin
    Result := Adapter.AccountFromText(ToCombo.Text).Name;
  end;
end;

function TpgnDropHelper.Statements: TpgnStringArray;
begin
  // DROP OWNED also takes away its grants, which DROP ROLE needs gone
  if Adapter.DropOwnedChoice then
  begin
    Result := Adapter.DropAccountSQL(Account, '', (DeleteCheck <> nil) and DeleteCheck.Checked);
  end
  else
  begin
    Result := Adapter.DropAccountSQL(Account, ReassignTo, Adapter.CanReassignOwned);
  end;
end;

procedure TpgnDropHelper.Preview(Sender: TObject);
var
  OK: Boolean;
begin
  OK := True;
  if Adapter.DropOwnedChoice and (Owns > 0) then
  begin
    OK := DeleteCheck.Checked;
  end
  else if Adapter.CanReassignOwned and (Owns > 0) then
  begin
    if DeleteCheck.Checked then
    begin
      ToCombo.Enabled := False;
    end
    else
    begin
      ToCombo.Enabled := True;
      OK := ReassignTo <> '';
    end;
  end;
  if OK then
  begin
    if Adapter.CanReassignOwned and (Owns > 0) and DeleteCheck.Checked then
    begin
      Dlg.Preview.Lines.Text := JoinStatements(Adapter.DropAccountSQL(Account, '', True));
    end
    else
    begin
      Dlg.Preview.Lines.Text := JoinStatements(Statements);
    end;
  end
  else
  begin
    if Adapter.DropOwnedChoice then
    begin
      Dlg.Preview.Lines.Text := '-- tick "Drop what it owns too" to go ahead';
    end
    else
    begin
      Dlg.Preview.Lines.Text := '-- choose who gets what it owns, or tick "Delete what it owns"';
    end;
  end;
  Dlg.BtnOK.Enabled := OK;
end;

procedure TpgnUsersPanel.DropClick(Sender: TObject);
var
  H: TpgnDropHelper;
  R: TpgnResultSet;
  Grid: TStringGrid;
  Items: TStringList;
  Who, Problem: string;
  I, C: Integer;
  SQL: TpgnStringArray;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  Who := FAdapter.AccountText(FCurrent);
  H := TpgnDropHelper.Create;
  try
    H.Adapter := FAdapter;
    H.Account := FCurrent;
    H.Dlg := TpgnAccountDialog.CreateDlg('Drop ' + Who + ' on ' + ConnectionLongLabel(FInfo), 'Drop...',
      620, FMono);
    try
      Problem := '';
      R := nil;
      try
        R := FAdapter.AccountOwns(FCurrent);
      except
        on E: Exception do
        begin
          Problem := E.Message;
        end;
      end;
      try
        if R <> nil then
        begin
          H.Owns := R.RowCount;
        end;
        if Problem <> '' then
        begin
          H.Dlg.AddLabel('Could not check what ' + Who + ' owns: ' + Problem);
        end
        else if H.Owns = 0 then
        begin
          H.Dlg.AddLabel(Who + ' owns nothing that Pagona can see.');
        end
        else if FAdapter.CanReassignOwned or FAdapter.DropOwnedChoice then
        begin
          H.Dlg.AddLabel(Who + ' owns ' + IntToStr(H.Owns) + ' objects:');
        end
        else
        begin
          H.Dlg.AddLabel(Who + ' is the definer of ' + IntToStr(H.Owns) + ' objects:');
        end;
        if H.Owns > 0 then
        begin
          Grid := H.Dlg.AddGrid(150);
          Grid.ColCount := R.ColumnCount;
          Grid.RowCount := R.RowCount + 1;
          for C := 0 to R.ColumnCount - 1 do
          begin
            Grid.Cells[C, 0] := R.Columns[C];
          end;
          for I := 0 to R.RowCount - 1 do
          begin
            for C := 0 to R.ColumnCount - 1 do
            begin
              Grid.Cells[C, I + 1] := R.Rows[I].Values[C];
            end;
          end;
          FitColumns(Grid);
        end;
      finally
        R.Free;
      end;
      if FAdapter.DropOwnedChoice then
      begin
        if H.Owns > 0 then
        begin
          H.DeleteCheck := H.Dlg.AddCheck('Drop what it owns too (CASCADE)');
          H.Dlg.AddLabel('Oracle can''t hand a user''s objects to someone else: the user can only be ' +
            'dropped together with them. Tables, code and data in its schema are gone for good. ' +
            'Code elsewhere that uses them becomes INVALID.', True);
        end;
      end
      else if FAdapter.CanReassignOwned then
      begin
        if H.Owns > 0 then
        begin
          Items := OtherAccounts(False);
          try
            Items.Insert(0, '(choose)');
            H.ToCombo := H.Dlg.AddCombo('Give them to', Items);
          finally
            Items.Free;
          end;
          H.DeleteCheck := H.Dlg.AddCheck('Delete what it owns instead');
        end;
        H.Dlg.AddLabel('REASSIGN OWNED and DROP OWNED work in this database only (' +
          FAdapter.CurrentDatabase + '). If it owns things in another database, PostgreSQL refuses the ' +
          'drop and nothing is changed. All of it runs as one transaction.', True);
      end
      else if H.Owns > 0 then
      begin
        H.Dlg.AddLabel('These keep ' + Who + ' as their definer. Once it''s gone they fail when used ' +
          '(MySQL 8.0.22 on refuses the drop). Change their DEFINER first.', True);
      end;
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(110);
      if H.Dlg.ShowModal <> mrOK then
      begin
        Exit;
      end;
      if FAdapter.CanReassignOwned and (H.Owns > 0) and H.DeleteCheck.Checked then
      begin
        SQL := FAdapter.DropAccountSQL(FCurrent, '', True);
      end
      else
      begin
        SQL := H.Statements;
      end;
    finally
      H.Dlg.Free;
    end;
  finally
    H.Free;
  end;
  // the list is read again; the first account is picked in its place
  RunStatements('Drop ' + Who, SQL, SQL, True);
end;

procedure TpgnUsersPanel.UndoClick(Sender: TObject);
begin
  FEdited := Copy(FAttrs);
  BuildAttrRows;
  UpdatePending;
end;

procedure TpgnUsersPanel.ApplyClick(Sender: TObject);
var
  SQL: TpgnStringArray;
begin
  if not FHasCurrent or (Length(FPending) = 0) then
  begin
    Exit;
  end;
  SQL := Copy(FPending);
  if RunStatements('Change ' + FAdapter.AccountText(FCurrent), SQL, SQL, False) then
  begin
    LoadAccount;
  end;
end;

procedure TpgnUsersPanel.GrantRoleClick(Sender: TObject);
begin
  RoleDialog(False);
end;

procedure TpgnUsersPanel.AddMemberClick(Sender: TObject);
begin
  RoleDialog(True);
end;

type
  TpgnRoleHelper = class
  public
    Adapter: TpgnAdapter;
    Current: TpgnAccount;
    AddMember: Boolean;
    Dlg: TpgnAccountDialog;
    Combo: TComboBox;
    Admin: TCheckBox;
    function Statements: TpgnStringArray;
    procedure Preview(Sender: TObject);
  end;

function TpgnRoleHelper.Statements: TpgnStringArray;
var
  Other: TpgnAccount;
begin
  Other := Adapter.AccountFromText(Combo.Text);
  if AddMember then
  begin
    Result := Adapter.GrantRoleSQL(Current, Other, Admin.Checked);
  end
  else
  begin
    Result := Adapter.GrantRoleSQL(Other, Current, Admin.Checked);
  end;
end;

procedure TpgnRoleHelper.Preview(Sender: TObject);
begin
  if Combo.ItemIndex < 1 then
  begin
    Dlg.Preview.Lines.Text := '-- choose one';
    Dlg.BtnOK.Enabled := False;
  end
  else
  begin
    Dlg.Preview.Lines.Text := JoinStatements(Statements);
    Dlg.BtnOK.Enabled := True;
  end;
end;

procedure TpgnUsersPanel.RoleDialog(AAddMember: Boolean);
var
  H: TpgnRoleHelper;
  Items: TStringList;
  Who, What: string;
  SQL: TpgnStringArray;
  I: Integer;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  Who := FAdapter.AccountText(FCurrent);
  H := TpgnRoleHelper.Create;
  try
    H.Adapter := FAdapter;
    H.Current := FCurrent;
    H.AddMember := AAddMember;
    if AAddMember then
    begin
      What := 'Add a member to ' + Who;
    end
    else
    begin
      What := 'Grant a role to ' + Who;
    end;
    H.Dlg := TpgnAccountDialog.CreateDlg(What, 'Grant...', 520, FMono);
    try
      Items := OtherAccounts(False);
      try
        // roles first when granting a role
        if not AAddMember then
        begin
          Items.Clear;
          for I := 0 to High(FAccounts) do
          begin
            if FAccounts[I].IsRole and not FAccounts[I].IsSystem and
              (FAdapter.AccountText(FAccounts[I]) <> Who) then
            begin
              Items.Add(FAdapter.AccountText(FAccounts[I]));
            end;
          end;
          for I := 0 to High(FAccounts) do
          begin
            if not FAccounts[I].IsRole and not FAccounts[I].IsSystem and
              (FAdapter.AccountText(FAccounts[I]) <> Who) then
            begin
              Items.Add(FAdapter.AccountText(FAccounts[I]));
            end;
          end;
        end;
        Items.Insert(0, '(choose)');
        if AAddMember then
        begin
          H.Combo := H.Dlg.AddCombo('Member', Items);
        end
        else
        begin
          H.Combo := H.Dlg.AddCombo('Role', Items);
        end;
      finally
        Items.Free;
      end;
      H.Admin := H.Dlg.AddCheck('Can pass it on to others (WITH ADMIN OPTION)');
      if FInfo.Engine <> fePostgreSQL then
      begin
        H.Dlg.AddLabel('MySQL uses a granted role only once it''s active, so it is also made a default ' +
          'role (SET DEFAULT ROLE ALL).', True);
      end;
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(80);
      if H.Dlg.ShowModal <> mrOK then
      begin
        Exit;
      end;
      SQL := H.Statements;
    finally
      H.Dlg.Free;
    end;
  finally
    H.Free;
  end;
  RunStatements(What, SQL, SQL, False);
end;

procedure TpgnUsersPanel.RevokeRoleClick(Sender: TObject);
var
  Role: string;
  SQL: TpgnStringArray;
begin
  Role := GridValue(FMemberOfGrid, FMemberOfGrid.Row, 0);
  if not FHasCurrent or (Role = '') then
  begin
    Exit;
  end;
  SQL := One(FAdapter.RevokeRoleSQL(FAdapter.AccountFromText(Role), FCurrent));
  RunStatements('Revoke ' + Role + ' from ' + FAdapter.AccountText(FCurrent), SQL, SQL, False);
end;

procedure TpgnUsersPanel.RemoveMemberClick(Sender: TObject);
var
  Member: string;
  SQL: TpgnStringArray;
begin
  Member := GridValue(FMembersGrid, FMembersGrid.Row, 0);
  if not FHasCurrent or (Member = '') then
  begin
    Exit;
  end;
  SQL := One(FAdapter.RevokeRoleSQL(FCurrent, FAdapter.AccountFromText(Member)));
  RunStatements('Revoke ' + FAdapter.AccountText(FCurrent) + ' from ' + Member, SQL, SQL, False);
end;

type
  { The Grant dialog: what kind of thing, which one, which privileges. }
  TpgnGrantHelper = class
  public
    Adapter: TpgnAdapter;
    Account: TpgnAccount;
    Dlg: TpgnAccountDialog;
    Kinds: TpgnStringArray;
    KindCombo, ContainerCombo, ObjectCombo: TComboBox;
    ContainerLabel, ObjectLabel: TLabel;
    PrivPanel: TPanel;
    Checks: array of TCheckBox;
    GrantOption: TCheckBox;
    Problem: string;
    function Kind: string;
    function Privileges: string;
    function Statement: string;
    procedure KindChanged(Sender: TObject);
    procedure ContainerChanged(Sender: TObject);
    procedure Preview(Sender: TObject);
  end;

function TpgnGrantHelper.Kind: string;
begin
  Result := '';
  if KindCombo.ItemIndex >= 0 then
  begin
    Result := Kinds[KindCombo.ItemIndex];
  end;
end;

function TpgnGrantHelper.Privileges: string;
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

function TpgnGrantHelper.Statement: string;
begin
  Result := Adapter.GrantPrivilegeSQL(Account,
    Adapter.GrantObjectText(Kind, ContainerCombo.Text, ObjectCombo.Text), Kind, Privileges,
    GrantOption.Checked);
end;

{ A new kind: its containers, its objects and its privilege boxes. }
procedure TpgnGrantHelper.KindChanged(Sender: TObject);
var
  K, Cap: string;
  I, Cols, ColW, RowH: Integer;
  List: TpgnStringArray;
begin
  K := Kind;
  Problem := '';
  Cap := Adapter.GrantContainerCaption(K);
  ContainerLabel.Caption := Cap;
  ContainerCombo.Enabled := Cap <> '';
  ContainerCombo.Items.Clear;
  if Cap <> '' then
  begin
    try
      List := Adapter.GrantContainers(K);
      for I := 0 to High(List) do
      begin
        ContainerCombo.Items.Add(List[I]);
      end;
    except
      on E: Exception do
      begin
        Problem := E.Message;
      end;
    end;
  end;
  if ContainerCombo.Items.Count > 0 then
  begin
    ContainerCombo.ItemIndex := 0;
  end;

  for I := 0 to High(Checks) do
  begin
    Checks[I].Free;
  end;
  List := Adapter.GrantPrivileges(K);
  SetLength(Checks, Length(List));
  Cols := 3;
  ColW := (PrivPanel.ClientWidth - PrivPanel.Scale96ToScreen(8)) div Cols;
  RowH := PrivPanel.Scale96ToScreen(24);
  for I := 0 to High(List) do
  begin
    Checks[I] := TCheckBox.Create(PrivPanel);
    Checks[I].Parent := PrivPanel;
    Checks[I].Caption := List[I];
    Checks[I].SetBounds(PrivPanel.Scale96ToScreen(4) + (I mod Cols) * ColW, (I div Cols) * RowH,
      ColW - PrivPanel.Scale96ToScreen(4), RowH);
    Checks[I].OnChange := @Preview;
  end;
  // just as tall as these boxes: the rest of the window follows
  Dlg.ResizePart(PrivPanel, ((Length(List) + Cols - 1) div Cols) * RowH + PrivPanel.Scale96ToScreen(4));
  ContainerChanged(nil);
end;

procedure TpgnGrantHelper.ContainerChanged(Sender: TObject);
var
  List: TpgnStringArray;
  I: Integer;
begin
  ObjectCombo.Items.Clear;
  ObjectCombo.Enabled := Adapter.GrantNeedsObject(Kind);
  if ObjectCombo.Enabled then
  begin
    ObjectLabel.Caption := 'Object';
    if ContainerCombo.Text <> '' then
    begin
      try
        List := Adapter.GrantObjects(Kind, ContainerCombo.Text);
        for I := 0 to High(List) do
        begin
          ObjectCombo.Items.Add(List[I]);
        end;
      except
        on E: Exception do
        begin
          Problem := E.Message;
        end;
      end;
    end;
    if ObjectCombo.Items.Count > 0 then
    begin
      ObjectCombo.ItemIndex := 0;
    end;
  end
  else
  begin
    ObjectLabel.Caption := '';
  end;
  Preview(nil);
end;

procedure TpgnGrantHelper.Preview(Sender: TObject);
var
  Why: string;
begin
  Why := '';
  if Problem <> '' then
  begin
    Why := 'could not read the list: ' + Problem;
  end
  else if ContainerCombo.Enabled and (ContainerCombo.Text = '') then
  begin
    Why := 'nothing to choose from: no ' + LowerCase(ContainerLabel.Caption) + ' is visible to this login';
  end
  else if ObjectCombo.Enabled and (ObjectCombo.Text = '') then
  begin
    Why := 'there is nothing of that kind in ' + ContainerCombo.Text;
  end
  else if Privileges = '' then
  begin
    Why := 'tick at least one privilege';
  end;
  if Why <> '' then
  begin
    Dlg.Preview.Lines.Text := '-- ' + Why;
    Dlg.BtnOK.Enabled := False;
  end
  else
  begin
    Dlg.Preview.Lines.Text := Statement + ';';
    Dlg.BtnOK.Enabled := True;
  end;
end;

procedure TpgnUsersPanel.GrantPrivClick(Sender: TObject);
var
  H: TpgnGrantHelper;
  Items: TStringList;
  Who, SQL: string;
  I: Integer;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  Who := FAdapter.AccountText(FCurrent);
  H := TpgnGrantHelper.Create;
  try
    H.Adapter := FAdapter;
    H.Account := FCurrent;
    H.Kinds := FAdapter.GrantTargets;
    H.Dlg := TpgnAccountDialog.CreateDlg('Grant to ' + Who + ' on ' + ConnectionLongLabel(FInfo), 'Grant...',
      680, FMono);
    try
      Items := TStringList.Create;
      try
        for I := 0 to High(H.Kinds) do
        begin
          Items.Add(FAdapter.GrantTargetCaption(H.Kinds[I]));
        end;
        H.KindCombo := H.Dlg.AddCombo('On', Items, 320);
        Items.Clear;
        H.ContainerCombo := H.Dlg.AddCombo('', Items, 320);
        H.ObjectCombo := H.Dlg.AddCombo('', Items, 320);
      finally
        Items.Free;
      end;
      // the labels the dialog made for the two empty captions
      H.ContainerLabel := H.Dlg.LastLabels[0];
      H.ObjectLabel := H.Dlg.LastLabels[1];
      H.Dlg.AddLabel('Privileges:');
      // sized to the boxes shown each time the kind changes (KindChanged)
      H.PrivPanel := H.Dlg.AddPanel(24);
      H.GrantOption := H.Dlg.AddCheck('Let ' + Who + ' grant these to others (WITH GRANT OPTION)', True);
      H.KindCombo.OnChange := @H.KindChanged;
      H.ContainerCombo.OnChange := @H.ContainerChanged;
      H.Dlg.OnPreview := @H.Preview;
      H.Dlg.Finish(120);
      H.KindChanged(nil);
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
  RunStatements('Grant to ' + Who, One(SQL), One(SQL), False);
end;

procedure TpgnUsersPanel.RevokePrivClick(Sender: TObject);
var
  SQL: TpgnStringArray;
  R, First, Last: Integer;
begin
  if not FHasCurrent then
  begin
    Exit;
  end;
  First := FPrivGrid.Selection.Top;
  Last := FPrivGrid.Selection.Bottom;
  if First < 1 then
  begin
    First := FPrivGrid.Row;
    Last := FPrivGrid.Row;
  end;
  SQL := nil;
  for R := First to Last do
  begin
    if GridValue(FPrivGrid, R, 0) <> '' then
    begin
      AddTo(SQL, One(FAdapter.RevokePrivilegeSQL(FCurrent, GridValue(FPrivGrid, R, 0),
        GridValue(FPrivGrid, R, 1), GridValue(FPrivGrid, R, 2))));
    end;
  end;
  RunStatements('Revoke privileges from ' + FAdapter.AccountText(FCurrent), SQL, SQL, False);
end;

procedure TpgnUsersPanel.CopyDDLClick(Sender: TObject);
begin
  if not FDDLLoaded and FHasCurrent then
  begin
    LoadDDL;
  end;
  Clipboard.AsText := FDDL.Lines.Text;
  FLog('Copied the SQL for ' + FAdapter.AccountText(FCurrent) + ' to the clipboard.');
end;

end.
