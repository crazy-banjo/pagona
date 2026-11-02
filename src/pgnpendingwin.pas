// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnPendingWin;

{ Transactions: every tab with work waiting for Commit (auto-commit off),
  as Toad's Transactions panel lists its sessions, and the statements of
  the one picked.

    Transactions                                                   [Close]
    [Commit Selected Sessions] [Rollback Selected Sessions]  [Commit All] [Rollback All ...]
     Pick  Environment  Connection        Tab      Connected  Since     Waiting
     [x]   TEST         randy@reports-db  Query 1  20:38:32   20:41:07  3
     [ ]   DEV          RLMORROW@DEVL     Query 2  20:50:10   20:52:44  1
    Statements in Query 1 (committed or rolled back together)  [Undo From Here...]
       20:41:07   12  UPDATE saturn.sfrstcr SET ...

  Each tab is its own session with its own transaction, so a whole session
  is committed or rolled back. The selected sessions are the ticked ones;
  with none ticked, the highlighted row. The tab the panel was opened from
  (or the active tab, docked) is ticked again whenever it comes back with
  new work. Within one session, Undo From Here goes back
  to the savepoint Pagona set before a statement: it and everything after
  it are undone, the earlier ones stay pending.

  Amphibian docks the panel at the bottom of the window (as Toad); Plume
  shows it in a window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids, Dialogs, Math,
  LCLType, pgnTypes, pgnResultGrid, pgnTheme, pgnQueryTab;

type
  { The tabs to list (those with work waiting), asked for on every refresh
    so a closed tab is never touched. }
  TpgnTabsFunc = function: TpgnTabArray of object;

  TpgnTransactionsPanel = class(TPanel)
  private
    FGetTabs: TpgnTabsFunc;
    FTabs: TpgnTabArray;
    FPicked: TList;                // tabs ticked in the list
    FShown: TpgnQueryTab;          // whose statements are listed below
    FFocus: TpgnQueryTab;          // the tab the panel is for; ticked when it shows up
    FHead: TPanel;
    FTitle: TLabel;
    FBtnClose: TButton;
    FBar: TPanel;
    FBtnCommitSel, FBtnRollSel, FBtnCommitAll, FBtnRollAll: TButton;
    FSessions: TpgnResultGrid;
    FStmtHead: TPanel;
    FStmtLabel: TLabel;
    FBtnUndo: TButton;
    FStatements: TpgnResultGrid;
    FOnClose: TNotifyEvent;
    FOnChanged: TNotifyEvent;
    FFilling: Boolean;
    function S(AValue: Integer): Integer;
    procedure LayoutBar(Sender: TObject);
    procedure LayoutStmtHead(Sender: TObject);
    procedure LayoutHead(Sender: TObject);
    function Alive(T: TpgnQueryTab): Boolean;
    procedure FillSessions;
    procedure FillStatements;
    procedure UpdateButtons;
    function PickedTabs: TpgnTabArray;
    procedure SessionsSelect(Sender: TObject; aCol, aRow: Integer);
    procedure SessionsMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SessionsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure StatementsSelect(Sender: TObject; aCol, aRow: Integer);
    procedure TogglePick(ARow: Integer);
    procedure Finish(const ATabs: TpgnTabArray; ACommit: Boolean; const AWhat: string);
    procedure CommitSelClick(Sender: TObject);
    procedure RollSelClick(Sender: TObject);
    procedure CommitAllClick(Sender: TObject);
    procedure RollAllClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
  public
    constructor CreatePanel(AOwner: TComponent; AGetTabs: TpgnTabsFunc; AShowClose: Boolean);
    destructor Destroy; override;
    { Reads the tabs again and redraws (keeps what was picked). }
    procedure Reload;
    { Lists AFocus's statements below (when it's among the tabs) and ticks it. }
    procedure ShowTab(AFocus: TpgnQueryTab);
    { The tab the panel is for (docked: the active tab). Ticked on the next
      Reload if it has just come back with new work. }
    property FocusTab: TpgnQueryTab read FFocus write FFocus;
    property OnCloseClick: TNotifyEvent read FOnClose write FOnClose;
    { After a commit, rollback or undo: the window updates its bars. }
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

