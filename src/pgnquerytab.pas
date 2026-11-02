// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnQueryTab;

{ One query tab: its own connection and database, its own session,
  editor, results and messages.

    +--------------------------------------------------------------+
    | PRODUCTION  Connection [..]  Database [..]  [x] Auto-commit   |
    +==============================================================+
    | SQL editor (the statement Run will execute is shaded)        |
    +--------------------------------------------------------------+
    | [Results] [Messages]                                          |
    +--------------------------------------------------------------+

  The tab never prompts for passwords itself: the main window hands it
  a connect function that asks once and remembers for the session. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, LazUTF8, Grids, Math,
  SynEdit, SynHighlighterSQL, SynEditMiscClasses, SynEditTypes,
  pgnTypes, pgnAdapter, pgnConnections, pgnSettings, pgnQueryThread, pgnUsersScreen, pgnWhoCanScreen,
  pgnSqlSplit, pgnColors, pgnTheme, pgnResultGrid, pgnDbaLog, pgnKeymap, pgnExport;

type
  { A DBA screen a tab can show instead of the editor. }
  TpgnDbaScreen = (dsNone, dsSessions, dsLocks, dsUsers, dsWhoCan);

  { Opens a new session for a profile (asks for the password if needed).
    Returns nil if the user canceled or the connection failed. }
  TpgnConnectFunc = function(const AInfo: TpgnConnectionInfo): TpgnAdapter of object;

  TpgnCommentMode = (cmToggle, cmComment, cmUncomment);

  { How a line in Messages is shown. The words always say it too
    ("ERROR: ...", "Cancel requested"); the style only makes it stand out. }
  TpgnMessageKind = (mkInfo, mkSuccess, mkWarning, mkError);

  { A statement waiting for Commit (auto-commit off). }
  TpgnPendingItem = record
    SQL: string;
    RanAt: TDateTime;
    Rows: Int64;          // rows it changed; -1 when not known
    Savepoint: string;    // set just before it ('' = can't be undone on its own)
  end;

  TpgnSchemaChangedEvent = procedure(Sender: TObject; const AConnectionId: string;
    AChange: TpgnSchemaChange; const ASQL: string) of object;

  TpgnQueryTab = class(TPanel)
  private
    FStore: TpgnConnectionStore;
    FSettings: TpgnSettings;
    FHistory: TStringList;
    FConnect: TpgnConnectFunc;
    FConnectedAt: TDateTime;

    FAdapter: TpgnAdapter;
    FInfo: TpgnConnectionInfo;
    FThread: TpgnQueryThread;
    FCurrentDb: string;
    FStatusText: string;
    FTitle: string;
    FFileName: string;
    FWasModified: Boolean;
    FSyncing: Boolean;
    FNextLeft: Integer;
    FPending: Integer;           // statements run since the last commit (auto-commit off)
    FReadsOnly: Boolean;         // the open transaction has only read, without locks
    FShadeFrom: Integer;         // lines of the statement Run will execute; 0 = none
    FShadeTo: Integer;
    FShadeTimer: TTimer;

    // routine mode: the tab edits one procedure, function or trigger
    FRoutineMode: Boolean;
    FRoutineDb: string;
    FRoutineName: string;        // '' = new, not saved yet
    FRoutineKind: TpgnRoutineKind;
    FRoutineReadOnly: Boolean;
    FRoutineBar: TPanel;
    FRoutineLabel: TLabel;
    FRoutineNote: TLabel;
    FBtnSave: TButton;
    FBtnExecute: TButton;
    FBtnRevert: TButton;
    FOnRoutineExecute: TNotifyEvent;
    FPendingList: array of TpgnPendingItem;
    FSavepointSeq: Integer;
    FOnReviewPending: TNotifyEvent;

    // DBA screen mode: a grid of sessions or locks instead of the editor
    FScreen: TpgnDbaScreen;
    FUsersPanel: TpgnUsersPanel;     // DBA > Users and Roles
    FWhoCanPanel: TpgnWhoCanPanel;   // DBA > Who Can Do What
    FOnOpenAccount: TpgnOpenAccountEvent;
    FKillRight: string;              // '' or what the login lacks to end others' sessions
    FScreenBar: TPanel;
    FScreenLabel: TLabel;
    FScreenNote: TLabel;
    FBtnScreenRefresh: TButton;
    FAutoCombo: TComboBox;
    FBtnShowStmt: TButton;
    FBtnCancelSess: TButton;
    FBtnKillSess: TButton;
    FScreenTimer: TTimer;
    FScreenBusy: Boolean;
    FScreenTime: string;
    FEditorSplitter: TSplitter;

    FEnvLabel: TLabel;
    FConnLabel: TLabel;
    FDbLabel: TLabel;
    FBandLine: TPanel;
    FConnCombo: TComboBox;
    FDbCombo: TComboBox;
    FSchemaLabel: TLabel;     // PostgreSQL: where unqualified names are found
    FSchemaCombo: TComboBox;
    FSchemaWanted: Boolean;
    FAutoCommitCheck: TCheckBox;
    FBand: TPanel;
    FEditor: TSynEdit;
    FHighlighter: TSynSQLSyn;
    FPages: TPageControl;
    FTabResults: TTabSheet;
    FResultSwitch: TTabControl;  // "Result 1, Result 2, ..." when a run returns several
    FResultGrids: TFPList;       // TpgnResultGrid, one per result set; one shown at a time
    FTabPlan: TTabSheet;
    FPlanGrid: TpgnResultGrid;
    FTabHistory: TTabSheet;
    FHistoryList: TListView;
    // Amphibian: Toad's result tabs (Messages, Data Grid, DBMS Output,
    // Explain Plan, History) and no band (the toolbar has its pickers)
    FAmph: Boolean;
    FTabMessages: TTabSheet;
    FTabDbms: TTabSheet;
    FDbmsGrid: TpgnResultGrid;
    FPagesTitle: TLabel;
    FMsgTitle: TLabel;
    FMsgSplitter: TSplitter;
    // Seattle: SSMS's arrangement (Results, Messages, Execution Plan; the
    // result sets stacked; a line under the editor; the query status bar)
    FLayout: string;
    FSea: Boolean;
    FEditorHost: TPanel;
    FEditorInfo: TPanel;
    FQueryBarHost: TPanel;
    FQueryBar: TPaintBox;
    FSeaGrids: TFPList;          // made up front: GTK3 draws a grid made later at its first size
    FSeaShown: Integer;
    FRunState: Integer;          // 0 nothing yet, 1 ok, 2 errors, 3 canceled, 4 running
    FRunMs: Int64;
    FRunRows: Int64;
    FRunStart: TDateTime;
    FProgressTimer: TTimer;
    FExplainRun: Boolean;        // the running query is an Explain: its rows go to Plan
    FResultsMode: Integer;       // Seattle's Results To: 0 grid, 1 text, 2 file
    FResultsText: TMemo;         // Seattle: Results to Text shows here
    FTextShown: Boolean;
    FResultsFile: string;        // Results to File: where this run's results go
    FExportOpt: TpgnExportOptions;   // the last Save Results As choices
    FExportIndex: Integer;       // which result set of the re-run to save
    FExportTitle: string;
    FMessagesPanel: TPanel;
    FMessages: TSynEdit;         // read-only; lets each line have its own style
    FMsgKinds: TFPList;          // TpgnMessageKind per line of FMessages

    FOnStateChanged: TNotifyEvent;
    FOnActivate: TNotifyEvent;
    FOnSchemaChanged: TpgnSchemaChangedEvent;
    FOnCaretMoved: TNotifyEvent;

    procedure BuildUI;
    procedure EditorLineMarkup(Sender: TObject; Line: Integer; var Special: Boolean;
      Markup: TSynSelectedColor);
    procedure EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure MessagesLineMarkup(Sender: TObject; Line: Integer; var Special: Boolean;
      Markup: TSynSelectedColor);
    procedure ShadeTimerTick(Sender: TObject);
    procedure UpdateShade;
    procedure LoadObjectNames;
    procedure RecordPending(const ASQL: string; ARows: Int64; const ASavepoint: string);
    procedure ClearPending;
    procedure AddHeaderControl(AControl: TControl);
    procedure LayoutBand(Sender: TObject);
    procedure LayoutRoutineBar(Sender: TObject);
    procedure LayoutScreenBar(Sender: TObject);
    function ScreenGrid: TpgnResultGrid;
    function ScreenSessionId: string;
    function ScreenRowValue(ACol: Integer): string;
    function ScreenWhoShort: string;
    procedure UpdateScreenNote;
    procedure ScreenRefreshClick(Sender: TObject);
    procedure ScreenAutoChange(Sender: TObject);
    procedure ScreenTimerTick(Sender: TObject);
    procedure ScreenShowStmtClick(Sender: TObject);
    procedure ScreenCancelClick(Sender: TObject);
    procedure ScreenKillClick(Sender: TObject);
    procedure ScreenSelect(Sender: TObject; aCol, aRow: Integer);
    procedure UpdateRoutineBar;
    procedure RoutineSaveClick(Sender: TObject);
    procedure RoutineExecuteClick(Sender: TObject);
    procedure RoutineRevertClick(Sender: TObject);
    function RoutineStatementText(out ALineOffset: Integer): string;
    procedure StateChanged;
    procedure UpdateBand;
    procedure SyncConnCombo;
    procedure SyncDbCombo;
    procedure SyncAutoCommitCheck;
    procedure FillDbCombo(const ANames: TpgnStringArray);
    procedure ConnComboChange(Sender: TObject);
    procedure DbComboChange(Sender: TObject);
    procedure AutoCommitClick(Sender: TObject);
    procedure EditorChange(Sender: TObject);
    procedure EditorEnter(Sender: TObject);
    procedure EditorMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure QueryDone(Sender: TObject);
    function AddResultGrid: TpgnResultGrid;
    procedure ShowResults(AList: TFPList);
    procedure PagesChange(Sender: TObject);
    procedure ResultSwitchChange(Sender: TObject);
    procedure FillHistory;
    procedure HistoryDblClick(Sender: TObject);
    procedure ProgressTick(Sender: TObject);
    function ConfirmStatements(const AStatements: TpgnStringArray): Boolean;
    procedure AddToHistory(const ASQL: string);
    function CaretOffset: Integer;
    procedure DropSession;
    procedure MessagesToTab(AIndex: Integer);
    procedure MessagesBack;
    procedure StackGrids;
    procedure SetResultsMode(AValue: Integer);
    function ConfirmDdlCommit(const AStatements: TpgnStringArray): Boolean;
    procedure PrepGrids;
    procedure GridSaveResults(Sender: TObject);
    procedure ExportDone(Sender: TObject);
    procedure ResultsResize(Sender: TObject);
    procedure AsyncStack(AData: PtrInt);
    procedure QueryBarPaint(Sender: TObject);
    procedure UpdateEditorInfo;
  public
    { The frame's colors again, after the look changed. }
    procedure RecolorFrame;
    constructor CreateTab(AOwner: TComponent; AStore: TpgnConnectionStore;
      ASettings: TpgnSettings; AHistory: TStringList; AConnect: TpgnConnectFunc;
      const ATitle: string);
    destructor Destroy; override;

    { connection }
    function ConnectTo(const AInfo: TpgnConnectionInfo; const ADatabase: string): Boolean;
    function ResolvePendingWork(const AReason: string): Boolean;
    procedure RefreshConnectionList;
    procedure UpdateConnectionInfo(const AInfo: TpgnConnectionInfo);
    procedure ReloadDatabaseList;
    procedure SelectDatabase(const AName: string);
    procedure ReloadSchemaList;
    procedure SyncSchemaCombo;
    procedure SchemaComboChange(Sender: TObject);
    procedure UpdateEngineLook;

    { running }
    procedure StartQuery(const AStatements: TpgnStringArray);
    procedure RunSQL(const ASQL: string);
    procedure RunStatement;
    procedure RunScript;
    procedure Explain;
    procedure Cancel;
    procedure Commit;
    procedure Rollback;
    procedure ToggleAutoCommit;

    { routine mode }
    procedure OpenRoutine(const ADatabase, AName: string; AKind: TpgnRoutineKind; const ASQL: string);
    procedure NewRoutine(const ADatabase: string; AKind: TpgnRoutineKind; const ASQL: string);
    function SaveRoutine: Boolean;
    procedure RevertRoutine;
    procedure SetSaveCaption(const ACaption: string);
    { Shows a DBA screen (sessions, locks) in place of the editor. }
    procedure OpenScreen(AScreen: TpgnDbaScreen);
    procedure RefreshScreen;
    { PostgreSQL: makes ASchema the one unqualified names are found in. }
    procedure SetSchema(const ASchema: string);
    { How the tab's engine writes SQL (MySQL when not connected). }
    function Dialect: TpgnDialect;
    function Disconnect: Boolean;
    procedure DescribeAtCaret;

    { editor }
    function CurrentStatement: string;
    function IdentifierAtCaret: string;
    procedure InsertText(const AText: string; AOwnLine: Boolean);
    procedure SetText(const AText: string);
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    function IsModified: Boolean;
    function IsEmpty: Boolean;
    procedure CommentLines(AMode: TpgnCommentMode);
    procedure ToggleComment;
    procedure BlockComment;
    procedure ChangeCase(AUpper: Boolean);
    procedure FocusEditor;
    procedure Log(const AText: string);
    { A short message in the tab's status (and the status bar). }
    procedure Notice(const AText: string);
    procedure ApplyTheme(const ATheme: string);
    function CaretText: string;

    function DisplayCaption: string;
    function IsConnected: Boolean;
    function IsRunning: Boolean;
    function HasText: Boolean;

    { The band's pickers (0 connection, 1 database, 2 schema), for a
      toolbar that shows them in the band's place (Amphibian). }
    function BandCombo(AWhich: Integer): TComboBox;
    procedure PickInBand(AWhich, AIndex: Integer);
    function SchemaWanted: Boolean;
    { Pending statements (auto-commit off): PendingCount of them. }
    function PendingItem(AIndex: Integer): TpgnPendingItem;
    function UndoFrom(AIndex: Integer): Boolean;
    { Rearranges the results area and band for a layout (see the body). }
    procedure ApplyLayout(const ALayout: string);
    { Seattle: the whole name, as SSMS's title bar shows it:
      "SQLQuery1.sql - server.database (login (session id))". }
    function FullTitle: string;

    property Adapter: TpgnAdapter read FAdapter;
    property ConnectedAt: TDateTime read FConnectedAt;
    property Info: TpgnConnectionInfo read FInfo;
    property CurrentDb: string read FCurrentDb;
    property StatusText: string read FStatusText;
    { statements run since the last commit, while auto-commit is off }
    property PendingCount: Integer read FPending;
    { Seattle's Query > Results To: 0 grid, 1 text, 2 file }
    property ResultsMode: Integer read FResultsMode write SetResultsMode;
    property Title: string read FTitle write FTitle;
    property FileName: string read FFileName;
    property Editor: TSynEdit read FEditor;
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    property OnActivate: TNotifyEvent read FOnActivate write FOnActivate;
    property OnSchemaChanged: TpgnSchemaChangedEvent read FOnSchemaChanged write FOnSchemaChanged;
    property OnCaretMoved: TNotifyEvent read FOnCaretMoved write FOnCaretMoved;
    property IsRoutine: Boolean read FRoutineMode;
    property DbaScreen: TpgnDbaScreen read FScreen;
    property UsersPanel: TpgnUsersPanel read FUsersPanel;
    property WhoCanPanel: TpgnWhoCanPanel read FWhoCanPanel;
    { Who Can Do What's Open Account: the main form opens Users and Roles. }
    property OnOpenAccount: TpgnOpenAccountEvent read FOnOpenAccount write FOnOpenAccount;
    property RoutineDb: string read FRoutineDb;
    property RoutineName: string read FRoutineName;
    property RoutineKind: TpgnRoutineKind read FRoutineKind;
    property OnRoutineExecute: TNotifyEvent read FOnRoutineExecute write FOnRoutineExecute;
    { Review... in the close question: the main window shows the pending list. }
    property OnReviewPending: TNotifyEvent read FOnReviewPending write FOnReviewPending;
  end;

type
  TpgnTabArray = array of TpgnQueryTab;

implementation

var
  LastExportDir: string = '';   // where the last export went, for the next


const
  QuietScriptSize = 50;   // longer scripts log only problems and the summary
  MaxHistory = 200;
  Dot = ' ' + #$C2#$B7 + ' ';

{ ---------------------------------------------------------------- setup }

constructor TpgnQueryTab.CreateTab(AOwner: TComponent; AStore: TpgnConnectionStore;
  ASettings: TpgnSettings; AHistory: TStringList; AConnect: TpgnConnectFunc;
  const ATitle: string);
begin
  inherited Create(AOwner);
  FStore := AStore;
  FSettings := ASettings;
  FHistory := AHistory;
  FConnect := AConnect;
  FTitle := ATitle;
  FAdapter := nil;
  FThread := nil;
  FExplainRun := False;
  FResultsMode := 0;
  FResultsText := nil;
  FTextShown := False;
  FResultsFile := '';
  FExportOpt.Format := efCSV;
  FExportOpt.Header := True;
  FExportOpt.NullAsWord := False;
  FExportOpt.Bom := True;
  FExportOpt.TableName := '';
  FExportOpt.FileName := '';
  FExportOpt.AllRows := False;
  FExportIndex := 0;
  FCurrentDb := '';
  FStatusText := '';
  FFileName := '';
  FWasModified := False;
  ClearPending;
  FShadeFrom := 0;
  FShadeTo := 0;
  FInfo := NewConnectionInfo;
  FInfo.Id := '';
  BevelOuter := bvNone;
  Caption := '';
  BuildUI;
  ApplyTheme(FSettings.Theme);
  RefreshConnectionList;
  UpdateBand;
  SyncAutoCommitCheck;
end;

destructor TpgnQueryTab.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  DropSession;
  FreeAndNil(FResultGrids);   // the grids themselves are owned controls
  inherited Destroy;
  FreeAndNil(FMsgKinds);
end;

procedure TpgnQueryTab.AddHeaderControl(AControl: TControl);
begin
  AControl.Parent := FBand;
  AControl.Align := alNone;
end;

{ Places the band's controls in a row, each centered vertically. Done by
  hand: automatic left alignment can loop on some widget sets while the
  tab is still being sized. }
procedure TpgnQueryTab.LayoutBand(Sender: TObject);
var
  X: Integer;

  // AWidth > 0 fixes the width; 0 keeps the control's own (labels size
  // themselves to their text)
  procedure Place(C: TControl; AWidth, AGapAfter: Integer);
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
    C.SetBounds(X, (FBand.ClientHeight - C.Height) div 2, W, C.Height);
    X := X + W + Scale96ToScreen(AGapAfter);
  end;

begin
  X := Scale96ToScreen(10);
  Place(FEnvLabel, 0, 16);
  Place(FConnLabel, 0, 6);
  // a schema picker as well: a little less room for each
  if FSchemaWanted then
  begin
    Place(FConnCombo, 230, 14);
    Place(FDbLabel, 0, 6);
    Place(FDbCombo, 160, 14);
  end
  else
  begin
    Place(FConnCombo, 260, 16);
    Place(FDbLabel, 0, 6);
    Place(FDbCombo, 200, 16);
  end;
  // shown for engines with schemas; otherwise parked out of sight (GTK3
  // brings hidden controls back when their parent is shown)
  if FSchemaWanted then
  begin
    Place(FSchemaLabel, 0, 6);
    Place(FSchemaCombo, 150, 14);
  end
  else
  begin
    FSchemaLabel.SetBounds(-2000, 0, FSchemaLabel.Width, FSchemaLabel.Height);
    FSchemaCombo.SetBounds(-2000, 0, FSchemaCombo.Width, FSchemaCombo.Height);
  end;
  Place(FAutoCommitCheck, 0, 0);
  FBand.Invalidate;   // labels that moved leave nothing behind
end;

procedure TpgnQueryTab.BuildUI;
var
  Splitter: TSplitter;
  L: TLabel;
begin
  FNextLeft := 0;
  FAmph := False;   // built as Plume; ApplyLayout rearranges for Amphibian or Seattle
  FSea := False;
  FLayout := LayoutPlume;
  FRunState := 0;

  // the environment band: which connection this tab is on, in words, with
  // the controls to change it. Always shown, so it can be checked at a glance.
  FBand := TPanel.Create(Self);
  FBand.Parent := Self;
  FBand.Align := alTop;
  FBand.Height := Scale96ToScreen(34);
  FBand.BevelOuter := bvNone;
  FBand.ParentColor := False;
  FBand.Caption := '';
  FBand.OnResize := @LayoutBand;

  FEnvLabel := TLabel.Create(Self);
  FEnvLabel.Layout := tlCenter;
  FEnvLabel.Font.Style := [fsBold];
  FEnvLabel.ParentFont := False;
  AddHeaderControl(FEnvLabel);
  // (spacing goes on the combo boxes and the panel: extra spacing on a
  // label makes the layout loop on some widget sets)

  FConnLabel := TLabel.Create(Self);
  FConnLabel.Caption := 'Connection:';
  FConnLabel.Layout := tlCenter;
  FConnLabel.ParentFont := False;
  AddHeaderControl(FConnLabel);

  FConnCombo := TComboBox.Create(Self);
  FConnCombo.Style := csDropDownList;
  FConnCombo.AutoSize := False;
  FConnCombo.Width := 260;
  FConnCombo.OnChange := @ConnComboChange;
  AddHeaderControl(FConnCombo);

  FDbLabel := TLabel.Create(Self);
  FDbLabel.Caption := 'Database:';
  FDbLabel.Layout := tlCenter;
  FDbLabel.ParentFont := False;
  AddHeaderControl(FDbLabel);

  FDbCombo := TComboBox.Create(Self);
  FDbCombo.Style := csDropDownList;
  FDbCombo.AutoSize := False;   // the band sets the width (GTK3 would fit it to the items)
  FDbCombo.Width := 200;
  FDbCombo.OnChange := @DbComboChange;
  AddHeaderControl(FDbCombo);

  FSchemaLabel := TLabel.Create(Self);
  FSchemaLabel.Caption := 'Schema:';
  FSchemaLabel.Layout := tlCenter;
  FSchemaLabel.ParentFont := False;
  AddHeaderControl(FSchemaLabel);

  FSchemaCombo := TComboBox.Create(Self);
  FSchemaCombo.Style := csDropDownList;
  FSchemaCombo.AutoSize := False;
  FSchemaCombo.Width := 150;
  FSchemaCombo.OnChange := @SchemaComboChange;
  AddHeaderControl(FSchemaCombo);

  FAutoCommitCheck := TCheckBox.Create(Self);
  FAutoCommitCheck.Caption := 'Auto-commit on';
  FAutoCommitCheck.Checked := True;
  FAutoCommitCheck.OnClick := @AutoCommitClick;
  FAutoCommitCheck.ParentFont := False;
  AddHeaderControl(FAutoCommitCheck);

  // a firm line under the band, in the environment's color
  FBandLine := TPanel.Create(Self);
  FBandLine.Parent := Self;
  FBandLine.Align := alTop;
  FBandLine.Top := FBand.Top + FBand.Height + 1;
  FBandLine.Height := Scale96ToScreen(2);
  FBandLine.BevelOuter := bvNone;
  FBandLine.ParentColor := False;

  // routine mode only: what is being edited, and Save / Execute / Revert
  FRoutineBar := TPanel.Create(Self);
  FRoutineBar.Parent := Self;
  FRoutineBar.Align := alTop;
  FRoutineBar.Top := FBandLine.Top + FBandLine.Height + 1;
  FRoutineBar.Height := Scale96ToScreen(36);
  FRoutineBar.BevelOuter := bvNone;
  FRoutineBar.Caption := '';
  FRoutineBar.Color := clPgnBar;
  FRoutineBar.ParentColor := False;
  FRoutineBar.Visible := False;
  FRoutineBar.OnResize := @LayoutRoutineBar;

  FRoutineLabel := TLabel.Create(Self);
  FRoutineLabel.Parent := FRoutineBar;
  FRoutineLabel.Font.Style := [fsBold];
  FRoutineLabel.ParentFont := False;

  FBtnSave := TButton.Create(Self);
  FBtnSave.Parent := FRoutineBar;
  FBtnSave.Caption := 'Save';
  FBtnSave.OnClick := @RoutineSaveClick;

  FBtnExecute := TButton.Create(Self);
  FBtnExecute.Parent := FRoutineBar;
  FBtnExecute.Caption := 'Execute...';
  FBtnExecute.OnClick := @RoutineExecuteClick;

  FBtnRevert := TButton.Create(Self);
  FBtnRevert.Parent := FRoutineBar;
  FBtnRevert.Caption := 'Revert';
  FBtnRevert.OnClick := @RoutineRevertClick;

  FRoutineNote := TLabel.Create(Self);
  FRoutineNote.Parent := FRoutineBar;
  FRoutineNote.ParentFont := False;

  // DBA screens only: what is shown, and what can be done to a session
  FScreenBar := TPanel.Create(Self);
  FScreenBar.Parent := Self;
  FScreenBar.Align := alTop;
  FScreenBar.Top := FBandLine.Top + FBandLine.Height + 1;
  FScreenBar.Height := Scale96ToScreen(36);
  FScreenBar.BevelOuter := bvNone;
  FScreenBar.Caption := '';
  FScreenBar.Color := clPgnBar;
  FScreenBar.ParentColor := False;
  FScreenBar.Visible := False;
  FScreenBar.OnResize := @LayoutScreenBar;

  FScreenLabel := TLabel.Create(Self);
  FScreenLabel.Parent := FScreenBar;
  FScreenLabel.Font.Style := [fsBold];
  FScreenLabel.ParentFont := False;

  FBtnScreenRefresh := TButton.Create(Self);
  FBtnScreenRefresh.Parent := FScreenBar;
  FBtnScreenRefresh.Caption := 'Refresh';
  FBtnScreenRefresh.OnClick := @ScreenRefreshClick;

  FAutoCombo := TComboBox.Create(Self);
  FAutoCombo.Parent := FScreenBar;
  FAutoCombo.Style := csDropDownList;
  FAutoCombo.AutoSize := False;
  FAutoCombo.Items.Add('Auto-refresh off');
  FAutoCombo.Items.Add('Every 5 seconds');
  FAutoCombo.Items.Add('Every 10 seconds');
  FAutoCombo.Items.Add('Every 30 seconds');
  FAutoCombo.Items.Add('Every 60 seconds');
  FAutoCombo.ItemIndex := 0;
  FAutoCombo.OnChange := @ScreenAutoChange;

  FBtnShowStmt := TButton.Create(Self);
  FBtnShowStmt.Parent := FScreenBar;
  FBtnShowStmt.Caption := 'Show Statement';
  FBtnShowStmt.OnClick := @ScreenShowStmtClick;

  FBtnCancelSess := TButton.Create(Self);
  FBtnCancelSess.Parent := FScreenBar;
  FBtnCancelSess.Caption := 'Cancel Query';
  FBtnCancelSess.OnClick := @ScreenCancelClick;

  FBtnKillSess := TButton.Create(Self);
  FBtnKillSess.Parent := FScreenBar;
  FBtnKillSess.Caption := 'Kill Session...';
  FBtnKillSess.OnClick := @ScreenKillClick;

  FScreenNote := TLabel.Create(Self);
  FScreenNote.Parent := FScreenBar;
  FScreenNote.ParentFont := False;
  FScreenNote.Font.Color := clPgnMuted;

  FScreenTimer := TTimer.Create(Self);
  FScreenTimer.Enabled := False;
  FScreenTimer.OnTimer := @ScreenTimerTick;

  FHighlighter := TSynSQLSyn.Create(Self);
  FHighlighter.SQLDialect := sqlMySQL;

  FEditor := TSynEdit.Create(Self);
  FEditor.Parent := Self;
  FEditor.Align := alTop;
  FEditor.Top := FRoutineBar.Top + FRoutineBar.Height + 1;
  FEditor.Height := 300;
  FEditor.Highlighter := FHighlighter;
  {$IFDEF WINDOWS}
  FEditor.Font.Name := 'Consolas';
  {$ELSE}
  FEditor.Font.Name := 'Monospace';
  {$ENDIF}
  FEditor.Font.Size := 10;
  SmoothFont(FEditor.Font);
  FEditor.Lines.Clear;   // starts empty, caret at the beginning
  FEditor.OnEnter := @EditorEnter;
  FEditor.OnChange := @EditorChange;
  FEditor.OnMouseDown := @EditorMouseDown;
  FEditor.OnSpecialLineMarkup := @EditorLineMarkup;
  FEditor.OnStatusChange := @EditorStatusChange;
  FEditor.Color := clPgnWork;
  FEditor.Gutter.Color := TColor($00FAF8F7);   // the editor is the same in every look
  FEditor.RightEdge := -1;
  // a click past the end of a line puts the cursor at the end of the text,
  // not out in empty space
  FEditor.Options := FEditor.Options - [eoScrollPastEol];

  // recomputing the shaded statement waits until typing pauses
  FShadeTimer := TTimer.Create(Self);
  FShadeTimer.Enabled := False;
  FShadeTimer.Interval := 120;
  FShadeTimer.OnTimer := @ShadeTimerTick;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alTop;
  Splitter.Top := FEditor.Top + FEditor.Height + 1;
  FEditorSplitter := Splitter;

  // Messages sit under the results, always in view, with a divider to drag
  FMessagesPanel := TPanel.Create(Self);
  FMessagesPanel.Parent := Self;
  FMessagesPanel.Align := alBottom;
  FMessagesPanel.Height := Scale96ToScreen(120);
  FMessagesPanel.BevelOuter := bvNone;
  FMessagesPanel.Caption := '';

  L := TLabel.Create(Self);
  FMsgTitle := L;
  L.Parent := FMessagesPanel;
  L.Align := alTop;
  L.Caption := 'Messages';
  L.Font.Style := [fsBold];
  L.BorderSpacing.Left := Scale96ToScreen(6);
  L.BorderSpacing.Top := Scale96ToScreen(2);
  L.BorderSpacing.Bottom := Scale96ToScreen(2);

  FMsgSplitter := TSplitter.Create(Self);
  FMsgSplitter.Parent := Self;
  FMsgSplitter.Align := alBottom;
  FMsgSplitter.Top := FMessagesPanel.Top - 1;
  FMsgSplitter.ResizeStyle := rsUpdate;

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;

  FPages.OnChange := @PagesChange;
  FResultGrids := TFPList.Create;
  FTabResults := FPages.AddTabSheet;
  FTabResults.Caption := 'Results';
  FResultSwitch := TTabControl.Create(Self);
  FResultSwitch.Parent := FTabResults;
  FResultSwitch.Align := alTop;
  FResultSwitch.Height := Scale96ToScreen(28);
  FResultSwitch.Visible := False;
  FResultSwitch.OnChange := @ResultSwitchChange;
  AddResultGrid;

  FTabPlan := FPages.AddTabSheet;
  FTabPlan.Caption := 'Plan';
  FPlanGrid := TpgnResultGrid.Create(Self);
  FPlanGrid.Parent := FTabPlan;
  FPlanGrid.Align := alClient;

  // every statement run in Pagona this session, newest first; double-click
  // (or Enter) puts one back in the editor
  FTabHistory := FPages.AddTabSheet;
  FTabHistory.Caption := 'History';
  FHistoryList := TListView.Create(Self);
  FHistoryList.Parent := FTabHistory;
  FHistoryList.Align := alClient;
  FHistoryList.ViewStyle := vsReport;
  FHistoryList.ReadOnly := True;
  FHistoryList.RowSelect := True;
  FHistoryList.OnDblClick := @HistoryDblClick;
  with FHistoryList.Columns.Add do
  begin
    Caption := '#';
    Width := Scale96ToScreen(50);
  end;
  with FHistoryList.Columns.Add do
  begin
    Caption := 'Statement (double-click to put it in the editor)';
    Width := Scale96ToScreen(900);
  end;

  FProgressTimer := TTimer.Create(Self);
  FProgressTimer.Enabled := False;
  FProgressTimer.Interval := 250;
  FProgressTimer.OnTimer := @ProgressTick;

  FMsgKinds := TFPList.Create;
  FMessages := TSynEdit.Create(Self);
  FMessages.Parent := FMessagesPanel;
  FMessages.Align := alClient;
  FMessages.ReadOnly := True;
  FMessages.Gutter.Visible := False;
  FMessages.RightEdge := -1;
  FMessages.Options := FMessages.Options - [eoScrollPastEol] + [eoHideRightMargin];
  FMessages.Font.Name := FEditor.Font.Name;
  FMessages.Font.Size := FEditor.Font.Size;
  SmoothFont(FMessages.Font);
  FMessages.Color := clPgnWork;
  FMessages.Lines.Clear;
  FMessages.OnSpecialLineMarkup := @MessagesLineMarkup;

  FPages.ActivePage := FTabResults;
  ApplyLayout(FSettings.Layout);
end;

{ Plume: Results / Plan / History with Messages under them, and the band.
  Amphibian: Toad's tabs (Messages, Data Grid, DBMS Output, Explain Plan,
  History) under a title naming the tab in view, and no band (the main
  window's editor toolbar has its pickers).
  Seattle: SSMS's tabs (Results, Messages, Execution Plan, plus History),
  several result sets stacked in Results, a line under the editor (Ln, Ch,
  ...), the query status bar at the bottom, and no band (the SQL Editor
  toolbar has the database box). What the tab holds stays. }
procedure TpgnQueryTab.ApplyLayout(const ALayout: string);
var
  Was: TTabSheet;
  ToAmph, ToSea: Boolean;
  H: Integer;
  G: TpgnResultGrid;
begin
  if SameText(ALayout, FLayout) then
  begin
    Exit;
  end;
  ToAmph := SameText(ALayout, LayoutAmphibian);
  ToSea := SameText(ALayout, LayoutSeattle);
  Was := FPages.ActivePage;
  DisableAlign;
  try
    // back to Plume first
    if FAmph then
    begin
      if (Was = FTabMessages) or (Was = FTabDbms) then
      begin
        Was := FTabResults;
      end;
      FPages.ActivePage := FTabResults;
      MessagesBack;
      FreeAndNil(FTabDbms);      // and its grid
      FDbmsGrid := nil;
      FreeAndNil(FPagesTitle);
      FTabResults.Caption := 'Results';
      FTabPlan.Caption := 'Plan';
      FAmph := False;
    end;
    if FSea then
    begin
      if Was = FTabMessages then
      begin
        Was := FTabResults;
      end;
      FPages.ActivePage := FTabResults;
      MessagesBack;
      FTabPlan.Caption := 'Plan';
      FTabResults.OnResize := nil;
      // the editor back where it was, without the line under it
      H := FEditorHost.Height - FEditorInfo.Height;
      FEditor.Parent := Self;
      FEditor.Align := alTop;
      FEditor.Top := FEditorHost.Top;
      FEditor.Height := Max(H, Scale96ToScreen(80));
      FreeAndNil(FEditorHost);   // and the line
      FEditorInfo := nil;
      FEditorSplitter.Top := FEditor.Top + FEditor.Height + 1;
      FreeAndNil(FQueryBarHost);
      FQueryBar := nil;
      for H := 0 to FSeaGrids.Count - 1 do
      begin
        TpgnResultGrid(FSeaGrids[H]).Free;
      end;
      FreeAndNil(FSeaGrids);
      FreeAndNil(FResultsText);
      FTextShown := False;
      FResultsMode := 0;
      FSea := False;
      ResultSwitchChange(nil);
    end;
    if (not ToAmph) and (not ToSea) then
    begin
      FBand.Align := alTop;
      FBand.Top := 0;
    end
    else
    begin
      // the band waits out of sight (GTK3 shows hidden panels again)
      FBand.Align := alNone;
      FBand.SetBounds(-4000, 0, 1200, FBand.Height);
    end;

    if ToAmph then
    begin
      FPagesTitle := TLabel.Create(Self);
      FPagesTitle.Parent := Self;
      FPagesTitle.AutoSize := False;
      FPagesTitle.Align := alTop;
      FPagesTitle.Top := FEditorSplitter.Top + FEditorSplitter.Height + 1;
      FPagesTitle.Height := Scale96ToScreen(22);
      FPagesTitle.Layout := tlCenter;
      FPagesTitle.BorderSpacing.Left := Scale96ToScreen(6);

      MessagesToTab(0);
      FTabResults.Caption := 'Data Grid';
      FTabDbms := FPages.AddTabSheet;
      FTabDbms.Caption := 'DBMS Output';
      FTabDbms.PageIndex := 2;
      FDbmsGrid := TpgnResultGrid.Create(Self);
      FDbmsGrid.Parent := FTabDbms;
      FDbmsGrid.Align := alClient;
      FTabPlan.Caption := 'Explain Plan';
      FAmph := True;
    end
    else if ToSea then
    begin
      MessagesToTab(1);
      FTabPlan.Caption := 'Execution Plan';

      // the editor and, under it, SSMS's line: Ln, Ch, tabs, line ends
      FEditorHost := TPanel.Create(Self);
      FEditorHost.Parent := Self;
      FEditorHost.BevelOuter := bvNone;
      FEditorHost.Caption := '';
      FEditorHost.Align := alTop;
      FEditorHost.Top := FEditor.Top;
      FEditorInfo := TPanel.Create(Self);
      FEditorInfo.Parent := FEditorHost;
      FEditorInfo.Align := alBottom;
      FEditorInfo.Height := Scale96ToScreen(22);
      FEditorInfo.BevelOuter := bvNone;
      FEditorInfo.Alignment := taRightJustify;
      FEditorInfo.Color := clPgnBar;
      FEditorInfo.ParentColor := False;
      FEditorInfo.BorderSpacing.InnerBorder := Scale96ToScreen(4);
      FEditorHost.Height := FEditor.Height + FEditorInfo.Height;
      FEditor.Parent := FEditorHost;
      FEditor.Align := alClient;
      FEditorSplitter.Top := FEditorHost.Top + FEditorHost.Height + 1;

      // the query status bar, under the results, as SSMS
      FQueryBarHost := TPanel.Create(Self);
      FQueryBarHost.Parent := Self;
      FQueryBarHost.Align := alBottom;
      FQueryBarHost.Height := Scale96ToScreen(24);
      FQueryBarHost.BevelOuter := bvNone;
      FQueryBarHost.Caption := '';
      FQueryBarHost.Top := ClientHeight + 100;
      FQueryBar := TPaintBox.Create(Self);
      FQueryBar.Parent := FQueryBarHost;
      FQueryBar.Align := alClient;
      FQueryBar.OnPaint := @QueryBarPaint;

      // one grid per possible result set, out of sight until used
      TpgnResultGrid(FResultGrids[0]).Align := alNone;
      TpgnResultGrid(FResultGrids[0]).SetBounds(-6000, 0, 300, 200);
      FSeaGrids := TFPList.Create;
      for H := 1 to MaxResultSets do
      begin
        G := TpgnResultGrid.Create(Self);
        G.Parent := FTabResults;
        G.Align := alNone;
        G.SetBounds(-6000, 0, 300, 200);
        FSeaGrids.Add(G);
      end;
      FSeaShown := 0;
      // Results to Text: fixed-width text in place of the grids
      FResultsText := TMemo.Create(Self);
      FResultsText.Parent := FTabResults;
      FResultsText.Align := alNone;
      FResultsText.ReadOnly := True;
      FResultsText.WordWrap := False;
      FResultsText.ScrollBars := ssBoth;
      FResultsText.Font.Assign(FEditor.Font);
      FResultsText.SetBounds(-6000, 0, 300, 200);
      FTextShown := False;
      FTabResults.OnResize := @ResultsResize;
      FSea := True;
      FResultSwitch.Visible := False;
      StackGrids;
      UpdateEditorInfo;
    end;
  finally
    EnableAlign;
  end;
  FLayout := ALayout;
  if (Was <> nil) and (Was.PageControl = FPages) then
  begin
    FPages.ActivePage := Was;
  end
  else
  begin
    FPages.ActivePage := FTabResults;
  end;
  PagesChange(nil);
  LayoutBand(nil);
  RecolorFrame;
end;

procedure TpgnQueryTab.RecolorFrame;
begin
  FRoutineBar.Color := clPgnBar;
  FScreenBar.Color := clPgnBar;
  if FEditorInfo <> nil then
  begin
    FEditorInfo.Color := clPgnBar;
  end;
  if FPagesTitle <> nil then
  begin
    FPagesTitle.Transparent := False;
    FPagesTitle.Color := clPgnHeader;
    FPagesTitle.Font.Color := clPgnHeaderText;
  end;
  if FQueryBar <> nil then
  begin
    FQueryBar.Invalidate;
  end;
end;

{ Messages become a tab of their own (Amphibian, Seattle) at AIndex. }
procedure TpgnQueryTab.MessagesToTab(AIndex: Integer);
begin
  FMsgSplitter.Align := alNone;
  FMsgSplitter.SetBounds(-3000, 0, 10, 5);
  FTabMessages := FPages.AddTabSheet;
  FTabMessages.Caption := 'Messages';
  FTabMessages.PageIndex := AIndex;
  FMessagesPanel.Parent := FTabMessages;
  FMessagesPanel.Align := alClient;
  // its own "Messages" title waits out of sight (the tab says it)
  FMsgTitle.Align := alNone;
  FMsgTitle.SetBounds(-2000, 0, 10, 10);
end;

{ Messages back under the results, always in view (Plume). }
procedure TpgnQueryTab.MessagesBack;
begin
  FMessagesPanel.Parent := Self;
  FMessagesPanel.Align := alBottom;
  FMessagesPanel.Height := Scale96ToScreen(120);
  FMessagesPanel.Top := ClientHeight + 100;
  FMsgTitle.Align := alTop;
  FMsgTitle.Top := 0;
  FMsgSplitter.Align := alBottom;
  FMsgSplitter.Top := FMessagesPanel.Top - 1;
  FreeAndNil(FTabMessages);
end;

{ Seattle, as SSMS: every result set in Results, one grid under another,
  sharing the height. Placed by hand (GTK3 doesn't re-lay out aligned
  controls reliably). }
procedure TpgnQueryTab.StackGrids;
var
  I, N, H, W, Y, Each, Gap: Integer;
  G: TpgnResultGrid;
begin
  if FSeaGrids = nil then
  begin
    Exit;
  end;
  N := FSeaShown;
  H := FTabResults.ClientHeight;
  W := FTabResults.ClientWidth;
  if FResultsText <> nil then
  begin
    if FTextShown then
    begin
      FResultsText.SetBounds(0, 0, W, H);
      N := 0;
    end
    else if FResultsText.Left > -6000 then
    begin
      FResultsText.SetBounds(-6000, 0, 300, 200);
    end;
  end;
  Gap := Scale96ToScreen(4);
  if N > 0 then
  begin
    Each := Max((H - Gap * (N - 1)) div N, Scale96ToScreen(60));
  end
  else
  begin
    Each := H;
  end;
  Y := 0;
  for I := 0 to FSeaGrids.Count - 1 do
  begin
    G := TpgnResultGrid(FSeaGrids[I]);
    if I < N then
    begin
      if I = N - 1 then
      begin
        G.SetBounds(0, Y, W, Max(H - Y, Scale96ToScreen(60)));
      end
      else
      begin
        G.SetBounds(0, Y, W, Each);
      end;
      Y := Y + Each + Gap;
    end
    else if G.Left > -6000 then
    begin
      G.SetBounds(-6000, 0, 300, 200);
    end;
  end;
end;

{ After the page is shown and laid out (GTK3 sizes a page only then). }
procedure TpgnQueryTab.AsyncStack(AData: PtrInt);
begin
  if FSea then
  begin
    StackGrids;
  end;
end;

procedure TpgnQueryTab.ResultsResize(Sender: TObject);
begin
  if FSea then
  begin
    StackGrids;
  end;
end;

procedure TpgnQueryTab.UpdateEditorInfo;
var
  Spaces, LineEnd: string;
begin
  if FEditorInfo = nil then
  begin
    Exit;
  end;
  if eoTabsToSpaces in FEditor.Options then
  begin
    Spaces := 'SPC';
  end
  else
  begin
    Spaces := 'TABS';
  end;
  {$IFDEF WINDOWS}
  LineEnd := 'CRLF';
  {$ELSE}
  LineEnd := 'LF';
  {$ENDIF}
  FEditorInfo.Caption := Format('Ln: %d, Ch: %d   |   %s   |   %s   |   UTF-8   ',
    [FEditor.CaretY, FEditor.CaretX, Spaces, LineEnd]);
end;

{ Seattle's query status bar: how the last run went, then the environment
  in words, server (version), login (session id), database, time, rows. In
  the environment's color, as SSMS colors it per connection; the word is
  always there. }
procedure TpgnQueryTab.QueryBarPaint(Sender: TObject);
var
  C: TCanvas;
  Look: TpgnEnvLook;
  Back, Fore: TColor;
  R: TRect;
  X, TY, Pad: Integer;
  Outcome, Sid, Ver, Secs: string;
  Ms: Int64;
  Parts: array of string;
  I: Integer;

  procedure AddPart(const AText: string);
  begin
    if AText <> '' then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := AText;
    end;
  end;

begin
  C := FQueryBar.Canvas;
  R := FQueryBar.ClientRect;
  if (FAdapter <> nil) and (FInfo.Environment <> enNone) then
  begin
    Look := EnvironmentLook(FInfo.Environment);
    Back := Look.Back;
    Fore := Look.Text;
  end
  else
  begin
    Back := clPgnSurface;
    Fore := clPgnText;
  end;
  C.Brush.Color := Back;
  C.FillRect(R);
  C.Pen.Color := clPgnLines;
  C.Line(R.Left, R.Top, R.Right, R.Top);
  C.Font.Assign(Font);
  C.Font.Color := Fore;
  C.Brush.Style := bsClear;
  Pad := Scale96ToScreen(8);
  TY := (R.Top + R.Bottom - C.TextHeight('Ag')) div 2;

  if FAdapter = nil then
  begin
    Outcome := 'Not connected.';
  end
  else
  begin
    case FRunState of
      1:
        begin
          Outcome := #$E2#$9C#$93 + ' Query executed successfully.';
        end;
      2:
        begin
          Outcome := #$E2#$9C#$97 + ' Query completed with errors.';
        end;
      3:
        begin
          Outcome := 'Query was canceled by user.';
        end;
      4:
        begin
          Outcome := 'Executing query...';
        end;
    else
      begin
        Outcome := 'Connected.';
      end;
    end;
  end;
  C.TextOut(R.Left + Pad, TY, Outcome);

  if FAdapter = nil then
  begin
    Exit;
  end;
  Parts := nil;
  if FInfo.Environment <> enNone then
  begin
    AddPart(UpperCase(EnvironmentShort[FInfo.Environment]));
  end;
  Ver := FAdapter.ServerVersion;
  if Ver <> '' then
  begin
    AddPart(FInfo.Name + ' (' + Ver + ')');
  end
  else
  begin
    AddPart(FInfo.Name);
  end;
  Sid := FAdapter.OwnSessionId;
  if Sid <> '' then
  begin
    AddPart(FInfo.User + ' (' + Sid + ')');
  end
  else
  begin
    AddPart(FInfo.User);
  end;
  AddPart(FCurrentDb);
  if FRunState = 4 then
  begin
    Ms := Round((Now - FRunStart) * 86400000);
  end
  else
  begin
    Ms := FRunMs;
  end;
  if FRunState <> 0 then
  begin
    Secs := Format('%.2d:%.2d:%.2d', [Ms div 3600000, (Ms div 60000) mod 60, (Ms div 1000) mod 60]);
    AddPart(Secs);
  end;
  if FRunState in [1, 2, 3] then
  begin
    if FRunRows = 1 then
    begin
      AddPart('1 row');
    end
    else
    begin
      AddPart(IntToStr(FRunRows) + ' rows');
    end;
  end;
  // right to left, a thin line between the parts
  X := R.Right - Pad;
  for I := High(Parts) downto 0 do
  begin
    if I = 0 then
    begin
      C.Font.Style := [fsBold];
    end
    else
    begin
      C.Font.Style := [];
    end;
    X := X - C.TextWidth(Parts[I]);
    C.TextOut(X, TY, Parts[I]);
    X := X - Pad;
    if I > 0 then
    begin
      C.Pen.Color := Fore;
      C.Line(X, R.Top + Scale96ToScreen(5), X, R.Bottom - Scale96ToScreen(5));
      X := X - Pad;
    end;
  end;
  C.Font.Style := [];
end;

function TpgnQueryTab.FullTitle: string;
var
  Sid, Where: string;
begin
  if FAdapter = nil then
  begin
    Result := FTitle + ' - not connected';
  end
  else
  begin
    Sid := FAdapter.OwnSessionId;
    Where := FInfo.Name;
    if FCurrentDb <> '' then
    begin
      Where := Where + '.' + FCurrentDb;
    end;
    if Sid <> '' then
    begin
      Result := FTitle + ' - ' + Where + ' (' + FInfo.User + ' (' + Sid + '))';
    end
    else
    begin
      Result := FTitle + ' - ' + Where + ' (' + FInfo.User + ')';
    end;
  end;
  if IsModified then
  begin
    Result := Result + '*';
  end;
end;

function TpgnQueryTab.BandCombo(AWhich: Integer): TComboBox;
begin
  case AWhich of
    0:
      begin
        Result := FConnCombo;
      end;
    1:
      begin
        Result := FDbCombo;
      end;
  else
    begin
      Result := FSchemaCombo;
    end;
  end;
end;

procedure TpgnQueryTab.PickInBand(AWhich, AIndex: Integer);
var
  C: TComboBox;
begin
  C := BandCombo(AWhich);
  if (AIndex < 0) or (AIndex >= C.Items.Count) or (C.ItemIndex = AIndex) then
  begin
    Exit;
  end;
  C.ItemIndex := AIndex;
  case AWhich of
    0:
      begin
        ConnComboChange(C);
      end;
    1:
      begin
        DbComboChange(C);
      end;
  else
    begin
      SchemaComboChange(C);
    end;
  end;
end;

function TpgnQueryTab.SchemaWanted: Boolean;
begin
  Result := FSchemaWanted;
end;

{ ------------------------------------------------------------- state }

procedure TpgnQueryTab.StateChanged;
var
  Running, Connected: Boolean;
begin
  Running := FThread <> nil;
  Connected := FAdapter <> nil;
  FConnCombo.Enabled := not Running;
  FDbCombo.Enabled := Connected and not Running;
  FAutoCommitCheck.Enabled := Connected and not Running;
  if FRoutineMode then
  begin
    UpdateRoutineBar;
  end;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

procedure TpgnQueryTab.UpdateBand;
var
  Look: TpgnEnvLook;
  Env: TpgnEnvironment;
  Txt: TColor;
begin
  if FAdapter = nil then
  begin
    Env := enNone;
    FEnvLabel.Caption := 'NOT CONNECTED';
  end
  else
  begin
    Env := FInfo.Environment;
    if Env = enNone then
    begin
      FEnvLabel.Caption := 'NO ENVIRONMENT SET';
    end
    else
    begin
      FEnvLabel.Caption := UpperCase(EnvironmentLong[Env]);
    end;
  end;

  Look := EnvironmentLook(Env);
  // a connection's own color, if it has one, replaces the environment's
  if (FAdapter <> nil) and (FInfo.Color <> NoConnectionColor) then
  begin
    Look.Back := FInfo.Color;
    Look.Border := FInfo.Color;
    Look.Text := ContrastTextColor(FInfo.Color);
  end;
  Txt := Look.Text;
  FBand.Color := Look.Back;
  FBandLine.Color := Look.Border;
  FEnvLabel.Font.Color := Txt;
  FConnLabel.Font.Color := Txt;
  FDbLabel.Font.Color := Txt;
  FAutoCommitCheck.Font.Color := Txt;
  LayoutBand(nil);
end;

function TpgnQueryTab.DisplayCaption: string;
const
  MaxTitle = 26;   // characters of the title kept on the tab
var
  T: string;
begin
  if FSea and not FRoutineMode and (FScreen = dsNone) then
  begin
    // SSMS's name, shortened in the middle as SSMS does: "SQLQuery1....andyw (83))*"
    T := FullTitle;
    if UTF8Length(T) > 28 then
    begin
      T := UTF8Copy(T, 1, 10) + '...' + UTF8Copy(T, UTF8Length(T) - 14, 15);
    end;
    if (FAdapter <> nil) and (FInfo.Environment <> enNone) then
    begin
      T := EnvironmentShort[FInfo.Environment] + ' ' + T;
    end;
    Result := T;
    Exit;
  end;
  // a long title keeps its start and end: "Procedure calc_s...lance"
  T := FTitle;
  if UTF8Length(T) > MaxTitle then
  begin
    T := UTF8Copy(T, 1, MaxTitle - 8) + #$E2#$80#$A6 + UTF8Copy(T, UTF8Length(T) - 6, 7);
  end;
  // "PROD dev9 · Query 1": the environment first, in words
  if FAdapter = nil then
  begin
    Result := T;
  end
  else if FInfo.Environment = enNone then
  begin
    Result := FInfo.Name + Dot + T;
  end
  else
  begin
    Result := EnvironmentShort[FInfo.Environment] + ' ' + FInfo.Name + Dot + T;
  end;
  if IsModified then
  begin
    Result := Result + ' *';
  end;
end;

{ Unsaved changes worth asking about: edits since the last open/save,
  ignoring an empty tab that was never saved. }
function TpgnQueryTab.IsModified: Boolean;
begin
  Result := FEditor.Modified and ((FFileName <> '') or HasText);
end;

function TpgnQueryTab.IsEmpty: Boolean;
begin
  Result := (FFileName = '') and not HasText;
end;

procedure TpgnQueryTab.EditorChange(Sender: TObject);
begin
  // only the switch between saved and unsaved matters to the tab title
  if IsModified <> FWasModified then
  begin
    FWasModified := IsModified;
    StateChanged;
  end;
end;

function TpgnQueryTab.IsConnected: Boolean;
begin
  Result := FAdapter <> nil;
end;

function TpgnQueryTab.IsRunning: Boolean;
begin
  Result := FThread <> nil;
end;

function TpgnQueryTab.HasText: Boolean;
begin
  Result := Trim(FEditor.Text) <> '';
end;

function MessageKindOf(const AText: string): TpgnMessageKind;
const
  Warnings: array[0..5] of string = ('Could not', 'Cancel', 'Not run',
    'Nothing to run', 'Explorer could not', 'WARNING');
var
  I: Integer;
begin
  Result := mkInfo;
  if Pos('Script finished', AText) = 1 then
  begin
    Result := mkSuccess;
    Exit;
  end;
  if Pos('ERROR', AText) = 1 then
  begin
    Result := mkError;
    Exit;
  end;
  for I := 0 to High(Warnings) do
  begin
    if Pos(Warnings[I], AText) = 1 then
    begin
      Result := mkWarning;
      Exit;
    end;
  end;
end;

{ Newest message first, so the latest result is always in view. A message
  of several lines keeps its lines in order, the later ones indented under
  the time. Errors and warnings are styled (see MessagesLineMarkup). }
procedure TpgnQueryTab.Log(const AText: string);
var
  Parts: TStringList;
  I: Integer;
  Kind: TpgnMessageKind;
  Line: string;
begin
  Kind := MessageKindOf(AText);
  Parts := TStringList.Create;
  try
    Parts.Text := AText;
    if Parts.Count = 0 then
    begin
      Parts.Add('');
    end;
    // insert from the last line up, so the first ends on top
    for I := Parts.Count - 1 downto 0 do
    begin
      if I = 0 then
      begin
        Line := FormatDateTime('hh:nn:ss', Now) + '  ' + Parts[I];
      end
      else
      begin
        Line := '          ' + Parts[I];
      end;
      if FMessages.Lines.Count = 0 then
      begin
        FMessages.Lines.Add(Line);
      end
      else
      begin
        FMessages.Lines.Insert(0, Line);
      end;
      FMsgKinds.Insert(0, Pointer(PtrUInt(Ord(Kind))));
    end;
  finally
    Parts.Free;
  end;
  FMessages.TopLine := 1;
  FMessages.CaretXY := Point(1, 1);
  FMessages.Invalidate;
end;

procedure TpgnQueryTab.MessagesLineMarkup(Sender: TObject; Line: Integer; var Special: Boolean;
  Markup: TSynSelectedColor);
var
  Kind: TpgnMessageKind;
begin
  if (Line < 1) or (Line > FMsgKinds.Count) then
  begin
    Exit;
  end;
  Kind := TpgnMessageKind(PtrUInt(FMsgKinds[Line - 1]));
  case Kind of
    mkError:
      begin
        Special := True;
        Markup.Foreground := clPgnDanger;
        Markup.Background := EnvironmentLook(enProduction).Back;
        Markup.Style := [fsBold];
        Markup.StyleMask := [fsBold];
      end;
    mkSuccess:
      begin
        Special := True;
        Markup.Foreground := clPgnSafe;
        Markup.Background := clNone;
        Markup.Style := [fsBold];
        Markup.StyleMask := [fsBold];
      end;
    mkWarning:
      begin
        Special := True;
        Markup.Foreground := EnvironmentLook(enTest).Text;
        Markup.Background := clNone;
        Markup.Style := [fsBold];
        Markup.StyleMask := [fsBold];
      end;
  end;
end;

{ Puts the cursor in this tab's editor. Before the window is on screen,
  the editor is marked as the control to focus when it appears; a focus
  request that can't be honored is simply skipped. }
procedure TpgnQueryTab.FocusEditor;
var
  F: TCustomForm;
begin
  F := GetParentForm(FEditor);
  if F = nil then
  begin
    Exit;
  end;
  try
    if not F.Showing then
    begin
      F.ActiveControl := FEditor;
    end
    else if FEditor.IsVisible and FEditor.CanFocus then
    begin
      FEditor.SetFocus;
    end;
  except
    on E: Exception do
    begin
      // focus is a convenience; never let it interrupt anything
    end;
  end;
end;

procedure TpgnQueryTab.EditorEnter(Sender: TObject);
begin
  if Assigned(FOnActivate) then
  begin
    FOnActivate(Self);
  end;
end;

procedure TpgnQueryTab.EditorMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Assigned(FOnActivate) then
  begin
    FOnActivate(Self);
  end;
end;

{ -------------------------------------------------------- connection }

procedure TpgnQueryTab.RefreshConnectionList;
var
  I: Integer;
begin
  FSyncing := True;
  try
    FConnCombo.Items.BeginUpdate;
    try
      FConnCombo.Items.Clear;
      for I := 0 to FStore.Count - 1 do
      begin
        FConnCombo.Items.Add(ConnectionLabel(FStore.Items[I]));
      end;
    finally
      FConnCombo.Items.EndUpdate;
    end;
  finally
    FSyncing := False;
  end;
  SyncConnCombo;
end;

procedure TpgnQueryTab.SyncConnCombo;
begin
  FSyncing := True;
  try
    if FAdapter = nil then
    begin
      FConnCombo.ItemIndex := -1;
    end
    else
    begin
      FConnCombo.ItemIndex := FStore.IndexOfId(FInfo.Id);
    end;
  finally
    FSyncing := False;
  end;
end;

{ A profile was edited: pick up its new name, label and color. }
procedure TpgnQueryTab.UpdateConnectionInfo(const AInfo: TpgnConnectionInfo);
begin
  if (FAdapter <> nil) and (FInfo.Id = AInfo.Id) then
  begin
    FInfo.Name := AInfo.Name;
    FInfo.Environment := AInfo.Environment;
    FInfo.Color := AInfo.Color;
    UpdateBand;
    StateChanged;
  end;
end;

procedure TpgnQueryTab.DropSession;
begin
  if FAdapter <> nil then
  begin
    try
      FAdapter.Disconnect;
    except
      on E: Exception do
      begin
        // the session is going away either way
      end;
    end;
    FreeAndNil(FAdapter);
  end;
end;

function TpgnQueryTab.ConnectTo(const AInfo: TpgnConnectionInfo; const ADatabase: string): Boolean;
var
  A: TpgnAdapter;
  Target: TpgnConnectionInfo;
begin
  Result := False;
  if FThread <> nil then
  begin
    Exit;
  end;
  if not ResolvePendingWork('switching connections') then
  begin
    Exit;
  end;

  // on the database asked for from the start (PostgreSQL can't switch
  // later without reconnecting)
  Target := AInfo;
  if ADatabase <> '' then
  begin
    Target.DefaultDatabase := ADatabase;
  end;
  A := FConnect(Target);
  if A = nil then
  begin
    Exit;
  end;

  DropSession;
  FAdapter := A;
  FInfo := A.Info;   // as connected (Windows Authentication fills in the login)
  FCurrentDb := FAdapter.CurrentDatabase;
  Log('Connected to ' + ConnectionLongLabel(FInfo) + ' (' + FInfo.Host + ')');
  FConnectedAt := Now;
  if (FSea and not FSettings.AutoCommitSeattle) or ((not FSea) and not FSettings.AutoCommitNewTabs) then
  begin
    // as Toad: changes wait for Commit (Edit > Options changes how tabs start;
    // Seattle has its own setting, on by default as SSMS)
    try
      FAdapter.SetAutoCommit(False);
      Log('Auto-commit off: changes stay pending until Commit or Rollback');
    except
      on E: Exception do
      begin
        Log('Could not turn auto-commit off: ' + E.Message);
      end;
    end;
  end;

  if (ADatabase <> '') and (ADatabase <> FCurrentDb) then
  begin
    try
      FAdapter.UseDatabase(ADatabase);
      FCurrentDb := ADatabase;
    except
      on E: Exception do
      begin
        Log('Could not switch to ' + ADatabase + ': ' + E.Message);
      end;
    end;
  end;

  ClearPending;
  ReloadDatabaseList;
  UpdateEngineLook;
  ReloadSchemaList;
  LoadObjectNames;
  SyncConnCombo;
  SyncAutoCommitCheck;
  UpdateBand;
  StateChanged;
  Result := True;
end;

procedure TpgnQueryTab.ConnComboChange(Sender: TObject);
var
  Idx: Integer;
begin
  if FSyncing then
  begin
    Exit;
  end;
  Idx := FConnCombo.ItemIndex;
  if (Idx < 0) or (Idx >= FStore.Count) then
  begin
    Exit;
  end;
  if (FAdapter <> nil) and (FStore.Items[Idx].Id = FInfo.Id) then
  begin
    Exit;
  end;
  if not ConnectTo(FStore.Items[Idx], FStore.Items[Idx].DefaultDatabase) then
  begin
    SyncConnCombo;   // canceled or failed: show the connection still in use
  end;
end;

procedure TpgnQueryTab.FillDbCombo(const ANames: TpgnStringArray);
var
  I: Integer;
begin
  FSyncing := True;
  try
    FDbCombo.Items.BeginUpdate;
    try
      FDbCombo.Items.Clear;
      for I := 0 to High(ANames) do
      begin
        FDbCombo.Items.Add(ANames[I]);
      end;
    finally
      FDbCombo.Items.EndUpdate;
    end;
  finally
    FSyncing := False;
  end;
  SyncDbCombo;
end;

procedure TpgnQueryTab.ReloadDatabaseList;
var
  Names: TpgnStringArray;
begin
  Names := nil;
  if (FAdapter = nil) or (FThread <> nil) then
  begin
    FillDbCombo(Names);
    Exit;
  end;
  try
    Names := FAdapter.ListDatabases;
  except
    on E: Exception do
    begin
      Log('Could not list databases: ' + E.Message);
    end;
  end;
  FillDbCombo(Names);
end;

procedure TpgnQueryTab.SyncDbCombo;
var
  Idx: Integer;
begin
  FSyncing := True;
  try
    if FCurrentDb = '' then
    begin
      FDbCombo.ItemIndex := -1;
    end
    else
    begin
      Idx := FDbCombo.Items.IndexOf(FCurrentDb);
      if Idx < 0 then
      begin
        Idx := FDbCombo.Items.Add(FCurrentDb);
      end;
      FDbCombo.ItemIndex := Idx;
    end;
  finally
    FSyncing := False;
  end;
end;

procedure TpgnQueryTab.SelectDatabase(const AName: string);
begin
  if (FAdapter = nil) or (FThread <> nil) or (AName = '') then
  begin
    Exit;
  end;
  if FAdapter.SessionPerDatabase and not SameText(AName, FCurrentDb) and
    not ResolvePendingWork('switching databases') then
  begin
    SyncDbCombo;
    Exit;
  end;
  try
    FAdapter.UseDatabase(AName);
    FCurrentDb := AName;
    if FAdapter.SessionPerDatabase then
    begin
      ClearPending;   // a new session: nothing is waiting any more
      Log('Connected to database ' + AName);
    end
    else
    begin
      Log('Using database ' + AName);
    end;
    ReloadSchemaList;
    LoadObjectNames;
  except
    on E: Exception do
    begin
      Log('ERROR: could not switch to database ' + AName + ': ' + E.Message);
      MessageDlg('Could not switch to database ' + AName + LineEnding + LineEnding + E.Message,
        mtError, [mbOK], 0);
    end;
  end;
  SyncDbCombo;
  StateChanged;
end;

{ The Schema picker: shown for engines with schemas, filled from the
  session's database, set to the schema the session is using. }
procedure TpgnQueryTab.ReloadSchemaList;
var
  Names: TpgnStringArray;
  I: Integer;
  Want: Boolean;
begin
  // SQL Server has no schema to switch to (the login's default is used)
  Want := (FAdapter <> nil) and FAdapter.HasSchemas and (FAdapter.Dialect <> sdTSQL);
  if FSchemaWanted <> Want then
  begin
    FSchemaWanted := Want;
    LayoutBand(nil);
  end;
  if not Want or (FThread <> nil) then
  begin
    Exit;
  end;
  Names := nil;
  try
    Names := FAdapter.ListSchemas(False);
  except
    on E: Exception do
    begin
      Log('Could not list schemas: ' + E.Message);
    end;
  end;
  FSyncing := True;
  try
    FSchemaCombo.Items.BeginUpdate;
    try
      FSchemaCombo.Items.Clear;
      for I := 0 to High(Names) do
      begin
        FSchemaCombo.Items.Add(Names[I]);
      end;
    finally
      FSchemaCombo.Items.EndUpdate;
    end;
  finally
    FSyncing := False;
  end;
  SyncSchemaCombo;
end;

procedure TpgnQueryTab.SyncSchemaCombo;
var
  Idx: Integer;
  Cur: string;
begin
  if (FAdapter = nil) or not FAdapter.HasSchemas then
  begin
    Exit;
  end;
  Cur := FAdapter.CurrentSchema;
  FSyncing := True;
  try
    Idx := FSchemaCombo.Items.IndexOf(Cur);
    if (Idx < 0) and (Cur <> '') then
    begin
      Idx := FSchemaCombo.Items.Add(Cur);
    end;
    FSchemaCombo.ItemIndex := Idx;
  finally
    FSyncing := False;
  end;
end;

procedure TpgnQueryTab.SetSchema(const ASchema: string);
begin
  if (FAdapter = nil) or (FThread <> nil) or (ASchema = '') or not FAdapter.HasSchemas then
  begin
    Exit;
  end;
  try
    FAdapter.UseSchema(ASchema);
    Log('Using schema ' + ASchema);
  except
    on E: Exception do
    begin
      Log('ERROR: could not use schema ' + ASchema + ': ' + E.Message);
    end;
  end;
  SyncSchemaCombo;
end;

procedure TpgnQueryTab.SchemaComboChange(Sender: TObject);
begin
  if FSyncing then
  begin
    Exit;
  end;
  if FSchemaCombo.ItemIndex >= 0 then
  begin
    SetSchema(FSchemaCombo.Items[FSchemaCombo.ItemIndex]);
  end;
end;

function TpgnQueryTab.Dialect: TpgnDialect;
begin
  if FAdapter = nil then
  begin
    Result := sdMySQL;
  end
  else
  begin
    Result := FAdapter.Dialect;
  end;
end;

{ The editor's keyword set follows the engine. }
procedure TpgnQueryTab.UpdateEngineLook;
begin
  if Dialect = sdPostgreSQL then
  begin
    FHighlighter.SQLDialect := sqlPostgres;
  end
  else if Dialect = sdOracle then
  begin
    FHighlighter.SQLDialect := sqlOracle;
  end
  else if Dialect = sdTSQL then
  begin
    FHighlighter.SQLDialect := sqlMSSQL2K;
  end
  else
  begin
    FHighlighter.SQLDialect := sqlMySQL;
  end;
  FEditor.Invalidate;
end;

procedure TpgnQueryTab.DbComboChange(Sender: TObject);
begin
  if FSyncing then
  begin
    Exit;
  end;
  if FDbCombo.ItemIndex >= 0 then
  begin
    SelectDatabase(FDbCombo.Items[FDbCombo.ItemIndex]);
  end;
end;

{ ------------------------------------------------------ transactions }

procedure TpgnQueryTab.SyncAutoCommitCheck;
begin
  FSyncing := True;
  try
    FAutoCommitCheck.Checked := (FAdapter = nil) or FAdapter.AutoCommit;
    if FAutoCommitCheck.Checked then
    begin
      FAutoCommitCheck.Caption := 'Auto-commit on';
      FAutoCommitCheck.Font.Style := [];
    end
    else
    begin
      FAutoCommitCheck.Caption := 'Auto-commit OFF';
      FAutoCommitCheck.Font.Style := [fsBold];
    end;
    LayoutBand(nil);
  finally
    FSyncing := False;
  end;
end;

procedure TpgnQueryTab.AutoCommitClick(Sender: TObject);
begin
  if FSyncing or (FAdapter = nil) then
  begin
    Exit;
  end;
  if FAutoCommitCheck.Checked = FAdapter.AutoCommit then
  begin
    Exit;
  end;
  if FAutoCommitCheck.Checked then
  begin
    if MessageDlg('Turning auto-commit on commits any pending changes on ' +
      ConnectionLongLabel(FInfo) + '. Continue?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    begin
      SyncAutoCommitCheck;
      Exit;
    end;
  end;
  try
    FAdapter.SetAutoCommit(FAutoCommitCheck.Checked);
    if FAdapter.AutoCommit then
    begin
      ClearPending;
      Log('Auto-commit on');
    end
    else
    begin
      Log('Auto-commit off: changes stay pending until Commit or Rollback');
    end;
  except
    on E: Exception do
    begin
      Log('ERROR: could not change auto-commit: ' + E.Message);
    end;
  end;
  SyncAutoCommitCheck;
  StateChanged;
end;

function TpgnQueryTab.ResolvePendingWork(const AReason: string): Boolean;
var
  Answer: TModalResult;
  Msg: string;
begin
  Result := True;
  // only when something is actually waiting (DDL on Oracle and MySQL has
  // already committed, so it leaves nothing to ask about)
  if (FAdapter = nil) or FAdapter.AutoCommit or (FPending = 0) then
  begin
    Exit;
  end;
  repeat
    if FPending = 1 then
    begin
      Msg := 'Tab "' + FTitle + '" on ' + ConnectionLongLabel(FInfo) + ' has 1 uncommitted statement.';
    end
    else if FPending > 1 then
    begin
      Msg := 'Tab "' + FTitle + '" on ' + ConnectionLongLabel(FInfo) + ' has ' + IntToStr(FPending) +
        ' uncommitted statements.';
    end
    else
    begin
      Msg := 'Auto-commit is off on ' + ConnectionLongLabel(FInfo) + ' (tab "' + FTitle +
        '"); there may be uncommitted work.';
    end;
    Msg := Msg + LineEnding + LineEnding + 'Commit before ' + AReason + '?';
    if FSea then
    begin
      // SSMS's question and buttons (No rolls back)
      Answer := QuestionDlg('Pagona', 'There are uncommitted transactions. Do you wish to commit these ' +
        'transactions before closing the window?' + LineEnding + LineEnding + '(' + FTitle + ' on ' +
        ConnectionLongLabel(FInfo) + ')', mtWarning, [mrYes, 'Yes', mrNo, 'No', mrCancel, 'Cancel'], 0);
    end
    else if Assigned(FOnReviewPending) and (FPending > 0) then
    begin
      Answer := QuestionDlg('Uncommitted changes', Msg, mtConfirmation,
        [mrRetry, 'Review...', mrYes, 'Commit', mrNo, 'Roll Back', mrCancel, 'Cancel'], 0);
    end
    else
    begin
      Answer := QuestionDlg('Uncommitted changes', Msg, mtConfirmation,
        [mrYes, 'Commit', mrNo, 'Roll Back', mrCancel, 'Cancel'], 0);
    end;
    if Answer = mrRetry then
    begin
      FOnReviewPending(Self);
      if FAdapter.AutoCommit or (FPending = 0) then
      begin
        Exit;   // committed or rolled back from the list
      end;
    end;
  until Answer <> mrRetry;
  if (Answer = mrCancel) or (Answer = mrNone) then
  begin
    Result := False;
    Exit;
  end;
  try
    if Answer = mrYes then
    begin
      FAdapter.Commit;
      Log('Committed');
    end
    else
    begin
      FAdapter.Rollback;
      Log('Rolled back');
    end;
    ClearPending;
  except
    on E: Exception do
    begin
      MessageDlg('Could not finish the transaction' + LineEnding + LineEnding + E.Message,
        mtError, [mbOK], 0);
      Result := False;
    end;
  end;
end;

procedure TpgnQueryTab.Commit;
begin
  if FAdapter = nil then
  begin
    Exit;
  end;
  try
    FAdapter.Commit;
    ClearPending;
    Log('Committed');
    FStatusText := 'Committed';
  except
    on E: Exception do
    begin
      Log('ERROR: commit failed: ' + E.Message);
    end;
  end;
  StateChanged;
end;

procedure TpgnQueryTab.Rollback;
begin
  if FAdapter = nil then
  begin
    Exit;
  end;
  try
    FAdapter.Rollback;
    ClearPending;
    Log('Rolled back');
    FStatusText := 'Rolled back';
  except
    on E: Exception do
    begin
      Log('ERROR: rollback failed: ' + E.Message);
    end;
  end;
  StateChanged;
end;

procedure TpgnQueryTab.ToggleAutoCommit;
begin
  if (FAdapter = nil) or (FThread <> nil) then
  begin
    Exit;
  end;
  // the checkbox's own handler asks, switches and logs
  FAutoCommitCheck.Checked := not FAutoCommitCheck.Checked;
end;

{ Closes this tab's session; the tab stays open, not connected.
  False if the person canceled at the pending-transaction question. }
function TpgnQueryTab.Disconnect: Boolean;
begin
  Result := False;
  if (FAdapter = nil) or (FThread <> nil) then
  begin
    Exit;
  end;
  if not ResolvePendingWork('disconnecting') then
  begin
    Exit;
  end;
  Log('Disconnected from ' + ConnectionLongLabel(FInfo));
  DropSession;
  FInfo := NewConnectionInfo;
  FInfo.Id := '';
  FCurrentDb := '';
  ClearPending;
  FHighlighter.TableNames.Clear;
  ReloadDatabaseList;
  SyncConnCombo;
  SyncAutoCommitCheck;
  UpdateBand;
  StateChanged;
  Result := True;
end;

{ Keeps count of what is waiting for Commit. DDL commits implicitly in
  MySQL and Oracle, so it starts the count over. }
{ Keeps the list of statements waiting for Commit (auto-commit off). }
procedure TpgnQueryTab.RecordPending(const ASQL: string; ARows: Int64; const ASavepoint: string);
var
  N: Integer;
begin
  if (FAdapter = nil) or FAdapter.AutoCommit then
  begin
    ClearPending;
    Exit;
  end;
  if not StatementOnlyReads(ASQL) then
  begin
    FReadsOnly := False;   // it may hold locks: the next run keeps the transaction
  end;
  if StatementChangesData(ASQL) or ((Dialect in [sdPostgreSQL, sdTSQL]) and StatementIsDDL(ASQL)) then
  begin
    N := Length(FPendingList);
    SetLength(FPendingList, N + 1);
    FPendingList[N].SQL := Trim(ASQL);
    FPendingList[N].RanAt := Now;
    FPendingList[N].Rows := ARows;
    FPendingList[N].Savepoint := ASavepoint;
    FPending := N + 1;
  end
  else if StatementEndsTransaction(ASQL, Dialect in [sdPostgreSQL, sdTSQL]) then
  begin
    ClearPending;
  end;
end;

procedure TpgnQueryTab.ClearPending;
begin
  SetLength(FPendingList, 0);
  FPending := 0;
  FReadsOnly := True;
end;

function TpgnQueryTab.PendingItem(AIndex: Integer): TpgnPendingItem;
begin
  Result := FPendingList[AIndex];
end;

{ Undoes pending statement AIndex and everything after it (back to the
  savepoint set just before it); the earlier ones stay pending. }
function TpgnQueryTab.UndoFrom(AIndex: Integer): Boolean;
var
  Gone: Integer;
begin
  Result := False;
  if (FAdapter = nil) or (FThread <> nil) or (AIndex < 0) or (AIndex > High(FPendingList)) then
  begin
    Exit;
  end;
  if FPendingList[AIndex].Savepoint = '' then
  begin
    MessageDlg('This statement can''t be undone on its own (the database didn''t take a savepoint ' +
      'before it). Roll Back All undoes everything pending.', mtInformation, [mbOK], 0);
    Exit;
  end;
  try
    FAdapter.Execute('ROLLBACK TO SAVEPOINT ' + FPendingList[AIndex].Savepoint, 0).Free;
  except
    on E: Exception do
    begin
      Log('ERROR: could not undo: ' + E.Message);
      MessageDlg('Could not undo' + LineEnding + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  Gone := Length(FPendingList) - AIndex;
  SetLength(FPendingList, AIndex);
  FPending := AIndex;
  Log(Format('Undid %d uncommitted statement(s), from statement %d on; %d still pending',
    [Gone, AIndex + 1, AIndex]));
  FStatusText := 'Undid ' + IntToStr(Gone) + ' statement(s)';
  StateChanged;
  Result := True;
end;

{ The editor colors your own tables, views and routines; the names come
  from the database this tab is using. }
procedure TpgnQueryTab.LoadObjectNames;
var
  Names: TpgnStringArray;
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    if (FAdapter <> nil) and (FThread = nil) and (FCurrentDb <> '') then
    begin
      try
        Names := FAdapter.ListObjectNames(FCurrentDb);
        for I := 0 to High(Names) do
        begin
          L.Add(Names[I]);
        end;
      except
        on E: Exception do
        begin
          Log('Could not read object names for coloring: ' + E.Message);
        end;
      end;
    end;
    FHighlighter.TableNames.Assign(L);
  finally
    L.Free;
  end;
  FEditor.Invalidate;
end;

procedure TpgnQueryTab.ApplyTheme(const ATheme: string);
begin
  ApplyEditorTheme(FHighlighter, ATheme);
  FEditor.Invalidate;
end;

function TpgnQueryTab.CaretText: string;
begin
  Result := Format('Ln %d, Col %d', [FEditor.CaretY, FEditor.CaretX]);
end;

{ ------------------------------------------------- the shaded statement }

procedure TpgnQueryTab.EditorStatusChange(Sender: TObject; Changes: TSynStatusChanges);
begin
  if (scCaretX in Changes) or (scCaretY in Changes) or (scSelection in Changes) or
    (scModified in Changes) then
  begin
    FShadeTimer.Enabled := False;
    FShadeTimer.Enabled := True;
    UpdateEditorInfo;
    if Assigned(FOnCaretMoved) then
    begin
      FOnCaretMoved(Self);
    end;
  end;
end;

procedure TpgnQueryTab.ShadeTimerTick(Sender: TObject);
begin
  FShadeTimer.Enabled := False;
  UpdateShade;
end;

function LineOfOffset(const AText: string; AOffset: Integer): Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to AOffset - 1 do
  begin
    if AText[I] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

{ Shades the lines of the statement Run would execute right now. Comment
  and blank lines before it aren't shaded; neither is anything when text
  is selected (the selection shows what runs). }
procedure TpgnQueryTab.UpdateShade;
var
  T, L: string;
  A, B, NewFrom, NewTo, OldFrom, OldTo: Integer;
begin
  NewFrom := 0;
  NewTo := 0;
  if not FEditor.SelAvail then
  begin
    T := FEditor.Text;
    if StatementSpanAt(T, CaretOffset, A, B, Dialect) then
    begin
      // trailing blanks don't count
      while (B > A) and (T[B] in [' ', #9, #10, #13]) do
      begin
        Dec(B);
      end;
      NewFrom := LineOfOffset(T, A);
      NewTo := LineOfOffset(T, B);
      while NewFrom < NewTo do
      begin
        L := TrimLeft(FEditor.Lines[NewFrom - 1]);
        if (L = '') or (Copy(L, 1, 2) = '--') or (Copy(L, 1, 1) = '#') then
        begin
          Inc(NewFrom);
        end
        else
        begin
          Break;
        end;
      end;
    end;
  end;
  if (NewFrom = FShadeFrom) and (NewTo = FShadeTo) then
  begin
    Exit;
  end;
  OldFrom := FShadeFrom;
  OldTo := FShadeTo;
  FShadeFrom := NewFrom;
  FShadeTo := NewTo;
  if OldFrom > 0 then
  begin
    FEditor.InvalidateLines(OldFrom, OldTo);
  end;
  if NewFrom > 0 then
  begin
    FEditor.InvalidateLines(NewFrom, NewTo);
  end;
end;

procedure TpgnQueryTab.EditorLineMarkup(Sender: TObject; Line: Integer; var Special: Boolean;
  Markup: TSynSelectedColor);
begin
  if (FShadeFrom > 0) and (Line >= FShadeFrom) and (Line <= FShadeTo) then
  begin
    Special := True;
    Markup.Foreground := clNone;
    Markup.Background := clPgnShade;
  end;
end;

{ --------------------------------------------------------- DBA screens }

const
  { where the session id sits in each screen's grid (Locks: the blocker) }
  ScreenIdColumn: array[TpgnDbaScreen] of Integer = (0, 0, 3, 0, 0);
  ScreenTitles: array[TpgnDbaScreen] of string = ('', 'Sessions', 'Locks and Blocking', 'Users and Roles',
    'Who Can Do What');

procedure TpgnQueryTab.LayoutScreenBar(Sender: TObject);
var
  X, H, W: Integer;

  procedure Place(C: TControl; AWidth, AGap: Integer);
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
  H := FScreenBar.ClientHeight;
  X := Scale96ToScreen(10);
  Place(FScreenLabel, 0, 18);
  Place(FBtnScreenRefresh, 90, 6);
  Place(FAutoCombo, 150, 18);
  Place(FBtnShowStmt, 130, 6);
  if FScreen = dsLocks then
  begin
    Place(FBtnCancelSess, 180, 6);
  end
  else
  begin
    Place(FBtnCancelSess, 120, 6);
  end;
  Place(FBtnKillSess, 130, 16);
  Place(FScreenNote, 0, 0);
  FScreenBar.Invalidate;
end;

procedure TpgnQueryTab.OpenScreen(AScreen: TpgnDbaScreen);
begin
  FScreen := AScreen;
  FTitle := ScreenTitles[AScreen];
  if AScreen = dsWhoCan then
  begin
    FEditor.Visible := False;
    if FEditorHost <> nil then
    begin
      FEditorHost.Visible := False;
    end;
    if FQueryBarHost <> nil then
    begin
      FQueryBarHost.Visible := False;
    end;
    FEditorSplitter.Visible := False;
    FPages.Align := alNone;
    FPages.SetBounds(-10000, 0, 100, 100);
    FWhoCanPanel := TpgnWhoCanPanel.CreateFor(Self, FAdapter, FInfo, @Log, FEditor.Font.Name);
    FWhoCanPanel.Parent := Self;
    FWhoCanPanel.Align := alClient;
    FWhoCanPanel.OnOpenAccount := FOnOpenAccount;
    StateChanged;
    Exit;   // the caller sets the object, then Reload
  end;
  if AScreen = dsUsers then
  begin
    // a screen of its own in place of the editor and the results; the
    // results are moved out of sight (GTK3 shows hidden children again)
    FEditor.Visible := False;
    if FEditorHost <> nil then
    begin
      FEditorHost.Visible := False;
    end;
    if FQueryBarHost <> nil then
    begin
      FQueryBarHost.Visible := False;
    end;
    FEditorSplitter.Visible := False;
    FPages.Align := alNone;
    FPages.SetBounds(-10000, 0, 100, 100);
    FUsersPanel := TpgnUsersPanel.CreateFor(Self, FAdapter, FInfo, @Log, FEditor.Font.Name);
    FUsersPanel.Parent := Self;
    FUsersPanel.Align := alClient;
    FUsersPanel.Reload;
    StateChanged;
    Exit;
  end;
  FScreenLabel.Caption := ScreenTitles[AScreen];
  if AScreen = dsLocks then
  begin
    FBtnCancelSess.Caption := 'Cancel Blocker''s Query';
    FBtnKillSess.Caption := 'Kill Blocker...';
  end
  else
  begin
    FBtnCancelSess.Caption := 'Cancel Query';
    FBtnKillSess.Caption := 'Kill Session...';
  end;
  // the grid takes the editor's place
  FEditor.Visible := False;
  if FEditorHost <> nil then
  begin
    FEditorHost.Visible := False;
  end;
  if FQueryBarHost <> nil then
  begin
    FQueryBarHost.Visible := False;
  end;
  FEditorSplitter.Visible := False;
  if not FScreenBar.Visible then
  begin
    FScreenBar.Top := FBandLine.Top + FBandLine.Height;   // under the band
  end;
  FScreenBar.Visible := True;
  FPages.ActivePage := FTabResults;
  ScreenGrid.Options := ScreenGrid.Options + [goRowSelect];
  ScreenGrid.OnSelection := @ScreenSelect;
  FKillRight := FAdapter.MissingRight('kill');
  LayoutScreenBar(nil);
  RefreshScreen;
  StateChanged;
end;

function TpgnQueryTab.ScreenGrid: TpgnResultGrid;
begin
  Result := TpgnResultGrid(FResultGrids[0]);
end;

function TpgnQueryTab.ScreenRowValue(ACol: Integer): string;
var
  R: TpgnResultSet;
  N: Integer;
begin
  Result := '';
  R := ScreenGrid.Data;
  N := ScreenGrid.Row - 1;
  if (R = nil) or (N < 0) or (N >= R.RowCount) or (ACol >= R.ColumnCount) then
  begin
    Exit;
  end;
  Result := R.Rows[N].Values[ACol];
end;

function TpgnQueryTab.ScreenSessionId: string;
begin
  Result := ScreenRowValue(ScreenIdColumn[FScreen]);
end;

{ "asmith on HACC-WS-022, psql" for messages and the DBA log. }
function TpgnQueryTab.ScreenWhoShort: string;
begin
  if FScreen = dsLocks then
  begin
    Result := ScreenRowValue(4);
    if ScreenRowValue(5) <> '' then
    begin
      Result := Result + ', ' + ScreenRowValue(5);
    end;
  end
  else
  begin
    Result := ScreenRowValue(1);
    if ScreenRowValue(2) <> '' then
    begin
      Result := Result + ' on ' + ScreenRowValue(2);
    end;
    if ScreenRowValue(3) <> '' then
    begin
      Result := Result + ', ' + ScreenRowValue(3);
    end;
  end;
end;

procedure TpgnQueryTab.RefreshScreen;
var
  R: TpgnResultSet;
  Keep: string;
  I: Integer;
begin
  if (FScreen = dsNone) or (FAdapter = nil) or (FThread <> nil) or FScreenBusy then
  begin
    Exit;
  end;
  if FScreen = dsWhoCan then
  begin
    FWhoCanPanel.Reload;
    Exit;
  end;
  if FScreen = dsUsers then
  begin
    if FUsersPanel.CanLeave then
    begin
      FUsersPanel.Reload;
    end;
    Exit;
  end;
  Keep := ScreenSessionId;
  FScreenBusy := True;
  try
    try
      if FScreen = dsLocks then
      begin
        R := FAdapter.ListLocks;
      end
      else
      begin
        R := FAdapter.ListSessions;
      end;
      ScreenGrid.ShowData(R);
      FScreenTime := FormatDateTime('hh:nn:ss', Now);
      // the same session stays selected
      if (Keep <> '') and (R <> nil) then
      begin
        for I := 0 to R.RowCount - 1 do
        begin
          if R.Rows[I].Values[ScreenIdColumn[FScreen]] = Keep then
          begin
            ScreenGrid.Row := I + 1;
          end;
        end;
      end;
      FScreenNote.Font.Color := clPgnMuted;
    except
      on E: Exception do
      begin
        ScreenGrid.ShowData(nil);
        FScreenTime := '';
        Log('ERROR: could not read ' + LowerCase(ScreenTitles[FScreen]) + ': ' + E.Message);
        FScreenNote.Caption := 'Could not read ' + LowerCase(ScreenTitles[FScreen]) +
          ' (Messages says why; your login may lack the right).';
        FScreenNote.Font.Color := clPgnDanger;
        LayoutScreenBar(nil);
        Exit;
      end;
    end;
  finally
    FScreenBusy := False;
  end;
  UpdateScreenNote;
end;

procedure TpgnQueryTab.UpdateScreenNote;
var
  N: Integer;
  S, Id: string;
  Allowed: Boolean;
begin
  N := 0;
  if ScreenGrid.Data <> nil then
  begin
    N := ScreenGrid.Data.RowCount;
  end;
  if FScreen = dsLocks then
  begin
    if N = 0 then
    begin
      S := 'Nobody is waiting on a lock';
    end
    else if N = 1 then
    begin
      S := '1 session waiting';
    end
    else
    begin
      S := IntToStr(N) + ' sessions waiting';
    end;
  end
  else if N = 1 then
  begin
    S := '1 session';
  end
  else
  begin
    S := IntToStr(N) + ' sessions';
  end;
  if FScreenTime <> '' then
  begin
    S := S + ' ' + #$C2#$B7 + ' read at ' + FScreenTime;
  end;
  Id := ScreenSessionId;
  if Id <> '' then
  begin
    if FScreen = dsLocks then
    begin
      S := S + ' ' + #$C2#$B7 + ' blocker: session ' + Id + ' (' + ScreenWhoShort + ')';
      if ScreenRowValue(7) = 'yes' then
      begin
        S := S + ', head of the chain';
      end;
    end
    else
    begin
      S := S + ' ' + #$C2#$B7 + ' selected: session ' + Id + ' (' + ScreenWhoShort + ')';
    end;
  end;
  FScreenNote.Caption := S;
  FScreenNote.Hint := S;   // the whole line, when the window is too narrow for it
  FScreenNote.ShowHint := True;
  FBtnShowStmt.Enabled := Id <> '';
  // look, but don't touch: others' sessions need the right; one's own don't
  if FScreen = dsLocks then
  begin
    Allowed := (FKillRight = '') or SameText(ScreenRowValue(4), FInfo.User);
  end
  else
  begin
    Allowed := (FKillRight = '') or SameText(ScreenRowValue(1), FInfo.User);
  end;
  FBtnCancelSess.Enabled := (Id <> '') and Allowed;
  FBtnKillSess.Enabled := (Id <> '') and Allowed;
  if Allowed then
  begin
    FBtnCancelSess.Hint := '';
  end
  else
  begin
    FBtnCancelSess.Hint := FKillRight;
  end;
  FBtnKillSess.Hint := FBtnCancelSess.Hint;
  FBtnCancelSess.ShowHint := True;
  FBtnKillSess.ShowHint := True;
  LayoutScreenBar(nil);
end;

procedure TpgnQueryTab.ScreenSelect(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateScreenNote;
end;

procedure TpgnQueryTab.ScreenRefreshClick(Sender: TObject);
begin
  RefreshScreen;
end;

procedure TpgnQueryTab.ScreenAutoChange(Sender: TObject);
const
  Seconds: array[0..4] of Integer = (0, 5, 10, 30, 60);
begin
  FScreenTimer.Enabled := False;
  if (FAutoCombo.ItemIndex > 0) and (FAutoCombo.ItemIndex <= 4) then
  begin
    FScreenTimer.Interval := Seconds[FAutoCombo.ItemIndex] * 1000;
    FScreenTimer.Enabled := True;
  end;
end;

procedure TpgnQueryTab.ScreenTimerTick(Sender: TObject);
begin
  RefreshScreen;
end;

{ The full statement goes to Messages, where it can be read and copied. }
procedure TpgnQueryTab.ScreenShowStmtClick(Sender: TObject);
var
  Id, SQL: string;
begin
  Id := ScreenSessionId;
  if (Id = '') or (FAdapter = nil) then
  begin
    Exit;
  end;
  try
    SQL := FAdapter.SessionStatement(Id);
    if Trim(SQL) = '' then
    begin
      Log('Session ' + Id + ' (' + ScreenWhoShort + ') isn''t running anything.');
    end
    else
    begin
      Log('Statement of session ' + Id + ' (' + ScreenWhoShort + '):' + LineEnding + SQL);
    end;
  except
    on E: Exception do
    begin
      Log('ERROR: could not read the statement of session ' + Id + ': ' + E.Message);
    end;
  end;
end;

procedure TpgnQueryTab.ScreenCancelClick(Sender: TObject);
var
  Id, Who, SQL: string;
begin
  Id := ScreenSessionId;
  if (Id = '') or (FAdapter = nil) then
  begin
    Exit;
  end;
  Who := ScreenWhoShort;
  FScreenBusy := True;
  try
    if MessageDlg('Cancel what session ' + Id + ' is running on ' + ConnectionLongLabel(FInfo) + '?' +
      LineEnding + LineEnding + Who + LineEnding + LineEnding +
      'The statement stops; the session stays connected.', mtConfirmation, [mbYes, mbNo], 0,
      mbNo) <> mrYes then
    begin
      Exit;
    end;
    try
      SQL := FAdapter.CancelSession(Id);
      DbaLog(FInfo, 'Cancel query of session ' + Id + ' (' + Who + ')', SQL);
      Log('Canceled the query of session ' + Id + ' (' + Who + '): ' + SQL);
    except
      on E: Exception do
      begin
        Log('ERROR: could not cancel session ' + Id + ': ' + E.Message);
        MessageDlg('Could not cancel session ' + Id + LineEnding + LineEnding + E.Message,
          mtError, [mbOK], 0);
      end;
    end;
  finally
    FScreenBusy := False;
  end;
  RefreshScreen;
end;

procedure TpgnQueryTab.ScreenKillClick(Sender: TObject);
var
  Id, Who, SQL: string;
begin
  Id := ScreenSessionId;
  if (Id = '') or (FAdapter = nil) then
  begin
    Exit;
  end;
  if (FScreen = dsSessions) and (ScreenRowValue(8) = 'this tab') then
  begin
    MessageDlg('Session ' + Id + ' is this tab''s own connection.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Who := ScreenWhoShort;
  FScreenBusy := True;
  try
    if MessageDlg('Kill session ' + Id + ' on ' + ConnectionLongLabel(FInfo) + '?' + LineEnding +
      LineEnding + Who + LineEnding + LineEnding +
      'The user is disconnected, and anything the session hasn''t committed is rolled back.',
      mtWarning, [mbYes, mbNo], 0, mbNo) <> mrYes then
    begin
      Exit;
    end;
    try
      SQL := FAdapter.KillSession(Id);
      DbaLog(FInfo, 'Kill session ' + Id + ' (' + Who + ')', SQL);
      Log('Killed session ' + Id + ' (' + Who + '): ' + SQL);
    except
      on E: Exception do
      begin
        Log('ERROR: could not kill session ' + Id + ': ' + E.Message);
        MessageDlg('Could not kill session ' + Id + LineEnding + LineEnding + E.Message,
          mtError, [mbOK], 0);
      end;
    end;
  finally
    FScreenBusy := False;
  end;
  RefreshScreen;
end;

{ ------------------------------------------------------- routine mode }

{ "calc_hours(integer, text)" -> "calc_hours": tab titles stay short. }
function NameWithoutTypes(const AName: string): string;
var
  P: Integer;
begin
  P := Pos('(', AName);
  if P > 0 then
  begin
    Result := Copy(AName, 1, P - 1);
  end
  else
  begin
    Result := AName;
  end;
end;

procedure TpgnQueryTab.LayoutRoutineBar(Sender: TObject);
var
  X, H, W: Integer;

  procedure Place(C: TControl; AWidth, AGap: Integer);
  begin
    if not C.Visible then
    begin
      Exit;   // Execute... isn't there for triggers
    end;
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
  H := FRoutineBar.ClientHeight;
  X := Scale96ToScreen(10);
  Place(FRoutineLabel, 0, 18);
  Place(FBtnSave, 100, 6);
  Place(FBtnExecute, 100, 6);
  Place(FBtnRevert, 90, 16);
  Place(FRoutineNote, 0, 0);
end;

procedure TpgnQueryTab.UpdateRoutineBar;
var
  What: string;
begin
  if FRoutineMode and not FRoutineBar.Visible then
  begin
    FRoutineBar.Top := FBandLine.Top + FBandLine.Height;   // above the editor
  end;
  FRoutineBar.Visible := FRoutineMode;
  if not FRoutineMode then
  begin
    Exit;
  end;
  if FRoutineName = '' then
  begin
    What := 'New ' + LowerCase(RoutineCaption[FRoutineKind]) + ' in ' + FRoutineDb;
  end
  else
  begin
    What := RoutineCaption[FRoutineKind] + ' ' + FRoutineDb + '.' + FRoutineName;
  end;
  FRoutineLabel.Caption := What;
  FBtnSave.Enabled := (not FRoutineReadOnly) and (FAdapter <> nil) and (FThread = nil);
  FBtnExecute.Enabled := (FRoutineName <> '') and (FRoutineKind <> rkTrigger) and (FAdapter <> nil);
  FBtnExecute.Visible := FRoutineKind <> rkTrigger;
  FBtnRevert.Enabled := FRoutineName <> '';
  if FRoutineReadOnly then
  begin
    FRoutineNote.Caption := 'Read-only: your login can''t see this ' +
      LowerCase(RoutineCaption[FRoutineKind]) + '''s definition, so it can''t be changed here.';
    FRoutineNote.Font.Color := clPgnDanger;
  end
  else if FRoutineName = '' then
  begin
    FRoutineNote.Caption := 'Not in the database yet: ' + FBtnSave.Caption + ' creates it.';
    FRoutineNote.Font.Color := clPgnMuted;
  end
  else if (FRoutineKind = rkTrigger) and (Dialect = sdPostgreSQL) then
  begin
    FRoutineNote.Caption := FBtnSave.Caption +
      ' replaces it in one transaction; if the new version fails, the old one stays.';
    FRoutineNote.Font.Color := clPgnMuted;
  end
  else if Dialect = sdTSQL then
  begin
    FRoutineNote.Caption := FBtnSave.Caption +
      ' replaces it in one step (CREATE OR ALTER) and keeps its grants.';
    FRoutineNote.Font.Color := clPgnMuted;
  end
  else if Dialect = sdPostgreSQL then
  begin
    FRoutineNote.Caption := FBtnSave.Caption +
      ' replaces it in one step (CREATE OR REPLACE) and keeps its grants.';
    FRoutineNote.Font.Color := clPgnMuted;
  end
  else if FRoutineKind = rkTrigger then
  begin
    FRoutineNote.Caption := 'No DELIMITER needed. ' + FBtnSave.Caption +
      ' replaces it; if the new version fails, the old one is put back.';
    FRoutineNote.Font.Color := clPgnMuted;
  end
  else
  begin
    FRoutineNote.Caption := 'No DELIMITER needed. ' + FBtnSave.Caption +
      ' replaces it safely and keeps its grants.';
    FRoutineNote.Font.Color := clPgnMuted;
  end;
  LayoutRoutineBar(nil);
end;

procedure TpgnQueryTab.SetSaveCaption(const ACaption: string);
begin
  FBtnSave.Caption := ACaption;
  UpdateRoutineBar;
end;

procedure TpgnQueryTab.OpenRoutine(const ADatabase, AName: string; AKind: TpgnRoutineKind;
  const ASQL: string);
begin
  FRoutineMode := True;
  FRoutineDb := ADatabase;
  FRoutineName := AName;
  FRoutineKind := AKind;
  FRoutineReadOnly := (AName <> '') and (Trim(ASQL) = '');
  if AName <> '' then
  begin
    FTitle := RoutineCaption[AKind] + ' ' + NameWithoutTypes(AName);
  end
  else
  begin
    FTitle := 'New ' + LowerCase(RoutineCaption[AKind]);
  end;
  if FRoutineReadOnly then
  begin
    SetText('-- Your login can''t see the definition of ' + ADatabase + '.' + AName + '.' +
      LineEnding + '-- Someone with more rights on it (or the DBA) can open it.' + LineEnding);
    FEditor.ReadOnly := True;
  end
  else
  begin
    SetText(ASQL);
    FEditor.ReadOnly := False;
  end;
  UpdateRoutineBar;
  StateChanged;
end;

procedure TpgnQueryTab.NewRoutine(const ADatabase: string; AKind: TpgnRoutineKind; const ASQL: string);
begin
  OpenRoutine(ADatabase, '', AKind, ASQL);
  FEditor.Modified := True;   // not saved anywhere yet
  StateChanged;
end;

{ The one CREATE statement to save, and the editor line it starts on (so
  "at line N" in an error can be found). DELIMITER lines, a DROP before
  it, and a trailing delimiter are all left out. }
function TpgnQueryTab.RoutineStatementText(out ALineOffset: Integer): string;
var
  I, J: Integer;
  L: string;
  Stmts: TpgnStringArray;
  HasDelimiter: Boolean;
begin
  Result := '';
  ALineOffset := 0;
  HasDelimiter := False;
  for I := 0 to FEditor.Lines.Count - 1 do
  begin
    if Pos('DELIMITER ', UpperCase(TrimLeft(FEditor.Lines[I]))) = 1 then
    begin
      HasDelimiter := True;
      Break;
    end;
  end;

  // the first line that starts the CREATE
  for I := 0 to FEditor.Lines.Count - 1 do
  begin
    L := UpperCase(TrimLeft(FEditor.Lines[I]));
    if Pos('CREATE', L) = 1 then
    begin
      ALineOffset := I;
      Break;
    end;
  end;

  if HasDelimiter then
  begin
    Stmts := StatementList(FEditor.Text, Dialect);
    for J := 0 to High(Stmts) do
    begin
      if FirstKeyword(Stmts[J]) = 'CREATE' then
      begin
        Result := Stmts[J];
        Exit;
      end;
    end;
    Exit;
  end;

  // no DELIMITER: everything from the CREATE line on is the statement
  for I := ALineOffset to FEditor.Lines.Count - 1 do
  begin
    Result := Result + FEditor.Lines[I] + LineEnding;
  end;
  Result := TrimRight(Result);
  while (Result <> '') and (Result[Length(Result)] = ';') do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
  if (Length(Result) >= 2) and ((Copy(Result, Length(Result) - 1, 2) = '$$') or
    (Copy(Result, Length(Result) - 1, 2) = '//')) then
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 2));
  end;
end;

{ "... at line 3" in a server error: the line within the statement. }
function ErrorLine(const AMessage: string): Integer;
var
  P, Q, W: Integer;
begin
  Result := 0;
  P := Pos(', Line ', AMessage);       // SQL Server: "Msg 102, Level 15, State 1, Line 3"
  W := 7;
  if P = 0 then
  begin
    P := Pos('at line ', AMessage);    // MySQL
    W := 8;
  end;
  if P = 0 then
  begin
    P := Pos('LINE ', AMessage);       // PostgreSQL
    W := 5;
  end;
  if P = 0 then
  begin
    Exit;
  end;
  Q := P + W;
  while (Q <= Length(AMessage)) and (AMessage[Q] in ['0'..'9']) do
  begin
    Inc(Q);
  end;
  Result := StrToIntDef(Copy(AMessage, P + W, Q - P - W), 0);
end;

function TpgnQueryTab.SaveRoutine: Boolean;
var
  SQL, NewName, Kw: string;
  Offset, St, Len, I, Line: Integer;
  Steps: TStringList;
begin
  Result := False;
  if (not FRoutineMode) or FRoutineReadOnly or (FAdapter = nil) or (FThread <> nil) then
  begin
    Exit;
  end;
  SQL := RoutineStatementText(Offset);
  if Trim(SQL) = '' then
  begin
    Log('ERROR: there''s no CREATE ' + RoutineWord[FRoutineKind] + ' statement in the editor');
    Exit;
  end;
  Steps := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    try
      NewName := FAdapter.SaveRoutine(FRoutineDb, FRoutineName, FRoutineKind, SQL, Steps);
      for I := 0 to Steps.Count - 1 do
      begin
        Log(Steps[I]);
      end;
      if NewName <> '' then
      begin
        FRoutineName := NewName;
      end
      else if FindCreateName(SQL, St, Len, NewName, Kw) then
      begin
        FRoutineName := NewName;
      end;
      FTitle := RoutineCaption[FRoutineKind] + ' ' + NameWithoutTypes(FRoutineName);
      FEditor.Modified := False;
      FWasModified := False;
      FStatusText := 'Saved ' + LowerCase(RoutineCaption[FRoutineKind]) + ' ' + FRoutineName;
      Result := True;
    except
      on E: Exception do
      begin
        for I := 0 to Steps.Count - 1 do
        begin
          Log(Steps[I]);
        end;
        Log('ERROR: ' + E.Message);
        FStatusText := 'Not saved';
        Line := ErrorLine(E.Message);
        if Line > 0 then
        begin
          Line := Line + Offset;
          if Line <= FEditor.Lines.Count then
          begin
            FEditor.CaretXY := Point(1, Line);
            if Line > 3 then
            begin
              FEditor.TopLine := Line - 3;
            end
            else
            begin
              FEditor.TopLine := 1;
            end;
            FocusEditor;
          end;
        end;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
    Steps.Free;
  end;
  UpdateRoutineBar;
  StateChanged;
  if Result and Assigned(FOnSchemaChanged) then
  begin
    FOnSchemaChanged(Self, FInfo.Id, scObjects, 'CREATE ' + RoutineWord[FRoutineKind] + ' ' +
      FRoutineName);
  end;
end;

procedure TpgnQueryTab.RevertRoutine;
var
  SQL: string;
begin
  if (not FRoutineMode) or (FRoutineName = '') or (FAdapter = nil) or (FThread <> nil) then
  begin
    Exit;
  end;
  if IsModified and (MessageDlg('Throw away your changes and reload ' + FRoutineName +
    ' from the database?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  try
    SQL := FAdapter.GetRoutineSQL(FRoutineDb, FRoutineName, FRoutineKind);
    OpenRoutine(FRoutineDb, FRoutineName, FRoutineKind, SQL);
    Log('Reloaded ' + FRoutineName + ' from the database');
  except
    on E: Exception do
    begin
      Log('ERROR: could not reload ' + FRoutineName + ': ' + E.Message);
    end;
  end;
end;

procedure TpgnQueryTab.RoutineSaveClick(Sender: TObject);
begin
  SaveRoutine;
end;

procedure TpgnQueryTab.RoutineExecuteClick(Sender: TObject);
begin
  if Assigned(FOnRoutineExecute) then
  begin
    FOnRoutineExecute(Self);
  end;
end;

procedure TpgnQueryTab.RoutineRevertClick(Sender: TObject);
begin
  RevertRoutine;
end;

{ ------------------------------------------------------------ running }

function TpgnQueryTab.ConfirmStatements(const AStatements: TpgnStringArray): Boolean;
var
  I, Found: Integer;
  K, Listing, Line: string;
begin
  Result := True;
  if not FSettings.ConfirmDestructive then
  begin
    Exit;
  end;

  Found := 0;
  Listing := '';
  for I := 0 to High(AStatements) do
  begin
    K := FirstKeyword(AStatements[I]);
    if (K = 'DELETE') or (K = 'TRUNCATE') or (K = 'DROP') then
    begin
      Inc(Found);
      if Found <= 5 then
      begin
        Line := StringReplace(AStatements[I], LineEnding, ' ', [rfReplaceAll]);
        if Length(Line) > 90 then
        begin
          Line := Copy(Line, 1, 87) + '...';
        end;
        Listing := Listing + '  ' + Line + LineEnding;
      end;
    end;
  end;

  if Found = 0 then
  begin
    Exit;
  end;
  if Found > 5 then
  begin
    Listing := Listing + Format('  ...and %d more', [Found - 5]) + LineEnding;
  end;

  Result := MessageDlg('This will run ' + IntToStr(Found) + ' statement(s) that remove data' +
    LineEnding + 'on ' + ConnectionLongLabel(FInfo) + ':' + LineEnding + LineEnding +
    Listing + LineEnding + 'Run it?' + LineEnding + LineEnding +
    '(You can turn this question off in Tools > Options.)',
    mtWarning, [mbYes, mbNo], 0) = mrYes;
end;

{ The first words of a statement, on one line, for a message. }
function StatementLabel(const ASQL: string): string;
begin
  Result := Trim(StringReplace(StringReplace(ASQL, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
  if Length(Result) > 60 then
  begin
    Result := Copy(Result, 1, 57) + '...';
  end;
end;

{ Oracle and MySQL commit the open transaction when they run DDL. With
  auto-commit off and changes waiting (in the tab, or made earlier in the
  same script), ask first: commit them, roll them back, or don't run.
  False = don't run. }
function TpgnQueryTab.ConfirmDdlCommit(const AStatements: TpgnStringArray): Boolean;
var
  I, Waiting, At, Shown: Integer;
  DdlText, Msg, Head: string;
  Answer: TModalResult;
begin
  Result := True;
  if (FAdapter = nil) or FAdapter.AutoCommit or not FSettings.WarnDdlCommit or
    not (Dialect in [sdOracle, sdMySQL]) then
  begin
    Exit;
  end;
  // walk the statements as they will run: does DDL meet waiting changes?
  Waiting := FPending;
  At := -1;
  for I := 0 to High(AStatements) do
  begin
    if StatementIsDDL(AStatements[I]) then
    begin
      if Waiting > 0 then
      begin
        At := I;
        Break;
      end;
    end
    else if StatementChangesData(AStatements[I]) then
    begin
      Inc(Waiting);
    end
    else if StatementEndsTransaction(AStatements[I], False) then
    begin
      Waiting := 0;
    end;
  end;
  if At < 0 then
  begin
    Exit;
  end;
  DdlText := StatementLabel(AStatements[At]);
  if FPending > 0 then
  begin
    if FPending = 1 then
    begin
      Head := 'the 1 pending change';
    end
    else
    begin
      Head := 'the ' + IntToStr(FPending) + ' pending changes';
    end;
    Msg := 'Running' + LineEnding + '  ' + DdlText + LineEnding + 'will also commit ' + Head +
      ' in this tab:' + LineEnding;
    Shown := 0;
    for I := 0 to FPending - 1 do
    begin
      if Shown = 3 then
      begin
        Msg := Msg + '  ...and ' + IntToStr(FPending - 3) + ' more' + LineEnding;
        Break;
      end;
      Msg := Msg + '  ' + StatementLabel(FPendingList[I].SQL) + LineEnding;
      Inc(Shown);
    end;
    if Waiting > FPending then
    begin
      Msg := Msg + '(and the changes this script makes before it)' + LineEnding;
    end;
    Msg := Msg + LineEnding + ConnectionLongLabel(FInfo) + ' commits them as soon as the DDL runs; ' +
      'they can''t be rolled back after that.';
    repeat
      if Assigned(FOnReviewPending) then
      begin
        Answer := QuestionDlg('DDL will commit pending changes', Msg, mtWarning,
          [mrYes, 'Commit and Run', mrNo, 'Rollback, then Run', mrRetry, 'Review...', mrCancel, 'Cancel'], 0);
      end
      else
      begin
        Answer := QuestionDlg('DDL will commit pending changes', Msg, mtWarning,
          [mrYes, 'Commit and Run', mrNo, 'Rollback, then Run', mrCancel, 'Cancel'], 0);
      end;
      if Answer = mrRetry then
      begin
        // the Transactions panel; nothing runs until they choose again
        FOnReviewPending(Self);
        Result := False;
        Exit;
      end;
    until Answer <> mrRetry;
    if Answer = mrYes then
    begin
      Commit;
      Result := FPending = 0;
    end
    else if Answer = mrNo then
    begin
      Rollback;
      Result := FPending = 0;
    end
    else
    begin
      Result := False;
    end;
    Exit;
  end;
  // nothing waiting yet: the script itself changes data before its DDL
  Msg := 'This script changes data and then runs' + LineEnding + '  ' + DdlText + LineEnding +
    '(statement ' + IntToStr(At + 1) + ').' + LineEnding + LineEnding + ConnectionLongLabel(FInfo) +
    ' commits the changes before it at that point, even though auto-commit is off; ' +
    'they can''t be rolled back after that.';
  Answer := QuestionDlg('DDL will commit changes', Msg, mtWarning,
    [mrYes, 'Run Anyway', mrCancel, 'Cancel'], 0);
  Result := Answer = mrYes;
end;

procedure TpgnQueryTab.AddToHistory(const ASQL: string);
var
  S: string;
begin
  S := Trim(ASQL);
  if S = '' then
  begin
    Exit;
  end;
  if (FHistory.Count > 0) and (FHistory[FHistory.Count - 1] = S) then
  begin
    Exit;
  end;
  FHistory.Add(S);
  while FHistory.Count > MaxHistory do
  begin
    FHistory.Delete(0);
  end;
end;

procedure TpgnQueryTab.StartQuery(const AStatements: TpgnStringArray);
var
  I: Integer;
  D: TSaveDialog;
begin
  if Length(AStatements) = 0 then
  begin
    Exit;
  end;
  if FAdapter = nil then
  begin
    MessageDlg('This tab is not connected. Choose a connection at the top of the tab.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if FThread <> nil then
  begin
    Exit;
  end;
  if not ConfirmStatements(AStatements) then
  begin
    Log('Not run');
    Exit;
  end;
  if not ConfirmDdlCommit(AStatements) then
  begin
    Log('Not run');
    Exit;
  end;
  FResultsFile := '';
  if FSea and (FResultsMode = 2) and not FExplainRun then
  begin
    // as SSMS: the file is asked for before the query runs
    D := TSaveDialog.Create(GetParentForm(Self));
    try
      D.Title := 'Save Results';
      D.Filter := 'Report files (*.rpt)|*.rpt|Text files (*.txt)|*.txt|All files|*';
      D.DefaultExt := 'rpt';
      D.Options := D.Options + [ofOverwritePrompt];
      D.InitialDir := LastExportDir;
      if not D.Execute then
      begin
        Log('Not run');
        Exit;
      end;
      FResultsFile := D.FileName;
      LastExportDir := ExtractFileDir(D.FileName);
    finally
      D.Free;
    end;
  end;
  for I := 0 to High(AStatements) do
  begin
    AddToHistory(AStatements[I]);
  end;
  FThread := TpgnQueryThread.Create(FAdapter, AStatements, FSettings.RowLimit, @QueryDone);
  if not FAdapter.AutoCommit then
  begin
    // a savepoint before each change, so one can be undone on its own
    FThread.SavepointBase := 'pgn_sp_';
    FThread.SavepointStart := FSavepointSeq;
    FThread.TransactionalDDL := Dialect in [sdPostgreSQL, sdTSQL];
    // MySQL's REPEATABLE READ keeps showing the first read's data until the
    // transaction ends; with nothing pending, end it so each run is fresh
    FThread.FreshSnapshot := (Dialect = sdMySQL) and (FPending = 0) and FReadsOnly;
    Inc(FSavepointSeq, Length(AStatements));
  end;
  FStatusText := 'Running...';
  FRunState := 4;
  FRunStart := Now;
  if FQueryBar <> nil then
  begin
    FQueryBar.Invalidate;
  end;
  FProgressTimer.Enabled := (Length(AStatements) > 1) or FSea;
  StateChanged;
  FThread.Start;
end;

procedure TpgnQueryTab.RunSQL(const ASQL: string);
var
  L: TpgnStringArray;
begin
  SetLength(L, 1);
  L[0] := ASQL;
  StartQuery(L);
end;

function TpgnQueryTab.CaretOffset: Integer;
var
  P: TPoint;
  I: Integer;
begin
  P := FEditor.LogicalCaretXY;
  Result := 0;
  for I := 0 to P.Y - 2 do
  begin
    Result := Result + Length(FEditor.Lines[I]) + Length(LineEnding);
  end;
  Result := Result + P.X;
end;

function TpgnQueryTab.CurrentStatement: string;
begin
  if FEditor.SelAvail then
  begin
    Result := TrimStatement(FEditor.SelText);
    if not HasCode(Result, Dialect) then
    begin
      Result := '';
    end;
  end
  else
  begin
    Result := StatementAt(FEditor.Text, CaretOffset, Dialect);
  end;
end;

procedure TpgnQueryTab.RunStatement;
var
  S: string;
begin
  if FRoutineMode then
  begin
    SaveRoutine;   // in a routine tab, Run (F5 / F9 / Ctrl+Enter) saves it
    Exit;
  end;
  S := CurrentStatement;
  if S <> '' then
  begin
    RunSQL(S);
  end
  else if (not FEditor.SelAvail) and CaretOnCommentLine(FEditor.Text, CaretOffset, Dialect) then
  begin
    Log('Nothing to run: the line under the cursor is a comment');
  end;
end;

procedure TpgnQueryTab.RunScript;
var
  T: string;
begin
  if FRoutineMode then
  begin
    SaveRoutine;
    Exit;
  end;
  if FEditor.SelAvail then
  begin
    T := FEditor.SelText;
  end
  else
  begin
    T := FEditor.Text;
  end;
  StartQuery(StatementList(T, Dialect));
end;

procedure TpgnQueryTab.Explain;
var
  S: string;
begin
  S := CurrentStatement;
  if S <> '' then
  begin
    FExplainRun := True;
    RunSQL('EXPLAIN ' + S);
    if FThread = nil then
    begin
      FExplainRun := False;   // it didn't start
    end;
  end;
end;

procedure TpgnQueryTab.Cancel;
begin
  if (FThread = nil) or (FAdapter = nil) then
  begin
    Exit;
  end;
  FThread.Terminate;   // stops a script between statements
  try
    FAdapter.CancelCurrent;   // stops the statement running now
    Log('Cancel requested');
  except
    on E: Exception do
    begin
      Log('Cancel failed: ' + E.Message);
    end;
  end;
end;

function ElapsedText(AMs: QWord): string;
begin
  if AMs < 1000 then
  begin
    Result := IntToStr(AMs) + ' ms';
  end
  else
  begin
    Result := FormatFloat('0.0', AMs / 1000) + ' s';
  end;
end;

function CountText(AValue: Integer): string;
begin
  Result := FormatFloat('#,##0', AValue);
end;

procedure TpgnQueryTab.QueryDone(Sender: TObject);
var
  T: TpgnQueryThread;
  Results: TFPList;
  First: TpgnResultSet;
  I, Total: Integer;
  RowInfo, SQL, Msg: string;
  SchemaChange, C: TpgnSchemaChange;
  IsScript, Quiet, WasExplain: Boolean;
begin
  T := Sender as TpgnQueryThread;
  FThread := nil;   // the thread frees itself after this returns
  FProgressTimer.Enabled := False;
  WasExplain := FExplainRun;
  FExplainRun := False;

  // a USE in the editor changes the session's database
  if (FAdapter <> nil) and (FAdapter.CurrentDatabase <> FCurrentDb) then
  begin
    FCurrentDb := FAdapter.CurrentDatabase;
    SyncDbCombo;
    LoadObjectNames;
  end;

  // long scripts: only problems and the summary, unless asked for more
  Total := Length(T.Statements);
  IsScript := Total > 1;
  Quiet := (Total > QuietScriptSize) and not FSettings.LogEveryStatement;
  for I := 0 to T.Messages.Count - 1 do
  begin
    if Quiet and (Pos('Statement ', T.Messages[I]) = 1) then
    begin
      Continue;
    end;
    Log(T.Messages[I]);
  end;

  Results := T.TakeResults;
  try
    RowInfo := '';
    First := nil;
    FRunRows := 0;
    for I := 0 to Results.Count - 1 do
    begin
      FRunRows := FRunRows + TpgnResultSet(Results[I]).RowCount;
    end;
    if Results.Count > 0 then
    begin
      First := TpgnResultSet(Results[0]);
      if First.HasMoreRows then
      begin
        RowInfo := 'First ' + CountText(First.RowCount) + ' rows (more available)';
      end
      else
      begin
        RowInfo := CountText(First.RowCount) + ' rows';
      end;
      if Results.Count > 1 then
      begin
        RowInfo := RowInfo + ', ' + IntToStr(Results.Count) + ' result sets';
      end;
    end;
    if WasExplain and (First <> nil) then
    begin
      // the plan goes to its own tab, leaving the results alone
      Results.Delete(0);
      PrepGrids;
      FPlanGrid.ShowData(First);
      FPages.ActivePage := FTabPlan;
      PagesChange(nil);
      for I := 0 to Results.Count - 1 do
      begin
        TpgnResultSet(Results[I]).Free;
      end;
      Results.Clear;
    end
    else if Results.Count > 0 then
    begin
      ShowResults(Results);    // the grids take the result sets
      Results.Clear;
    end;
  finally
    for I := 0 to Results.Count - 1 do
    begin
      TpgnResultSet(Results[I]).Free;
    end;
    Results.Free;
  end;
  if T.DroppedResults > 0 then
  begin
    Log(Format('WARNING: %d more result set(s) not shown (Pagona shows up to %d)',
      [T.DroppedResults, MaxResultSets]));
  end;

  FRunMs := T.ElapsedMs;
  if T.ErrorText <> '' then
  begin
    FRunState := 2;
  end
  else if T.Stopped then
  begin
    FRunState := 3;
  end
  else
  begin
    FRunState := 1;
  end;
  if FQueryBar <> nil then
  begin
    FQueryBar.Invalidate;
  end;
  if FSea and ((T.ErrorText <> '') or ((RowInfo = '') and not WasExplain)) then
  begin
    // as SSMS: an error, or nothing to show in Results, so Messages
    FPages.ActivePage := FTabMessages;
    PagesChange(nil);
  end;
  if FAmph and ((T.ErrorText <> '') or ((RowInfo = '') and not WasExplain)) then
  begin
    // nothing to show in the grid: Toad shows the messages
    if (T.ErrorText <> '') or (FPages.ActivePage <> FTabDbms) then
    begin
      FPages.ActivePage := FTabMessages;
      PagesChange(nil);
    end;
  end;
  if T.ErrorText <> '' then
  begin
    Log('ERROR: ' + T.ErrorText);
    FStatusText := 'Error after ' + ElapsedText(T.ElapsedMs);
  end
  else
  begin
    FStatusText := Trim(RowInfo + '   ' + ElapsedText(T.ElapsedMs));
  end;

  // a script ends with one line that says how it went
  if IsScript then
  begin
    if T.ErrorText <> '' then
    begin
      Msg := 'ERROR: Script stopped at statement ' + CountText(T.ErrorIndex) + ' of ' +
        CountText(Total) + ' (' + CountText(T.ExecutedCount) + ' ran, ' +
        ElapsedText(T.ElapsedMs) + ')';
    end
    else if T.Stopped then
    begin
      Msg := 'Canceled: ' + CountText(T.ExecutedCount) + ' of ' + CountText(Total) +
        ' statements ran (' + ElapsedText(T.ElapsedMs) + ')';
    end
    else
    begin
      Msg := 'Script finished: ' + CountText(Total) + ' statements in ' +
        ElapsedText(T.ElapsedMs) + ', no errors';
    end;
    Log(Msg);
    FStatusText := Msg;
  end;

  if FPages.ActivePage = FTabHistory then
  begin
    FillHistory;
  end;

  // statements that changed the schema: let the window refresh the tree
  SchemaChange := scNone;
  // a statement that failed part way may still hold locks
  if (T.ErrorIndex > 0) and (T.ErrorIndex <= Length(T.Statements)) and
    not StatementOnlyReads(T.Statements[T.ErrorIndex - 1]) then
  begin
    FReadsOnly := False;
  end;
  SQL := '';
  for I := 0 to T.ExecutedCount - 1 do
  begin
    RecordPending(T.Statements[I], T.Affected(I), T.SavepointOf(I));
    C := SchemaChangeOf(T.Statements[I]);
    if C <> scNone then
    begin
      SQL := SQL + T.Statements[I] + LineEnding;
      if (C = scDatabases) or (SchemaChange = scNone) then
      begin
        SchemaChange := C;
      end;
    end;
  end;
  if SchemaChange = scDatabases then
  begin
    ReloadDatabaseList;
  end;
  if SchemaChange <> scNone then
  begin
    LoadObjectNames;
  end;

  StateChanged;

  if (SchemaChange <> scNone) and Assigned(FOnSchemaChanged) then
  begin
    FOnSchemaChanged(Self, FInfo.Id, SchemaChange, SQL);
  end;
end;

{ ------------------------------------------------------- result tabs }

procedure TpgnQueryTab.SetResultsMode(AValue: Integer);
begin
  FResultsMode := AValue;
  if (AValue = 0) and FTextShown then
  begin
    // back to grids: the text goes until the next run fills the grids
    FTextShown := False;
    FResultsText.Text := '';
    StackGrids;
  end;
  if AValue = 1 then
  begin
    Log('Results to Text: the next run shows its results as text');
  end
  else if AValue = 2 then
  begin
    Log('Results to File: the next run asks for a file and saves its results there');
  end;
end;

{ Every grid: how to quote for Copy As, and Save Results As (Export
  Dataset in Amphibian, as Toad names it). }
procedure TpgnQueryTab.PrepGrids;

  procedure Prep(G: TpgnResultGrid);
  begin
    if G = nil then
    begin
      Exit;
    end;
    G.Dialect := Dialect;
    if FAmph then
    begin
      G.SaveCaption := 'Export &Dataset...';
    end
    else
    begin
      G.SaveCaption := 'Save Results &As...';
    end;
    G.OnSaveResults := @GridSaveResults;
  end;

var
  I: Integer;
begin
  for I := 0 to FResultGrids.Count - 1 do
  begin
    Prep(TpgnResultGrid(FResultGrids[I]));
  end;
  if FSeaGrids <> nil then
  begin
    for I := 0 to FSeaGrids.Count - 1 do
    begin
      Prep(TpgnResultGrid(FSeaGrids[I]));
    end;
  end;
  Prep(FPlanGrid);
  Prep(FDbmsGrid);
end;

procedure TpgnQueryTab.GridSaveResults(Sender: TObject);
var
  G: TpgnResultGrid;
  D: TpgnResultSet;
  Note, DlgTitle, Txt: string;
  Opt: TpgnExportOptions;
  L: TpgnStringArray;
begin
  G := Sender as TpgnResultGrid;
  D := G.Data;
  if (D = nil) or (D.ColumnCount = 0) then
  begin
    Exit;
  end;
  // why "All rows" can't be offered, if it can't
  Note := '';
  if FThread <> nil then
  begin
    Note := 'This tab is running a query; all rows can be saved once it finishes.';
  end
  else if FAdapter = nil then
  begin
    Note := 'This tab is no longer connected, so the query can''t run again.';
  end
  else if Trim(D.SourceSQL) = '' then
  begin
    Note := 'Pagona doesn''t know the query these rows came from.';
  end
  else if SqlMayChangeData(D.SourceSQL) then
  begin
    Note := 'The query changes data or runs a procedure, so Pagona won''t run it again. ' +
      'Raise the row limit in Tools > Options and run it yourself for more rows.';
  end;
  if FAmph then
  begin
    DlgTitle := 'Export Dataset';
  end
  else
  begin
    DlgTitle := 'Save Results As';
  end;
  Opt := FExportOpt;
  if Opt.FileName = '' then
  begin
    if LastExportDir = '' then
    begin
      LastExportDir := GetUserDir;
    end;
    Opt.FileName := IncludeTrailingPathDelimiter(LastExportDir) + 'results.' + ExportFormatExt[Opt.Format];
  end;
  if not AskExport(Self, DlgTitle, D.RowCount, D.HasMoreRows, Note, GuessTableName(D.SourceSQL),
    LastExportDir, Opt) then
  begin
    Exit;
  end;
  FExportOpt := Opt;
  LastExportDir := ExtractFileDir(Opt.FileName);
  if Opt.AllRows and D.HasMoreRows and (Note = '') then
  begin
    // the same query again, with no row limit; the file is written when it's done
    FExportIndex := D.SourceIndex;
    FExportTitle := DlgTitle;
    SetLength(L, 1);
    L[0] := D.SourceSQL;
    FThread := TpgnQueryThread.Create(FAdapter, L, 0, @ExportDone);
    FStatusText := 'Saving all rows...';
    FRunState := 4;
    FRunStart := Now;
    if FQueryBar <> nil then
    begin
      FQueryBar.Invalidate;
    end;
    FProgressTimer.Enabled := FSea;
    Log('Running the query again with no row limit, to save every row to ' + Opt.FileName);
    StateChanged;
    FThread.Start;
    Exit;
  end;
  try
    Txt := CellsAs(D, WholeRange(D), Opt, Dialect);
    WriteTextFile(Opt.FileName, Txt, Opt.Bom);
    Log(Format('Saved %s rows to %s', [FormatFloat('#,##0', D.RowCount), Opt.FileName]));
  except
    on E: Exception do
    begin
      Log('ERROR: could not save ' + Opt.FileName + ': ' + E.Message);
      MessageDlg(DlgTitle, 'Could not save ' + Opt.FileName + ':' + LineEnding + E.Message,
        mtError, [mbOK], 0);
    end;
  end;
end;

{ The re-run for Save Results As finished: write the file. }
procedure TpgnQueryTab.ExportDone(Sender: TObject);
var
  T: TpgnQueryThread;
  Results: TFPList;
  D: TpgnResultSet;
  I: Integer;
begin
  T := Sender as TpgnQueryThread;
  FThread := nil;
  FProgressTimer.Enabled := False;
  FRunMs := T.ElapsedMs;
  Results := T.TakeResults;
  try
    if T.ErrorText <> '' then
    begin
      FRunState := 2;
      Log('ERROR: ' + T.ErrorText);
      FStatusText := 'Nothing saved: the query failed';
      MessageDlg(FExportTitle, 'Nothing was saved: the query failed.' + LineEnding + LineEnding +
        T.ErrorText, mtError, [mbOK], 0);
    end
    else if T.Stopped or (Results.Count = 0) then
    begin
      FRunState := 3;
      Log('Nothing saved: the query was canceled or returned no rows');
      FStatusText := 'Nothing saved';
    end
    else
    begin
      if FExportIndex < Results.Count then
      begin
        D := TpgnResultSet(Results[FExportIndex]);
      end
      else
      begin
        D := TpgnResultSet(Results[0]);
      end;
      try
        WriteTextFile(FExportOpt.FileName, CellsAs(D, WholeRange(D), FExportOpt, Dialect), FExportOpt.Bom);
        FRunState := 1;
        FStatusText := Format('Saved %s rows', [FormatFloat('#,##0', D.RowCount)]);
        Log(Format('Saved %s rows to %s', [FormatFloat('#,##0', D.RowCount), FExportOpt.FileName]));
      except
        on E: Exception do
        begin
          FRunState := 2;
          Log('ERROR: could not save ' + FExportOpt.FileName + ': ' + E.Message);
          FStatusText := 'Nothing saved';
        end;
      end;
    end;
  finally
    for I := 0 to Results.Count - 1 do
    begin
      TpgnResultSet(Results[I]).Free;
    end;
    Results.Free;
  end;
  if FQueryBar <> nil then
  begin
    FQueryBar.Invalidate;
  end;
  StateChanged;
end;

function TpgnQueryTab.AddResultGrid: TpgnResultGrid;
begin
  Result := TpgnResultGrid.Create(Self);
  Result.Parent := FTabResults;
  Result.Align := alClient;
  FResultGrids.Add(Result);
end;

{ One grid per result set. With several, a row of tabs inside Results
  ("Result 1", "Result 2", ...) switches between them. The grids take
  ownership of the result sets. }
procedure TpgnQueryTab.ShowResults(AList: TFPList);
var
  I: Integer;
  G: TpgnResultGrid;
  R, Dbms: TpgnResultSet;
  Txt: string;
begin
  // Amphibian: what DBMS_OUTPUT printed goes to its own tab
  Dbms := nil;
  if FAmph then
  begin
    for I := AList.Count - 1 downto 0 do
    begin
      R := TpgnResultSet(AList[I]);
      if (Length(R.Columns) = 1) and (R.Columns[0] = 'DBMS Output') then
      begin
        AList.Delete(I);
        if Dbms = nil then
        begin
          Dbms := R;
        end
        else
        begin
          R.Free;
        end;
      end;
    end;
    if Dbms <> nil then
    begin
      FDbmsGrid.ShowData(Dbms);
    end
    else
    begin
      FDbmsGrid.ShowData(nil);
    end;
    if AList.Count = 0 then
    begin
      if Dbms <> nil then
      begin
        FPages.ActivePage := FTabDbms;
        PagesChange(nil);
      end;
      Exit;
    end;
  end;
  PrepGrids;
  if FSea and (FResultsMode <> 0) then
  begin
    // Results to Text / to File: SSMS's fixed-width text
    Txt := ResultsAsText(AList);
    for I := 0 to AList.Count - 1 do
    begin
      TpgnResultSet(AList[I]).Free;
    end;
    AList.Clear;
    for I := 0 to FSeaShown - 1 do
    begin
      TpgnResultGrid(FSeaGrids[I]).ShowData(nil);
    end;
    FSeaShown := 0;
    if (FResultsMode = 2) and (FResultsFile <> '') then
    begin
      try
        WriteTextFile(FResultsFile, Txt, True);
        Log('Results saved to ' + FResultsFile);
        FResultsText.Text := 'Results saved to ' + FResultsFile;
      except
        on E: Exception do
        begin
          Log('ERROR: could not save the results to ' + FResultsFile + ': ' + E.Message);
          FResultsText.Text := Txt;   // shown instead, so nothing is lost
        end;
      end;
    end
    else
    begin
      FResultsText.Text := Txt;
    end;
    FTextShown := True;
    FPages.ActivePage := FTabResults;
    PagesChange(nil);
    StackGrids;
    Application.QueueAsyncCall(@AsyncStack, 0);
    Exit;
  end;
  if FSea then
  begin
    // as SSMS: every result set, one under another, in Results
    FTextShown := False;
    for I := 0 to FSeaGrids.Count - 1 do
    begin
      if I < AList.Count then
      begin
        TpgnResultGrid(FSeaGrids[I]).ShowData(TpgnResultSet(AList[I]));
      end
      else if I < FSeaShown then
      begin
        TpgnResultGrid(FSeaGrids[I]).ShowData(nil);
      end;
    end;
    FSeaShown := Min(AList.Count, FSeaGrids.Count);
    for I := FSeaGrids.Count to AList.Count - 1 do
    begin
      TpgnResultSet(AList[I]).Free;   // past the most Pagona shows
    end;
    FPages.ActivePage := FTabResults;
    PagesChange(nil);
    StackGrids;
    Application.QueueAsyncCall(@AsyncStack, 0);
    Exit;
  end;
  while FResultGrids.Count > 1 do
  begin
    G := TpgnResultGrid(FResultGrids[FResultGrids.Count - 1]);
    FResultGrids.Delete(FResultGrids.Count - 1);
    G.Free;
  end;
  while FResultGrids.Count < AList.Count do
  begin
    AddResultGrid;
  end;
  for I := 0 to AList.Count - 1 do
  begin
    TpgnResultGrid(FResultGrids[I]).ShowData(TpgnResultSet(AList[I]));
  end;

  FResultSwitch.Tabs.BeginUpdate;
  try
    FResultSwitch.Tabs.Clear;
    if AList.Count > 1 then
    begin
      for I := 0 to AList.Count - 1 do
      begin
        FResultSwitch.Tabs.Add('Result ' + IntToStr(I + 1));
      end;
    end;
  finally
    FResultSwitch.Tabs.EndUpdate;
  end;
  FResultSwitch.Visible := AList.Count > 1;
  if AList.Count > 1 then
  begin
    FResultSwitch.TabIndex := 0;
  end;
  ResultSwitchChange(nil);
  FPages.ActivePage := FTabResults;
  PagesChange(nil);
end;

procedure TpgnQueryTab.ResultSwitchChange(Sender: TObject);
var
  I, Shown: Integer;
begin
  if FSea then
  begin
    StackGrids;
    Exit;
  end;
  for I := 0 to FResultGrids.Count - 1 do
  begin
    TpgnResultGrid(FResultGrids[I]).Align := alClient;
    TpgnResultGrid(FResultGrids[I]).BorderSpacing.Bottom := 0;
  end;
  Shown := 0;
  if FResultSwitch.Visible and (FResultSwitch.TabIndex >= 0) then
  begin
    Shown := FResultSwitch.TabIndex;
  end;
  for I := 0 to FResultGrids.Count - 1 do
  begin
    TpgnResultGrid(FResultGrids[I]).Visible := I = Shown;
  end;
end;

procedure TpgnQueryTab.PagesChange(Sender: TObject);
begin
  if FPagesTitle <> nil then
  begin
    FPagesTitle.Caption := FPages.ActivePage.Caption;
  end;
  if FPages.ActivePage = FTabHistory then
  begin
    FillHistory;
  end;
end;

procedure TpgnQueryTab.FillHistory;
var
  I: Integer;
  Item: TListItem;
  S: string;
begin
  FHistoryList.Items.BeginUpdate;
  try
    FHistoryList.Items.Clear;
    for I := FHistory.Count - 1 downto 0 do
    begin
      S := StringReplace(StringReplace(FHistory[I], #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
      if Length(S) > 300 then
      begin
        S := Copy(S, 1, 297) + '...';
      end;
      Item := FHistoryList.Items.Add;
      Item.Caption := IntToStr(I + 1);
      Item.SubItems.Add(S);
      Item.Data := Pointer(PtrUInt(I));
    end;
  finally
    FHistoryList.Items.EndUpdate;
  end;
end;

procedure TpgnQueryTab.HistoryDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FHistoryList.Selected = nil then
  begin
    Exit;
  end;
  Idx := Integer(PtrUInt(FHistoryList.Selected.Data));
  if (Idx >= 0) and (Idx < FHistory.Count) then
  begin
    InsertText(FHistory[Idx], True);
  end;
end;

{ While a script runs: which statement it is on. }
procedure TpgnQueryTab.ProgressTick(Sender: TObject);
begin
  if FThread = nil then
  begin
    FProgressTimer.Enabled := False;
    Exit;
  end;
  if FQueryBar <> nil then
  begin
    FQueryBar.Invalidate;
  end;
  if Length(FThread.Statements) < 2 then
  begin
    Exit;
  end;
  FStatusText := 'Running statement ' + CountText(FThread.Current) + ' of ' +
    CountText(Length(FThread.Statements)) + '...';
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

function TpgnQueryTab.IdentifierAtCaret: string;
const
  IdentChars = ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '.', '`', #128..#255];
var
  Line: string;
  X, StartX, EndX: Integer;
begin
  Result := '';
  Line := FEditor.LineText;
  X := FEditor.LogicalCaretXY.X;
  if Line = '' then
  begin
    Exit;
  end;
  if X > Length(Line) then
  begin
    X := Length(Line);
  end;
  if (X > 1) and not (Line[X] in IdentChars) then
  begin
    Dec(X);
  end;
  if not (Line[X] in IdentChars) then
  begin
    Exit;
  end;
  StartX := X;
  while (StartX > 1) and (Line[StartX - 1] in IdentChars) do
  begin
    Dec(StartX);
  end;
  EndX := X;
  while (EndX < Length(Line)) and (Line[EndX + 1] in IdentChars) do
  begin
    Inc(EndX);
  end;
  Result := StringReplace(Copy(Line, StartX, EndX - StartX + 1), '`', '', [rfReplaceAll]);
end;

procedure TpgnQueryTab.Notice(const AText: string);
begin
  FStatusText := AText;
  StateChanged;
end;

procedure TpgnQueryTab.DescribeAtCaret;
var
  Ident, Db, Tbl: string;
  P: Integer;
begin
  if FAdapter = nil then
  begin
    Exit;
  end;
  Ident := IdentifierAtCaret;
  if Ident = '' then
  begin
    Exit;
  end;
  P := Pos('.', Ident);
  if P > 0 then
  begin
    Db := Copy(Ident, 1, P - 1);
    Tbl := Copy(Ident, P + 1, MaxInt);
  end
  else
  begin
    Db := FCurrentDb;
    if FAdapter.HasSchemas then
    begin
      Db := FAdapter.CurrentSchema;   // PostgreSQL: the schema in the band
    end;
    Tbl := Ident;
  end;
  if Db = '' then
  begin
    MessageDlg('Choose a database in this tab first, or write it as db.table.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  RunSQL(FAdapter.DescribeSQL(Db, Tbl));
end;

{ ------------------------------------------------------------- editor }

procedure TpgnQueryTab.InsertText(const AText: string; AOwnLine: Boolean);
begin
  if AText = '' then
  begin
    Exit;
  end;
  if AOwnLine and (FEditor.LogicalCaretXY.X > 1) then
  begin
    FEditor.InsertTextAtCaret(LineEnding + AText);
  end
  else
  begin
    FEditor.InsertTextAtCaret(AText);
  end;
  FocusEditor;
end;

{ Puts generated SQL in the tab. It doesn't count as an unsaved change,
  so tabs opened from the Explorer close without a question. }
procedure TpgnQueryTab.SetText(const AText: string);
begin
  FEditor.Text := AText;
  FEditor.Modified := False;
  FWasModified := False;
  StateChanged;
end;

procedure TpgnQueryTab.LoadFromFile(const AFileName: string);
begin
  FEditor.Lines.LoadFromFile(AFileName);
  FFileName := AFileName;
  FTitle := ExtractFileName(AFileName);
  FEditor.Modified := False;
  FWasModified := False;
  FEditor.CaretXY := Point(1, 1);
  Log('Opened ' + AFileName);
  StateChanged;
end;

procedure TpgnQueryTab.SaveToFile(const AFileName: string);
begin
  FEditor.Lines.SaveToFile(AFileName);
  FFileName := AFileName;
  FTitle := ExtractFileName(AFileName);
  FEditor.Modified := False;
  FWasModified := False;
  Log('Saved ' + AFileName);
  StateChanged;
end;

{ Comments or uncomments, with "-- ", every line the selection touches
  (or the caret line). Comment always adds a level, Uncomment removes one,
  Toggle uncomments when every non-blank line is already commented.
  Blank lines inside a selection are left alone; a blank line on its own
  (or an empty editor) gets "-- " with the caret after it. Done as one edit, so a single Undo reverses
  it. "--" is a comment in every database Pagona talks to. }
procedure TpgnQueryTab.CommentLines(AMode: TpgnCommentMode);
var
  Y1, Y2, I, CaretX, CaretY, OldLen, IndentLen: Integer;
  NewLines: TStringList;
  AllCommented, AllBlank, Uncommenting, HadSelection: Boolean;
  S, T, Indent: string;
begin
  HadSelection := FEditor.SelAvail;
  CaretX := FEditor.LogicalCaretXY.X;
  CaretY := FEditor.LogicalCaretXY.Y;
  if FEditor.SelAvail then
  begin
    Y1 := FEditor.BlockBegin.Y;
    Y2 := FEditor.BlockEnd.Y;
    // a selection ending at column 1 doesn't include that line
    if (FEditor.BlockEnd.X = 1) and (Y2 > Y1) then
    begin
      Dec(Y2);
    end;
  end
  else
  begin
    Y1 := FEditor.CaretY;
    Y2 := Y1;
  end;
  if FEditor.Lines.Count = 0 then
  begin
    // empty editor: commenting starts a comment line
    if AMode <> cmUncomment then
    begin
      FEditor.InsertTextAtCaret('-- ');
    end;
    Exit;
  end;
  if (Y1 < 1) or (Y2 > FEditor.Lines.Count) then
  begin
    Exit;
  end;

  NewLines := TStringList.Create;
  try
    AllCommented := True;
    AllBlank := True;
    for I := Y1 to Y2 do
    begin
      S := FEditor.Lines[I - 1];
      NewLines.Add(S);
      T := TrimLeft(S);
      if T <> '' then
      begin
        AllBlank := False;
      end;
      if (T <> '') and (Copy(T, 1, 2) <> '--') then
      begin
        AllCommented := False;
      end;
    end;

    case AMode of
      cmComment:
        begin
          Uncommenting := False;
        end;
      cmUncomment:
        begin
          Uncommenting := True;
        end;
    else
      begin
        Uncommenting := AllCommented and not AllBlank;
      end;
    end;

    for I := 0 to NewLines.Count - 1 do
    begin
      S := NewLines[I];
      T := TrimLeft(S);
      if T = '' then
      begin
        // a blank line on its own gets a "-- " to type after; blank lines
        // inside a selection of code stay blank
        if AllBlank and not Uncommenting then
        begin
          NewLines[I] := S + '-- ';
        end;
        Continue;
      end;
      Indent := Copy(S, 1, Length(S) - Length(T));
      if Uncommenting then
      begin
        if Copy(T, 1, 3) = '-- ' then
        begin
          NewLines[I] := Indent + Copy(T, 4, MaxInt);
        end
        else if Copy(T, 1, 2) = '--' then
        begin
          NewLines[I] := Indent + Copy(T, 3, MaxInt);
        end;
      end
      else
      begin
        NewLines[I] := Indent + '-- ' + T;
      end;
    end;

    // replace the whole lines as one edit, so a single Undo reverses it
    FEditor.BlockBegin := Point(1, Y1);
    FEditor.BlockEnd := Point(Length(FEditor.Lines[Y2 - 1]) + 1, Y2);
    S := NewLines[0];
    for I := 1 to NewLines.Count - 1 do
    begin
      S := S + LineEnding + NewLines[I];
    end;
    OldLen := Length(FEditor.Lines[CaretY - 1]);
    IndentLen := Length(FEditor.Lines[CaretY - 1]) - Length(TrimLeft(FEditor.Lines[CaretY - 1]));
    FEditor.SelText := S;
    if HadSelection then
    begin
      // keep the lines selected, so the same key can undo the change
      FEditor.BlockBegin := Point(1, Y1);
      FEditor.BlockEnd := Point(Length(FEditor.Lines[Y2 - 1]) + 1, Y2);
    end
    else
    begin
      // no selection before, none after: the caret stays put, moved along
      // with the text, so a stray Enter can't wipe the line
      if AllBlank then
      begin
        // after the new "-- ", ready to type the comment
        CaretX := Length(FEditor.Lines[CaretY - 1]) + 1;
      end
      else if CaretX > IndentLen + 1 then
      begin
        CaretX := CaretX + Length(FEditor.Lines[CaretY - 1]) - OldLen;
      end;
      if CaretX < 1 then
      begin
        CaretX := 1;
      end;
      FEditor.BlockBegin := Point(CaretX, CaretY);
      FEditor.BlockEnd := Point(CaretX, CaretY);
      FEditor.LogicalCaretXY := Point(CaretX, CaretY);
    end;
  finally
    NewLines.Free;
  end;
end;

procedure TpgnQueryTab.ToggleComment;
begin
  CommentLines(cmToggle);
end;

{ Wraps the selection in /* */, or unwraps it if it already is wrapped.
  With no selection, works on the caret line's text. }
procedure TpgnQueryTab.BlockComment;
var
  S, T: string;
  Y: Integer;
begin
  if not FEditor.SelAvail then
  begin
    Y := FEditor.CaretY;
    if (Y < 1) or (Y > FEditor.Lines.Count) or (Trim(FEditor.Lines[Y - 1]) = '') then
    begin
      Exit;
    end;
    FEditor.BlockBegin := Point(1, Y);
    FEditor.BlockEnd := Point(Length(FEditor.Lines[Y - 1]) + 1, Y);
  end;
  S := FEditor.SelText;
  T := Trim(S);
  if (Length(T) >= 4) and (Copy(T, 1, 2) = '/*') and (Copy(T, Length(T) - 1, 2) = '*/') then
  begin
    // unwrap, dropping one space just inside each marker if there is one
    T := Copy(T, 3, Length(T) - 4);
    if Copy(T, 1, 1) = ' ' then
    begin
      Delete(T, 1, 1);
    end;
    if Copy(T, Length(T), 1) = ' ' then
    begin
      Delete(T, Length(T), 1);
    end;
    FEditor.SelText := T;
  end
  else
  begin
    FEditor.SelText := '/* ' + S + ' */';
  end;
end;

procedure TpgnQueryTab.ChangeCase(AUpper: Boolean);
var
  B, E: TPoint;
begin
  if not FEditor.SelAvail then
  begin
    FEditor.SelectWord;
  end;
  if not FEditor.SelAvail then
  begin
    Exit;
  end;
  B := FEditor.BlockBegin;
  E := FEditor.BlockEnd;
  if AUpper then
  begin
    FEditor.SelText := UTF8UpperCase(FEditor.SelText);
  end
  else
  begin
    FEditor.SelText := UTF8LowerCase(FEditor.SelText);
  end;
  FEditor.BlockBegin := B;
  FEditor.BlockEnd := E;
end;

end.