{ Plume (and Review... in the close question): the panel in a window. }
procedure ShowTransactionsWindow(AOwner: TComponent; AGetTabs: TpgnTabsFunc;
  AFocus: TpgnQueryTab; AOnChanged: TNotifyEvent);

implementation

const
  PickOn = '[x]';
  PickOff = '[ ]';

function Plural(N: Integer; const AWord: string): string;
begin
  if N = 1 then
  begin
    Result := '1 ' + AWord;
  end
  else
  begin
    Result := IntToStr(N) + ' ' + AWord + 's';
  end;
end;

{ ============================================================ the panel }

constructor TpgnTransactionsPanel.CreatePanel(AOwner: TComponent; AGetTabs: TpgnTabsFunc;
  AShowClose: Boolean);

  function Btn(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.AutoSize := True;
    Result.OnClick := AHandler;
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FGetTabs := AGetTabs;
  FPicked := TList.Create;

  // title strip, as Toad's "Transactions" bar
  FHead := TPanel.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.Height := S(28);
  FHead.BevelOuter := bvNone;
  FHead.Caption := '';
  FHead.Color := clPgnSelection;
  FHead.ParentColor := False;
  FHead.OnResize := @LayoutHead;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FHead;
  FTitle.Caption := 'Transactions';
  FTitle.Font.Style := [fsBold];
  if AShowClose then
  begin
    FBtnClose := TButton.Create(Self);
    FBtnClose.Parent := FHead;
    FBtnClose.Caption := 'Close';
    FBtnClose.OnClick := @CloseClick;
  end;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Top := FHead.Top + FHead.Height + 1;
  FBar.Height := S(38);
  FBar.BevelOuter := bvNone;
  FBar.Caption := '';
  FBar.OnResize := @LayoutBar;
  FBtnCommitSel := Btn(FBar, 'Commit Selected Sessions', @CommitSelClick);
  FBtnRollSel := Btn(FBar, 'Rollback Selected Sessions', @RollSelClick);
  FBtnCommitAll := Btn(FBar, 'Commit All', @CommitAllClick);
  FBtnRollAll := Btn(FBar, 'Rollback All in Transaction', @RollAllClick);

  FSessions := TpgnResultGrid.Create(Self);
  FSessions.Parent := Self;
  FSessions.Align := alTop;
  FSessions.Top := FBar.Top + FBar.Height + 1;
  FSessions.Height := S(84);
  FSessions.Options := FSessions.Options + [goRowSelect];
  FSessions.OnSelection := @SessionsSelect;
  FSessions.OnMouseUp := @SessionsMouseUp;
  FSessions.OnKeyDown := @SessionsKeyDown;

  FStmtHead := TPanel.Create(Self);
  FStmtHead.Parent := Self;
  FStmtHead.Align := alTop;
  FStmtHead.Top := FSessions.Top + FSessions.Height + 1;
  FStmtHead.Height := S(36);
  FStmtHead.BevelOuter := bvNone;
  FStmtHead.Caption := '';
  FStmtHead.OnResize := @LayoutStmtHead;
  FStmtLabel := TLabel.Create(Self);
  FStmtLabel.Parent := FStmtHead;
  FStmtLabel.Font.Style := [fsBold];
  FBtnUndo := Btn(FStmtHead, 'Undo From Here...', @UndoClick);

  FStatements := TpgnResultGrid.Create(Self);
  FStatements.Parent := Self;
  FStatements.Align := alClient;
  FStatements.Options := FStatements.Options + [goRowSelect];
  FStatements.OnSelection := @StatementsSelect;
end;

destructor TpgnTransactionsPanel.Destroy;
begin
  FPicked.Free;
  inherited Destroy;
end;

function TpgnTransactionsPanel.S(AValue: Integer): Integer;
begin
  Result := Scale96ToScreen(AValue);
end;

procedure TpgnTransactionsPanel.LayoutHead(Sender: TObject);
begin
  FTitle.SetBounds(S(8), (FHead.ClientHeight - FTitle.Height) div 2, FTitle.Width, FTitle.Height);
  if FBtnClose <> nil then
  begin
    FBtnClose.SetBounds(FHead.ClientWidth - FBtnClose.Width - S(4),
      (FHead.ClientHeight - FBtnClose.Height) div 2, FBtnClose.Width, FBtnClose.Height);
  end;
end;

procedure TpgnTransactionsPanel.LayoutBar(Sender: TObject);
var
  X, Y: Integer;

  procedure Place(B: TButton);
  begin
    B.SetBounds(X, Y, B.Width, B.Height);
    X := X + B.Width + S(6);
  end;

begin
  X := S(6);
  Y := (FBar.ClientHeight - FBtnCommitSel.Height) div 2;
  Place(FBtnCommitSel);
  Place(FBtnRollSel);
  X := X + S(12);
  Place(FBtnCommitAll);
  Place(FBtnRollAll);
end;

procedure TpgnTransactionsPanel.LayoutStmtHead(Sender: TObject);
begin
  FStmtLabel.SetBounds(S(8), (FStmtHead.ClientHeight - FStmtLabel.Height) div 2, FStmtLabel.Width,
    FStmtLabel.Height);
  FBtnUndo.SetBounds(FStmtHead.ClientWidth - FBtnUndo.Width - S(6),
    (FStmtHead.ClientHeight - FBtnUndo.Height) div 2, FBtnUndo.Width, FBtnUndo.Height);
end;

function TpgnTransactionsPanel.Alive(T: TpgnQueryTab): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FTabs) do
  begin
    if FTabs[I] = T then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TpgnTransactionsPanel.Reload;
var
  I: Integer;
  FocusWasListed: Boolean;
begin
  FocusWasListed := (FFocus <> nil) and Alive(FFocus);
  if Assigned(FGetTabs) then
  begin
    FTabs := FGetTabs();
  end
  else
  begin
    FTabs := nil;
  end;
  // forget picks and the shown tab once they're gone
  for I := FPicked.Count - 1 downto 0 do
  begin
    if not Alive(TpgnQueryTab(FPicked[I])) then
    begin
      FPicked.Delete(I);
    end;
  end;
  // the focus tab is back with new work (after a commit, say): tick it again
  if (FFocus <> nil) and not FocusWasListed and Alive(FFocus) then
  begin
    if FPicked.IndexOf(FFocus) < 0 then
    begin
      FPicked.Add(FFocus);
    end;
    FShown := FFocus;
  end;
  if not Alive(FShown) then
  begin
    FShown := nil;
    if Length(FTabs) > 0 then
    begin
      FShown := FTabs[0];
    end;
  end;
  FillSessions;
  FillStatements;
end;

procedure TpgnTransactionsPanel.ShowTab(AFocus: TpgnQueryTab);
begin
  FFocus := AFocus;
  Reload;
  if Alive(AFocus) then
  begin
    FShown := AFocus;
    if FPicked.IndexOf(AFocus) < 0 then
    begin
      FPicked.Add(AFocus);
    end;
    FillSessions;
    FillStatements;
  end;
end;

procedure TpgnTransactionsPanel.FillSessions;
var
  R: TpgnResultSet;
  I, ShownRow: Integer;
  T: TpgnQueryTab;
  Since: string;
begin
  FFilling := True;
  try
    R := TpgnResultSet.Create;
    R.ReturnsRows := True;
    SetLength(R.Columns, 7);
    R.Columns[0] := 'Pick';
    R.Columns[1] := 'Environment';
    R.Columns[2] := 'Connection';
    R.Columns[3] := 'Tab';
    R.Columns[4] := 'Connected';
    R.Columns[5] := 'In transaction since';
    R.Columns[6] := 'Waiting';
    SetLength(R.Rows, Length(FTabs));
    ShownRow := 0;
    for I := 0 to High(FTabs) do
    begin
      T := FTabs[I];
      SetLength(R.Rows[I].Values, 7);
      SetLength(R.Rows[I].Nulls, 7);
      if FPicked.IndexOf(T) >= 0 then
      begin
        R.Rows[I].Values[0] := PickOn;
      end
      else
      begin
        R.Rows[I].Values[0] := PickOff;
      end;
      if T.Info.Environment = enNone then
      begin
        R.Rows[I].Values[1] := '(none)';
      end
      else
      begin
        R.Rows[I].Values[1] := EnvironmentLong[T.Info.Environment];
      end;
      R.Rows[I].Values[2] := T.Info.User + '@' + T.Info.Name;
      R.Rows[I].Values[3] := T.Title;
      R.Rows[I].Values[4] := FormatDateTime('hh:nn:ss', T.ConnectedAt);
      Since := '';
      if T.PendingCount > 0 then
      begin
        Since := FormatDateTime('hh:nn:ss', T.PendingItem(0).RanAt);
      end;
      R.Rows[I].Values[5] := Since;
      if T.PendingCount = 1 then
      begin
        R.Rows[I].Values[6] := '1 statement';
      end
      else
      begin
        R.Rows[I].Values[6] := IntToStr(T.PendingCount) + ' statements';
      end;
      if T = FShown then
      begin
        ShownRow := I;
      end;
    end;
    FSessions.ShowData(R);   // the grid keeps it
    if Length(FTabs) > 0 then
    begin
      FSessions.Row := ShownRow + 1;
    end;
  finally
    FFilling := False;
  end;
  UpdateButtons;
end;

procedure TpgnTransactionsPanel.FillStatements;
var
  R: TpgnResultSet;
  I: Integer;
  It: TpgnPendingItem;
  Txt: string;
begin
  FFilling := True;
  try
    R := TpgnResultSet.Create;
    R.ReturnsRows := True;
    SetLength(R.Columns, 3);
    R.Columns[0] := 'Ran at';
    R.Columns[1] := 'Rows';
    R.Columns[2] := 'Statement';
    if FShown <> nil then
    begin
      FStmtLabel.Caption := 'Statements in ' + FShown.Title + ' on ' +
        ConnectionLongLabel(FShown.Info) + ' (committed or rolled back together)';
      SetLength(R.Rows, FShown.PendingCount);
      for I := 0 to FShown.PendingCount - 1 do
      begin
        It := FShown.PendingItem(I);
        SetLength(R.Rows[I].Values, 3);
        SetLength(R.Rows[I].Nulls, 3);
        R.Rows[I].Values[0] := FormatDateTime('hh:nn:ss', It.RanAt);
        if It.Rows >= 0 then
        begin
          R.Rows[I].Values[1] := IntToStr(It.Rows);
        end
        else
        begin
          R.Rows[I].Values[1] := '';
        end;
        Txt := StringReplace(StringReplace(It.SQL, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
        if Length(Txt) > 400 then
        begin
          Txt := Copy(Txt, 1, 397) + '...';
        end;
        R.Rows[I].Values[2] := Txt;
      end;
    end
    else
    begin
      FStmtLabel.Caption := 'Nothing is waiting for Commit';
    end;
    FStatements.ShowData(R);
    if (FShown <> nil) and (FShown.PendingCount > 0) then
    begin
      FStatements.Row := FShown.PendingCount;   // the newest
    end;
  finally
    FFilling := False;
  end;
  LayoutStmtHead(nil);
  UpdateButtons;
end;

{ The ticked sessions; with none ticked, the highlighted one. }
function TpgnTransactionsPanel.PickedTabs: TpgnTabArray;
var
  I, N: Integer;
begin
  Result := nil;
  for I := 0 to High(FTabs) do
  begin
    if FPicked.IndexOf(FTabs[I]) >= 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := FTabs[I];
    end;
  end;
  if Length(Result) = 0 then
  begin
    N := FSessions.Row - 1;
    if (N >= 0) and (N <= High(FTabs)) then
    begin
      SetLength(Result, 1);
      Result[0] := FTabs[N];
    end;
  end;
end;

procedure TpgnTransactionsPanel.UpdateButtons;
var
  I, N: Integer;
  Any, Picked: Boolean;
begin
  Any := Length(FTabs) > 0;
  Picked := Length(PickedTabs) > 0;
  FBtnCommitSel.Enabled := Picked;
  FBtnRollSel.Enabled := Picked;
  FBtnCommitAll.Enabled := Any;
  FBtnRollAll.Enabled := Any;
  N := FStatements.Row - 1;
  I := -1;
  if (FShown <> nil) and (N >= 0) and (N < FShown.PendingCount) then
  begin
    I := N;
  end;
  FBtnUndo.Enabled := (I >= 0) and not FShown.IsRunning and (FShown.PendingItem(I).Savepoint <> '');
end;

procedure TpgnTransactionsPanel.SessionsSelect(Sender: TObject; aCol, aRow: Integer);
var
  N: Integer;
begin
  if FFilling then
  begin
    Exit;
  end;
  N := FSessions.Row - 1;
  if (N >= 0) and (N <= High(FTabs)) and (FTabs[N] <> FShown) then
  begin
    FShown := FTabs[N];
    FillStatements;
  end
  else
  begin
    UpdateButtons;
  end;
end;

procedure TpgnTransactionsPanel.TogglePick(ARow: Integer);
var
  T: TpgnQueryTab;
begin
  if (ARow < 1) or (ARow > Length(FTabs)) then
  begin
    Exit;
  end;
  T := FTabs[ARow - 1];
  if FPicked.IndexOf(T) >= 0 then
  begin
    FPicked.Remove(T);
  end
  else
  begin
    FPicked.Add(T);
  end;
  FillSessions;
  FSessions.Row := ARow;
end;

{ A click in the Pick column ticks or unticks the session. }
procedure TpgnTransactionsPanel.SessionsMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  C, R: Integer;
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  FSessions.MouseToCell(X, Y, C, R);
  if C = 1 then
  begin
    TogglePick(R);
  end;
end;

{ Space ticks or unticks the session in the row. }
procedure TpgnTransactionsPanel.SessionsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_SPACE then
  begin
    Key := 0;
    TogglePick(FSessions.Row);
  end;
end;

procedure TpgnTransactionsPanel.StatementsSelect(Sender: TObject; aCol, aRow: Integer);
begin
  if not FFilling then
  begin
    UpdateButtons;
  end;
end;

{ Commits or rolls back each tab's whole transaction, after one question. }
procedure TpgnTransactionsPanel.Finish(const ATabs: TpgnTabArray; ACommit: Boolean; const AWhat: string);
var
  I, Total: Integer;
  Names, Verb, Msg: string;
begin
  if Length(ATabs) = 0 then
  begin
    Exit;
  end;
  Total := 0;
  Names := '';
  for I := 0 to High(ATabs) do
  begin
    Total := Total + ATabs[I].PendingCount;
    Names := Names + LineEnding + '  ' + ATabs[I].Title + ' on ' + ConnectionLongLabel(ATabs[I].Info) +
      ' (' + IntToStr(ATabs[I].PendingCount) + ')';
  end;
  if ACommit then
  begin
    Verb := 'Commit';
  end
  else
  begin
    Verb := 'Roll back';
  end;
  if Length(ATabs) = 1 then
  begin
    Msg := Verb + ' ' + Plural(Total, 'statement') + ' in ' + ATabs[0].Title + ' on ' +
      ConnectionLongLabel(ATabs[0].Info) + '?' + LineEnding +
      'A session is committed or rolled back as a whole.';
  end
  else
  begin
    Msg := Verb + ' ' + AWhat + ': ' + Plural(Total, 'statement') + ' in ' +
      IntToStr(Length(ATabs)) + ' sessions?' + Names;
  end;
  if MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  for I := 0 to High(ATabs) do
  begin
    if ACommit then
    begin
      ATabs[I].Commit;
    end
    else
    begin
      ATabs[I].Rollback;
    end;
    FPicked.Remove(ATabs[I]);
  end;
  Reload;
  if Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

procedure TpgnTransactionsPanel.CommitSelClick(Sender: TObject);
begin
  Reload;
  Finish(PickedTabs, True, 'the selected sessions');
end;

procedure TpgnTransactionsPanel.RollSelClick(Sender: TObject);
begin
  Reload;
  Finish(PickedTabs, False, 'the selected sessions');
end;

procedure TpgnTransactionsPanel.CommitAllClick(Sender: TObject);
begin
  Reload;
  Finish(FTabs, True, 'every session in transaction');
end;

procedure TpgnTransactionsPanel.RollAllClick(Sender: TObject);
begin
  Reload;
  Finish(FTabs, False, 'every session in transaction');
end;

procedure TpgnTransactionsPanel.UndoClick(Sender: TObject);
var
  I, After: Integer;
  Msg: string;
  Row: Integer;
begin
  Row := FStatements.Row;
  Reload;
  if FShown = nil then
  begin
    Exit;
  end;
  I := Row - 1;
  if (I < 0) or (I >= FShown.PendingCount) then
  begin
    Exit;
  end;
  After := FShown.PendingCount - I - 1;
  Msg := 'Undo statement ' + IntToStr(I + 1) + ' in ' + FShown.Title;
  if After = 1 then
  begin
    Msg := Msg + ' and the 1 after it';
  end
  else if After > 1 then
  begin
    Msg := Msg + ' and the ' + IntToStr(After) + ' after it';
  end;
  Msg := Msg + '?';
  if I > 0 then
  begin
    Msg := Msg + LineEnding + 'Statements 1 to ' + IntToStr(I) + ' stay pending.';
  end;
  if MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  FShown.UndoFrom(I);
  Reload;
  if Assigned(FOnChanged) then
  begin
    FOnChanged(Self);
  end;
end;

procedure TpgnTransactionsPanel.CloseClick(Sender: TObject);
begin
  if Assigned(FOnClose) then
  begin
    FOnClose(Self);
  end;
end;

{ ============================================================ the window }

procedure ShowTransactionsWindow(AOwner: TComponent; AGetTabs: TpgnTabsFunc;
  AFocus: TpgnQueryTab; AOnChanged: TNotifyEvent);
var
  W: TForm;
  Bar: TPanel;
  B: TButton;
  P: TpgnTransactionsPanel;
begin
  W := TForm.CreateNew(AOwner);
  try
    SmoothFont(W.Font);
    W.Caption := 'Transactions';
    W.Position := poOwnerFormCenter;
    W.BorderStyle := bsSizeable;
    W.Width := W.Scale96ToScreen(900);
    W.Height := W.Scale96ToScreen(480);

    Bar := TPanel.Create(W);
    Bar.Parent := W;
    Bar.Align := alBottom;
    Bar.Height := W.Scale96ToScreen(42);
    Bar.BevelOuter := bvNone;
    Bar.Caption := '';
    B := TButton.Create(W);
    B.Parent := Bar;
    B.Caption := 'Close';
    B.ModalResult := mrClose;
    B.Cancel := True;
    B.Align := alRight;
    B.BorderSpacing.Around := W.Scale96ToScreen(6);

    P := TpgnTransactionsPanel.CreatePanel(W, AGetTabs, False);
    P.Parent := W;
    P.Align := alClient;
    P.OnChanged := AOnChanged;
    if AFocus <> nil then
    begin
      P.ShowTab(AFocus);
    end
    else
    begin
      P.Reload;
    end;
    W.ShowModal;
  finally
    W.Free;
  end;
end;

end.
