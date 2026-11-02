// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnMain;

{ Pagona's main window, built in code:

    +----------------------------------------------------------------+
    | New Tab  Run  Run Script  Cancel  Commit  Rollback             |
    +--------------+-------------------------------------------------+
    | Explorer     | [PROD · MySQL · finaid: Query 1] [DEV · ...]    |
    |  [Refresh]   |  (each tab: connection, database, editor,       |
    |  connection  |   results, messages; see pgnQueryTab)           |
    |   database   |                         | (split view: a second |
    |    Tables    |                         |  tab group on the     |
    |    Views     |                         |  right)               |
    +--------------+-------------------------------------------------+
    | status bar (active tab)                                        |

  The Explorer shows every saved connection; expanding one connects it
  with its own session for browsing. Each query tab has its own session.
  A password is asked for once per connection and remembered in memory
  until Pagona closes; it is never written to disk.

  Every command is a TAction, so keymaps only change which keys point at
  which action. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, ActnList, Menus, LCLType, Clipbrd, Grids,
  SynEdit, SynEditKeyCmds, SynEditTypes,
  pgnTypes, pgnAdapter, pgnAdapters, pgnConnections, pgnSettings, pgnKeymap,
  ExtTabCtrl, ExtTabCtrlDrawing, ExtPageCtrl,
  pgnSqlSplit, pgnConnectDlg, pgnOptionsDlg, pgnScriptGen, pgnQueryTab,
  pgnTheme, pgnToolbar, pgnStatusBar, pgnResultGrid, pgnRoutineDlg, SynHighlighterSQL, pgnDbaLog,
  pgnAmphibian, pgnIcons, Process, pgnConnectWin, pgnPendingWin, pgnMenuColor, pgnAdapterMSSQL, pgnDescribeWin, pgnAboutDlg;

type
  TpgnDetailsPage = (dpColumns, dpIndexes, dpTriggers, dpParameters, dpDefinition, dpGrants);
  TpgnDetailsPages = set of TpgnDetailsPage;

  TpgnNodeKind = (nkConnection, nkDatabase, nkFolderTables, nkFolderViews,
    nkTable, nkView, nkColumn, nkPlaceholder,
    nkFolderProcs, nkFolderFuncs, nkFolderTriggers, nkProcedure, nkFunction, nkTrigger,
    // PostgreSQL's levels and folders
    nkFolderDatabases, nkFolderSchemas, nkFolderCatalogs, nkSchema,
    nkFolderMatViews, nkMatView, nkFolderTrigFuncs,
    nkFolderColumns, nkFolderIndexes, nkFolderTableTriggers, nkIndex,
    nkFolderOther, nkOther,    // folders named by the adapter, and their items
    nkFolderMore);             // holds the rarely used folders

const
  FolderKinds = [nkFolderTables, nkFolderViews, nkFolderProcs, nkFolderFuncs, nkFolderTriggers,
    nkFolderDatabases, nkFolderSchemas, nkFolderCatalogs, nkFolderMatViews, nkFolderTrigFuncs,
    nkFolderColumns, nkFolderIndexes, nkFolderTableTriggers, nkFolderOther];
  { nodes that never open further }
  LeafKinds = [nkColumn, nkProcedure, nkFunction, nkTrigger, nkIndex, nkOther];
  RelationKinds = [nkTable, nkView, nkMatView];
  RoutineNodeKinds = [nkProcedure, nkFunction, nkTrigger];

type

  TpgnTreeCommand = (tcConnect, tcDisconnect, tcNewTab, tcEditConnection,
    tcDeleteConnection, tcNewConnection, tcRefresh, tcRefreshAll, tcSelectTop,
    tcDescribe, tcShowDDL, tcScriptSelect, tcScriptInsert, tcScriptUpdate,
    tcScriptDelete, tcScriptCreate, tcCopyName, tcTruncate, tcDrop,
    tcOpenRoutine, tcExecuteRoutine, tcScriptRoutine, tcGrant, tcNewProcedure,
    tcNewFunction, tcNewTrigger, tcDropRoutine, tcCopyDefinition, tcWhoCan);

  { A saved connection as shown in the Explorer, with its browsing session. }
  TpgnExplorerConn = record
    Info: TpgnConnectionInfo;
    Adapter: TpgnAdapter;
    Root: TTreeNode;
    { PostgreSQL: a session per database opened, by database name }
    Sessions: TStringList;
  end;

  TpgnMainForm = class(TForm)
  private
    FStore: TpgnConnectionStore;
    FSettings: TpgnSettings;
    FHistory: TStringList;
    FPasswords: TStringList;         // connection id=password, memory only
    FExplorer: array of TpgnExplorerConn;
    FActiveTab: TpgnQueryTab;
    FTabCounter: Integer;
    FKeymap: string;                 // the keymap in use (setting resolved against the layout)
    FChordShown: Boolean;            // status bar shows "Ctrl+K: ..." (Seattle)
    FNextLeft: Integer;

    // UI
    FActions: TActionList;
    FMainMenu: TMainMenu;
    FKeymapItems: array of TMenuItem;
    FThemeItems: array of TMenuItem;
    FLookItems: array of TMenuItem;   // 0 = Match layout, then LookNames
    FUpdatingChecks: Boolean;         // setting menu checks: GTK reports them as clicks
    FToolBar: TpgnToolbar;
    FExplorerPanel: TPanel;
    FTree: TTreeView;
    FFilterEdit: TEdit;
    FFilterTimer: TTimer;
    FFoundList: TpgnResultGrid;      // filter results, shown in place of the tree
    FFoundNote: TLabel;
    FFound: array of record          // what each row of FFoundList points at
      ConnIndex: Integer;
      Ref: TpgnObjectRef;
      Node: TTreeNode;               // nil if not loaded in the tree yet
    end;
    FDetailsLabel: TLabel;
    FDetailsTabs: TTabControl;
    FDetailsBody: TPanel;
    FDetailsArea: array[TpgnDetailsPage] of TControl;
    FDetailsShowing: array of TpgnDetailsPage;   // the pages on the tabs, in order
    FDetailsPage: TpgnDetailsPage;                // the one in view
    FDetailsColumns: TpgnResultGrid;
    FDetailsIndexes: TpgnResultGrid;
    FDetailsTriggers: TpgnResultGrid;
    FDetailsGrants: TpgnResultGrid;
    FDetailsParams: TpgnResultGrid;
    FDetailsDefinition: TSynEdit;
    FDetailsHighlighter: TSynSQLSyn;
    FDetailsConn: Integer;           // where the object in Details lives
    FDetailsDb: string;
    FDetailsSchema: string;
    FRefreshError: string;           // the first error a refresh met
    FDetailsTimer: TTimer;
    FDetailsShown: string;           // conn|db|name now in Details, to skip reloads
    FTreeMenu: TPopupMenu;
    FTabArea: TPanel;
    FLeftPages: TExtPageCtrl;
    FRightPages: TExtPageCtrl;
    FDeletingPage: Boolean;          // our own DeletePage calls are allowed through
    FTabSplitter: TSplitter;
    FTabMenu: TPopupMenu;
    FEditorMenu: TPopupMenu;
    FStatus: TpgnStatusBar;

    // actions
    FActNewConn, FActEditConn, FActDeleteConn, FActExit: TAction;
    FActNewTab, FActCloseTab, FActNextTab, FActPrevTab, FActMoveTab, FActRenameTab: TAction;
    FActResGrid, FActResText, FActResFile: TAction;   // Seattle: Results To
    FActAbout: TAction;
    FActOpen, FActSave, FActSaveAs: TAction;
    FLastDir: string;
    FActRunStatement, FActRunScript, FActCancel, FActExplain: TAction;
    FActDescribe, FActHistory, FActOptions, FActRefreshAll: TAction;
    FActDbaSessions, FActDbaLocks, FActDbaUsers, FActDbaWhoCan, FActDbaLog: TAction;
    FDbaMenu: TMenuItem;
    FActCommit, FActRollback, FActAutoCommit, FActDisconnect: TAction;
    FActCut, FActCopy, FActPaste, FActSelectAll: TAction;
    FActToggleComment, FActUpper, FActLower: TAction;
    FActComment, FActUncomment, FActBlockComment: TAction;
    FActIndent, FActOutdent, FActFind, FActFindNext, FActReplace: TAction;
    FActSchemaBrowser, FActShowEditor: TAction;
    FActPending: TAction;
    FCommitMenu: TPopupMenu;          // Commit's drop arrow
    FTxPanel: TpgnTransactionsPanel;  // Amphibian: docked at the bottom, as Toad
    FTxSplitter: TSplitter;
    FTxShown: Boolean;
    FLayoutItems: array of TMenuItem;
    FFindDialog: TFindDialog;
    FReplaceDialog: TReplaceDialog;

    // Amphibian (Toad's arrangement)
    FAmph: Boolean;
    FDetailsPanel: TPanel;
    FSessionBar: TpgnStripBar;
    FWindowBar: TpgnStripBar;
    FWindowArea: TPanel;
    FEditorWindow: TPanel;
    FEditorBar: TpgnToolbar;
    FPickPanel: TPanel;
    FPickLabels: array[0..2] of TLabel;
    FPicks: array[0..2] of TComboBox;
    FMirrorTimer: TTimer;
    FMirroring: Boolean;
    FBrowser: TpgnSchemaBrowser;
    FDescribeWin: TpgnDescribeWindow;   // the one Describe window, while open
    FBrowserShown: Boolean;
    FCloseChecked: Boolean;
    FExplorerSplitter: TSplitter;
    FPendingLayout: string;           // closing to restart: the questions were asked
    FLastTabOf: TStringList;          // connection id -> the tab last used on it
    FTabOrder: TList;                 // every tab, in the order they'd sit in one row

    // Seattle (SSMS's arrangement)
    FSea: Boolean;
    FExplorerHeader: TPanel;
    FExplorerTitle: TLabel;
    FExplorerRefresh: TButton;
    FDetailsSplitter: TSplitter;
    FOEBar: TpgnToolbar;              // Object Explorer's own bar
    FOEMenu: TPopupMenu;              // its Connect drop arrow
    FOEFilterShown: Boolean;
    FSqlHost: TPanel;                 // the SQL Editor toolbar row
    FSqlLeft: TpgnToolbar;
    FActUndo, FActRedo, FActConnectOE, FActDisconnectOE, FActConnectTab, FActChangeConn: TAction;
    FActOEFilter: TAction;

    procedure BuildActions;
    procedure BuildMenu;
    procedure BuildLayout;
    procedure BuildPopupMenus;
    function NewAction(const AName, ACaption: string; AHandler: TNotifyEvent): TAction;
    function AddMenu(AParent: TMenuItem; const ACaption: string): TMenuItem;
    procedure AddActionItem(AParent: TMenuItem; AAction: TAction);
    procedure AddSeparator(AParent: TMenuItem);
    procedure BuildToolbar;
    procedure BuildAmphibianMenu;
    procedure BuildSeattleMenu;
    procedure RecolorFrame;
    procedure ColorMenu;
    procedure AsyncColorMenu(AData: PtrInt);
    procedure DoSelectLook(Sender: TObject);
    procedure BuildSeattleArea;
    procedure TearDownSeattle;
    procedure SyncSeattleRoots;
    procedure PlaceOEFilter;
    function PickConnection: Integer;
    procedure DoUndo(Sender: TObject);
    procedure DoRedo(Sender: TObject);
    procedure DoConnectOE(Sender: TObject);
    procedure DoDisconnectOE(Sender: TObject);
    procedure DoChangeConn(Sender: TObject);
    procedure DoOEFilter(Sender: TObject);
    procedure AddKeymapThemeMenus(M: TMenuItem);
    function RevealOther(AHolder: TTreeNode; const AFolder, AName: string): TTreeNode;
    procedure AddLayoutMenu(AParent: TMenuItem);
    procedure BuildAmphibianArea;
    procedure TearDownAmphibian;
    procedure RestorePlumeArea;
    procedure ApplyActionCaptions;
    procedure SwitchLayout(const AWant: string);
    procedure AsyncSwitchLayout(AData: PtrInt);
    procedure AsyncConnectWindow(AData: PtrInt);
    procedure ShowConnectWindow;
    procedure ConnectChosen(const AInfo: TpgnConnectionInfo);
    function NewSavedConnection: Boolean;
    function EditConnectionAt(AIndex: Integer): Boolean;
    function DeleteConnectionAt(AIndex: Integer): Boolean;
    function WinNewConnection: Boolean;
    function WinEditConnection(AStoreIndex: Integer): Boolean;
    function WinDeleteConnection(AStoreIndex: Integer): Boolean;
    procedure EditorBarChanged(Sender: TObject);
    procedure LayoutPicks(Sender: TObject);
    procedure MirrorTimerTick(Sender: TObject);
    procedure PickChange(Sender: TObject);
    procedure UpdateAmphBars;
    procedure SessionBarClick(Sender: TObject; AIndex: Integer);
    procedure WindowBarClick(Sender: TObject; AIndex: Integer);
    procedure ShowEditorWindow;
    procedure ShowSchemaBrowser;
    procedure ActivateTab(ATab: TpgnQueryTab);
    function BrowserAdapter(AConnIndex: Integer; const ADatabase: string): TpgnAdapter;
    procedure BrowserSelect(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef);
    procedure BrowserOpen(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef);
    procedure BrowserMenu(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef;
      const AScreenPos: TPoint);
    procedure DoSchemaBrowser(Sender: TObject);
    procedure DoPending(Sender: TObject);
    function FirstPendingTab: TpgnQueryTab;
    function PendingTabs: TpgnTabArray;
    procedure TabReviewPending(Sender: TObject);
    procedure TxChanged(Sender: TObject);
    procedure TxCloseClick(Sender: TObject);
    procedure ShowTxPanel(AFocus: TpgnQueryTab);
    procedure HideTxPanel;
    procedure StatusSegmentClick(Sender: TObject; AIndex: Integer);
    procedure DoShowEditor(Sender: TObject);
    procedure DoSelectLayout(Sender: TObject);
    procedure DoIndent(Sender: TObject);
    procedure DoOutdent(Sender: TObject);
    procedure DoFind(Sender: TObject);
    procedure DoFindNext(Sender: TObject);
    procedure DoReplace(Sender: TObject);
    procedure FindDialogFind(Sender: TObject);
    procedure ReplaceDialogReplace(Sender: TObject);
    procedure SearchEditor(const AText: string; AOptions: TFindOptions; AReplace: Boolean;
      const AWith: string);
    procedure ToolbarChanged(Sender: TObject);
    function DefaultToolbar(const ALayout: string): string;
    procedure TabCaretMoved(Sender: TObject);

    procedure ApplyCurrentKeymap;
    procedure ApplyKeysToEditor(AEditor: TSynEdit);
    procedure UpdateActionStates;
    procedure RefreshStatus;
    procedure ShowError(const AWhat: string; E: Exception);

    // passwords and sessions
    procedure RememberPassword(const AId, APassword: string);
    procedure ForgetPassword(const AId: string);
    function ConnectAdapter(const AInfo: TpgnConnectionInfo): TpgnAdapter;

    // tabs
    function TabCount: Integer;
    function TabAt(AIndex: Integer): TpgnQueryTab;
    function TabOfPage(APage: TExtPage): TpgnQueryTab;
    function PageOfTab(ATab: TpgnQueryTab): TExtPage;
    function GroupOfTab(ATab: TpgnQueryTab): TExtPageCtrl;
    function NewPageCtrl(AAlign: TAlign): TExtPageCtrl;
    procedure RemovePage(AGroup: TExtPageCtrl; APage: TExtPage);
    function NewTab(const ATitle: string): TpgnQueryTab;
    function NewTabOn(const AInfo: TpgnConnectionInfo; const ADatabase, ATitle: string;
      const ASchema: string = ''): TpgnQueryTab;
    procedure CloseTab(ATab: TpgnQueryTab);
    function ConfirmCloseTab(ATab: TpgnQueryTab; const AReason: string): Boolean;
    function SaveTab(ATab: TpgnQueryTab; AAskName: Boolean): Boolean;
    procedure PagesTabDeleting(Sender: TObject; Index: Integer; var Allow: Boolean);
    procedure PagesAddClick(Sender: TObject);
    procedure AsyncCloseTab(AData: PtrInt);
    procedure AsyncCommentLines(AData: PtrInt);
    procedure MoveTab(ATab: TpgnQueryTab);
    procedure UpdateSplit;
    procedure SyncTabOrder;
    procedure SetActiveTab(ATab: TpgnQueryTab);
    procedure TabStateChanged(Sender: TObject);
    procedure TabActivated(Sender: TObject);
    procedure TabSchemaChanged(Sender: TObject; const AConnectionId: string;
      AChange: TpgnSchemaChange; const ASQL: string);
    procedure PagesChanged(Sender: TObject; NewIndex: Integer);
    procedure PagesMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SelectAdjacentTab(AForward: Boolean);
    procedure TabMenuPopup(Sender: TObject);

    // explorer
    function KindToPtr(AKind: TpgnNodeKind): Pointer;
    function NodeKind(ANode: TTreeNode): TpgnNodeKind;
    function AddNode(AParent: TTreeNode; const AText: string; AKind: TpgnNodeKind;
      AHasChildren: Boolean): TTreeNode;
    function InsertSortedNode(AParent: TTreeNode; const AText: string; AKind: TpgnNodeKind): TTreeNode;
    function ChildrenLoaded(ANode: TTreeNode): Boolean;
    procedure ResetNode(ANode: TTreeNode);
    procedure ReconcileChildren(AParent: TTreeNode; const ANames: TpgnStringArray; AKind: TpgnNodeKind);
    function ExplorerIndexOfNode(ANode: TTreeNode): Integer;
    function ExplorerIndexOfId(const AId: string): Integer;
    function SelectedExplorerIndex: Integer;
    function EnsureExplorerConnected(AIndex: Integer): Boolean;
    procedure DisconnectExplorer(AIndex: Integer);
    procedure AddExplorerRoot(const AInfo: TpgnConnectionInfo);
    procedure BuildExplorer;
    function RefreshConnection(AIndex: Integer; const ASQLHint: string; AAllColumns: Boolean): string;
    function DatabaseOf(ANode: TTreeNode): string;
    function SchemaOf(ANode: TTreeNode): string;
    function ContainerOf(ANode: TTreeNode): string;
    function TableOf(ANode: TTreeNode): string;
    function FolderBase(ANode: TTreeNode): string;
    procedure SetFolderCount(ANode: TTreeNode);
    function AdapterFor(AIndex: Integer; const ADatabase: string): TpgnAdapter;
    function NodeAdapter(ANode: TTreeNode): TpgnAdapter;
    procedure FreeSessions(AIndex: Integer);
    function RefOfNode(ANode: TTreeNode): TpgnObjectRef;
    procedure AddExtraFolders(ANode: TTreeNode; AAdapter: TpgnAdapter; ALevel: TpgnFolderLevel);
    procedure AddContainerFolders(ANode: TTreeNode; AAdapter: TpgnAdapter);
    function FolderContents(ANode: TTreeNode; out ANames: TpgnStringArray;
      out AChildKind: TpgnNodeKind; out AHasChildren: Boolean): Boolean;
    procedure RefreshNode(AIndex: Integer; ANode: TTreeNode; const AHintUpper: string;
      AAllColumns: Boolean);
    function FindChild(AParent: TTreeNode; AKind: TpgnNodeKind; const AText: string): TTreeNode;
    function NodeKindFor(const AKind: string): TpgnNodeKind;
    procedure OpenDbaScreen(AScreen: TpgnDbaScreen; const AKind: string = '';
      const AContainer: string = ''; const AName: string = ''; AConnIndex: Integer = -1);
    procedure DoDbaSessions(Sender: TObject);
    procedure DoDbaLocks(Sender: TObject);
    procedure DoDbaUsers(Sender: TObject);
    procedure DoDbaWhoCan(Sender: TObject);
    procedure TabOpenAccount(const AAccount: string);
    procedure DoDbaLog(Sender: TObject);
    function ObjectNameOf(ANode: TTreeNode): string;
    function QualifiedNameOf(AIndex: Integer; ANode: TTreeNode): string;
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TreeMenuPopup(Sender: TObject);
    function AddTreeItem(AParent: TMenuItem; const ACaption: string; ACommand: TpgnTreeCommand): TMenuItem;
    procedure TreeMenuClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);

    // filter and details
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FilterTimerTick(Sender: TObject);
    procedure RunFilter(const AText: string);
    procedure FillFoundList;
    procedure FoundSelect(Sender: TObject; aCol, aRow: Integer);
    procedure FoundKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FoundDblClick(Sender: TObject);
    function RevealObject(AConnIndex: Integer; const ARef: TpgnObjectRef): TTreeNode;
    procedure DetailsTimerTick(Sender: TObject);
    procedure ShowDetails(AConnIndex: Integer; const ARef: TpgnObjectRef);
    procedure ClearDetails(const ACaption: string);
    procedure DetailsTriggersDblClick(Sender: TObject);
    procedure SetDetailsPages(APages: TpgnDetailsPages);
    procedure ShowDetailsPage(APage: TpgnDetailsPage);
    procedure DetailsTabChange(Sender: TObject);
    procedure DetailsBodyResize(Sender: TObject);
    function NodeObjectKind(ANode: TTreeNode): string;

    // procedures, functions, triggers
    function SaveWord: string;
    function RoutineKindOf(ANode: TTreeNode): TpgnRoutineKind;
    procedure OpenRoutineTab(AConnIndex: Integer; const ADatabase, ASchema, AName: string;
      AKind: TpgnRoutineKind);
    procedure NewRoutineTab(AConnIndex: Integer; const ADatabase, ASchema: string;
      AKind: TpgnRoutineKind; const ASQL: string);
    procedure ExecuteRoutine(AConnIndex: Integer; const ADatabase, ASchema, AName: string;
      AKind: TpgnRoutineKind);
    procedure TabRoutineExecute(Sender: TObject);

    // handlers
    procedure DoNewConnection(Sender: TObject);
    procedure DoEditConnection(Sender: TObject);
    procedure DoDeleteConnection(Sender: TObject);
    procedure DoExitApp(Sender: TObject);
    procedure DoNewTab(Sender: TObject);
    procedure DoCloseTab(Sender: TObject);
    procedure DoNextTab(Sender: TObject);
    procedure DoPrevTab(Sender: TObject);
    procedure DoMoveTab(Sender: TObject);
    procedure DoResultsTo(Sender: TObject);
    procedure DoAbout(Sender: TObject);
    procedure DoRenameTab(Sender: TObject);
    procedure DoOpenFile(Sender: TObject);
    procedure DoSaveFile(Sender: TObject);
    procedure DoSaveFileAs(Sender: TObject);
    procedure DoRunStatement(Sender: TObject);
    procedure DoRunScript(Sender: TObject);
    procedure DoExplain(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure DoDescribe(Sender: TObject);
    function DescribeAdapter(const AConnId, ADatabase: string): TpgnAdapter;
    procedure DescribeReveal(const AConnId: string; const ARef: TpgnObjectRef);
    function DescribeResolve(const AConnId, AName: string; out ARef: TpgnObjectRef;
      out AVia: string): Boolean;
    procedure DescribeWinDestroyed(Sender: TObject);
    procedure DoHistory(Sender: TObject);
    procedure DoOptions(Sender: TObject);
    procedure DoRefreshAll(Sender: TObject);
    procedure DoCommit(Sender: TObject);
    procedure DoRollback(Sender: TObject);
    procedure DoCut(Sender: TObject);
    procedure DoCopy(Sender: TObject);
    procedure DoPaste(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoToggleComment(Sender: TObject);
    procedure DoComment(Sender: TObject);
    procedure DoUncomment(Sender: TObject);
    procedure DoBlockComment(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorUserCommand(Sender: TObject; var Command: TSynEditorCommand;
      var AChar: TUTF8Char; Data: Pointer);
    procedure DoUpper(Sender: TObject);
    procedure DoLower(Sender: TObject);
    procedure DoSelectKeymap(Sender: TObject);
    procedure DoSelectTheme(Sender: TObject);
    procedure DoAutoCommit(Sender: TObject);
    procedure DoDisconnect(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function PickFromHistory: string;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  pgnMainForm: TpgnMainForm;

implementation

type
  { reaches members ExtTabCtrls keeps protected (OnMouseDown, TabAtPos) }
  TExtPageCtrlAccess = class(TExtPageCtrl);

{ Where a password is for: the host, or the TNS alias for Oracle. }
function PasswordWhere(const AInfo: TpgnConnectionInfo): string;
begin
  if AInfo.TnsAlias <> '' then
  begin
    Result := AInfo.TnsAlias;
  end
  else
  begin
    Result := AInfo.Host;
  end;
end;

const
  DefaultTopRows = 1000;

  // editor commands for Seattle's Ctrl+K Ctrl+C / Ctrl+K Ctrl+U
  ecPgnComment   = ecUserFirst + 1;
  ecPgnUncomment = ecUserFirst + 2;

{ ---------------------------------------------------------------- setup }

constructor TpgnMainForm.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  // smoothed text for everything in the window (controls take the form's font)
  SmoothFont(Font);
  Caption := 'Pagona';
  Width := 1280;
  Height := 820;
  Position := poScreenCenter;
  FNextLeft := 0;
  FTabCounter := 0;
  FActiveTab := nil;

  FHistory := TStringList.Create;
  FPasswords := TStringList.Create;
  FStore := TpgnConnectionStore.Create;
  FStore.Load;
  FSettings := TpgnSettings.Create;
  FSettings.Load;
  FAmph := SameText(FSettings.Layout, LayoutAmphibian);
  FSea := SameText(FSettings.Layout, LayoutSeattle);
  // the frame's colors come from the look (by default the layout's)
  ApplyLook(EffectiveLook(FSettings.Look, FSettings.Layout));
  Color := clPgnSurface;
  FLastTabOf := TStringList.Create;
  FTabOrder := TList.Create;

  BuildActions;
  BuildMenu;
  BuildLayout;
  BuildPopupMenus;
  OnCloseQuery := @FormCloseQuery;

  BuildExplorer;
  NewTab('');
  RecolorFrame;
  Application.QueueAsyncCall(@AsyncColorMenu, 0);
  ApplyCurrentKeymap;
  RefreshStatus;
  UpdateActionStates;
  if FAmph then
  begin
    UpdateAmphBars;
    FMirrorTimer.Enabled := True;
    // as Toad does: start by asking where to connect
    Application.QueueAsyncCall(@AsyncConnectWindow, 0);
  end;
  if FSea then
  begin
    SyncSeattleRoots;
    FMirrorTimer.Enabled := True;
    // as SSMS does: Connect to Server first
    Application.QueueAsyncCall(@AsyncConnectWindow, 0);
  end;
end;

destructor TpgnMainForm.Destroy;
var
  I: Integer;
begin
  // no tab events while everything is being taken down
  Application.RemoveAsyncCalls(Self);
  if FMirrorTimer <> nil then
  begin
    FMirrorTimer.Enabled := False;
  end;
  if FBrowser <> nil then
  begin
    FBrowser.OnSelectObject := nil;
    FBrowser.OnAdapter := nil;
  end;
  FActiveTab := nil;
  FLeftPages.OnTabChanged := nil;
  FRightPages.OnTabChanged := nil;
  FLeftPages.OnTabDeleting := nil;
  FRightPages.OnTabDeleting := nil;
  for I := 0 to TabCount - 1 do
  begin
    TabAt(I).OnStateChanged := nil;
    TabAt(I).OnActivate := nil;
    TabAt(I).OnSchemaChanged := nil;
    TabAt(I).OnCaretMoved := nil;
    TabAt(I).OnRoutineExecute := nil;
    TabAt(I).OnReviewPending := nil;
  end;
  for I := 0 to High(FExplorer) do
  begin
    FreeSessions(I);
    FreeAndNil(FExplorer[I].Sessions);
    if FExplorer[I].Adapter <> nil then
    begin
      try
        FExplorer[I].Adapter.Disconnect;
      except
        on E: Exception do
        begin
          // shutting down
        end;
      end;
      FreeAndNil(FExplorer[I].Adapter);
    end;
  end;
  // The tab pages belong to the form, which frees them before the two
  // tab groups; a tab group still listing a freed page then reads freed
  // memory (crash on exit). Freeing the groups first unlinks every page
  // while it still exists.
  FreeAndNil(FRightPages);
  FreeAndNil(FLeftPages);
  inherited Destroy;   // frees the tabs, which close their own sessions
  FreeAndNil(FHistory);
  FreeAndNil(FPasswords);
  FreeAndNil(FLastTabOf);
  FreeAndNil(FTabOrder);
  FreeAndNil(FStore);
  FreeAndNil(FSettings);
end;

function TpgnMainForm.NewAction(const AName, ACaption: string; AHandler: TNotifyEvent): TAction;
begin
  Result := TAction.Create(FActions);
  Result.ActionList := FActions;
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.OnExecute := AHandler;
end;

procedure TpgnMainForm.BuildActions;
begin
  FActions := TActionList.Create(Self);

  FActNewConn := NewAction('actNewConnection', '&New Connection...', @DoNewConnection);
  FActEditConn := NewAction('actEditConnection', '&Edit Connection...', @DoEditConnection);
  FActDeleteConn := NewAction('actDeleteConnection', '&Delete Connection...', @DoDeleteConnection);
  FActExit := NewAction('actExit', 'E&xit', @DoExitApp);

  FActNewTab := NewAction(actNewTab, 'New &Query Tab', @DoNewTab);
  FActCloseTab := NewAction(actCloseTab, '&Close Tab', @DoCloseTab);
  FActNextTab := NewAction(actNextTab, 'Next Tab', @DoNextTab);
  FActPrevTab := NewAction(actPrevTab, 'Previous Tab', @DoPrevTab);
  FActMoveTab := NewAction('actMoveTab', 'Side by Side', @DoMoveTab);
  FActAbout := NewAction('actAbout', '&About Pagona', @DoAbout);
  FActResGrid := NewAction(actResultsGrid, 'Results to &Grid', @DoResultsTo);
  FActResGrid.Tag := 0;
  FActResText := NewAction(actResultsText, 'Results to &Text', @DoResultsTo);
  FActResText.Tag := 1;
  FActResFile := NewAction(actResultsFile, 'Results to &File', @DoResultsTo);
  FActResFile.Tag := 2;
  FActRenameTab := NewAction('actRenameTab', '&Rename Tab...', @DoRenameTab);
  FActOpen := NewAction(actOpenFile, '&Open SQL File...', @DoOpenFile);
  FActSave := NewAction(actSaveFile, '&Save', @DoSaveFile);
  FActSaveAs := NewAction(actSaveFileAs, 'Save &As...', @DoSaveFileAs);

  FActRunStatement := NewAction(actRunStatement, '&Run Statement', @DoRunStatement);
  FActRunScript := NewAction(actRunScript, 'Run as &Script', @DoRunScript);
  FActExplain := NewAction(actExplain, '&Explain Plan', @DoExplain);
  FActCancel := NewAction(actCancel, '&Cancel Query', @DoCancel);
  FActDescribe := NewAction(actDescribe, '&Describe Object at Cursor', @DoDescribe);
  FActHistory := NewAction(actHistory, 'SQL &History...', @DoHistory);
  FActOptions := NewAction('actOptions', '&Options...', @DoOptions);
  FActRefreshAll := NewAction('actRefreshAll', 'Refresh All', @DoRefreshAll);
  FActDbaSessions := NewAction('actDbaSessions', '&Sessions', @DoDbaSessions);
  FActDbaLocks := NewAction('actDbaLocks', '&Locks and Blocking', @DoDbaLocks);
  FActDbaUsers := NewAction('actDbaUsers', '&Users and Roles', @DoDbaUsers);
  FActDbaWhoCan := NewAction('actDbaWhoCan', '&Who Can Do What', @DoDbaWhoCan);
  FActDbaLog := NewAction('actDbaLog', 'Pagona DBA &Log', @DoDbaLog);

  FActCommit := NewAction('actCommit', 'Co&mmit', @DoCommit);
  FActRollback := NewAction('actRollback', 'Roll&back', @DoRollback);
  FActAutoCommit := NewAction('actAutoCommit', '&Auto-commit', @DoAutoCommit);
  FActDisconnect := NewAction('actDisconnect', '&Disconnect This Tab', @DoDisconnect);

  // Cut/Copy/Paste/Select All keep the editor's own keys
  FActCut := NewAction('actCut', 'Cu&t', @DoCut);
  FActCopy := NewAction('actCopy', '&Copy', @DoCopy);
  FActPaste := NewAction('actPaste', '&Paste', @DoPaste);
  FActSelectAll := NewAction('actSelectAll', 'Select &All', @DoSelectAll);
  FActComment := NewAction(actComment, 'Comme&nt Lines', @DoComment);
  FActUncomment := NewAction(actUncomment, 'Unc&omment Lines', @DoUncomment);
  FActToggleComment := NewAction(actToggleComment, '&Toggle Comment', @DoToggleComment);
  FActBlockComment := NewAction(actBlockComment, '&Block Comment /* */', @DoBlockComment);
  FActUpper := NewAction('actUpper', '&Uppercase', @DoUpper);
  FActLower := NewAction('actLower', '&Lowercase', @DoLower);
  FActIndent := NewAction('actIndent', '&Indent Lines', @DoIndent);
  FActOutdent := NewAction('actOutdent', 'Unindent Lines', @DoOutdent);
  FActFind := NewAction(actFind, '&Find...', @DoFind);
  FActFindNext := NewAction(actFindNext, 'Find &Next', @DoFindNext);
  FActReplace := NewAction(actReplace, '&Replace...', @DoReplace);
  FActSchemaBrowser := NewAction('actSchemaBrowser', 'Schema &Browser', @DoSchemaBrowser);
  FActShowEditor := NewAction('actShowEditor', '&Editor', @DoShowEditor);
  FActPending := NewAction('actPending', '&Transactions...', @DoPending);
  FActUndo := NewAction('actUndo', '&Undo', @DoUndo);
  FActRedo := NewAction('actRedo', '&Redo', @DoRedo);
  FActConnectOE := NewAction('actConnectOE', 'Connect Object E&xplorer...', @DoConnectOE);
  FActDisconnectOE := NewAction('actDisconnectOE', '&Disconnect Object Explorer', @DoDisconnectOE);
  FActConnectTab := NewAction('actConnectTab', '&Connect...', @DoChangeConn);
  FActChangeConn := NewAction('actChangeConn', 'C&hange Connection...', @DoChangeConn);
  FActOEFilter := NewAction('actOEFilter', '&Filter', @DoOEFilter);

  // Commit's drop arrow, as in Toad
  FCommitMenu := TPopupMenu.Create(Self);
  AddActionItem(FCommitMenu.Items, FActCommit);
  AddActionItem(FCommitMenu.Items, FActRollback);
  AddSeparator(FCommitMenu.Items);
  AddActionItem(FCommitMenu.Items, FActPending);

  ApplyActionCaptions;
end;

{ Toad's words in Amphibian, Pagona's elsewhere, for the same commands. }
procedure TpgnMainForm.ApplyActionCaptions;
begin
  // Pagona's words first; Seattle and Amphibian change some of them
  FActExplain.Caption := '&Explain Plan';
  FActComment.Caption := 'Comme&nt Lines';
  FActUncomment.Caption := 'Unc&omment Lines';
  FActUpper.Caption := '&Uppercase';
  FActLower.Caption := '&Lowercase';
  FActIndent.Caption := '&Indent Lines';
  FActOutdent.Caption := 'Unindent Lines';
  FActMoveTab.Caption := 'Side by Side';
  FActAutoCommit.Caption := '&Auto-commit';
  FActDbaUsers.Caption := '&Users and Roles';
  if FSea then
  begin
    // SSMS's words
    FActNewTab.Caption := '&New Query';
    FActCloseTab.Caption := '&Close';
    FActOpen.Caption := '&Open File...';
    FActRunScript.Caption := '&Execute';
    FActRunStatement.Caption := 'Execute Current &Statement';
    FActCancel.Caption := 'Cancel Executing &Query';
    FActExplain.Caption := 'Display Estimated E&xecution Plan';
    FActDescribe.Caption := '&Describe Object (sp_help)';
    FActHistory.Caption := 'Query &History...';
    FActDisconnect.Caption := '&Disconnect';
    FActDbaSessions.Caption := '&Activity Monitor';
    FActDbaLocks.Caption := '&Locks and Blocking';
    FActComment.Caption := 'Co&mment Selection';
    FActUncomment.Caption := '&Uncomment Selection';
    FActUpper.Caption := 'Make &Uppercase';
    FActLower.Caption := 'Make &Lowercase';
    FActIndent.Caption := '&Increase Indent';
    FActOutdent.Caption := '&Decrease Indent';
    FActMoveTab.Caption := 'New &Vertical Tab Group';
    FActAutoCommit.Caption := 'Auto-&commit';
    Exit;
  end;
  if FAmph then
  begin
    FActNewTab.Caption := '&New Editor';
    FActCloseTab.Caption := '&Close Editor Tab';
    FActOpen.Caption := '&Open File...';
    FActRunStatement.Caption := '&Execute Statement';
    FActRunScript.Caption := 'Execute as &Script';
    FActCancel.Caption := 'S&top Execution';
    FActDescribe.Caption := '&Describe';
    FActHistory.Caption := 'SQL &Recall...';
    FActDisconnect.Caption := '&End Connection';
    FActDbaSessions.Caption := '&Session Browser';
    FActDbaLocks.Caption := '&Locks';
  end
  else
  begin
    FActNewTab.Caption := 'New &Query Tab';
    FActCloseTab.Caption := '&Close Tab';
    FActOpen.Caption := '&Open SQL File...';
    FActRunStatement.Caption := '&Run Statement';
    FActRunScript.Caption := 'Run as &Script';
    FActCancel.Caption := '&Cancel Query';
    FActDescribe.Caption := '&Describe Object at Cursor';
    FActHistory.Caption := 'SQL &History...';
    FActDisconnect.Caption := '&Disconnect This Tab';
    FActDbaSessions.Caption := '&Sessions';
    FActDbaLocks.Caption := '&Locks and Blocking';
  end;
end;

function TpgnMainForm.AddMenu(AParent: TMenuItem; const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  AParent.Add(Result);
end;

procedure TpgnMainForm.AddActionItem(AParent: TMenuItem; AAction: TAction);
var
  Item: TMenuItem;
begin
  Item := TMenuItem.Create(Self);
  Item.Action := AAction;
  AParent.Add(Item);
end;

procedure TpgnMainForm.AddSeparator(AParent: TMenuItem);
begin
  AddMenu(AParent, '-');
end;

procedure TpgnMainForm.BuildMenu;
var
  M, KM, Item: TMenuItem;
  I: Integer;
begin
  FMainMenu := TMainMenu.Create(Self);
  Menu := FMainMenu;
  if FAmph then
  begin
    BuildAmphibianMenu;
    Exit;
  end;
  if FSea then
  begin
    BuildSeattleMenu;
    Exit;
  end;

  M := AddMenu(FMainMenu.Items, '&File');
  AddActionItem(M, FActNewTab);
  AddActionItem(M, FActOpen);
  AddActionItem(M, FActSave);
  AddActionItem(M, FActSaveAs);
  AddActionItem(M, FActCloseTab);
  AddSeparator(M);
  AddActionItem(M, FActExit);

  M := AddMenu(FMainMenu.Items, '&Edit');
  AddActionItem(M, FActCut);
  AddActionItem(M, FActCopy);
  AddActionItem(M, FActPaste);
  AddActionItem(M, FActSelectAll);
  AddSeparator(M);
  AddActionItem(M, FActComment);
  AddActionItem(M, FActUncomment);
  AddActionItem(M, FActToggleComment);
  AddActionItem(M, FActBlockComment);
  AddActionItem(M, FActUpper);
  AddActionItem(M, FActLower);
  AddSeparator(M);
  AddActionItem(M, FActFind);
  AddActionItem(M, FActFindNext);
  AddActionItem(M, FActReplace);
  AddSeparator(M);
  AddActionItem(M, FActOptions);

  M := AddMenu(FMainMenu.Items, '&Query');
  AddActionItem(M, FActRunStatement);
  AddActionItem(M, FActRunScript);
  AddActionItem(M, FActExplain);
  AddActionItem(M, FActCancel);
  AddSeparator(M);
  AddActionItem(M, FActDescribe);
  AddActionItem(M, FActHistory);

  // connections and transactions, the way Toad groups them
  M := AddMenu(FMainMenu.Items, '&Session');
  AddActionItem(M, FActNewConn);
  AddActionItem(M, FActEditConn);
  AddActionItem(M, FActDeleteConn);
  AddSeparator(M);
  AddActionItem(M, FActDisconnect);
  AddSeparator(M);
  AddActionItem(M, FActCommit);
  AddActionItem(M, FActRollback);
  AddActionItem(M, FActPending);
  AddActionItem(M, FActAutoCommit);

  M := AddMenu(FMainMenu.Items, '&View');
  AddActionItem(M, FActNextTab);
  AddActionItem(M, FActPrevTab);
  AddActionItem(M, FActMoveTab);
  AddActionItem(M, FActRenameTab);
  AddSeparator(M);
  AddActionItem(M, FActRefreshAll);
  AddSeparator(M);
  AddLayoutMenu(M);
  AddKeymapThemeMenus(M);

  // the DBA menu is there for everyone: look at anything; the database's
  // privileges decide what can be changed
  FDbaMenu := AddMenu(FMainMenu.Items, 'D&BA');
  AddActionItem(FDbaMenu, FActDbaSessions);
  AddActionItem(FDbaMenu, FActDbaLocks);
  AddActionItem(FDbaMenu, FActDbaUsers);
  AddActionItem(FDbaMenu, FActDbaWhoCan);
  AddSeparator(FDbaMenu);
  AddActionItem(FDbaMenu, FActDbaLog);

  M := AddMenu(FMainMenu.Items, '&Help');
  AddActionItem(M, FActAbout);
end;

{ Radio items for the Keymap and Look menus on Windows; check marks elsewhere
  (GTK checks a radio group's first item by itself and reports it as a
  click, and a separator splits the group). }
function MenuRadios: Boolean;
begin
  {$IFDEF WINDOWS}
  Result := True;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TpgnMainForm.AddKeymapThemeMenus(M: TMenuItem);
var
  KM, Item: TMenuItem;
  I: Integer;
begin
  KM := AddMenu(M, '&Keymap');
  // item 0 = Match layout, then one item per keymap; Tag = position
  SetLength(FKeymapItems, Length(KeymapNames) + 1);
  Item := AddMenu(KM, 'Match Layout');
  Item.RadioItem := MenuRadios;
  Item.GroupIndex := 1;
  Item.Tag := 0;
  Item.OnClick := @DoSelectKeymap;
  FKeymapItems[0] := Item;
  AddSeparator(KM);
  for I := 0 to High(KeymapNames) do
  begin
    Item := AddMenu(KM, KeymapNames[I]);
    Item.RadioItem := MenuRadios;
    Item.GroupIndex := 1;
    Item.Tag := I + 1;
    Item.OnClick := @DoSelectKeymap;
    FKeymapItems[I + 1] := Item;
  end;

  KM := AddMenu(M, 'L&ook');
  SetLength(FLookItems, Length(LookNames) + 1);
  Item := AddMenu(KM, 'Match Layout');
  Item.RadioItem := MenuRadios;
  Item.GroupIndex := 4;
  Item.Tag := 0;
  Item.OnClick := @DoSelectLook;
  FLookItems[0] := Item;
  AddSeparator(KM);
  for I := 0 to High(LookNames) do
  begin
    Item := AddMenu(KM, LookNames[I]);
    Item.RadioItem := MenuRadios;
    Item.GroupIndex := 4;
    Item.Tag := I + 1;
    Item.OnClick := @DoSelectLook;
    FLookItems[I + 1] := Item;
  end;

  KM := AddMenu(M, 'T&heme');
  SetLength(FThemeItems, Length(ThemeNames));
  for I := 0 to High(ThemeNames) do
  begin
    Item := AddMenu(KM, ThemeNames[I]);
    Item.RadioItem := True;
    Item.GroupIndex := 2;
    Item.Tag := I;
    Item.Checked := SameText(ThemeNames[I], FSettings.Theme);
    Item.OnClick := @DoSelectTheme;
    FThemeItems[I] := Item;
  end;
end;

{ The toolbar's buttons. Ids are what the saved arrangement uses, so they
  never change once released. }
procedure TpgnMainForm.BuildToolbar;
var
  Saved: string;
begin
  FToolBar := TpgnToolbar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := alTop;
  FToolBar.Height := Scale96ToScreen(40);
  if FAmph then
  begin
    // Toad's main toolbar: small icons, names in the tooltips
    FToolBar.IconOnly := True;
    FToolBar.Height := Scale96ToScreen(32);
    FToolBar.AddIconDef('neweditor', 'New Editor', FActNewTab, icEditor, isTwoTone);
    FToolBar.AddIconDef('schemabrowser', 'Schema Browser', FActSchemaBrowser, icSchema, isTwoTone);
    FToolBar.AddIconDef('newconn', 'New Connection', FActNewConn, icNewSession, isTwoTone);
    FToolBar.AddIconDef('endconn', 'End Connection', FActDisconnect, icEndSession, isTwoTone);
    FToolBar.AddIconDef('sessionbrowser', 'Session Browser', FActDbaSessions, icSessionBrowser, isTwoTone);
    FToolBar.AddIconDef('commit', 'Commit', FActCommit, icCommit, isTwoTone);
    FToolBar.AddIconDef('rollback', 'Rollback', FActRollback, icRollback, isTwoTone);
    FToolBar.AddIconDef('users', 'Users and Roles', FActDbaUsers, icUsers, isTwoTone);
    FToolBar.AddIconDef('locks', 'Locks', FActDbaLocks, icLocks, isTwoTone);
    FToolBar.AddIconDef('whocan', 'Who Can Do What', FActDbaWhoCan, icNone, isTwoTone);
    FToolBar.AddIconDef('refresh', 'Refresh All', FActRefreshAll, icNone, isTwoTone);
    FToolBar.SetDropMenu('commit', FCommitMenu);
    FToolBar.DefaultArrangement := DefaultToolbar(FSettings.Layout);
    Saved := FSettings.Toolbars.Values[FSettings.Layout];
    if Saved = '' then
    begin
      Saved := FToolBar.DefaultArrangement;
    end;
    FToolBar.SetArrangement(Saved);
    FToolBar.OnChanged := @ToolbarChanged;
    Exit;
  end;
  if FSea then
  begin
    // SSMS's Standard toolbar: small icons, New Query with its name
    FToolBar.IconOnly := True;
    FToolBar.Height := Scale96ToScreen(32);
    FToolBar.AddIconDef('open', 'Open File', FActOpen, icOpen, isTwoTone);
    FToolBar.AddIconDef('save', 'Save', FActSave, icSave, isTwoTone);
    FToolBar.AddIconDef('saveas', 'Save As', FActSaveAs, icSaveAs, isTwoTone);
    FToolBar.AddIconDef('newquery', 'New Query', FActNewTab, icNewQuery, isTwoTone, True);
    FToolBar.AddIconDef('undo', 'Undo', FActUndo, icUndo, isTwoTone);
    FToolBar.AddIconDef('redo', 'Redo', FActRedo, icRedo, isTwoTone);
    FToolBar.AddIconDef('activity', 'Activity Monitor', FActDbaSessions, icActivity, isTwoTone);
    FToolBar.AddIconDef('locks', 'Locks and Blocking', FActDbaLocks, icLocks, isTwoTone);
    FToolBar.AddIconDef('users', 'Users and Roles', FActDbaUsers, icUsers, isTwoTone);
    FToolBar.AddIconDef('refresh', 'Refresh All', FActRefreshAll, icRefresh, isTwoTone);
    FToolBar.DefaultArrangement := DefaultToolbar(FSettings.Layout);
    Saved := FSettings.Toolbars.Values[FSettings.Layout];
    if Saved = '' then
    begin
      Saved := FToolBar.DefaultArrangement;
    end;
    FToolBar.SetArrangement(Saved);
    FToolBar.OnChanged := @ToolbarChanged;
    Exit;
  end;
  FToolBar.AddDef('newtab', 'New Tab', FActNewTab, glPlus, bsFlat);
  FToolBar.AddDef('run', 'Run', FActRunStatement, glRun, bsPrimary);
  FToolBar.AddDef('script', 'Run Script', FActRunScript, glScript, bsFlat);
  FToolBar.AddDef('cancel', 'Cancel', FActCancel, glStop, bsFlat);
  FToolBar.AddDef('commit', 'Commit', FActCommit, glCommit, bsOutline);
  FToolBar.AddDef('rollback', 'Rollback', FActRollback, glRollback, bsOutline);
  FToolBar.AddDef('explain', 'Explain', FActExplain, glExplain, bsFlat);
  FToolBar.AddDef('describe', 'Describe', FActDescribe, glDescribe, bsFlat);
  FToolBar.AddDef('comment', 'Comment', FActComment, glComment, bsFlat);
  FToolBar.AddDef('uncomment', 'Uncomment', FActUncomment, glUncomment, bsFlat);
  FToolBar.AddDef('open', 'Open', FActOpen, glNone, bsFlat);
  FToolBar.AddDef('save', 'Save', FActSave, glNone, bsFlat);
  FToolBar.AddDef('history', 'History', FActHistory, glNone, bsFlat);
  FToolBar.AddDef('togglecomment', 'Toggle Comment', FActToggleComment, glComment, bsFlat);
  FToolBar.AddDef('upper', 'Uppercase', FActUpper, glNone, bsFlat);
  FToolBar.AddDef('lower', 'Lowercase', FActLower, glNone, bsFlat);
  FToolBar.AddDef('refresh', 'Refresh All', FActRefreshAll, glNone, bsFlat);
  FToolBar.AddDef('newconn', 'New Connection', FActNewConn, glNone, bsFlat);
  // offered only in DBA Mode
  FToolBar.AddDef('dbasessions', 'Sessions', FActDbaSessions, glSessions, bsFlat);
  FToolBar.AddDef('dbalocks', 'Locks', FActDbaLocks, glLock, bsFlat);
  FToolBar.AddDef('dbausers', 'Users', FActDbaUsers, glUsers, bsFlat);
  FToolBar.AddDef('dbawhocan', 'Who Can', FActDbaWhoCan, glNone, bsFlat);
  FToolBar.SetDropMenu('commit', FCommitMenu);
  FToolBar.DefaultArrangement := DefaultToolbar(FSettings.Layout);
  Saved := FSettings.Toolbars.Values[FSettings.Layout];
  if Saved = '' then
  begin
    Saved := FToolBar.DefaultArrangement;
  end;
  FToolBar.SetArrangement(Saved);
  FToolBar.OnChanged := @ToolbarChanged;
end;

function TpgnMainForm.DefaultToolbar(const ALayout: string): string;
begin
  if SameText(ALayout, LayoutAmphibian) then
  begin
    Result := 'neweditor,schemabrowser,|,newconn,endconn,|,sessionbrowser,|,commit,rollback,|,users,locks';
  end
  else if SameText(ALayout, LayoutAmphibian + '.Editor') then
  begin
    Result := 'open,save,saveas,|,run,script,stop,|,explain,describe,recall,|,comment,uncomment,|,' +
      'upper,lower,|,indent,outdent,|,find';
  end
  else if SameText(ALayout, LayoutSeattle) then
  begin
    Result := 'open,save,|,newquery,|,undo,redo,|,activity';
  end
  else if SameText(ALayout, LayoutSeattle + '.Editor') then
  begin
    Result := 'execute,stop,|,explain,|,comment,uncomment,|,outdent,indent';
  end
  else
  begin
    Result := 'newtab,|,run,script,cancel,|,commit,rollback,|,explain,describe,|,comment,uncomment';
  end;
end;

procedure TpgnMainForm.ToolbarChanged(Sender: TObject);
begin
  FSettings.Toolbars.Values[FSettings.Layout] := FToolBar.Arrangement;
  FSettings.Save;
end;

procedure TpgnMainForm.BuildLayout;
var
  Header, DetailsPanel: TPanel;
  L: TLabel;
  B: TButton;
  Splitter: TSplitter;
  DP: TpgnDetailsPage;
begin
  BuildToolbar;

  // 0 environment + connection + server   1 transaction (red when work
  // is waiting for Commit)   2 rows and time, messages   3 caret
  FStatus := TpgnStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.SetSegments([300, 290, 0, 130]);
  FStatus.OnSegmentClick := @StatusSegmentClick;

  // Explorer
  FExplorerPanel := TPanel.Create(Self);
  FExplorerPanel.Parent := Self;
  FExplorerPanel.Align := alLeft;
  FExplorerPanel.Width := 290;
  FExplorerPanel.BevelOuter := bvNone;

  Header := TPanel.Create(Self);
  FExplorerHeader := Header;
  Header.Parent := FExplorerPanel;
  Header.Align := alTop;
  Header.Height := 32;
  Header.BevelOuter := bvNone;

  L := TLabel.Create(Self);
  FExplorerTitle := L;
  L.Parent := Header;
  L.Caption := 'Explorer';
  L.Font.Style := [fsBold];
  L.Align := alLeft;
  L.Layout := tlCenter;
  L.BorderSpacing.Left := 6;

  B := TButton.Create(Self);
  FExplorerRefresh := B;
  B.Parent := Header;
  B.Action := FActRefreshAll;
  B.AutoSize := True;
  B.Align := alRight;
  B.BorderSpacing.Around := 3;

  // filter: instant over what the tree has loaded, then the databases
  FFilterEdit := TEdit.Create(Self);
  FFilterEdit.Parent := FExplorerPanel;
  FFilterEdit.Align := alTop;
  FFilterEdit.Top := Header.Top + Header.Height + 1;
  FFilterEdit.TextHint := 'Filter objects...';
  FFilterEdit.OnChange := @FilterChange;
  FFilterEdit.OnKeyDown := @FilterKeyDown;

  FFilterTimer := TTimer.Create(Self);
  FFilterTimer.Enabled := False;
  FFilterTimer.Interval := 350;
  FFilterTimer.OnTimer := @FilterTimerTick;

  // Details: columns and indexes of what's selected in the Explorer
  DetailsPanel := TPanel.Create(Self);
  FDetailsPanel := DetailsPanel;
  DetailsPanel.Parent := FExplorerPanel;
  DetailsPanel.Align := alBottom;
  DetailsPanel.Height := Scale96ToScreen(240);
  DetailsPanel.BevelOuter := bvNone;
  DetailsPanel.Caption := '';

  FDetailsLabel := TLabel.Create(Self);
  FDetailsLabel.Parent := DetailsPanel;
  // fixed sizes: labels that size themselves can make the layout loop
  FDetailsLabel.AutoSize := False;
  FDetailsLabel.Align := alTop;
  FDetailsLabel.Height := Scale96ToScreen(24);
  FDetailsLabel.Layout := tlCenter;
  FDetailsLabel.Font.Style := [fsBold];
  FDetailsLabel.Caption := 'Details';

  // a strip of tabs over one shared area: which tabs it has depends on the
  // kind of object shown (GTK3 mixes up pages when sheets are hidden)
  FDetailsTabs := TTabControl.Create(Self);
  FDetailsTabs.Parent := DetailsPanel;
  FDetailsTabs.Align := alTop;
  FDetailsTabs.Top := FDetailsLabel.Top + FDetailsLabel.Height;
  FDetailsTabs.Height := Scale96ToScreen(30);
  FDetailsTabs.OnChange := @DetailsTabChange;

  FDetailsColumns := TpgnResultGrid.Create(Self);
  FDetailsIndexes := TpgnResultGrid.Create(Self);
  FDetailsTriggers := TpgnResultGrid.Create(Self);
  FDetailsTriggers.Options := FDetailsTriggers.Options + [goRowSelect];
  FDetailsTriggers.OnDblClick := @DetailsTriggersDblClick;
  FDetailsParams := TpgnResultGrid.Create(Self);
  FDetailsHighlighter := TSynSQLSyn.Create(Self);
  FDetailsHighlighter.SQLDialect := sqlMySQL;
  ApplyEditorTheme(FDetailsHighlighter, FSettings.Theme);
  FDetailsDefinition := TSynEdit.Create(Self);
  SmoothFont(FDetailsDefinition.Font);
  FDetailsDefinition.ReadOnly := True;
  FDetailsDefinition.Highlighter := FDetailsHighlighter;
  FDetailsDefinition.Gutter.Visible := False;
  FDetailsDefinition.RightEdge := -1;
  FDetailsDefinition.Options := FDetailsDefinition.Options - [eoScrollPastEol];
  FDetailsDefinition.Lines.Clear;
  FDetailsGrants := TpgnResultGrid.Create(Self);
  FDetailsArea[dpColumns] := FDetailsColumns;
  FDetailsArea[dpIndexes] := FDetailsIndexes;
  FDetailsArea[dpTriggers] := FDetailsTriggers;
  FDetailsArea[dpParameters] := FDetailsParams;
  FDetailsArea[dpDefinition] := FDetailsDefinition;
  FDetailsArea[dpGrants] := FDetailsGrants;
  // the page in view is sized by hand: GTK3 doesn't re-lay out aligned
  // controls that are shown and hidden in turn
  FDetailsBody := TPanel.Create(Self);
  FDetailsBody.Parent := DetailsPanel;
  FDetailsBody.Align := alClient;
  FDetailsBody.BevelOuter := bvNone;
  FDetailsBody.Caption := '';
  FDetailsBody.OnResize := @DetailsBodyResize;
  for DP := Low(TpgnDetailsPage) to High(TpgnDetailsPage) do
  begin
    FDetailsArea[DP].Parent := FDetailsBody;
    FDetailsArea[DP].Align := alNone;
  end;
  FDetailsConn := -1;
  SetDetailsPages([dpColumns, dpIndexes, dpTriggers, dpGrants]);

  Splitter := TSplitter.Create(Self);
  FDetailsSplitter := Splitter;
  Splitter.Parent := FExplorerPanel;
  Splitter.Align := alBottom;
  Splitter.Top := DetailsPanel.Top - 1;

  FDetailsTimer := TTimer.Create(Self);
  FDetailsTimer.Enabled := False;
  FDetailsTimer.Interval := 250;
  FDetailsTimer.OnTimer := @DetailsTimerTick;

  FFoundNote := TLabel.Create(Self);
  FFoundNote.Parent := FExplorerPanel;
  FFoundNote.AutoSize := False;
  FFoundNote.Align := alBottom;
  FFoundNote.Height := Scale96ToScreen(36);
  FFoundNote.WordWrap := True;
  FFoundNote.Font.Color := clPgnMuted;
  FFoundNote.Visible := False;

  FFoundList := TpgnResultGrid.Create(Self);
  FFoundList.Parent := FExplorerPanel;
  FFoundList.Align := alClient;
  FFoundList.Options := FFoundList.Options + [goRowSelect];
  FFoundList.Visible := False;
  FFoundList.OnSelection := @FoundSelect;
  FFoundList.OnDblClick := @FoundDblClick;
  FFoundList.OnKeyDown := @FoundKeyDown;

  FTree := TTreeView.Create(Self);
  FTree.Parent := FExplorerPanel;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnExpanding := @TreeExpanding;
  FTree.OnDblClick := @TreeDblClick;
  FTree.OnMouseDown := @TreeMouseDown;
  FTree.OnChange := @TreeChange;

  if not FAmph then
  begin
    FExplorerSplitter := TSplitter.Create(Self);
    FExplorerSplitter.Parent := Self;
    FExplorerSplitter.Align := alLeft;
    FExplorerSplitter.Left := FExplorerPanel.Left + FExplorerPanel.Width + 1;
  end;

  // tab area: left group always; right group appears for split view
  FTabArea := TPanel.Create(Self);
  FTabArea.Parent := Self;
  FTabArea.Align := alClient;
  FTabArea.BevelOuter := bvNone;
  if FAmph then
  begin
    BuildAmphibianArea;
  end;
  if FSea then
  begin
    BuildSeattleArea;
  end;

  FRightPages := NewPageCtrl(alRight);
  FRightPages.Width := 500;
  FRightPages.Visible := False;

  FTabSplitter := TSplitter.Create(Self);
  FTabSplitter.Parent := FTabArea;
  FTabSplitter.Align := alRight;
  FTabSplitter.Visible := False;

  FLeftPages := NewPageCtrl(alClient);
end;

procedure TpgnMainForm.BuildPopupMenus;
var
  Root: TMenuItem;
begin
  FEditorMenu := TPopupMenu.Create(Self);
  Root := FEditorMenu.Items;
  AddActionItem(Root, FActRunStatement);
  AddActionItem(Root, FActRunScript);
  AddActionItem(Root, FActExplain);
  AddSeparator(Root);
  AddActionItem(Root, FActCut);
  AddActionItem(Root, FActCopy);
  AddActionItem(Root, FActPaste);
  AddActionItem(Root, FActSelectAll);
  AddSeparator(Root);
  AddActionItem(Root, FActComment);
  AddActionItem(Root, FActUncomment);
  AddActionItem(Root, FActToggleComment);
  AddActionItem(Root, FActBlockComment);
  AddActionItem(Root, FActUpper);
  AddActionItem(Root, FActLower);
  AddSeparator(Root);
  AddActionItem(Root, FActDescribe);

  FTabMenu := TPopupMenu.Create(Self);
  FTabMenu.OnPopup := @TabMenuPopup;
  AddActionItem(FTabMenu.Items, FActNewTab);
  AddActionItem(FTabMenu.Items, FActCloseTab);
  AddActionItem(FTabMenu.Items, FActRenameTab);
  AddSeparator(FTabMenu.Items);
  AddActionItem(FTabMenu.Items, FActMoveTab);
  FLeftPages.PopupMenu := FTabMenu;
  FRightPages.PopupMenu := FTabMenu;

  FTreeMenu := TPopupMenu.Create(Self);
  FTreeMenu.OnPopup := @TreeMenuPopup;
  FTree.PopupMenu := FTreeMenu;
end;

{ ------------------------------------------------------------- helpers }

procedure TpgnMainForm.ApplyKeysToEditor(AEditor: TSynEdit);
var
  I, J: Integer;
  A: TCustomAction;

  procedure RemoveKey(AShortCut: TShortCut);
  var
    Idx: Integer;
  begin
    if AShortCut = 0 then
    begin
      Exit;
    end;
    // so the editor never swallows a key that belongs to a Pagona command
    Idx := AEditor.Keystrokes.FindShortcut(AShortCut);
    while Idx >= 0 do
    begin
      AEditor.Keystrokes.Delete(Idx);
      Idx := AEditor.Keystrokes.FindShortcut(AShortCut);
    end;
  end;

  procedure AddChord(AKey2: Word; ACommand: TSynEditorCommand);
  var
    K: TSynEditKeyStroke;
  begin
    K := AEditor.Keystrokes.Add;
    try
      // second key first, so the editor never sees a half-made Ctrl+K entry
      K.Key2 := AKey2;
      K.Shift2 := [];
      K.ShiftMask2 := [ssCtrl];   // Ctrl+K then C, or Ctrl+K then Ctrl+C
      K.Key := VK_K;
      K.Shift := [ssCtrl];
      K.Command := ACommand;
    except
      K.Free;
    end;
  end;

begin
  AEditor.Keystrokes.ResetDefaults;
  for I := 0 to FActions.ActionCount - 1 do
  begin
    if FActions.Actions[I] is TCustomAction then
    begin
      A := TCustomAction(FActions.Actions[I]);
      RemoveKey(A.ShortCut);
      for J := 0 to A.SecondaryShortCuts.Count - 1 do
      begin
        RemoveKey(A.SecondaryShortCuts.ShortCuts[J]);
      end;
    end;
  end;

  // Seattle's two-key comment shortcuts. The editor handles the pair itself
  // (it waits for the second key after Ctrl+K), which a menu shortcut can't.
  if SameText(FKeymap, KeymapSeattle) then
  begin
    RemoveKey(ShortCut(VK_K, [ssCtrl]));
    AddChord(VK_C, ecPgnComment);
    AddChord(VK_U, ecPgnUncomment);
  end;
  AEditor.OnProcessUserCommand := @EditorUserCommand;
  AEditor.OnKeyDown := @EditorKeyDown;
end;

{ Shows in the status bar that Ctrl+K is waiting for its second key. It only
  watches; the editor itself decides what the keys do. }
procedure TpgnMainForm.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not SameText(FKeymap, KeymapSeattle) then
  begin
    Exit;
  end;
  if (Key = VK_CONTROL) or (Key = VK_SHIFT) or (Key = VK_MENU)
    or (Key = VK_LCONTROL) or (Key = VK_RCONTROL) then
  begin
    Exit;
  end;
  if (Key = VK_K) and (Shift = [ssCtrl]) then
  begin
    FStatus.Texts[2] := 'Ctrl+K: C comments, U uncomments';
    FChordShown := True;
  end
  else if FChordShown then
  begin
    FStatus.Texts[2] := '';
    FChordShown := False;
  end;
end;

procedure TpgnMainForm.ApplyCurrentKeymap;
const
  LayoutNames: array[0..2] of string = (LayoutPlume, LayoutAmphibian, LayoutSeattle);
var
  I: Integer;
begin
  // radio items get their check here, once the menu exists (GTK checks the
  // first one of a group when it builds it)
  FUpdatingChecks := True;
  try
    for I := 0 to High(FLayoutItems) do
    begin
      FLayoutItems[I].Checked := SameText(LayoutNames[I], FSettings.Layout);
    end;
  finally
    FUpdatingChecks := False;
  end;
  FKeymap := EffectiveKeymap(FSettings.Keymap, FSettings.Layout);
  if FChordShown or (Pos('Ctrl+K', FStatus.Texts[2]) = 1) then
  begin
    FStatus.Texts[2] := '';   // no leftover Ctrl+K hint after switching
  end;
  FChordShown := False;
  ApplyKeymap(FActions, FKeymap);
  for I := 0 to TabCount - 1 do
  begin
    ApplyKeysToEditor(TabAt(I).Editor);
  end;
  FUpdatingChecks := True;
  try
  FLookItems[0].Checked := not (SameText(FSettings.Look, LookPlume) or
    SameText(FSettings.Look, LookAmphibian) or SameText(FSettings.Look, LookSeattle));
  for I := 0 to High(LookNames) do
  begin
    FLookItems[I + 1].Checked := SameText(LookNames[I], FSettings.Look);
  end;
  FKeymapItems[0].Checked := SameText(FSettings.Keymap, KeymapMatchLayout);
  for I := 0 to High(KeymapNames) do
  begin
    FKeymapItems[I + 1].Checked := SameText(KeymapNames[I], FSettings.Keymap);
  end;
  finally
    FUpdatingChecks := False;
  end;
end;

procedure TpgnMainForm.UpdateActionStates;
var
  T: TpgnQueryTab;
  Connected, Running, Manual, HasConn, Others: Boolean;
  I, Waiting: Integer;
begin
  T := FActiveTab;
  Connected := (T <> nil) and T.IsConnected;
  Running := (T <> nil) and T.IsRunning;
  Manual := Connected and not T.Adapter.AutoCommit;
  HasConn := FStore.Count > 0;

  FActEditConn.Enabled := HasConn;
  FActDeleteConn.Enabled := HasConn;
  FActCloseTab.Enabled := T <> nil;
  FActRenameTab.Enabled := T <> nil;
  FActSave.Enabled := T <> nil;
  FActSaveAs.Enabled := T <> nil;
  FActMoveTab.Enabled := (T <> nil) and
    ((FLeftPages.PageCount > 1) or (FRightPages.PageCount > 0));
  // checked = the tabs are side by side; choosing it again puts them back
  FActMoveTab.Checked := FRightPages.PageCount > 0;
  FActResGrid.Enabled := (T <> nil) and FSea;
  FActResText.Enabled := FActResGrid.Enabled;
  FActResFile.Enabled := FActResGrid.Enabled;
  // GTK reports a check set from code as a click: ignore those
  FUpdatingChecks := True;
  try
    FActResGrid.Checked := (T <> nil) and (T.ResultsMode = 0);
    FActResText.Checked := (T <> nil) and (T.ResultsMode = 1);
    FActResFile.Checked := (T <> nil) and (T.ResultsMode = 2);
  finally
    FUpdatingChecks := False;
  end;
  FActRunStatement.Enabled := Connected and not Running;
  FActRunScript.Enabled := Connected and not Running;
  FActExplain.Enabled := Connected and not Running;
  FActDescribe.Enabled := Connected and not Running;
  FActCancel.Enabled := Running;
  // pending work in any tab keeps Commit and its menu reachable
  Others := FirstPendingTab <> nil;
  FActCommit.Enabled := (Manual and not Running) or Others;
  FActRollback.Enabled := (Manual and not Running) or Others;
  FActHistory.Enabled := FHistory.Count > 0;
  FActAutoCommit.Enabled := Connected and not Running;
  FActAutoCommit.Checked := Connected and T.Adapter.AutoCommit;
  FActDisconnect.Enabled := Connected and not Running;
  Waiting := 0;
  for I := 0 to TabCount - 1 do
  begin
    if TabAt(I).IsConnected then
    begin
      Waiting := Waiting + TabAt(I).PendingCount;
    end;
  end;
  FActPending.Enabled := Waiting > 0;
  if Waiting > 0 then
  begin
    FActPending.Caption := '&Transactions (' + IntToStr(Waiting) + ' waiting)...';
  end
  else
  begin
    FActPending.Caption := '&Transactions...';
  end;
  if FTxShown and (FTxPanel <> nil) then
  begin
    FTxPanel.FocusTab := T;   // the active tab is ticked when it gets new work
    FTxPanel.Reload;
  end;
  FActFind.Enabled := T <> nil;
  FActFindNext.Enabled := T <> nil;
  FActReplace.Enabled := T <> nil;
  FActIndent.Enabled := T <> nil;
  FActOutdent.Enabled := T <> nil;
  FActUndo.Enabled := (T <> nil) and T.Editor.CanUndo;
  FActRedo.Enabled := (T <> nil) and T.Editor.CanRedo;
  FActConnectTab.Enabled := (T <> nil) and not Connected and (T.DbaScreen = dsNone) and not Running;
  FActChangeConn.Enabled := (T <> nil) and (T.DbaScreen = dsNone) and not T.IsRoutine and not Running;
  I := ExplorerIndexOfNode(FTree.Selected);
  FActDisconnectOE.Enabled := (I >= 0) and (FExplorer[I].Adapter <> nil);
  if FSea then
  begin
    SyncSeattleRoots;
  end;
  if FOEBar <> nil then
  begin
    FOEBar.Invalidate;
  end;
  if FSqlLeft <> nil then
  begin
    FSqlLeft.Invalidate;
  end;
  FToolBar.Invalidate;
  if FEditorBar <> nil then
  begin
    FEditorBar.Invalidate;
  end;
end;

procedure TpgnMainForm.RefreshStatus;
var
  T: TpgnQueryTab;
  Ver: string;
begin
  T := FActiveTab;
  if (T <> nil) and T.IsConnected then
  begin
    Ver := T.Adapter.ServerVersion;
    // panel 0 is drawn with the environment label in front
    FStatus.Texts[0] := T.Info.Name + ' ' + #$C2#$B7 + ' ' +
      Trim(EngineCaptions[T.Info.Engine] + ' ' + Ver);
    if T.Adapter.AutoCommit then
    begin
      FStatus.Texts[1] := 'Auto-commit on';
    end
    else if (T.PendingCount = 0) and (FirstPendingTab <> nil) then
    begin
      // this tab is clear, but work waits elsewhere
      FStatus.Texts[1] := 'Nothing pending here ' + #$C2#$B7 + ' ' + IntToStr(FirstPendingTab.PendingCount) +
        ' waiting in ' + FirstPendingTab.Title;
    end
    else if T.PendingCount = 0 then
    begin
      FStatus.Texts[1] := 'Auto-commit OFF ' + #$C2#$B7 + ' nothing pending';
    end
    else if T.PendingCount = 1 then
    begin
      FStatus.Texts[1] := '1 uncommitted statement';
    end
    else
    begin
      FStatus.Texts[1] := IntToStr(T.PendingCount) + ' uncommitted statements';
    end;
    if T.CurrentDb <> '' then
    begin
      Caption := 'Pagona - ' + T.Info.Name + ' / ' + T.CurrentDb;
    end
    else
    begin
      Caption := 'Pagona - ' + T.Info.Name;
    end;
  end
  else
  begin
    FStatus.Texts[0] := 'Not connected';
    FStatus.Texts[1] := '';
    Caption := 'Pagona';
  end;
  if FAmph then
  begin
    // Toad's title: USER@DB - Pagona - [Editor (Query 1)]
    if FBrowserShown and (FBrowser.ConnIndex >= 0) then
    begin
      Caption := FBrowser.Info.User + '@' + FBrowser.Info.Name + ' - Pagona - [Schema Browser]';
    end
    else if (T <> nil) and T.IsConnected then
    begin
      Caption := T.Info.User + '@' + T.Info.Name + ' - Pagona - [Editor (' + T.Title + ')]';
    end
    else if T <> nil then
    begin
      Caption := 'Pagona - [Editor (' + T.Title + ')]';
    end;
  end;
  if FSea then
  begin
    // SSMS's title, and "Ready" below: the query status bar has the rest
    if T <> nil then
    begin
      Caption := T.FullTitle + ' - Pagona';
    end;
    FStatus.Texts[0] := 'Ready';
    if not FChordShown then
    begin
      FStatus.Texts[2] := '';
    end;
    FStatus.Texts[3] := '';
    FStatus.Env := enNone;
    FStatus.Warn := (T <> nil) and T.IsConnected and (T.PendingCount > 0);
    Exit;
  end;
  if not FChordShown then
  begin
    if T <> nil then
    begin
      FStatus.Texts[2] := T.StatusText;
    end
    else
    begin
      FStatus.Texts[2] := '';
    end;
  end;
  if T <> nil then
  begin
    FStatus.Texts[3] := T.CaretText;
  end
  else
  begin
    FStatus.Texts[3] := '';
  end;
  if (T <> nil) and T.IsConnected then
  begin
    FStatus.Env := T.Info.Environment;
    FStatus.Warn := T.PendingCount > 0;
  end
  else
  begin
    FStatus.Env := enNone;
    FStatus.Warn := False;
  end;
end;

procedure TpgnMainForm.TabCaretMoved(Sender: TObject);
begin
  if (Sender = FActiveTab) and not FSea then
  begin
    FStatus.Texts[3] := FActiveTab.CaretText;
  end;
end;

procedure TpgnMainForm.ShowError(const AWhat: string; E: Exception);
begin
  MessageDlg(AWhat + LineEnding + LineEnding + E.Message, mtError, [mbOK], 0);
end;

{ ---------------------------------------------- passwords and sessions }

procedure TpgnMainForm.RememberPassword(const AId, APassword: string);
begin
  ForgetPassword(AId);
  FPasswords.Add(AId + '=' + APassword);
end;

procedure TpgnMainForm.ForgetPassword(const AId: string);
var
  Idx: Integer;
begin
  Idx := FPasswords.IndexOfName(AId);
  if Idx >= 0 then
  begin
    FPasswords.Delete(Idx);
  end;
end;

{ Opens a new session. Uses the password remembered for this connection
  if there is one; otherwise asks, and remembers it once it works. }
function TpgnMainForm.ConnectAdapter(const AInfo: TpgnConnectionInfo): TpgnAdapter;
var
  Pwd: string;
  HaveCached: Boolean;
  A: TpgnAdapter;
  Attempt: Integer;
begin
  Result := nil;
  // SQL Server with Windows Authentication: no password to ask for
  if (AInfo.Engine = feSQLServer) and AInfo.WindowsAuth then
  begin
    A := CreateAdapter(AInfo, '');
    Screen.Cursor := crHourGlass;
    try
      try
        A.Connect;
        Result := A;
      except
        on E: Exception do
        begin
          A.Free;
          Screen.Cursor := crDefault;
          ShowError('Could not connect to ' + ConnectionLongLabel(AInfo), E);
        end;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
    Exit;
  end;
  HaveCached := FPasswords.IndexOfName(AInfo.Id) >= 0;
  if HaveCached then
  begin
    Pwd := FPasswords.Values[AInfo.Id];
  end
  else
  begin
    Pwd := '';
  end;

  for Attempt := 1 to 2 do
  begin
    if not HaveCached then
    begin
      if not InputQuery('Connect to ' + ConnectionLongLabel(AInfo),
        'Password for ' + AInfo.User + '@' + PasswordWhere(AInfo) + ':', True, Pwd) then
      begin
        Exit;
      end;
    end;

    A := CreateAdapter(AInfo, Pwd);
    Screen.Cursor := crHourGlass;
    try
      try
        A.Connect;
        RememberPassword(AInfo.Id, Pwd);
        Result := A;
        Exit;
      except
        on E: Exception do
        begin
          A.Free;
          if HaveCached then
          begin
            // the remembered password stopped working: ask again
            ForgetPassword(AInfo.Id);
            HaveCached := False;
            Pwd := '';
          end
          else
          begin
            Screen.Cursor := crDefault;
            ShowError('Could not connect to ' + ConnectionLongLabel(AInfo), E);
            Exit;
          end;
        end;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
  end;
end;

{ ---------------------------------------------------------------- tabs }

function TpgnMainForm.TabCount: Integer;
begin
  Result := FLeftPages.PageCount + FRightPages.PageCount;
end;

function TpgnMainForm.TabAt(AIndex: Integer): TpgnQueryTab;
begin
  if AIndex < FLeftPages.PageCount then
  begin
    Result := TabOfPage(FLeftPages.Page[AIndex]);
  end
  else
  begin
    Result := TabOfPage(FRightPages.Page[AIndex - FLeftPages.PageCount]);
  end;
end;

function TpgnMainForm.TabOfPage(APage: TExtPage): TpgnQueryTab;
var
  I: Integer;
begin
  Result := nil;
  if APage = nil then
  begin
    Exit;
  end;
  for I := 0 to APage.ControlCount - 1 do
  begin
    if APage.Controls[I] is TpgnQueryTab then
    begin
      Result := TpgnQueryTab(APage.Controls[I]);
      Exit;
    end;
  end;
end;

function TpgnMainForm.PageOfTab(ATab: TpgnQueryTab): TExtPage;
begin
  Result := ATab.Parent as TExtPage;
end;

function TpgnMainForm.GroupOfTab(ATab: TpgnQueryTab): TExtPageCtrl;
begin
  if FRightPages.IndexOfPage(PageOfTab(ATab)) >= 0 then
  begin
    Result := FRightPages;
  end
  else
  begin
    Result := FLeftPages;
  end;
end;

{ A tab group: Pagona draws its own tabs (ExtTabCtrls), so they look the
  same on Windows and Linux, with close buttons, "+", middle-click close
  and drag to reorder. }
function TpgnMainForm.NewPageCtrl(AAlign: TAlign): TExtPageCtrl;
begin
  Result := TExtPageCtrl.Create(Self);
  Result.Parent := FTabArea;
  Result.Align := AAlign;
  Result.TabStyle := etsChrome;
  // the tab shortens its caption by bytes, which can cut a character in two;
  // the query tab shortens its own caption instead. The minimum goes to 0
  // first: newer ExtTabCtrls keep the maximum at or above the minimum
  // (5), which cut every caption to "P...1"
  Result.MinCaptionLen := 0;
  Result.MaxCaptionLen := 0;
  // no etoGetFocus: clicking a tab should leave the focus in its editor
  Result.TabOptions := [etoActivateNewTab, etoShowCloseButton, etoShowAddButton,
    etoCloseOnMiddleClick, etoAllowDragReorder, etoActiveBold];
  Result.OnTabChanged := @PagesChanged;
  Result.OnTabDeleting := @PagesTabDeleting;
  Result.OnAddButtonClick := @PagesAddClick;
  TExtPageCtrlAccess(Result).OnMouseDown := @PagesMouseDown;
end;

{ Deletes a page whose tab has already been freed or moved elsewhere. }
procedure TpgnMainForm.RemovePage(AGroup: TExtPageCtrl; APage: TExtPage);
var
  Idx: Integer;
begin
  Idx := AGroup.IndexOfPage(APage);
  if Idx < 0 then
  begin
    Exit;
  end;
  FDeletingPage := True;
  try
    AGroup.DeletePage(Idx);
  finally
    FDeletingPage := False;
  end;
end;

function TpgnMainForm.NewTab(const ATitle: string): TpgnQueryTab;
var
  Group: TExtPageCtrl;
  Page: TExtPage;
  T: string;
begin
  // open next to the active tab, in the same group
  Group := FLeftPages;
  if FActiveTab <> nil then
  begin
    Group := GroupOfTab(FActiveTab);
  end;

  Inc(FTabCounter);
  T := ATitle;
  if (T = '') and FSea then
  begin
    T := 'SQLQuery' + IntToStr(FTabCounter) + '.sql';
  end
  else if T = '' then
  begin
    T := 'Query ' + IntToStr(FTabCounter);
  end;

  Page := Group.AddPage(T);
  // owned by the form, not the page, so a tab can move between groups
  Result := TpgnQueryTab.CreateTab(Self, FStore, FSettings, FHistory, @ConnectAdapter, T);
  Result.Parent := Page;
  Result.Align := alClient;
  Result.OnStateChanged := @TabStateChanged;
  Result.OnActivate := @TabActivated;
  Result.OnSchemaChanged := @TabSchemaChanged;
  Result.OnCaretMoved := @TabCaretMoved;
  Result.OnReviewPending := @TabReviewPending;
  Result.Editor.PopupMenu := FEditorMenu;
  ApplyKeysToEditor(Result.Editor);
  Page.Tab.Caption := Result.DisplayCaption;
  Group.PageIndex := Group.IndexOfPage(Page);
  UpdateSplit;
  if FAmph and FBrowserShown then
  begin
    ShowEditorWindow;
  end;
  SetActiveTab(Result);
  Result.FocusEditor;
end;

{ A new tab already connected (no extra prompt: the password is remembered).
  Returns nil, and closes the tab, if the connection can't be opened. }
function TpgnMainForm.NewTabOn(const AInfo: TpgnConnectionInfo; const ADatabase, ATitle: string;
  const ASchema: string): TpgnQueryTab;
begin
  Result := NewTab(ATitle);
  if not Result.ConnectTo(AInfo, ADatabase) then
  begin
    CloseTab(Result);
    Result := nil;
    Exit;
  end;
  if ASchema <> '' then
  begin
    Result.SetSchema(ASchema);
  end;
end;

procedure TpgnMainForm.CloseTab(ATab: TpgnQueryTab);
var
  Group: TExtPageCtrl;
  Page: TExtPage;
begin
  if ATab = nil then
  begin
    Exit;
  end;
  if not ConfirmCloseTab(ATab, 'closing the tab') then
  begin
    Exit;
  end;

  Page := PageOfTab(ATab);
  Group := GroupOfTab(ATab);
  if FActiveTab = ATab then
  begin
    FActiveTab := nil;
  end;
  ATab.Free;   // closes its session
  RemovePage(Group, Page);

  if TabCount = 0 then
  begin
    UpdateSplit;
    NewTab('');   // always keep one tab open
    Exit;
  end;
  if Group.PageCount = 0 then
  begin
    Group := FLeftPages;
    if Group.PageCount = 0 then
    begin
      Group := FRightPages;
    end;
  end;
  UpdateSplit;
  SetActiveTab(TabOfPage(Group.ActivePage));
  if FActiveTab <> nil then
  begin
    FActiveTab.FocusEditor;
  end;
end;

{ Everything that must be settled before a tab goes away: a running query,
  uncommitted changes, unsaved SQL. False if the user cancels. }
function TpgnMainForm.ConfirmCloseTab(ATab: TpgnQueryTab; const AReason: string): Boolean;
var
  Answer: TModalResult;
begin
  Result := False;
  if ATab.IsRunning then
  begin
    MessageDlg('A query is still running in "' + ATab.Title + '". Cancel it first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  if not ATab.ResolvePendingWork(AReason) then
  begin
    Exit;
  end;
  if ATab.IsModified then
  begin
    Answer := MessageDlg('Save changes to "' + ATab.Title + '"?' + LineEnding + LineEnding +
      'Yes = Save, No = Don''t save', mtConfirmation, [mbYes, mbNo, mbCancel], 0);
    if Answer = mrCancel then
    begin
      Exit;
    end;
    if Answer = mrYes then
    begin
      if not SaveTab(ATab, False) then
      begin
        Exit;
      end;
    end;
  end;
  Result := True;
end;

{ Saves a tab; asks for a file name if it has none (or AAskName). }
function TpgnMainForm.SaveTab(ATab: TpgnQueryTab; AAskName: Boolean): Boolean;
var
  D: TSaveDialog;
  SaveName: string;
begin
  Result := False;
  if ATab = nil then
  begin
    Exit;
  end;
  SaveName := ATab.FileName;
  if AAskName or (SaveName = '') then
  begin
    D := TSaveDialog.Create(Self);
    try
      D.Title := 'Save SQL';
      D.Filter := 'SQL files (*.sql)|*.sql|All files|*';
      D.DefaultExt := 'sql';
      D.Options := D.Options + [ofOverwritePrompt];
      if SaveName <> '' then
      begin
        D.InitialDir := ExtractFileDir(SaveName);
        D.FileName := ExtractFileName(SaveName);
      end
      else
      begin
        D.InitialDir := FLastDir;
      end;
      if not D.Execute then
      begin
        Exit;
      end;
      SaveName := D.FileName;
    finally
      D.Free;
    end;
  end;
  try
    ATab.SaveToFile(SaveName);
    FLastDir := ExtractFileDir(SaveName);
    Result := True;
  except
    on E: Exception do
    begin
      ShowError('Could not save ' + SaveName, E);
    end;
  end;
end;

{ The close button and middle-click ask to delete a tab. Pagona says no
  and closes it its own way (with the save / commit questions) right after
  the click is finished. }
procedure TpgnMainForm.PagesTabDeleting(Sender: TObject; Index: Integer; var Allow: Boolean);
var
  Group: TExtPageCtrl;
begin
  if FDeletingPage then
  begin
    Allow := True;
    Exit;
  end;
  Allow := False;
  Group := Sender as TExtPageCtrl;
  if (Index >= 0) and (Index < Group.PageCount) then
  begin
    Application.QueueAsyncCall(@AsyncCloseTab, PtrInt(TabOfPage(Group.Page[Index])));
  end;
end;

procedure TpgnMainForm.PagesAddClick(Sender: TObject);
var
  Group: TExtPageCtrl;
  T: TpgnQueryTab;
begin
  // the new tab goes in the group whose "+" was clicked
  Group := Sender as TExtPageCtrl;
  if Group.PageCount > 0 then
  begin
    T := TabOfPage(Group.ActivePage);
    if T <> nil then
    begin
      SetActiveTab(T);
    end;
  end;
  DoNewTab(Self);
end;

procedure TpgnMainForm.AsyncCloseTab(AData: PtrInt);
var
  I: Integer;
begin
  // only if that tab still exists
  for I := 0 to TabCount - 1 do
  begin
    if PtrInt(TabAt(I)) = AData then
    begin
      CloseTab(TabAt(I));
      Exit;
    end;
  end;
end;

{ Moves a tab to the other group: "Split Right" from the left, back from the right. }
procedure TpgnMainForm.MoveTab(ATab: TpgnQueryTab);
var
  FromGroup, ToGroup: TExtPageCtrl;
  OldPage, NewPage: TExtPage;
  Want, I: Integer;
  T: TpgnQueryTab;
begin
  if ATab = nil then
  begin
    Exit;
  end;
  FromGroup := GroupOfTab(ATab);
  if FromGroup = FLeftPages then
  begin
    if FLeftPages.PageCount < 2 then
    begin
      Exit;   // keep at least one tab on the left
    end;
    ToGroup := FRightPages;
    if not FRightPages.Visible then
    begin
      FRightPages.Width := FTabArea.ClientWidth div 2;
    end;
  end
  else
  begin
    ToGroup := FLeftPages;
  end;

  OldPage := PageOfTab(ATab);
  // where the tab sits in the overall order decides where it lands, so
  // moving over and back keeps every tab's place
  SyncTabOrder;
  NewPage := ToGroup.AddPage(ATab.Title);
  ATab.Parent := NewPage;          // the tab and its session move as they are
  NewPage.Tab.Caption := ATab.DisplayCaption;
  RemovePage(FromGroup, OldPage);
  Want := 0;
  for I := 0 to ToGroup.PageCount - 1 do
  begin
    T := TabOfPage(ToGroup.Page[I]);
    if (T <> nil) and (T <> ATab) and (FTabOrder.IndexOf(T) < FTabOrder.IndexOf(ATab)) then
    begin
      Inc(Want);
    end;
  end;
  if Want > ToGroup.PageCount - 1 then
  begin
    Want := ToGroup.PageCount - 1;
  end;
  if ToGroup.IndexOfPage(NewPage) <> Want then
  begin
    ToGroup.MovePage(ToGroup.IndexOfPage(NewPage), Want);
  end;
  ToGroup.PageIndex := ToGroup.IndexOfPage(NewPage);
  UpdateSplit;
  SetActiveTab(ATab);
  ATab.FocusEditor;
end;

{ Brings the overall tab order up to date: closed tabs out, new ones in,
  and each group's tabs in the slots they hold, in the order the group
  shows them (they may have been dragged). }
procedure TpgnMainForm.SyncTabOrder;
var
  I, K, G: Integer;
  T: TpgnQueryTab;
  Group: TExtPageCtrl;
  Slots, Shown: TList;
begin
  for I := FTabOrder.Count - 1 downto 0 do
  begin
    K := -1;
    for G := 0 to TabCount - 1 do
    begin
      if Pointer(TabAt(G)) = FTabOrder[I] then
      begin
        K := G;
      end;
    end;
    if K < 0 then
    begin
      FTabOrder.Delete(I);
    end;
  end;
  for I := 0 to TabCount - 1 do
  begin
    if FTabOrder.IndexOf(TabAt(I)) < 0 then
    begin
      FTabOrder.Add(TabAt(I));
    end;
  end;
  Slots := TList.Create;
  Shown := TList.Create;
  try
    for G := 0 to 1 do
    begin
      if G = 0 then
      begin
        Group := FLeftPages;
      end
      else
      begin
        Group := FRightPages;
      end;
      Slots.Clear;
      Shown.Clear;
      for I := 0 to Group.PageCount - 1 do
      begin
        T := TabOfPage(Group.Page[I]);
        if T <> nil then
        begin
          Shown.Add(T);
        end;
      end;
      for I := 0 to FTabOrder.Count - 1 do
      begin
        if Shown.IndexOf(FTabOrder[I]) >= 0 then
        begin
          Slots.Add(Pointer(PtrInt(I)));
        end;
      end;
      for I := 0 to Slots.Count - 1 do
      begin
        FTabOrder[PtrInt(Slots[I])] := Shown[I];
      end;
    end;
  finally
    Slots.Free;
    Shown.Free;
  end;
end;

procedure TpgnMainForm.UpdateSplit;
var
  Split: Boolean;
begin
  Split := FRightPages.PageCount > 0;
  FRightPages.Visible := Split;
  FTabSplitter.Visible := Split;
  if Split then
  begin
    FTabSplitter.Left := FRightPages.Left - 1;
  end;
end;

procedure TpgnMainForm.SetActiveTab(ATab: TpgnQueryTab);
begin
  FActiveTab := ATab;
  if FAmph and (ATab <> nil) and ATab.IsConnected then
  begin
    FLastTabOf.Values[ATab.Info.Id] := IntToStr(PtrUInt(ATab));
  end;
  RefreshStatus;
  UpdateActionStates;
  if FSea then
  begin
    MirrorTimerTick(nil);
  end;
  if FAmph then
  begin
    UpdateAmphBars;
    MirrorTimerTick(nil);
  end;
end;

procedure TpgnMainForm.TabStateChanged(Sender: TObject);
var
  T: TpgnQueryTab;
begin
  T := Sender as TpgnQueryTab;
  if T.Parent is TExtPage then
  begin
    TExtPage(T.Parent).Tab.Caption := T.DisplayCaption;
  end;
  if T = FActiveTab then
  begin
    RefreshStatus;
  end;
  // other tabs' pending work counts for Commit and its menu too
  UpdateActionStates;
  if FAmph then
  begin
    if (T = FActiveTab) and T.IsConnected then
    begin
      FLastTabOf.Values[T.Info.Id] := IntToStr(PtrUInt(T));
    end;
    UpdateAmphBars;
  end;
end;

procedure TpgnMainForm.TabActivated(Sender: TObject);
begin
  if Sender <> FActiveTab then
  begin
    SetActiveTab(Sender as TpgnQueryTab);
  end;
end;

procedure TpgnMainForm.PagesChanged(Sender: TObject; NewIndex: Integer);
var
  Group: TExtPageCtrl;
  T: TpgnQueryTab;
begin
  Group := Sender as TExtPageCtrl;
  if (NewIndex < 0) or (NewIndex >= Group.PageCount) then
  begin
    Exit;
  end;
  T := TabOfPage(Group.Page[NewIndex]);
  if T <> nil then
  begin
    SetActiveTab(T);
    T.FocusEditor;
  end;
end;

procedure TpgnMainForm.PagesMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Group: TExtPageCtrl;
  Idx: Integer;
begin
  Group := Sender as TExtPageCtrl;
  // right-clicking a tab selects it, so the menu acts on the tab clicked
  if Button = mbRight then
  begin
    Idx := TExtPageCtrlAccess(Group).TabAtPos(X, Y);
    if (Idx >= 0) and (Idx <> Group.PageIndex) then
    begin
      Group.PageIndex := Idx;
    end;
  end;
end;

procedure TpgnMainForm.SelectAdjacentTab(AForward: Boolean);
var
  Group: TExtPageCtrl;
  Idx: Integer;
begin
  if FActiveTab = nil then
  begin
    Exit;
  end;
  Group := GroupOfTab(FActiveTab);
  if Group.PageCount < 2 then
  begin
    Exit;
  end;
  Idx := Group.PageIndex;
  if AForward then
  begin
    Idx := (Idx + 1) mod Group.PageCount;
  end
  else
  begin
    Idx := (Idx + Group.PageCount - 1) mod Group.PageCount;
  end;
  Group.PageIndex := Idx;
  PagesChanged(Group, Idx);
end;

procedure TpgnMainForm.TabMenuPopup(Sender: TObject);
begin
  UpdateActionStates;
end;

{ After CREATE / DROP / ALTER / RENAME: update the Explorer and the
  database lists of other tabs on the same connection. }
procedure TpgnMainForm.TabSchemaChanged(Sender: TObject; const AConnectionId: string;
  AChange: TpgnSchemaChange; const ASQL: string);
var
  Idx, I: Integer;
  T: TpgnQueryTab;
  Err: string;
begin
  Idx := ExplorerIndexOfId(AConnectionId);
  FDetailsShown := '';   // read the Details again next time
  if (Idx >= 0) and (FExplorer[Idx].Adapter <> nil) then
  begin
    Err := RefreshConnection(Idx, ASQL, False);
    if Err = '' then
    begin
      (Sender as TpgnQueryTab).Log('Explorer updated');
    end
    else
    begin
      (Sender as TpgnQueryTab).Log('Explorer could not update: ' + Err);
    end;
  end;
  if AChange = scDatabases then
  begin
    for I := 0 to TabCount - 1 do
    begin
      T := TabAt(I);
      if (T <> Sender) and T.IsConnected and (T.Info.Id = AConnectionId) and not T.IsRunning then
      begin
        T.ReloadDatabaseList;
      end;
    end;
  end;
end;

{ ----------------------------------------------------------- explorer }

function TpgnMainForm.KindToPtr(AKind: TpgnNodeKind): Pointer;
begin
  Result := Pointer(PtrUInt(Ord(AKind)));
end;

{ Table, View, Procedure, Function or Trigger: the words the filter list
  and the Details panel use. }
{ "calc_hours(integer, text)" -> "calc_hours", for tab titles. }
function RoutineShortName(const AName: string): string;
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

function NodeObjectKindCaption(AKind: TpgnNodeKind): string;
begin
  case AKind of
    nkView:
      begin
        Result := 'View';
      end;
    nkMatView:
      begin
        Result := 'Materialized View';
      end;
    nkProcedure:
      begin
        Result := 'Procedure';
      end;
    nkFunction:
      begin
        Result := 'Function';
      end;
    nkTrigger:
      begin
        Result := 'Trigger';
      end;
    nkIndex:
      begin
        Result := 'Index';
      end;
    nkOther:
      begin
        Result := 'Object';
      end;
  else
    begin
      Result := 'Table';
    end;
  end;
end;

function TpgnMainForm.NodeKind(ANode: TTreeNode): TpgnNodeKind;
begin
  Result := TpgnNodeKind(PtrUInt(ANode.Data));
end;

function TpgnMainForm.AddNode(AParent: TTreeNode; const AText: string; AKind: TpgnNodeKind;
  AHasChildren: Boolean): TTreeNode;
var
  Child: TTreeNode;
begin
  if AParent = nil then
  begin
    Result := FTree.Items.Add(nil, AText);
  end
  else
  begin
    Result := FTree.Items.AddChild(AParent, AText);
  end;
  Result.Data := KindToPtr(AKind);
  if AHasChildren then
  begin
    // placeholder child: real children load on first expand
    Child := FTree.Items.AddChild(Result, 'loading...');
    Child.Data := KindToPtr(nkPlaceholder);
  end;
end;

function TpgnMainForm.InsertSortedNode(AParent: TTreeNode; const AText: string;
  AKind: TpgnNodeKind): TTreeNode;
var
  Sibling, Child: TTreeNode;
begin
  Sibling := AParent.GetFirstChild;
  while (Sibling <> nil) and (CompareText(Sibling.Text, AText) < 0) do
  begin
    Sibling := Sibling.GetNextSibling;
  end;
  if Sibling = nil then
  begin
    Result := FTree.Items.AddChild(AParent, AText);
  end
  else
  begin
    Result := FTree.Items.Insert(Sibling, AText);
  end;
  Result.Data := KindToPtr(AKind);
  if not (AKind in LeafKinds) then
  begin
    Child := FTree.Items.AddChild(Result, 'loading...');
    Child.Data := KindToPtr(nkPlaceholder);
  end;
end;

function TpgnMainForm.ChildrenLoaded(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Count > 0) and (NodeKind(ANode.GetFirstChild) <> nkPlaceholder);
end;

{ Drops a node's loaded children so they reload; re-expands if it was open. }
procedure TpgnMainForm.ResetNode(ANode: TTreeNode);
var
  WasExpanded: Boolean;
  Child: TTreeNode;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  WasExpanded := ANode.Expanded;
  FTree.Items.BeginUpdate;
  try
    ANode.Collapse(False);
    ANode.DeleteChildren;
    Child := FTree.Items.AddChild(ANode, 'loading...');
    Child.Data := KindToPtr(nkPlaceholder);
  finally
    FTree.Items.EndUpdate;
  end;
  if WasExpanded then
  begin
    ANode.Expand(False);
  end;
end;

{ Makes a loaded node's children match ANames: removes what's gone, adds
  what's new, and leaves everything else (and its expansion) alone. }
procedure TpgnMainForm.ReconcileChildren(AParent: TTreeNode; const ANames: TpgnStringArray;
  AKind: TpgnNodeKind);
var
  Child, NextChild: TTreeNode;
  I: Integer;
  Found: Boolean;
begin
  // no children at all means loaded and empty (unloaded nodes hold a placeholder)
  if (AParent.Count > 0) and not ChildrenLoaded(AParent) then
  begin
    Exit;
  end;
  FTree.Items.BeginUpdate;
  try
    Child := AParent.GetFirstChild;
    while Child <> nil do
    begin
      NextChild := Child.GetNextSibling;
      Found := False;
      for I := 0 to High(ANames) do
      begin
        if ANames[I] = Child.Text then
        begin
          Found := True;
          Break;
        end;
      end;
      if not Found then
      begin
        Child.Delete;
      end;
      Child := NextChild;
    end;

    for I := 0 to High(ANames) do
    begin
      Found := False;
      Child := AParent.GetFirstChild;
      while Child <> nil do
      begin
        if Child.Text = ANames[I] then
        begin
          Found := True;
          Break;
        end;
        Child := Child.GetNextSibling;
      end;
      if not Found then
      begin
        InsertSortedNode(AParent, ANames[I], AKind);
      end;
    end;
    SetFolderCount(AParent);
  finally
    FTree.Items.EndUpdate;
  end;
end;

function TpgnMainForm.ExplorerIndexOfNode(ANode: TTreeNode): Integer;
var
  Root: TTreeNode;
  I: Integer;
begin
  Result := -1;
  if ANode = nil then
  begin
    Exit;
  end;
  Root := ANode;
  while Root.Parent <> nil do
  begin
    Root := Root.Parent;
  end;
  for I := 0 to High(FExplorer) do
  begin
    if FExplorer[I].Root = Root then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TpgnMainForm.ExplorerIndexOfId(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FExplorer) do
  begin
    if FExplorer[I].Info.Id = AId then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

{ The connection of the selected Explorer node, or of the active tab. }
function TpgnMainForm.SelectedExplorerIndex: Integer;
begin
  Result := ExplorerIndexOfNode(FTree.Selected);
  if (Result < 0) and (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    Result := ExplorerIndexOfId(FActiveTab.Info.Id);
  end;
end;

function TpgnMainForm.EnsureExplorerConnected(AIndex: Integer): Boolean;
begin
  if FExplorer[AIndex].Adapter = nil then
  begin
    FExplorer[AIndex].Adapter := ConnectAdapter(FExplorer[AIndex].Info);
  end;
  Result := FExplorer[AIndex].Adapter <> nil;
end;

procedure TpgnMainForm.DisconnectExplorer(AIndex: Integer);
var
  Root: TTreeNode;
  Child: TTreeNode;
begin
  if (FBrowser <> nil) and (FBrowser.ConnIndex = AIndex) then
  begin
    FBrowser.Detach;
  end;
  FreeSessions(AIndex);
  if FExplorer[AIndex].Adapter <> nil then
  begin
    try
      FExplorer[AIndex].Adapter.Disconnect;
    except
      on E: Exception do
      begin
        // going away either way
      end;
    end;
    FreeAndNil(FExplorer[AIndex].Adapter);
  end;
  // back to a collapsed, unloaded node (no re-expand, which would reconnect)
  Root := FExplorer[AIndex].Root;
  FTree.Items.BeginUpdate;
  try
    Root.Collapse(True);
    Root.DeleteChildren;
    Child := FTree.Items.AddChild(Root, 'loading...');
    Child.Data := KindToPtr(nkPlaceholder);
  finally
    FTree.Items.EndUpdate;
  end;
  if FSea then
  begin
    SyncSeattleRoots;
  end;
end;

procedure TpgnMainForm.AddExplorerRoot(const AInfo: TpgnConnectionInfo);
var
  N: Integer;
begin
  N := Length(FExplorer);
  SetLength(FExplorer, N + 1);
  FExplorer[N].Info := AInfo;
  FExplorer[N].Adapter := nil;
  FExplorer[N].Sessions := TStringList.Create;
  FExplorer[N].Sessions.CaseSensitive := True;   // PostgreSQL names are
  FExplorer[N].Root := AddNode(nil, ConnectionLabel(AInfo), nkConnection, True);
end;

procedure TpgnMainForm.BuildExplorer;
var
  I: Integer;
begin
  if FBrowser <> nil then
  begin
    FBrowser.Detach;
  end;
  FTree.Items.Clear;
  FExplorer := nil;
  for I := 0 to FStore.Count - 1 do
  begin
    AddExplorerRoot(FStore.Items[I]);
  end;
end;

{ Brings a connection's loaded nodes up to date with the server. With
  AAllColumns, reloads every open column list; otherwise only those of
  tables named in ASQLHint (after an ALTER). }
function TpgnMainForm.RefreshConnection(AIndex: Integer; const ASQLHint: string; AAllColumns: Boolean): string;
begin
  Result := '';
  if FExplorer[AIndex].Adapter = nil then
  begin
    Exit;
  end;
  FRefreshError := '';
  Screen.Cursor := crHourGlass;
  try
    RefreshNode(AIndex, FExplorer[AIndex].Root, UpperCase(ASQLHint), AAllColumns);
  finally
    Screen.Cursor := crDefault;
  end;
  Result := FRefreshError;
  if Result <> '' then
  begin
    FStatus.Texts[2] := 'Refresh failed: ' + Result;
  end;
end;

{ Brings a loaded part of the tree up to date: what's gone goes, what's new
  comes, and what's still there (with its expansion) stays. Columns are
  only re-read for the tables AHintUpper names, unless AAllColumns. }
procedure TpgnMainForm.RefreshNode(AIndex: Integer; ANode: TTreeNode; const AHintUpper: string;
  AAllColumns: Boolean);
var
  Names: TpgnStringArray;
  ChildKind: TpgnNodeKind;
  HasKids, Skip: Boolean;
  Child, NextChild: TTreeNode;
  K: TpgnNodeKind;
  A: TpgnAdapter;
begin
  K := NodeKind(ANode);
  try
    if K = nkConnection then
    begin
      if not ChildrenLoaded(ANode) then
      begin
        Exit;
      end;
      A := FExplorer[AIndex].Adapter;
      if not A.SessionPerDatabase then
      begin
        ReconcileChildren(ANode, A.ListDatabases, nkDatabase);
      end;
    end
    else if K in RelationKinds then
    begin
      // columns straight under the table: read again when the SQL names it
      if ChildrenLoaded(ANode) and (NodeKind(ANode.GetFirstChild) = nkColumn) then
      begin
        if AAllColumns or (Pos(UpperCase(ANode.Text), AHintUpper) > 0) then
        begin
          ResetNode(ANode);
        end;
        Exit;
      end;
    end
    else if (K in FolderKinds) and ((ANode.Count = 0) or ChildrenLoaded(ANode)) then
    begin
      Skip := (K in [nkFolderColumns, nkFolderIndexes]) and not AAllColumns and
        (Pos(UpperCase(TableOf(ANode)), AHintUpper) = 0);
      if not Skip and FolderContents(ANode, Names, ChildKind, HasKids) then
      begin
        ReconcileChildren(ANode, Names, ChildKind);
      end;
    end;
  except
    on E: Exception do
    begin
      if FRefreshError = '' then
      begin
        FRefreshError := E.Message;
      end;
      Exit;
    end;
  end;

  Child := ANode.GetFirstChild;
  while Child <> nil do
  begin
    NextChild := Child.GetNextSibling;
    if ChildrenLoaded(Child) or ((Child.Count = 0) and (NodeKind(Child) in FolderKinds)) then
    begin
      RefreshNode(AIndex, Child, AHintUpper, AAllColumns);
    end;
    Child := NextChild;
  end;
end;

function TpgnMainForm.DatabaseOf(ANode: TTreeNode): string;
var
  N: TTreeNode;
begin
  Result := '';
  N := ANode;
  while N <> nil do
  begin
    if NodeKind(N) = nkDatabase then
    begin
      Result := N.Text;
      Exit;
    end;
    N := N.Parent;
  end;
end;

{ The schema a node sits in (PostgreSQL); '' on engines without schemas. }
function TpgnMainForm.SchemaOf(ANode: TTreeNode): string;
var
  N: TTreeNode;
begin
  Result := '';
  N := ANode;
  while N <> nil do
  begin
    if NodeKind(N) = nkSchema then
    begin
      Result := N.Text;
      Exit;
    end;
    N := N.Parent;
  end;
end;

{ What holds the node's objects, as the adapter wants it: the schema in
  PostgreSQL, the database in MySQL. }
function TpgnMainForm.ContainerOf(ANode: TTreeNode): string;
begin
  Result := SchemaOf(ANode);
  if Result = '' then
  begin
    Result := DatabaseOf(ANode);
  end;
end;

{ The table, view or materialized view a node belongs to (itself, or the
  one above its Columns / Indexes / Triggers folder). }
function TpgnMainForm.TableOf(ANode: TTreeNode): string;
var
  N: TTreeNode;
begin
  Result := '';
  N := ANode;
  while N <> nil do
  begin
    if NodeKind(N) in RelationKinds then
    begin
      Result := N.Text;
      Exit;
    end;
    N := N.Parent;
  end;
end;

{ A folder's name without its count: "Tables (12)" -> "Tables". }
function TpgnMainForm.FolderBase(ANode: TTreeNode): string;
var
  P: Integer;
begin
  Result := ANode.Text;
  if (Result <> '') and (Result[Length(Result)] = ')') then
  begin
    P := Length(Result);
    while (P > 1) and (Result[P] <> '(') do
    begin
      Dec(P);
    end;
    if (P > 2) and (Result[P - 1] = ' ') then
    begin
      Result := Copy(Result, 1, P - 2);
    end;
  end;
end;

procedure TpgnMainForm.SetFolderCount(ANode: TTreeNode);
begin
  if NodeKind(ANode) in FolderKinds then
  begin
    ANode.Text := FolderBase(ANode) + ' (' + IntToStr(ANode.Count) + ')';
  end;
end;

{ The session that answers for a database: the connection's own, or for
  engines with a session per database (PostgreSQL) one opened for it on
  first use and kept until the connection is closed. }
function TpgnMainForm.AdapterFor(AIndex: Integer; const ADatabase: string): TpgnAdapter;
var
  I: Integer;
  A: TpgnAdapter;
begin
  A := FExplorer[AIndex].Adapter;
  Result := A;
  if (A = nil) or not A.SessionPerDatabase or (ADatabase = '') or (ADatabase = A.CurrentDatabase) then
  begin
    Exit;
  end;
  I := FExplorer[AIndex].Sessions.IndexOf(ADatabase);
  if I >= 0 then
  begin
    Result := TpgnAdapter(FExplorer[AIndex].Sessions.Objects[I]);
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    Result := A.NewSession(ADatabase);
  finally
    Screen.Cursor := crDefault;
  end;
  FExplorer[AIndex].Sessions.AddObject(ADatabase, Result);
end;

function TpgnMainForm.NodeAdapter(ANode: TTreeNode): TpgnAdapter;
begin
  Result := AdapterFor(ExplorerIndexOfNode(ANode), DatabaseOf(ANode));
end;

procedure TpgnMainForm.FreeSessions(AIndex: Integer);
var
  I: Integer;
  A: TpgnAdapter;
begin
  if FExplorer[AIndex].Sessions = nil then
  begin
    Exit;
  end;
  for I := 0 to FExplorer[AIndex].Sessions.Count - 1 do
  begin
    A := TpgnAdapter(FExplorer[AIndex].Sessions.Objects[I]);
    try
      A.Disconnect;
    except
      on E: Exception do
      begin
        // going away either way
      end;
    end;
    A.Free;
  end;
  FExplorer[AIndex].Sessions.Clear;
end;

{ Everything a node stands for, as the filter and Details use it. }
function TpgnMainForm.RefOfNode(ANode: TTreeNode): TpgnObjectRef;
begin
  Result.Database := DatabaseOf(ANode);
  Result.Schema := SchemaOf(ANode);
  Result.Name := ObjectNameOf(ANode);
  Result.Kind := NodeObjectKindCaption(NodeKind(ANode));
  if NodeKind(ANode) = nkOther then
  begin
    Result.Kind := 'Other:' + FolderBase(ANode.Parent);
  end
  else if (NodeKind(ANode) = nkFunction) and (ANode.Parent <> nil) and
    (NodeKind(ANode.Parent) = nkFolderTrigFuncs) then
  begin
    Result.Kind := 'Trigger Function';
  end;
end;

procedure TpgnMainForm.AddExtraFolders(ANode: TTreeNode; AAdapter: TpgnAdapter; ALevel: TpgnFolderLevel);
var
  Extra: TpgnStringArray;
  I: Integer;
  More: TTreeNode;
begin
  Extra := AAdapter.ExtraFolders(ALevel, False);
  for I := 0 to High(Extra) do
  begin
    AddNode(ANode, Extra[I], nkFolderOther, True);
  end;
  // the rarely used ones, together in one folder to keep the tree clean
  Extra := AAdapter.ExtraFolders(ALevel, True);
  if Length(Extra) > 0 then
  begin
    More := AddNode(ANode, 'More', nkFolderMore, False);
    for I := 0 to High(Extra) do
    begin
      AddNode(More, Extra[I], nkFolderOther, True);
    end;
  end;
end;

{ The folders of whatever holds tables and code: a MySQL database or a
  PostgreSQL schema. }
procedure TpgnMainForm.AddContainerFolders(ANode: TTreeNode; AAdapter: TpgnAdapter);
begin
  AddNode(ANode, 'Tables', nkFolderTables, True);
  AddNode(ANode, 'Views', nkFolderViews, True);
  if AAdapter.HasSchemas then
  begin
    AddNode(ANode, 'Materialized Views', nkFolderMatViews, True);
    AddNode(ANode, 'Functions', nkFolderFuncs, True);
    AddNode(ANode, 'Procedures', nkFolderProcs, True);
    if AAdapter.Dialect = sdPostgreSQL then
    begin
      AddNode(ANode, 'Trigger Functions', nkFolderTrigFuncs, True);
    end
    else
    begin
      AddNode(ANode, 'Triggers', nkFolderTriggers, True);
    end;
  end
  else
  begin
    AddNode(ANode, 'Procedures', nkFolderProcs, True);
    AddNode(ANode, 'Functions', nkFolderFuncs, True);
    AddNode(ANode, 'Triggers', nkFolderTriggers, True);
  end;
  AddExtraFolders(ANode, AAdapter, flSchema);
end;

{ What a folder (or a table without folders) holds: names, their kind, and
  whether they open further. False if the node isn't one of these. }
function TpgnMainForm.FolderContents(ANode: TTreeNode; out ANames: TpgnStringArray;
  out AChildKind: TpgnNodeKind; out AHasChildren: Boolean): Boolean;
var
  A: TpgnAdapter;
  C, T: string;
  R: TpgnResultSet;
  I: Integer;

  procedure FromResult(AWithType: Boolean);
  var
    J: Integer;
  begin
    try
      SetLength(ANames, R.RowCount);
      for J := 0 to R.RowCount - 1 do
      begin
        if AWithType then
        begin
          ANames[J] := R.Rows[J].Values[0] + '  ' + R.Rows[J].Values[1];
        end
        else
        begin
          ANames[J] := R.Rows[J].Values[0];
        end;
      end;
    finally
      R.Free;
    end;
  end;

begin
  Result := True;
  ANames := nil;
  AChildKind := nkOther;
  AHasChildren := False;
  A := NodeAdapter(ANode);
  C := ContainerOf(ANode);
  case NodeKind(ANode) of
    nkFolderDatabases:
      begin
        ANames := A.ListDatabases;
        AChildKind := nkDatabase;
        AHasChildren := True;
      end;
    nkFolderSchemas:
      begin
        ANames := A.ListSchemas(False);
        AChildKind := nkSchema;
        AHasChildren := True;
      end;
    nkFolderCatalogs:
      begin
        ANames := A.ListSchemas(True);
        AChildKind := nkSchema;
        AHasChildren := True;
      end;
    nkFolderTables:
      begin
        ANames := A.ListObjects(C, okTable);
        AChildKind := nkTable;
        AHasChildren := True;
      end;
    nkFolderViews:
      begin
        ANames := A.ListObjects(C, okView);
        AChildKind := nkView;
        AHasChildren := True;
      end;
    nkFolderMatViews:
      begin
        ANames := A.ListObjects(C, okMatView);
        AChildKind := nkMatView;
        AHasChildren := True;
      end;
    nkFolderProcs:
      begin
        ANames := A.ListRoutines(C, rkProcedure);
        AChildKind := nkProcedure;
      end;
    nkFolderFuncs:
      begin
        ANames := A.ListRoutines(C, rkFunction);
        AChildKind := nkFunction;
      end;
    nkFolderTriggers:
      begin
        ANames := A.ListRoutines(C, rkTrigger);
        AChildKind := nkTrigger;
      end;
    nkFolderTrigFuncs:
      begin
        ANames := A.ListFolder(C, 'Trigger Functions');
        AChildKind := nkFunction;
      end;
    nkFolderColumns, nkTable, nkView, nkMatView:
      begin
        R := A.DescribeTable(C, TableOf(ANode));
        FromResult(True);
        AChildKind := nkColumn;
      end;
    nkFolderIndexes:
      begin
        R := A.DescribeIndexes(C, TableOf(ANode));
        if R = nil then
        begin
          Exit;
        end;
        FromResult(False);
        AChildKind := nkIndex;
      end;
    nkFolderTableTriggers:
      begin
        T := TableOf(ANode);
        R := A.DescribeTriggers(C, T);
        if R = nil then
        begin
          Exit;
        end;
        FromResult(False);
        AChildKind := nkTrigger;
      end;
    nkFolderOther:
      begin
        ANames := A.ListFolder(C, FolderBase(ANode));
        AChildKind := nkOther;
      end;
  else
    begin
      Result := False;
    end;
  end;
  // one row per column in some index listings: each name once
  if AChildKind = nkIndex then
  begin
    for I := High(ANames) downto 1 do
    begin
      if ANames[I] = ANames[I - 1] then
      begin
        Delete(ANames, I, 1);
      end;
    end;
  end;
end;

{ A DBA screen in a tab of its own, on the active tab's connection (or
  the one selected in the Explorer). }
procedure TpgnMainForm.OpenDbaScreen(AScreen: TpgnDbaScreen; const AKind, AContainer, AName: string;
  AConnIndex: Integer);
var
  Info: TpgnConnectionInfo;
  Db: string;
  Idx: Integer;
  T: TpgnQueryTab;
begin
  // the connection selected in the Explorer when that's where you are,
  // else the active tab's
  Idx := AConnIndex;   // the Explorer's right-click menu says which
  if (Idx < 0) and FTree.Focused then
  begin
    Idx := ExplorerIndexOfNode(FTree.Selected);
  end;
  if (Idx < 0) and (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    Info := FActiveTab.Info;
    Db := FActiveTab.CurrentDb;
  end
  else
  begin
    if Idx < 0 then
    begin
      Idx := ExplorerIndexOfNode(FTree.Selected);
    end;
    if Idx < 0 then
    begin
      MessageDlg('Choose a connection first: select it in the Explorer, or open a tab on it.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    Info := FExplorer[Idx].Info;
    Db := DatabaseOf(FTree.Selected);
  end;
  T := NewTabOn(Info, Db, '');
  if T <> nil then
  begin
    T.OnOpenAccount := @TabOpenAccount;
    T.OpenScreen(AScreen);
    if AScreen = dsWhoCan then
    begin
      if AKind <> '' then
      begin
        T.WhoCanPanel.SetTarget(AKind, AContainer, AName);
      end;
      T.WhoCanPanel.Reload;
    end;
    PageOfTab(T).Tab.Caption := T.DisplayCaption;
  end;
end;

procedure TpgnMainForm.DoDbaSessions(Sender: TObject);
begin
  OpenDbaScreen(dsSessions);
end;

procedure TpgnMainForm.DoDbaLocks(Sender: TObject);
begin
  OpenDbaScreen(dsLocks);
end;

procedure TpgnMainForm.DoDbaUsers(Sender: TObject);
begin
  OpenDbaScreen(dsUsers);
end;

procedure TpgnMainForm.DoDbaWhoCan(Sender: TObject);
begin
  OpenDbaScreen(dsWhoCan);
end;

{ Who Can Do What > Open Account: Users and Roles on the same connection,
  with that account picked. }
procedure TpgnMainForm.TabOpenAccount(const AAccount: string);
var
  Src, T: TpgnQueryTab;
begin
  Src := FActiveTab;
  if (Src = nil) or not Src.IsConnected then
  begin
    Exit;
  end;
  T := NewTabOn(Src.Info, Src.CurrentDb, '');
  if T <> nil then
  begin
    T.OnOpenAccount := @TabOpenAccount;
    T.OpenScreen(dsUsers);
    T.UsersPanel.SelectAccount(AAccount);
    PageOfTab(T).Tab.Caption := T.DisplayCaption;
  end;
end;

{ The log of DBA actions, read-only in a tab, newest at the bottom. }
procedure TpgnMainForm.DoDbaLog(Sender: TObject);
var
  T: TpgnQueryTab;
begin
  T := NewTab('Pagona DBA Log');
  if FileExists(DbaLogFileName) then
  begin
    T.Editor.Lines.LoadFromFile(DbaLogFileName);
  end
  else
  begin
    T.Editor.Lines.Text := '-- Nothing yet. Each DBA action Pagona carries out (such as killing a' +
      LineEnding + '-- session) is added here: when, where, as whom, and the statement.' +
      LineEnding + '-- The file: ' + DbaLogFileName;
  end;
  T.Editor.ReadOnly := True;
  T.Editor.Modified := False;
  T.Editor.CaretY := T.Editor.Lines.Count;
end;

{ The bare object name of a node; column nodes show "name  type". }
function TpgnMainForm.ObjectNameOf(ANode: TTreeNode): string;
var
  P: Integer;
begin
  Result := ANode.Text;
  if NodeKind(ANode) = nkColumn then
  begin
    P := Pos('  ', Result);
    if P > 0 then
    begin
      Result := Copy(Result, 1, P - 1);
    end;
  end;
end;

function TpgnMainForm.QualifiedNameOf(AIndex: Integer; ANode: TTreeNode): string;
var
  A: TpgnAdapter;
begin
  A := NodeAdapter(ANode);
  Result := A.QuoteIdent(ContainerOf(ANode)) + '.' + A.QuoteIdent(ObjectNameOf(ANode));
end;

procedure TpgnMainForm.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  Idx, I: Integer;
  A: TpgnAdapter;
  Names: TpgnStringArray;
  ChildKind: TpgnNodeKind;
  HasKids: Boolean;
  Child: TTreeNode;
begin
  AllowExpansion := True;
  if (Node.Count = 0) or (NodeKind(Node.GetFirstChild) <> nkPlaceholder) then
  begin
    Exit;
  end;
  Idx := ExplorerIndexOfNode(Node);
  if Idx < 0 then
  begin
    Exit;
  end;
  if not EnsureExplorerConnected(Idx) then
  begin
    AllowExpansion := False;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  FTree.Items.BeginUpdate;
  try
    try
      A := NodeAdapter(Node);   // PostgreSQL: may open the database's session
      Node.DeleteChildren;
      case NodeKind(Node) of
        nkConnection:
          begin
            if A.SessionPerDatabase then
            begin
              AddNode(Node, 'Databases', nkFolderDatabases, True);
              AddExtraFolders(Node, A, flServer);
            end
            else
            begin
              Names := A.ListDatabases;
              for I := 0 to High(Names) do
              begin
                AddNode(Node, Names[I], nkDatabase, True);
              end;
            end;
          end;
        nkDatabase:
          begin
            if A.HasSchemas then
            begin
              AddNode(Node, 'Schemas', nkFolderSchemas, True);
              AddNode(Node, 'Catalogs', nkFolderCatalogs, True);
              AddExtraFolders(Node, A, flDatabase);
            end
            else
            begin
              AddContainerFolders(Node, A);
            end;
          end;
        nkSchema:
          begin
            AddContainerFolders(Node, A);
          end;
      else
        begin
          if (NodeKind(Node) = nkTable) and A.TableFolders then
          begin
            AddNode(Node, 'Columns', nkFolderColumns, True);
            AddNode(Node, 'Indexes', nkFolderIndexes, True);
            AddNode(Node, 'Triggers', nkFolderTableTriggers, True);
          end
          else if FolderContents(Node, Names, ChildKind, HasKids) then
          begin
            for I := 0 to High(Names) do
            begin
              AddNode(Node, Names[I], ChildKind, HasKids);
            end;
            SetFolderCount(Node);
          end;
        end;
      end;
    except
      on E: Exception do
      begin
        // put the placeholder back so it can be tried again
        Node.DeleteChildren;
        Child := FTree.Items.AddChild(Node, 'loading...');
        Child.Data := KindToPtr(nkPlaceholder);
        AllowExpansion := False;
        ShowError('Could not load ' + Node.Text, E);
      end;
    end;
  finally
    FTree.Items.EndUpdate;
    Screen.Cursor := crDefault;
  end;
end;

procedure TpgnMainForm.TreeDblClick(Sender: TObject);
var
  N: TTreeNode;
  Idx: Integer;
begin
  N := FTree.Selected;
  if N = nil then
  begin
    Exit;
  end;
  Idx := ExplorerIndexOfNode(N);
  if (Idx < 0) or (FExplorer[Idx].Adapter = nil) then
  begin
    Exit;
  end;
  if (NodeKind(N) in RelationKinds) and (FActiveTab <> nil) then
  begin
    FActiveTab.InsertText(QualifiedNameOf(Idx, N), False);
  end
  else if NodeKind(N) in RoutineNodeKinds then
  begin
    OpenRoutineTab(Idx, DatabaseOf(N), SchemaOf(N), ObjectNameOf(N), RoutineKindOf(N));
  end;
end;

procedure TpgnMainForm.TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  N: TTreeNode;
begin
  // right-clicking a node selects it, so its menu acts on the node clicked
  if Button = mbRight then
  begin
    N := FTree.GetNodeAt(X, Y);
    if N <> nil then
    begin
      N.Selected := True;
    end;
  end;
end;

function TpgnMainForm.AddTreeItem(AParent: TMenuItem; const ACaption: string;
  ACommand: TpgnTreeCommand): TMenuItem;
begin
  Result := TMenuItem.Create(FTreeMenu);
  Result.Caption := ACaption;
  Result.Tag := Ord(ACommand);
  if ACaption <> '-' then
  begin
    Result.OnClick := @TreeMenuClick;
  end;
  if AParent = nil then
  begin
    FTreeMenu.Items.Add(Result);
  end
  else
  begin
    AParent.Add(Result);
  end;
end;

procedure TpgnMainForm.TreeMenuPopup(Sender: TObject);
var
  N: TTreeNode;
  Idx, TopRows: Integer;
  Connected: Boolean;
  Sub: TMenuItem;
  K: TpgnNodeKind;
begin
  FTreeMenu.Items.Clear;
  N := FTree.Selected;
  TopRows := FSettings.RowLimit;
  if TopRows <= 0 then
  begin
    TopRows := DefaultTopRows;
  end;

  if N = nil then
  begin
    AddTreeItem(nil, 'New Connection...', tcNewConnection);
    AddTreeItem(nil, 'Refresh All', tcRefreshAll);
    Exit;
  end;

  Idx := ExplorerIndexOfNode(N);
  Connected := (Idx >= 0) and (FExplorer[Idx].Adapter <> nil);
  K := NodeKind(N);

  case K of
    nkConnection:
      begin
        if Connected and FSea then
        begin
          // SSMS's server menu
          AddActionItem(FTreeMenu.Items, FActConnectOE);
          AddTreeItem(nil, 'Disconnect', tcDisconnect);
          AddTreeItem(nil, '-', tcRefresh);
          AddTreeItem(nil, 'New Query', tcNewTab);
          AddTreeItem(nil, '-', tcRefresh);
          AddActionItem(FTreeMenu.Items, FActDbaSessions);
          AddActionItem(FTreeMenu.Items, FActDbaLocks);
          AddActionItem(FTreeMenu.Items, FActDbaUsers);
          AddTreeItem(nil, '-', tcRefresh);
          AddTreeItem(nil, 'Refresh', tcRefresh);
          AddTreeItem(nil, '-', tcRefresh);
          AddTreeItem(nil, 'Edit Connection...', tcEditConnection);
          Exit;
        end;
        if Connected then
        begin
          AddTreeItem(nil, 'New Query Tab', tcNewTab);
          AddTreeItem(nil, 'Disconnect', tcDisconnect);
        end
        else
        begin
          AddTreeItem(nil, 'Connect', tcConnect);
          AddTreeItem(nil, 'New Query Tab', tcNewTab);
        end;
        AddTreeItem(nil, '-', tcRefresh);
        AddTreeItem(nil, 'Edit Connection...', tcEditConnection);
        AddTreeItem(nil, 'Delete Connection...', tcDeleteConnection);
        AddTreeItem(nil, 'New Connection...', tcNewConnection);
      end;
    nkDatabase, nkSchema:
      begin
        AddTreeItem(nil, 'New Query Tab Here', tcNewTab);
        AddTreeItem(nil, 'Refresh', tcRefresh);
        AddTreeItem(nil, 'Copy Name', tcCopyName);
        AddTreeItem(nil, 'Who Can Do What', tcWhoCan);
      end;
    nkFolderProcs:
      begin
        AddTreeItem(nil, 'New Procedure...', tcNewProcedure);
        AddTreeItem(nil, 'Refresh', tcRefresh);
      end;
    nkFolderFuncs, nkFolderTrigFuncs:
      begin
        AddTreeItem(nil, 'New Function...', tcNewFunction);
        AddTreeItem(nil, 'Refresh', tcRefresh);
      end;
    nkFolderTableTriggers:
      begin
        AddTreeItem(nil, 'New Trigger...', tcNewTrigger);
        AddTreeItem(nil, 'Refresh', tcRefresh);
      end;
    nkProcedure, nkFunction:
      begin
        AddTreeItem(nil, 'Open', tcOpenRoutine);
        AddTreeItem(nil, 'Execute...', tcExecuteRoutine);
        Sub := AddTreeItem(nil, 'Script As', tcRefresh);
        Sub.OnClick := nil;
        AddTreeItem(Sub, 'CREATE', tcScriptRoutine);
        AddTreeItem(nil, 'Copy Definition', tcCopyDefinition);
        AddTreeItem(nil, 'Grant...', tcGrant);
        AddTreeItem(nil, 'Who Can Do What', tcWhoCan);
        AddTreeItem(nil, 'Copy Name', tcCopyName);
        AddTreeItem(nil, '-', tcRefresh);
        if K = nkProcedure then
        begin
          AddTreeItem(nil, 'New Procedure...', tcNewProcedure);
          AddTreeItem(nil, '-', tcRefresh);
          AddTreeItem(nil, 'Drop Procedure...', tcDropRoutine);
        end
        else
        begin
          AddTreeItem(nil, 'New Function...', tcNewFunction);
          AddTreeItem(nil, '-', tcRefresh);
          AddTreeItem(nil, 'Drop Function...', tcDropRoutine);
        end;
      end;
    nkTrigger:
      begin
        AddTreeItem(nil, 'Open', tcOpenRoutine);
        Sub := AddTreeItem(nil, 'Script As', tcRefresh);
        Sub.OnClick := nil;
        AddTreeItem(Sub, 'CREATE', tcScriptRoutine);
        AddTreeItem(nil, 'Copy Definition', tcCopyDefinition);
        AddTreeItem(nil, 'Copy Name', tcCopyName);
        AddTreeItem(nil, '-', tcRefresh);
        AddTreeItem(nil, 'Drop Trigger...', tcDropRoutine);
      end;
    nkTable, nkView, nkMatView:
      begin
        AddTreeItem(nil, Format('Select Top %d Rows', [TopRows]), tcSelectTop);
        AddTreeItem(nil, 'Describe', tcDescribe);
        AddTreeItem(nil, 'Show DDL', tcShowDDL);
        Sub := AddTreeItem(nil, 'Script As', tcRefresh);
        Sub.OnClick := nil;
        AddTreeItem(Sub, 'SELECT', tcScriptSelect);
        if K = nkTable then
        begin
          AddTreeItem(Sub, 'INSERT', tcScriptInsert);
          AddTreeItem(Sub, 'UPDATE', tcScriptUpdate);
          AddTreeItem(Sub, 'DELETE', tcScriptDelete);
        end;
        AddTreeItem(Sub, 'CREATE', tcScriptCreate);
        AddTreeItem(nil, 'Copy Definition', tcCopyDefinition);
        AddTreeItem(nil, 'Copy Name', tcCopyName);
        AddTreeItem(nil, 'Refresh', tcRefresh);
        AddTreeItem(nil, '-', tcRefresh);
        if K = nkTable then
        begin
          AddTreeItem(nil, 'New Trigger...', tcNewTrigger);
        end;
        AddTreeItem(nil, 'Grant...', tcGrant);
        AddTreeItem(nil, 'Who Can Do What', tcWhoCan);
        AddTreeItem(nil, '-', tcRefresh);
        if K = nkTable then
        begin
          AddTreeItem(nil, 'Truncate Table...', tcTruncate);
          AddTreeItem(nil, 'Drop Table...', tcDrop);
        end
        else if K = nkMatView then
        begin
          AddTreeItem(nil, 'Drop Materialized View...', tcDrop);
        end
        else
        begin
          AddTreeItem(nil, 'Drop View...', tcDrop);
        end;
      end;
    nkColumn, nkIndex, nkOther:
      begin
        AddTreeItem(nil, 'Copy Name', tcCopyName);
      end;
  else
    begin
      if K in FolderKinds then
      begin
        AddTreeItem(nil, 'Refresh', tcRefresh);
      end;
    end;
  end;
  AddTreeItem(nil, '-', tcRefresh);
  AddTreeItem(nil, 'Refresh All', tcRefreshAll);
end;

procedure TpgnMainForm.TreeMenuClick(Sender: TObject);
var
  N: TTreeNode;
  Cmd: TpgnTreeCommand;
  Idx, TopRows: Integer;
  Kind: TpgnObjectKind;
  Db, Schema, C, Obj, SQL, Returns: string;
  A: TpgnAdapter;
  T: TpgnQueryTab;
begin
  Cmd := TpgnTreeCommand((Sender as TMenuItem).Tag);

  if Cmd = tcNewConnection then
  begin
    DoNewConnection(Self);
    Exit;
  end;
  if Cmd = tcRefreshAll then
  begin
    DoRefreshAll(Self);
    Exit;
  end;

  N := FTree.Selected;
  if N = nil then
  begin
    Exit;
  end;
  Idx := ExplorerIndexOfNode(N);
  if Idx < 0 then
  begin
    Exit;
  end;

  case Cmd of
    tcConnect:
      begin
        N.Expand(False);   // expanding connects
        Exit;
      end;
    tcDisconnect:
      begin
        DisconnectExplorer(Idx);
        Exit;
      end;
    tcEditConnection:
      begin
        DoEditConnection(Self);
        Exit;
      end;
    tcDeleteConnection:
      begin
        DoDeleteConnection(Self);
        Exit;
      end;
    tcNewTab:
      begin
        NewTabOn(FExplorer[Idx].Info, DatabaseOf(N), '', SchemaOf(N));
        Exit;
      end;
  end;

  if not EnsureExplorerConnected(Idx) then
  begin
    Exit;
  end;
  Db := DatabaseOf(N);
  Schema := SchemaOf(N);
  C := ContainerOf(N);
  Obj := ObjectNameOf(N);
  case NodeKind(N) of
    nkView:
      begin
        Kind := okView;
      end;
    nkMatView:
      begin
        Kind := okMatView;
      end;
  else
    begin
      Kind := okTable;
    end;
  end;

  try
    A := NodeAdapter(N);
    case Cmd of
      tcRefresh:
        begin
          if NodeKind(N) = nkConnection then
          begin
            RefreshConnection(Idx, '', True);
          end
          else
          begin
            ResetNode(N);
          end;
        end;
      tcSelectTop:
        begin
          TopRows := FSettings.RowLimit;
          if TopRows <= 0 then
          begin
            TopRows := DefaultTopRows;
          end;
          SQL := A.SelectTopSQL(QualifiedNameOf(Idx, N), TopRows);
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL + ';');
            T.RunSQL(SQL);
          end;
        end;
      tcDescribe:
        begin
          SQL := A.DescribeSQL(C, Obj);
          T := NewTabOn(FExplorer[Idx].Info, Db, 'Describe ' + Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL + ';');
            T.RunSQL(SQL);
          end;
        end;
      tcShowDDL:
        begin
          SQL := A.GetDDL(C, Obj, Kind);
          T := NewTabOn(FExplorer[Idx].Info, Db, 'DDL ' + Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL + ';' + LineEnding);
          end;
        end;
      tcScriptSelect, tcScriptInsert, tcScriptUpdate, tcScriptDelete:
        begin
          case Cmd of
            tcScriptInsert:
              begin
                SQL := ScriptFor(A, C, Obj, skInsert);
              end;
            tcScriptUpdate:
              begin
                SQL := ScriptFor(A, C, Obj, skUpdate);
              end;
            tcScriptDelete:
              begin
                SQL := ScriptFor(A, C, Obj, skDelete);
              end;
          else
            begin
              SQL := ScriptFor(A, C, Obj, skSelect);
            end;
          end;
          // Explorer actions never touch the tab you're working in
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL);
          end;
        end;
      tcScriptCreate:
        begin
          SQL := A.GetDDL(C, Obj, Kind) + ';' + LineEnding;
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL);
          end;
        end;
      tcCopyName:
        begin
          Clipboard.AsText := Obj;
        end;
      tcWhoCan:
        begin
          if NodeKind(N) = nkSchema then
          begin
            OpenDbaScreen(dsWhoCan, 'schema', Schema, '', Idx);
          end
          else if NodeKind(N) = nkDatabase then
          begin
            OpenDbaScreen(dsWhoCan, 'database', Db, '', Idx);
          end
          else if NodeKind(N) = nkProcedure then
          begin
            OpenDbaScreen(dsWhoCan, 'procedure', C, Obj, Idx);
          end
          else if NodeKind(N) = nkFunction then
          begin
            OpenDbaScreen(dsWhoCan, 'function', C, Obj, Idx);
          end
          else
          begin
            OpenDbaScreen(dsWhoCan, 'table', C, Obj, Idx);
          end;
          Exit;
        end;
      tcCopyDefinition:
        begin
          // the CREATE statement on the clipboard, ready to paste into an
          // email or a ticket
          if NodeKind(N) in RoutineNodeKinds then
          begin
            SQL := A.GetRoutineSQL(C, Obj, RoutineKindOf(N));
            if A.Dialect = sdMySQL then
            begin
              SQL := 'DELIMITER $$' + LineEnding + SQL + ' $$' + LineEnding + 'DELIMITER ;' + LineEnding;
            end
            else
            begin
              SQL := SQL + ';' + LineEnding;
            end;
          end
          else
          begin
            SQL := A.GetDDL(C, Obj, Kind) + ';' + LineEnding;
          end;
          Clipboard.AsText := SQL;
          FStatus.Texts[2] := 'Copied the definition of ' + Obj + ' to the clipboard';
        end;
      tcOpenRoutine:
        begin
          OpenRoutineTab(Idx, Db, Schema, Obj, RoutineKindOf(N));
        end;
      tcExecuteRoutine:
        begin
          ExecuteRoutine(Idx, Db, Schema, Obj, RoutineKindOf(N));
        end;
      tcScriptRoutine:
        begin
          SQL := A.GetRoutineSQL(C, Obj, RoutineKindOf(N));
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            if A.Dialect = sdMySQL then
            begin
              // DELIMITER lines so the script runs as it stands
              T.SetText('DELIMITER $$' + LineEnding + SQL + ' $$' + LineEnding + 'DELIMITER ;' +
                LineEnding);
            end
            else
            begin
              T.SetText(SQL + ';' + LineEnding);
            end;
          end;
        end;
      tcNewProcedure, tcNewFunction:
        begin
          if Cmd = tcNewProcedure then
          begin
            if NewRoutineDialog(Self, A, rkProcedure, SQL) then
            begin
              NewRoutineTab(Idx, Db, Schema, rkProcedure, SQL);
            end;
          end
          else
          begin
            // in Trigger Functions, a new function returns trigger
            Returns := 'INT';
            if (NodeKind(N) = nkFolderTrigFuncs) or
              ((N.Parent <> nil) and (NodeKind(N.Parent) = nkFolderTrigFuncs)) then
            begin
              Returns := 'trigger';
            end;
            if NewRoutineDialog(Self, A, rkFunction, SQL, Returns) then
            begin
              NewRoutineTab(Idx, Db, Schema, rkFunction, SQL);
            end;
          end;
        end;
      tcNewTrigger:
        begin
          SQL := A.NewTriggerSQL(C, TableOf(N));
          NewRoutineTab(Idx, Db, Schema, rkTrigger, SQL);
        end;
      tcGrant:
        begin
          if GrantDialog(Self, A, C, Obj, NodeObjectKind(N), SQL) then
          begin
            T := NewTabOn(FExplorer[Idx].Info, Db, 'Grant ' + Obj, Schema);
            if T <> nil then
            begin
              T.SetText(SQL);
              T.RunScript;
            end;
          end;
        end;
      tcDropRoutine:
        begin
          SQL := A.DropRoutineSQL(C, Obj, RoutineKindOf(N));
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL + ';');
            T.RunSQL(SQL);
          end;
        end;
      tcTruncate, tcDrop:
        begin
          if Cmd = tcTruncate then
          begin
            SQL := 'TRUNCATE TABLE ' + QualifiedNameOf(Idx, N);
          end
          else if Kind = okView then
          begin
            SQL := 'DROP VIEW ' + QualifiedNameOf(Idx, N);
          end
          else if Kind = okMatView then
          begin
            SQL := 'DROP MATERIALIZED VIEW ' + QualifiedNameOf(Idx, N);
          end
          else
          begin
            SQL := 'DROP TABLE ' + QualifiedNameOf(Idx, N);
          end;
          // run in a tab of its own, so what ran is visible
          T := NewTabOn(FExplorer[Idx].Info, Db, Obj, Schema);
          if T <> nil then
          begin
            T.SetText(SQL + ';');
            T.RunSQL(SQL);
          end;
        end;
    end;
  except
    on E: Exception do
    begin
      ShowError((Sender as TMenuItem).Caption, E);
    end;
  end;
end;

{ ------------------------------------------------------------ handlers }

{ ------------------------------------------------------ filter, details }

procedure TpgnMainForm.FilterChange(Sender: TObject);
begin
  // what the tree already holds shows at once; the databases are asked
  // once typing pauses
  RunFilter(Trim(FFilterEdit.Text));
  FFilterTimer.Enabled := False;
  FFilterTimer.Enabled := Trim(FFilterEdit.Text) <> '';
end;

procedure TpgnMainForm.FilterTimerTick(Sender: TObject);
var
  Txt: string;
  I, S, Searched, NotConnected: Integer;
  Refs: TpgnObjectRefs;
  Sessions: array of TpgnAdapter;
  J, K, N: Integer;
  Dup: Boolean;
begin
  FFilterTimer.Enabled := False;
  Txt := Trim(FFilterEdit.Text);
  if Txt = '' then
  begin
    Exit;
  end;
  Searched := 0;
  NotConnected := 0;
  Screen.Cursor := crHourGlass;
  try
    for I := 0 to High(FExplorer) do
    begin
      if FExplorer[I].Adapter = nil then
      begin
        Inc(NotConnected);
        Continue;
      end;
      Inc(Searched);
      // the connection's session, and (PostgreSQL) every database opened
      SetLength(Sessions, 1 + FExplorer[I].Sessions.Count);
      Sessions[0] := FExplorer[I].Adapter;
      for S := 0 to FExplorer[I].Sessions.Count - 1 do
      begin
        Sessions[S + 1] := TpgnAdapter(FExplorer[I].Sessions.Objects[S]);
      end;
      for S := 0 to High(Sessions) do
      begin
        try
          Refs := Sessions[S].SearchObjects(Txt, 200);
        except
          on E: Exception do
          begin
            Refs := nil;
          end;
        end;
        for J := 0 to High(Refs) do
        begin
          Dup := False;
          for K := 0 to High(FFound) do
          begin
            if (FFound[K].ConnIndex = I) and SameText(FFound[K].Ref.Database, Refs[J].Database) and
              (FFound[K].Ref.Schema = Refs[J].Schema) and (FFound[K].Ref.Name = Refs[J].Name) then
            begin
              Dup := True;
              Break;
            end;
          end;
          if Dup then
          begin
            Continue;
          end;
          N := Length(FFound);
          SetLength(FFound, N + 1);
          FFound[N].ConnIndex := I;
          FFound[N].Ref := Refs[J];
          FFound[N].Node := nil;
        end;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  FillFoundList;
  FFoundNote.Caption := IntToStr(Length(FFound)) + ' found. Searched ' + IntToStr(Searched) +
    ' connected connection(s).';
  if NotConnected > 0 then
  begin
    FFoundNote.Caption := FFoundNote.Caption + ' ' + IntToStr(NotConnected) +
      ' not connected yet.';
  end;
end;

{ Shows what the tree has loaded that matches AText, in place of the tree.
  An empty filter brings the tree back. }
procedure TpgnMainForm.RunFilter(const AText: string);
var
  Lower: string;
  Node: TTreeNode;
  K: TpgnNodeKind;
  N: Integer;
begin
  SetLength(FFound, 0);
  if AText = '' then
  begin
    FFoundList.ShowData(nil);
    FFoundList.Visible := False;
    FFoundNote.Visible := False;
    FTree.Visible := True;
    Exit;
  end;
  Lower := LowerCase(AText);
  Node := FTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    K := NodeKind(Node);
    if (K in RelationKinds + RoutineNodeKinds) and (Pos(Lower, LowerCase(Node.Text)) > 0) then
    begin
      N := Length(FFound);
      SetLength(FFound, N + 1);
      FFound[N].ConnIndex := ExplorerIndexOfNode(Node);
      FFound[N].Ref := RefOfNode(Node);
      FFound[N].Node := Node;
    end;
    Node := Node.GetNext;
  end;
  FillFoundList;
  FFoundNote.Caption := IntToStr(Length(FFound)) + ' found so far. Searching the databases...';
  FFoundNote.Visible := True;
  FFoundList.Visible := True;
  FTree.Visible := False;
end;

procedure TpgnMainForm.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    FFilterEdit.Text := '';
    Key := 0;
  end
  else if (Key = VK_DOWN) and FFoundList.Visible and (Length(FFound) > 0) then
  begin
    FFoundList.SetFocus;
    FFoundList.Row := 1;
    Key := 0;
  end
  else if (Key = VK_RETURN) and FFoundList.Visible and (Length(FFound) > 0) then
  begin
    FoundDblClick(FFoundList);
    Key := 0;
  end;
end;

{ The list as a grid: Name, Type, Database, Connection. Row N+1 is
  FFound[N]. }
procedure TpgnMainForm.FillFoundList;
var
  R: TpgnResultSet;
  I: Integer;
begin
  R := TpgnResultSet.Create;
  SetLength(R.Columns, 4);
  R.Columns[0] := 'Name';
  R.Columns[1] := 'Type';
  R.Columns[2] := 'Where';
  R.Columns[3] := 'Connection';
  SetLength(R.Rows, Length(FFound));
  for I := 0 to High(FFound) do
  begin
    SetLength(R.Rows[I].Values, 4);
    SetLength(R.Rows[I].Nulls, 4);
    R.Rows[I].Values[0] := FFound[I].Ref.Name;
    R.Rows[I].Values[1] := FFound[I].Ref.Kind;
    R.Rows[I].Values[2] := FFound[I].Ref.Database;
    if FFound[I].Ref.Schema <> '' then
    begin
      R.Rows[I].Values[2] := FFound[I].Ref.Database + '.' + FFound[I].Ref.Schema;
    end;
    if (FFound[I].ConnIndex >= 0) and (FFound[I].ConnIndex <= High(FExplorer)) then
    begin
      R.Rows[I].Values[3] := FExplorer[FFound[I].ConnIndex].Info.Name;
    end;
  end;
  R.ReturnsRows := True;
  FFoundList.ShowData(R);
end;

procedure TpgnMainForm.FoundSelect(Sender: TObject; aCol, aRow: Integer);
var
  N: Integer;
begin
  N := aRow - 1;
  if (N < 0) or (N > High(FFound)) then
  begin
    Exit;
  end;
  ShowDetails(FFound[N].ConnIndex, FFound[N].Ref);
end;

procedure TpgnMainForm.FoundKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FoundDblClick(FFoundList);
    Key := 0;
  end;
end;

{ Double-click (or Enter): back to the tree, with the object selected. }
procedure TpgnMainForm.FoundDblClick(Sender: TObject);
var
  N, Conn: Integer;
  Ref: TpgnObjectRef;
  Node: TTreeNode;
begin
  N := FFoundList.Row - 1;
  if (N < 0) or (N > High(FFound)) then
  begin
    Exit;
  end;
  Conn := FFound[N].ConnIndex;
  Ref := FFound[N].Ref;
  Node := FFound[N].Node;
  if Node = nil then
  begin
    try
      Node := RevealObject(Conn, Ref);
    except
      on E: Exception do
      begin
        ShowError('Could not open the Explorer to ' + Ref.Name, E);
      end;
    end;
  end;
  FFilterEdit.Text := '';     // brings the tree back
  if Node <> nil then
  begin
    FTree.Selected := Node;
    Node.MakeVisible;
    if FTree.CanFocus then
    begin
      FTree.SetFocus;
    end;
  end;
  if Ref.Kind = 'Procedure' then
  begin
    OpenRoutineTab(Conn, Ref.Database, Ref.Schema, Ref.Name, rkProcedure);
  end
  else if (Ref.Kind = 'Function') or (Ref.Kind = 'Trigger Function') then
  begin
    OpenRoutineTab(Conn, Ref.Database, Ref.Schema, Ref.Name, rkFunction);
  end
  else if Ref.Kind = 'Trigger' then
  begin
    OpenRoutineTab(Conn, Ref.Database, Ref.Schema, Ref.Name, rkTrigger);
  end;
end;

{ Opens the tree down to an object (loading folders as needed). }
{ The first child of AParent of kind AKind (named AText, if given). }
function TpgnMainForm.FindChild(AParent: TTreeNode; AKind: TpgnNodeKind; const AText: string): TTreeNode;
begin
  Result := nil;
  if AParent = nil then
  begin
    Exit;
  end;
  Result := AParent.GetFirstChild;
  while (Result <> nil) and not ((NodeKind(Result) = AKind) and
    ((AText = '') or (Result.Text = AText))) do
  begin
    Result := Result.GetNextSibling;
  end;
end;

function TpgnMainForm.RevealObject(AConnIndex: Integer; const ARef: TpgnObjectRef): TTreeNode;
var
  Root, DbNode, Holder, Folder: TTreeNode;
  Want: TpgnNodeKind;
begin
  Result := nil;
  if (AConnIndex < 0) or (AConnIndex > High(FExplorer)) then
  begin
    Exit;
  end;
  Root := FExplorer[AConnIndex].Root;
  Root.Expand(False);
  if FExplorer[AConnIndex].Adapter = nil then
  begin
    Exit;
  end;
  if (Copy(ARef.Kind, 1, 6) = 'Other:') and (ARef.Database = '') then
  begin
    Result := RevealOther(Root, Copy(ARef.Kind, 7, MaxInt), ARef.Name);
    Exit;
  end;
  if FExplorer[AConnIndex].Adapter.SessionPerDatabase then
  begin
    Folder := FindChild(Root, nkFolderDatabases, '');
    if Folder = nil then
    begin
      Exit;
    end;
    Folder.Expand(False);
    DbNode := FindChild(Folder, nkDatabase, ARef.Database);
  end
  else
  begin
    DbNode := FindChild(Root, nkDatabase, ARef.Database);
  end;
  if DbNode = nil then
  begin
    Exit;
  end;
  DbNode.Expand(False);
  Holder := DbNode;
  if ARef.Schema <> '' then
  begin
    Folder := FindChild(DbNode, nkFolderSchemas, '');
    if Folder <> nil then
    begin
      Folder.Expand(False);
      Holder := FindChild(Folder, nkSchema, ARef.Schema);
    end;
    if (Folder = nil) or (Holder = nil) then
    begin
      Folder := FindChild(DbNode, nkFolderCatalogs, '');
      if Folder = nil then
      begin
        Exit;
      end;
      Folder.Expand(False);
      Holder := FindChild(Folder, nkSchema, ARef.Schema);
    end;
    if Holder = nil then
    begin
      Exit;
    end;
    Holder.Expand(False);
  end;

  if Copy(ARef.Kind, 1, 6) = 'Other:' then
  begin
    Result := RevealOther(Holder, Copy(ARef.Kind, 7, MaxInt), ARef.Name);
    Exit;
  end;
  if ARef.Kind = 'View' then
  begin
    Want := nkFolderViews;
  end
  else if ARef.Kind = 'Materialized View' then
  begin
    Want := nkFolderMatViews;
  end
  else if ARef.Kind = 'Procedure' then
  begin
    Want := nkFolderProcs;
  end
  else if ARef.Kind = 'Function' then
  begin
    Want := nkFolderFuncs;
  end
  else if ARef.Kind = 'Trigger Function' then
  begin
    Want := nkFolderTrigFuncs;
  end
  else if ARef.Kind = 'Trigger' then
  begin
    Want := nkFolderTriggers;
  end
  else
  begin
    Want := nkFolderTables;
  end;
  Folder := FindChild(Holder, Want, '');
  if Folder = nil then
  begin
    Exit;
  end;
  Folder.Expand(False);
  Result := FindChild(Folder, NodeKindFor(ARef.Kind), ARef.Name);
end;

{ The tree's node kind for an object kind word. }
function TpgnMainForm.NodeKindFor(const AKind: string): TpgnNodeKind;
begin
  if AKind = 'View' then
  begin
    Result := nkView;
  end
  else if AKind = 'Materialized View' then
  begin
    Result := nkMatView;
  end
  else if AKind = 'Procedure' then
  begin
    Result := nkProcedure;
  end
  else if (AKind = 'Function') or (AKind = 'Trigger Function') then
  begin
    Result := nkFunction;
  end
  else if AKind = 'Trigger' then
  begin
    Result := nkTrigger;
  end
  else
  begin
    Result := nkTable;
  end;
end;

procedure TpgnMainForm.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  // wait for the selection to settle (arrowing down a long list)
  FDetailsTimer.Enabled := False;
  FDetailsTimer.Enabled := True;
end;

procedure TpgnMainForm.DetailsTimerTick(Sender: TObject);
var
  Node: TTreeNode;
begin
  FDetailsTimer.Enabled := False;
  Node := FTree.Selected;
  // a column, an index or a table's folder: show the table
  while (Node <> nil) and (NodeKind(Node) in [nkColumn, nkIndex, nkFolderColumns, nkFolderIndexes,
    nkFolderTableTriggers]) do
  begin
    Node := Node.Parent;
  end;
  if (Node = nil) or not (NodeKind(Node) in RelationKinds + RoutineNodeKinds + [nkOther]) then
  begin
    Exit;   // keep showing the last object
  end;
  ShowDetails(ExplorerIndexOfNode(Node), RefOfNode(Node));
end;

procedure TpgnMainForm.ClearDetails(const ACaption: string);
begin
  FDetailsLabel.Caption := ACaption;
  FDetailsColumns.ShowData(nil);
  FDetailsIndexes.ShowData(nil);
  FDetailsTriggers.ShowData(nil);
  FDetailsParams.ShowData(nil);
  FDetailsGrants.ShowData(nil);
  FDetailsDefinition.Lines.Clear;
  FDetailsShown := '';
end;

{ Puts these pages on the Details tabs, in their usual order. The page in
  view stays if it is still there, else the first one is shown. }
procedure TpgnMainForm.SetDetailsPages(APages: TpgnDetailsPages);
const
  Captions: array[TpgnDetailsPage] of string = ('Columns', 'Indexes', 'Triggers', 'Parameters',
    'Definition', 'Grants');
var
  DP, Want: TpgnDetailsPage;
  N, I: Integer;
begin
  SetLength(FDetailsShowing, 0);
  FDetailsTabs.OnChange := nil;
  FDetailsTabs.Tabs.BeginUpdate;
  try
    FDetailsTabs.Tabs.Clear;
    for DP := Low(TpgnDetailsPage) to High(TpgnDetailsPage) do
    begin
      if DP in APages then
      begin
        N := Length(FDetailsShowing);
        SetLength(FDetailsShowing, N + 1);
        FDetailsShowing[N] := DP;
        FDetailsTabs.Tabs.Add(Captions[DP]);
      end;
    end;
  finally
    FDetailsTabs.Tabs.EndUpdate;
  end;
  Want := FDetailsShowing[0];
  if FDetailsPage in APages then
  begin
    Want := FDetailsPage;
  end;
  for I := 0 to High(FDetailsShowing) do
  begin
    if FDetailsShowing[I] = Want then
    begin
      FDetailsTabs.TabIndex := I;
    end;
  end;
  FDetailsTabs.OnChange := @DetailsTabChange;
  ShowDetailsPage(Want);
end;

procedure TpgnMainForm.ShowDetailsPage(APage: TpgnDetailsPage);
begin
  FDetailsPage := APage;
  DetailsBodyResize(nil);
end;

{ The page in view fills the area; the others wait out of sight. They stay
  "visible": GTK3 shows hidden children again when their parent is shown. }
procedure TpgnMainForm.DetailsBodyResize(Sender: TObject);
var
  DP: TpgnDetailsPage;
  W, H: Integer;
begin
  W := FDetailsBody.ClientWidth;
  H := FDetailsBody.ClientHeight;
  for DP := Low(TpgnDetailsPage) to High(TpgnDetailsPage) do
  begin
    if DP = FDetailsPage then
    begin
      FDetailsArea[DP].SetBounds(0, 0, W, H);
    end
    else
    begin
      FDetailsArea[DP].SetBounds(-W - 50, 0, W, H);
    end;
  end;
end;

procedure TpgnMainForm.DetailsTabChange(Sender: TObject);
var
  I: Integer;
begin
  I := FDetailsTabs.TabIndex;
  if (I >= 0) and (I <= High(FDetailsShowing)) then
  begin
    ShowDetailsPage(FDetailsShowing[I]);
  end;
end;

{ A one-cell result that says why a list is empty. }
function NoteResult(const ATitle, AText: string): TpgnResultSet;
begin
  Result := TpgnResultSet.Create;
  SetLength(Result.Columns, 1);
  Result.Columns[0] := ATitle;
  SetLength(Result.Rows, 1);
  SetLength(Result.Rows[0].Values, 1);
  SetLength(Result.Rows[0].Nulls, 1);
  Result.Rows[0].Values[0] := AText;
  Result.ReturnsRows := True;
end;

{ What the Details panel shows for each kind of object:
    Table      Columns | Indexes | Triggers | Grants
    View       Columns | Definition
    Procedure  Parameters | Definition | Grants   (and Function)
    Trigger    Definition
  Everything is read on the Explorer's own session for that connection. }
procedure TpgnMainForm.ShowDetails(AConnIndex: Integer; const ARef: TpgnObjectRef);
var
  A: TpgnAdapter;
  Key, ObjWord, C, AKind, AName, Folder: string;
  IsTable, IsView, IsMat, IsRoutine, IsTrigger, IsOther: Boolean;
  RKind: TpgnRoutineKind;

  procedure LoadGrants;
  begin
    try
      FDetailsGrants.ShowData(A.DescribeGrants(C, AName, ObjWord));
    except
      on E: Exception do
      begin
        FDetailsGrants.ShowData(NoteResult('Grants', 'Your login can''t read the grants here: ' +
          E.Message));
      end;
    end;
  end;

  procedure LoadDefinition;
  var
    SQL: string;
  begin
    try
      if IsOther then
      begin
        SQL := A.FolderItemSQL(C, Folder, AName);
        if SQL = '' then
        begin
          SQL := '-- ' + AName + LineEnding + '-- (no definition shown for ' + LowerCase(Folder) +
            ' yet)';
        end;
      end
      else if IsView then
      begin
        SQL := A.GetDDL(C, AName, okView);
      end
      else if IsMat then
      begin
        SQL := A.GetDDL(C, AName, okMatView);
      end
      else
      begin
        SQL := A.GetRoutineSQL(C, AName, RKind);
      end;
      if Trim(SQL) = '' then
      begin
        SQL := '-- Your login can''t see this definition.';
      end;
    except
      on E: Exception do
      begin
        SQL := '-- Could not read the definition: ' + E.Message;
      end;
    end;
    FDetailsDefinition.Lines.Text := SQL;
    FDetailsDefinition.CaretXY := Point(1, 1);
    FDetailsDefinition.TopLine := 1;
  end;

begin
  if (AConnIndex < 0) or (AConnIndex > High(FExplorer)) then
  begin
    Exit;
  end;
  if FExplorer[AConnIndex].Adapter = nil then
  begin
    Exit;
  end;
  AKind := ARef.Kind;
  AName := ARef.Name;
  C := ARef.Schema;
  if C = '' then
  begin
    C := ARef.Database;
  end;
  Key := IntToStr(AConnIndex) + '|' + ARef.Database + '|' + ARef.Schema + '|' + AName + '|' + AKind;
  if Key = FDetailsShown then
  begin
    Exit;
  end;
  IsTable := AKind = 'Table';
  IsView := AKind = 'View';
  IsMat := AKind = 'Materialized View';
  IsRoutine := (AKind = 'Procedure') or (AKind = 'Function') or (AKind = 'Trigger Function');
  IsTrigger := AKind = 'Trigger';
  IsOther := Copy(AKind, 1, 6) = 'Other:';
  Folder := '';
  if IsOther then
  begin
    Folder := Copy(AKind, 7, MaxInt);
  end;
  if not (IsTable or IsView or IsMat or IsRoutine or IsTrigger or IsOther) then
  begin
    Exit;
  end;
  if AKind = 'Procedure' then
  begin
    RKind := rkProcedure;
  end
  else if IsTrigger then
  begin
    RKind := rkTrigger;
  end
  else
  begin
    RKind := rkFunction;
  end;
  if IsRoutine then
  begin
    ObjWord := RoutineWord[RKind];
  end
  else
  begin
    ObjWord := 'TABLE';
    if IsView then
    begin
      ObjWord := 'VIEW';
    end;
  end;
  ClearDetails('Details ' + #$C2#$B7 + ' ' + AName);
  FDetailsConn := AConnIndex;
  FDetailsDb := ARef.Database;
  FDetailsSchema := ARef.Schema;

  if IsTable then
  begin
    SetDetailsPages([dpColumns, dpIndexes, dpTriggers, dpGrants]);
  end
  else if IsView or IsMat then
  begin
    SetDetailsPages([dpColumns, dpDefinition]);
  end
  else if IsRoutine then
  begin
    SetDetailsPages([dpParameters, dpDefinition, dpGrants]);
  end
  else
  begin
    SetDetailsPages([dpDefinition]);
  end;

  try
    A := AdapterFor(AConnIndex, ARef.Database);
    if IsTable or IsView or IsMat then
    begin
      FDetailsColumns.ShowData(A.DescribeTable(C, AName));
    end;
    if IsTable then
    begin
      FDetailsIndexes.ShowData(A.DescribeIndexes(C, AName));
      try
        FDetailsTriggers.ShowData(A.DescribeTriggers(C, AName));
      except
        on E: Exception do
        begin
          FDetailsTriggers.ShowData(NoteResult('Trigger', 'Could not read the triggers: ' +
            E.Message));
        end;
      end;
    end;
    if IsRoutine then
    begin
      try
        FDetailsParams.ShowData(A.DescribeParameters(C, AName));
      except
        on E: Exception do
        begin
          FDetailsParams.ShowData(NoteResult('Parameters', 'Could not read the parameters: ' +
            E.Message));
        end;
      end;
    end;
    if IsView or IsMat or IsRoutine or IsTrigger or IsOther then
    begin
      LoadDefinition;
    end;
    if IsTable or IsRoutine then
    begin
      LoadGrants;
    end;
    if IsOther then
    begin
      FDetailsLabel.Caption := 'Details ' + #$C2#$B7 + ' ' + AName;
    end
    else
    begin
      FDetailsLabel.Caption := 'Details ' + #$C2#$B7 + ' ' + AName + '  (' + LowerCase(AKind) + ')';
    end;
    FDetailsShown := Key;
  except
    on E: Exception do
    begin
      ClearDetails('Details: could not read ' + AName);
    end;
  end;
end;

{ Double-click a trigger in a table's Triggers list: open it. }
procedure TpgnMainForm.DetailsTriggersDblClick(Sender: TObject);
var
  R: TpgnResultSet;
  N: Integer;
begin
  R := FDetailsTriggers.Data;
  N := FDetailsTriggers.Row - 1;
  if (R = nil) or (N < 0) or (N >= R.RowCount) or (Length(R.Columns) < 2) then
  begin
    Exit;   // nothing there, or only a note
  end;
  OpenRoutineTab(FDetailsConn, FDetailsDb, FDetailsSchema, R.Rows[N].Values[0], rkTrigger);
end;

{ TABLE, VIEW, PROCEDURE, FUNCTION or TRIGGER, for GRANT and friends. }
function TpgnMainForm.NodeObjectKind(ANode: TTreeNode): string;
begin
  Result := UpperCase(NodeObjectKindCaption(NodeKind(ANode)));
end;

{ ------------------------------------------ procedures, functions, triggers }

{ What the routine tab's Save button says: Toad calls it Compile. }
function TpgnMainForm.SaveWord: string;
begin
  if SameText(FSettings.Layout, LayoutAmphibian) then
  begin
    Result := 'Compile';
  end
  else
  begin
    Result := 'Save';
  end;
end;

function TpgnMainForm.RoutineKindOf(ANode: TTreeNode): TpgnRoutineKind;
begin
  case NodeKind(ANode) of
    nkFunction, nkFolderFuncs, nkFolderTrigFuncs:
      begin
        Result := rkFunction;
      end;
    nkTrigger, nkFolderTriggers, nkFolderTableTriggers:
      begin
        Result := rkTrigger;
      end;
  else
    begin
      Result := rkProcedure;
    end;
  end;
end;

{ Opens a procedure, function or trigger in a routine tab, or brings
  forward the tab that already has it. }
{ Opens a procedure, function or trigger in a routine tab, or brings
  forward the tab that already has it. ASchema is '' on engines without
  schemas. }
procedure TpgnMainForm.OpenRoutineTab(AConnIndex: Integer; const ADatabase, ASchema, AName: string;
  AKind: TpgnRoutineKind);
var
  I: Integer;
  T: TpgnQueryTab;
  A: TpgnAdapter;
  SQL, C: string;
  Page: TExtPage;
  Group: TExtPageCtrl;
begin
  if (AConnIndex < 0) or (AConnIndex > High(FExplorer)) then
  begin
    Exit;
  end;
  C := ASchema;
  if C = '' then
  begin
    C := ADatabase;
  end;
  for I := 0 to TabCount - 1 do
  begin
    T := TabAt(I);
    if T.IsRoutine and (T.RoutineKind = AKind) and (T.RoutineName = AName) and
      (T.RoutineDb = C) and (T.Info.Id = FExplorer[AConnIndex].Info.Id) and
      ((ASchema = '') or (T.CurrentDb = ADatabase)) then
    begin
      Page := PageOfTab(T);
      Group := GroupOfTab(T);
      Group.PageIndex := Group.IndexOfPage(Page);
      SetActiveTab(T);
      T.FocusEditor;
      Exit;
    end;
  end;
  if not EnsureExplorerConnected(AConnIndex) then
  begin
    Exit;
  end;
  try
    A := AdapterFor(AConnIndex, ADatabase);
    SQL := A.GetRoutineSQL(C, AName, AKind);
  except
    on E: Exception do
    begin
      SQL := '';   // opens read-only and says why
    end;
  end;
  T := NewTabOn(FExplorer[AConnIndex].Info, ADatabase, RoutineCaption[AKind] + ' ' +
    RoutineShortName(AName), ASchema);
  if T = nil then
  begin
    Exit;
  end;
  T.OnRoutineExecute := @TabRoutineExecute;
  T.SetSaveCaption(SaveWord);
  T.OpenRoutine(C, AName, AKind, SQL);
  T.FocusEditor;
end;

procedure TpgnMainForm.NewRoutineTab(AConnIndex: Integer; const ADatabase, ASchema: string;
  AKind: TpgnRoutineKind; const ASQL: string);
var
  T: TpgnQueryTab;
  C: string;
begin
  C := ASchema;
  if C = '' then
  begin
    C := ADatabase;
  end;
  T := NewTabOn(FExplorer[AConnIndex].Info, ADatabase, 'New ' + LowerCase(RoutineCaption[AKind]),
    ASchema);
  if T = nil then
  begin
    Exit;
  end;
  T.OnRoutineExecute := @TabRoutineExecute;
  T.SetSaveCaption(SaveWord);
  T.NewRoutine(C, AKind, ASQL);
  T.FocusEditor;
end;

{ Asks for the parameters, then runs the CALL (or SELECT) in a tab of its
  own, so the routine tab keeps its code. }
{ Asks for the parameters, then runs the call in a tab of its own, so the
  routine tab keeps its code. }
procedure TpgnMainForm.ExecuteRoutine(AConnIndex: Integer; const ADatabase, ASchema, AName: string;
  AKind: TpgnRoutineKind);
var
  A: TpgnAdapter;
  Params: TpgnResultSet;
  SQL, C: string;
  T: TpgnQueryTab;
  OK: Boolean;
begin
  if AKind = rkTrigger then
  begin
    Exit;   // triggers run by themselves
  end;
  if not EnsureExplorerConnected(AConnIndex) then
  begin
    Exit;
  end;
  C := ASchema;
  if C = '' then
  begin
    C := ADatabase;
  end;
  try
    A := AdapterFor(AConnIndex, ADatabase);
    Params := A.DescribeParameters(C, AName);
  except
    on E: Exception do
    begin
      ShowError('Could not read the parameters of ' + AName, E);
      Exit;
    end;
  end;
  try
    OK := ExecuteDialog(Self, A, C, AName, AKind, Params, SQL);
  finally
    Params.Free;
  end;
  if not OK then
  begin
    Exit;
  end;
  T := NewTabOn(FExplorer[AConnIndex].Info, ADatabase, 'Run ' + RoutineShortName(AName), ASchema);
  if T <> nil then
  begin
    T.SetText(SQL);
    T.RunScript;
  end;
end;

{ The Execute... button on a routine tab. }
{ The Execute... button on a routine tab. }
procedure TpgnMainForm.TabRoutineExecute(Sender: TObject);
var
  T: TpgnQueryTab;
  Idx: Integer;
begin
  T := Sender as TpgnQueryTab;
  Idx := ExplorerIndexOfId(T.Info.Id);
  if Idx < 0 then
  begin
    Exit;
  end;
  if T.IsModified and (MessageDlg(T.RoutineName + ' has changes that aren''t saved. ' +
    'Execute runs the version in the database. Run it anyway?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  if (T.Adapter <> nil) and T.Adapter.HasSchemas then
  begin
    ExecuteRoutine(Idx, T.CurrentDb, T.RoutineDb, T.RoutineName, T.RoutineKind);
  end
  else
  begin
    ExecuteRoutine(Idx, T.RoutineDb, '', T.RoutineName, T.RoutineKind);
  end;
end;

{ Amphibian: Toad's New Connection window, listing the saved connections.
  Plume: a new saved connection (the Explorer lists them). }
procedure TpgnMainForm.DoNewConnection(Sender: TObject);
begin
  if FAmph or FSea then
  begin
    ShowConnectWindow;
  end
  else
  begin
    NewSavedConnection;
  end;
end;

function TpgnMainForm.NewSavedConnection: Boolean;
var
  Info: TpgnConnectionInfo;
  I: Integer;
begin
  Result := False;
  Info := NewConnectionInfo;
  if EditConnection(Self, Info) then
  begin
    FStore.Add(Info);
    FStore.Save;
    AddExplorerRoot(Info);
    for I := 0 to TabCount - 1 do
    begin
      TabAt(I).RefreshConnectionList;
    end;
    UpdateActionStates;
    Result := True;
  end;
end;

procedure TpgnMainForm.DoEditConnection(Sender: TObject);
var
  Idx: Integer;
begin
  if FAmph then
  begin
    ShowConnectWindow;
    Exit;
  end;
  Idx := SelectedExplorerIndex;
  if Idx < 0 then
  begin
    MessageDlg('Select a connection in the Explorer first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  EditConnectionAt(Idx);
end;

function TpgnMainForm.EditConnectionAt(AIndex: Integer): Boolean;
var
  Idx, StoreIdx, I: Integer;
  Info, Old: TpgnConnectionInfo;
begin
  Result := False;
  Idx := AIndex;
  StoreIdx := FStore.IndexOfId(FExplorer[Idx].Info.Id);
  if StoreIdx < 0 then
  begin
    Exit;
  end;
  Info := FStore.Items[StoreIdx];
  Old := Info;
  if EditConnection(Self, Info) then
  begin
    Result := True;
    FStore.Items[StoreIdx] := Info;
    FStore.Save;
    // open sessions keep their server settings; name, label and color update now
    FExplorer[Idx].Info := Info;
    FExplorer[Idx].Root.Text := ConnectionLabel(Info);
    // a different server or user needs the password again; a new name,
    // label or color doesn't
    if (Old.Host <> Info.Host) or (Old.Port <> Info.Port) or (Old.User <> Info.User) or
      (Old.Engine <> Info.Engine) then
    begin
      ForgetPassword(Info.Id);
    end;
    for I := 0 to TabCount - 1 do
    begin
      TabAt(I).RefreshConnectionList;
      TabAt(I).UpdateConnectionInfo(Info);
    end;
    RefreshStatus;
  end;
end;

procedure TpgnMainForm.DoDeleteConnection(Sender: TObject);
var
  Idx: Integer;
begin
  if FAmph then
  begin
    ShowConnectWindow;
    Exit;
  end;
  Idx := SelectedExplorerIndex;
  if Idx < 0 then
  begin
    MessageDlg('Select a connection in the Explorer first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  DeleteConnectionAt(Idx);
end;

function TpgnMainForm.DeleteConnectionAt(AIndex: Integer): Boolean;
var
  Idx, StoreIdx, I: Integer;
  Id: string;
begin
  Result := False;
  Idx := AIndex;
  if MessageDlg('Delete the saved connection "' + FExplorer[Idx].Info.Name + '"?' + LineEnding +
    'Tabs already using it stay connected until you close them.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;

  Id := FExplorer[Idx].Info.Id;
  DisconnectExplorer(Idx);
  FreeAndNil(FExplorer[Idx].Sessions);
  FExplorer[Idx].Root.Delete;
  ForgetPassword(Id);
  for I := Idx to High(FExplorer) - 1 do
  begin
    FExplorer[I] := FExplorer[I + 1];
  end;
  SetLength(FExplorer, Length(FExplorer) - 1);
  StoreIdx := FStore.IndexOfId(Id);
  if StoreIdx >= 0 then
  begin
    FStore.Delete(StoreIdx);
    FStore.Save;
  end;
  for I := 0 to TabCount - 1 do
  begin
    TabAt(I).RefreshConnectionList;
  end;
  UpdateActionStates;
  Result := True;
end;

procedure TpgnMainForm.DoExitApp(Sender: TObject);
begin
  Close;
end;

{ A new tab starts on the active tab's connection and database. }
procedure TpgnMainForm.DoNewTab(Sender: TObject);
var
  Idx: Integer;
  Db: string;
begin
  if FSea then
  begin
    // as SSMS: New Query opens on what's selected in Object Explorer
    Idx := ExplorerIndexOfNode(FTree.Selected);
    if (Idx >= 0) and (FExplorer[Idx].Adapter <> nil) then
    begin
      Db := DatabaseOf(FTree.Selected);
      if Db = '' then
      begin
        Db := FExplorer[Idx].Info.DefaultDatabase;
      end;
      NewTabOn(FExplorer[Idx].Info, Db, '');
      Exit;
    end;
  end;
  if (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    NewTabOn(FActiveTab.Info, FActiveTab.CurrentDb, '');
  end
  else
  begin
    NewTab('');
  end;
end;

procedure TpgnMainForm.DoCloseTab(Sender: TObject);
begin
  CloseTab(FActiveTab);
end;

procedure TpgnMainForm.DoNextTab(Sender: TObject);
begin
  SelectAdjacentTab(True);
end;

procedure TpgnMainForm.DoPrevTab(Sender: TObject);
begin
  SelectAdjacentTab(False);
end;

procedure TpgnMainForm.DoAbout(Sender: TObject);
begin
  ShowAbout(Self);
end;

{ Seattle's Query > Results To: Grid, Text or File, for the tab in use
  (as SSMS, each query window keeps its own). }
procedure TpgnMainForm.DoResultsTo(Sender: TObject);
begin
  if FUpdatingChecks then
  begin
    Exit;
  end;
  if (FActiveTab <> nil) and FSea then
  begin
    FActiveTab.ResultsMode := (Sender as TAction).Tag;
    UpdateActionStates;
  end;
end;

{ Side by Side keeps the tabs' left-to-right order: from the first tab on
  the left, the tab after it goes right (tab1 | tab2), and the first tab
  stays the one you're in; from any other tab, that tab goes right. When
  already side by side: from a right-hand tab, that tab comes back; from a
  left-hand tab, they all do. }
procedure TpgnMainForm.DoMoveTab(Sender: TObject);
var
  Keep, Other: TpgnQueryTab;
begin
  Keep := FActiveTab;
  // from a left-hand tab while split: the right-hand tabs all come back
  if (Keep <> nil) and (GroupOfTab(Keep) = FLeftPages) and (FRightPages.PageCount > 0) then
  begin
    while FRightPages.PageCount > 0 do
    begin
      Other := TabOfPage(FRightPages.Page[0]);
      if Other = nil then
      begin
        Break;
      end;
      MoveTab(Other);
    end;
    FLeftPages.PageIndex := FLeftPages.IndexOfPage(PageOfTab(Keep));
    SetActiveTab(Keep);
    Keep.FocusEditor;
    Exit;
  end;
  if (Keep <> nil) and (GroupOfTab(Keep) = FLeftPages) and (FLeftPages.PageCount >= 2) and
    (FLeftPages.IndexOfPage(PageOfTab(Keep)) = 0) then
  begin
    Other := TabOfPage(FLeftPages.Page[1]);
    if Other <> nil then
    begin
      MoveTab(Other);
      FLeftPages.PageIndex := FLeftPages.IndexOfPage(PageOfTab(Keep));
      SetActiveTab(Keep);
      Keep.FocusEditor;
      Exit;
    end;
  end;
  MoveTab(Keep);
end;

procedure TpgnMainForm.DoRenameTab(Sender: TObject);
var
  S: string;
begin
  if FActiveTab = nil then
  begin
    Exit;
  end;
  S := FActiveTab.Title;
  if InputQuery('Rename Tab', 'Tab name:', S) and (Trim(S) <> '') then
  begin
    FActiveTab.Title := Trim(S);
    TabStateChanged(FActiveTab);
  end;
end;

{ Opens into the current tab if it's empty, otherwise into a new tab on
  the current tab's connection. }
procedure TpgnMainForm.DoOpenFile(Sender: TObject);
var
  D: TOpenDialog;
  T: TpgnQueryTab;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Open SQL';
    D.Filter := 'SQL files (*.sql)|*.sql|All files|*';
    D.InitialDir := FLastDir;
    if not D.Execute then
    begin
      Exit;
    end;
    if (FActiveTab <> nil) and FActiveTab.IsEmpty and not FActiveTab.IsRunning then
    begin
      T := FActiveTab;
    end
    else if (FActiveTab <> nil) and FActiveTab.IsConnected then
    begin
      T := NewTabOn(FActiveTab.Info, FActiveTab.CurrentDb, '');
      if T = nil then
      begin
        T := NewTab('');
      end;
    end
    else
    begin
      T := NewTab('');
    end;
    try
      T.LoadFromFile(D.FileName);
      FLastDir := ExtractFileDir(D.FileName);
    except
      on E: Exception do
      begin
        ShowError('Could not open ' + D.FileName, E);
      end;
    end;
  finally
    D.Free;
  end;
end;

procedure TpgnMainForm.DoSaveFile(Sender: TObject);
begin
  SaveTab(FActiveTab, False);
end;

procedure TpgnMainForm.DoSaveFileAs(Sender: TObject);
begin
  SaveTab(FActiveTab, True);
end;

procedure TpgnMainForm.DoRunStatement(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.RunStatement;
  end;
end;

procedure TpgnMainForm.DoRunScript(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.RunScript;
  end;
end;

procedure TpgnMainForm.DoExplain(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Explain;
  end;
end;

procedure TpgnMainForm.DoCancel(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Cancel;
  end;
end;

{ The Describe window for the name under the cursor (F4 in Amphibian,
  Alt+F1 in Plume and Seattle). The name is looked up as the database
  would (Oracle: your schema, then synonyms), on the connection's Explorer
  session, so a query running in the tab doesn't matter. }
procedure TpgnMainForm.DoDescribe(Sender: TObject);
var
  T: TpgnQueryTab;
  Ident, Default, Via: string;
  Idx: Integer;
  A: TpgnAdapter;
  Ref: TpgnObjectRef;
  Found: Boolean;
begin
  T := FActiveTab;
  if (T = nil) or not T.IsConnected then
  begin
    Exit;
  end;
  Ident := T.IdentifierAtCaret;
  if Ident = '' then
  begin
    T.Log('Describe: put the cursor on a table, view or procedure name first');
    Exit;
  end;
  Idx := ExplorerIndexOfId(T.Info.Id);
  if (Idx < 0) or not EnsureExplorerConnected(Idx) then
  begin
    Exit;
  end;
  if T.Adapter.HasSchemas then
  begin
    Default := T.Adapter.CurrentSchema;
  end
  else
  begin
    Default := T.CurrentDb;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      A := AdapterFor(Idx, T.CurrentDb);
      Found := A.ResolveObject(Ident, Default, Ref, Via);
    except
      on E: Exception do
      begin
        Screen.Cursor := crDefault;
        ShowError('Could not look up ' + Ident, E);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if not Found then
  begin
    T.Log('Describe: ' + Ident + ': no table, view, synonym or procedure by that name that your login can see');
    T.Notice(Ident + ': nothing by that name');
    Exit;
  end;
  // one window: a new object is a new tab in it
  if FDescribeWin = nil then
  begin
    FDescribeWin := TpgnDescribeWindow.CreateIn(Self, FSettings.Layout, FSettings.Theme,
      @DescribeAdapter, @DescribeReveal, @DescribeResolve);
    FDescribeWin.OnDestroy := @DescribeWinDestroyed;
  end;
  FDescribeWin.AddObject(T.Info.Id, ConnectionLongLabel(T.Info), Ref, Via, T.Adapter.Dialect);
  FDescribeWin.Show;
  FDescribeWin.BringToFront;
end;

procedure TpgnMainForm.DescribeWinDestroyed(Sender: TObject);
begin
  if Sender = FDescribeWin then
  begin
    FDescribeWin := nil;
  end;
end;

{ The Describe window's +: a name looked up on that connection, in the
  active tab's database and schema when the tab is on it. }
function TpgnMainForm.DescribeResolve(const AConnId, AName: string; out ARef: TpgnObjectRef;
  out AVia: string): Boolean;
var
  Idx: Integer;
  Db, Default: string;
  A: TpgnAdapter;
begin
  Result := False;
  AVia := '';
  Idx := ExplorerIndexOfId(AConnId);
  if (Idx < 0) or not EnsureExplorerConnected(Idx) then
  begin
    Exit;
  end;
  Db := '';
  Default := '';
  if (FActiveTab <> nil) and FActiveTab.IsConnected and (FActiveTab.Info.Id = AConnId) then
  begin
    Db := FActiveTab.CurrentDb;
    if FActiveTab.Adapter.HasSchemas then
    begin
      Default := FActiveTab.Adapter.CurrentSchema;
    end
    else
    begin
      Default := Db;
    end;
  end;
  A := AdapterFor(Idx, Db);
  if (Default = '') and (A <> nil) then
  begin
    if A.HasSchemas then
    begin
      Default := A.CurrentSchema;
    end
    else
    begin
      Default := A.CurrentDatabase;
    end;
  end;
  if A <> nil then
  begin
    Result := A.ResolveObject(AName, Default, ARef, AVia);
  end;
end;

function TpgnMainForm.DescribeAdapter(const AConnId, ADatabase: string): TpgnAdapter;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ExplorerIndexOfId(AConnId);
  if (Idx < 0) or (FExplorer[Idx].Adapter = nil) then
  begin
    Exit;
  end;
  Result := AdapterFor(Idx, ADatabase);
end;

{ Show in Schema Browser / Object Explorer / Explorer. }
procedure TpgnMainForm.DescribeReveal(const AConnId: string; const ARef: TpgnObjectRef);
var
  Idx: Integer;
  Node: TTreeNode;
begin
  Idx := ExplorerIndexOfId(AConnId);
  if (Idx < 0) or not EnsureExplorerConnected(Idx) then
  begin
    Exit;
  end;
  BringToFront;
  if FAmph and (FBrowser <> nil) then
  begin
    ShowSchemaBrowser;
    if FBrowser.ConnIndex <> Idx then
    begin
      FBrowser.Attach(Idx, FExplorer[Idx].Info, FExplorer[Idx].Adapter);
    end;
    FBrowser.ShowObject(ARef);
    Exit;
  end;
  Node := nil;
  try
    Node := RevealObject(Idx, ARef);
  except
    on E: Exception do
    begin
      ShowError('Could not open the Explorer to ' + ARef.Name, E);
    end;
  end;
  if Node <> nil then
  begin
    FFilterEdit.Text := '';
    FTree.Selected := Node;
    Node.MakeVisible;
    if FTree.CanFocus then
    begin
      FTree.SetFocus;
    end;
  end;
end;

function TpgnMainForm.PickFromHistory: string;
var
  F: TForm;
  LB: TListBox;
  P: TPanel;
  BOK, BCancel: TButton;
  I: Integer;
  Preview: string;
begin
  Result := '';
  F := TForm.CreateNew(Self);
  SmoothFont(F.Font);
  try
    F.Caption := 'SQL History';
    F.Width := 720;
    F.Height := 460;
    F.Position := poOwnerFormCenter;

    P := TPanel.Create(F);
    P.Parent := F;
    P.Align := alBottom;
    P.Height := 44;
    P.BevelOuter := bvNone;

    BCancel := TButton.Create(F);
    BCancel.Parent := P;
    BCancel.Caption := 'Cancel';
    BCancel.ModalResult := mrCancel;
    BCancel.Cancel := True;
    BCancel.Align := alRight;
    BCancel.Width := Scale96ToScreen(90);
    BCancel.BorderSpacing.Around := 8;

    BOK := TButton.Create(F);
    BOK.Parent := P;
    BOK.Caption := 'Put in Editor';
    BOK.ModalResult := mrOK;
    BOK.Default := True;
    BOK.Align := alRight;
    BOK.Width := Scale96ToScreen(130);   // room for the words
    BOK.BorderSpacing.Around := 8;

    LB := TListBox.Create(F);
    LB.Parent := F;
    LB.Align := alClient;
    for I := FHistory.Count - 1 downto 0 do
    begin
      Preview := StringReplace(FHistory[I], LineEnding, ' ', [rfReplaceAll]);
      LB.Items.AddObject(Preview, TObject(PtrInt(I)));
    end;
    if LB.Items.Count > 0 then
    begin
      LB.ItemIndex := 0;
    end;

    if (F.ShowModal = mrOK) and (LB.ItemIndex >= 0) then
    begin
      Result := FHistory[PtrInt(LB.Items.Objects[LB.ItemIndex])];
    end;
  finally
    F.Free;
  end;
end;

procedure TpgnMainForm.DoHistory(Sender: TObject);
var
  S: string;
begin
  if (FHistory.Count = 0) or (FActiveTab = nil) then
  begin
    Exit;
  end;
  S := PickFromHistory;
  if S <> '' then
  begin
    FActiveTab.InsertText(S, False);
  end;
end;

procedure TpgnMainForm.DoOptions(Sender: TObject);
begin
  if EditOptions(Self, FSettings) then
  begin
    ApplyCurrentKeymap;
  end;
end;

procedure TpgnMainForm.DoRefreshAll(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FExplorer) do
  begin
    if FExplorer[I].Adapter <> nil then
    begin
      RefreshConnection(I, '', True);
    end;
  end;
  for I := 0 to TabCount - 1 do
  begin
    if TabAt(I).IsConnected and not TabAt(I).IsRunning then
    begin
      TabAt(I).ReloadDatabaseList;
    end;
  end;
end;

{ Commit acts on the tab in view when it has work waiting; when only other
  tabs do, the Pending Statements window opens on them to choose. }
procedure TpgnMainForm.DoCommit(Sender: TObject);
begin
  if (FActiveTab <> nil) and FActiveTab.IsConnected and not FActiveTab.Adapter.AutoCommit and
    ((FActiveTab.PendingCount > 0) or (FirstPendingTab = nil)) then
  begin
    FActiveTab.Commit;
  end
  else if FirstPendingTab <> nil then
  begin
    DoPending(nil);
  end;
  RefreshStatus;
  UpdateActionStates;
end;

procedure TpgnMainForm.DoRollback(Sender: TObject);
begin
  if (FActiveTab <> nil) and FActiveTab.IsConnected and not FActiveTab.Adapter.AutoCommit and
    ((FActiveTab.PendingCount > 0) or (FirstPendingTab = nil)) then
  begin
    FActiveTab.Rollback;
  end
  else if FirstPendingTab <> nil then
  begin
    DoPending(nil);
  end;
  RefreshStatus;
  UpdateActionStates;
end;

{ The first tab other than the one in view with statements waiting for
  Commit, or nil. }
function TpgnMainForm.FirstPendingTab: TpgnQueryTab;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to TabCount - 1 do
  begin
    if (TabAt(I) <> FActiveTab) and TabAt(I).IsConnected and (TabAt(I).PendingCount > 0) then
    begin
      Result := TabAt(I);
      Exit;
    end;
  end;
end;

{ Every tab with statements waiting, the one in view first. }
function TpgnMainForm.PendingTabs: TpgnTabArray;
var
  I: Integer;

  procedure AddTab(T: TpgnQueryTab);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := T;
  end;

begin
  Result := nil;
  if (FActiveTab <> nil) and FActiveTab.IsConnected and (FActiveTab.PendingCount > 0) then
  begin
    AddTab(FActiveTab);
  end;
  for I := 0 to TabCount - 1 do
  begin
    if (TabAt(I) <> FActiveTab) and TabAt(I).IsConnected and (TabAt(I).PendingCount > 0) then
    begin
      AddTab(TabAt(I));
    end;
  end;
end;

procedure TpgnMainForm.DoCut(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.CutToClipboard;
  end;
end;

procedure TpgnMainForm.DoCopy(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.CopyToClipboard;
  end;
end;

procedure TpgnMainForm.DoPaste(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.PasteFromClipboard;
  end;
end;

procedure TpgnMainForm.DoSelectAll(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.SelectAll;
  end;
end;

procedure TpgnMainForm.DoToggleComment(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.ToggleComment;
  end;
end;

procedure TpgnMainForm.DoComment(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.CommentLines(cmComment);
  end;
end;

procedure TpgnMainForm.DoUncomment(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.CommentLines(cmUncomment);
  end;
end;

procedure TpgnMainForm.DoBlockComment(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.BlockComment;
  end;
end;

{ Two-key shortcuts for the Seattle keymap, as in SSMS:
  Ctrl+K Ctrl+C comments, Ctrl+K Ctrl+U uncomments. The editor recognizes
  the pair (see ApplyKeysToEditor) and sends the command here. }
procedure TpgnMainForm.EditorUserCommand(Sender: TObject; var Command: TSynEditorCommand;
  var AChar: TUTF8Char; Data: Pointer);
begin
  // The edit runs just after the editor finishes handling the key, not in
  // the middle of it, so the editor can't undo or swallow the change.
  if Command = ecPgnComment then
  begin
    Command := ecNone;
    Application.QueueAsyncCall(@AsyncCommentLines, Ord(cmComment));
  end
  else if Command = ecPgnUncomment then
  begin
    Command := ecNone;
    Application.QueueAsyncCall(@AsyncCommentLines, Ord(cmUncomment));
  end;
end;

procedure TpgnMainForm.AsyncCommentLines(AData: PtrInt);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.CommentLines(TpgnCommentMode(AData));
  end;
end;

procedure TpgnMainForm.DoUpper(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.ChangeCase(True);
  end;
end;

procedure TpgnMainForm.DoLower(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.ChangeCase(False);
  end;
end;

procedure TpgnMainForm.DoSelectKeymap(Sender: TObject);
begin
  if FUpdatingChecks then
  begin
    Exit;
  end;
  if (Sender as TMenuItem).Tag = 0 then
  begin
    FSettings.Keymap := KeymapMatchLayout;
  end
  else
  begin
    FSettings.Keymap := KeymapNames[(Sender as TMenuItem).Tag - 1];
  end;
  FSettings.Save;
  ApplyCurrentKeymap;
end;

procedure TpgnMainForm.DoSelectTheme(Sender: TObject);
var
  I: Integer;
begin
  if FUpdatingChecks then
  begin
    Exit;
  end;
  FSettings.Theme := ThemeNames[(Sender as TMenuItem).Tag];
  FSettings.Save;
  FUpdatingChecks := True;
  try
    for I := 0 to High(FThemeItems) do
    begin
      FThemeItems[I].Checked := I = (Sender as TMenuItem).Tag;
    end;
  finally
    FUpdatingChecks := False;
  end;
  for I := 0 to TabCount - 1 do
  begin
    TabAt(I).ApplyTheme(FSettings.Theme);
  end;
end;

procedure TpgnMainForm.DoAutoCommit(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.ToggleAutoCommit;
  end;
end;

procedure TpgnMainForm.DoDisconnect(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Disconnect;
  end;
end;

procedure TpgnMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
begin
  if FCloseChecked then
  begin
    CanClose := True;
    Exit;
  end;
  CanClose := False;
  for I := 0 to TabCount - 1 do
  begin
    if TabAt(I).IsRunning then
    begin
      MessageDlg('A query is still running in "' + TabAt(I).Title +
        '". Cancel it before closing Pagona.', mtInformation, [mbOK], 0);
      Exit;
    end;
  end;
  for I := 0 to TabCount - 1 do
  begin
    if not ConfirmCloseTab(TabAt(I), 'closing Pagona') then
    begin
      Exit;
    end;
  end;
  CanClose := True;
end;


{ ================================================================ looks }

{ Gives the frame (panels, bars, headers, status bar) the look's colors.
  The editor, grids and environment colors don't change. }
procedure TpgnMainForm.RecolorFrame;
var
  I: Integer;

  procedure Bar(C: TControl);
  begin
    if C <> nil then
    begin
      C.Color := clPgnBar;
      C.Invalidate;
    end;
  end;

begin
  Color := clPgnSurface;
  FExplorerPanel.ParentColor := False;
  FExplorerPanel.Color := clPgnSurface;
  FExplorerHeader.ParentColor := False;
  FExplorerHeader.Color := clPgnHeader;
  FExplorerTitle.Font.Color := clPgnHeaderText;
  FTabArea.ParentColor := False;
  FTabArea.Color := clPgnSurface;
  Bar(FToolBar);
  Bar(FEditorBar);
  Bar(FOEBar);
  Bar(FSqlLeft);
  Bar(FSqlHost);
  Bar(FPickPanel);
  Bar(FSessionBar);
  Bar(FWindowBar);
  if (FEditorBar <> nil) and (FEditorBar.Parent <> nil) and (FEditorBar.Parent <> FSqlHost) then
  begin
    Bar(FEditorBar.Parent);    // Amphibian's editor toolbar row
  end;
  FStatus.Color := clPgnStatus;
  FStatus.Invalidate;
  for I := 0 to TabCount - 1 do
  begin
    TabAt(I).RecolorFrame;
  end;
end;

procedure TpgnMainForm.ColorMenu;
begin
  if FMainMenu.HandleAllocated and HandleAllocated then
  begin
    ColorMenuBar(PtrUInt(FMainMenu.Handle), PtrUInt(Handle), clPgnMenu);
  end;
end;

procedure TpgnMainForm.AsyncColorMenu(AData: PtrInt);
begin
  ColorMenu;
end;

procedure TpgnMainForm.DoSelectLook(Sender: TObject);
var
  N: Integer;
begin
  if FUpdatingChecks then
  begin
    Exit;
  end;
  N := (Sender as TMenuItem).Tag;
  if N = 0 then
  begin
    FSettings.Look := LookMatchLayout;
  end
  else
  begin
    FSettings.Look := LookNames[N - 1];
  end;
  FSettings.Save;
  ApplyLook(EffectiveLook(FSettings.Look, FSettings.Layout));
  RecolorFrame;
  ColorMenu;
  ApplyCurrentKeymap;   // sets the radio checks
end;


{ ============================================================== Seattle }

{ SSMS's menus, with a query window open: File, Edit, View, Query, Tools,
  Window (Git, Project, Extensions and Help are left out). }
procedure TpgnMainForm.BuildSeattleMenu;
var
  M, Sub, Item: TMenuItem;
  I: Integer;
begin
  M := AddMenu(FMainMenu.Items, '&File');
  AddActionItem(M, FActNewTab);
  AddActionItem(M, FActOpen);
  AddSeparator(M);
  AddActionItem(M, FActSave);
  AddActionItem(M, FActSaveAs);
  AddSeparator(M);
  AddActionItem(M, FActCloseTab);
  AddSeparator(M);
  AddActionItem(M, FActConnectOE);
  AddActionItem(M, FActDisconnectOE);
  AddSeparator(M);
  AddActionItem(M, FActExit);

  M := AddMenu(FMainMenu.Items, '&Edit');
  AddActionItem(M, FActUndo);
  AddActionItem(M, FActRedo);
  AddSeparator(M);
  AddActionItem(M, FActCut);
  AddActionItem(M, FActCopy);
  AddActionItem(M, FActPaste);
  AddActionItem(M, FActSelectAll);
  AddSeparator(M);
  Sub := AddMenu(M, '&Find and Replace');
  AddActionItem(Sub, FActFind);
  AddActionItem(Sub, FActFindNext);
  AddActionItem(Sub, FActReplace);
  Sub := AddMenu(M, 'Ad&vanced');
  AddActionItem(Sub, FActComment);
  AddActionItem(Sub, FActUncomment);
  AddActionItem(Sub, FActUpper);
  AddActionItem(Sub, FActLower);
  AddActionItem(Sub, FActIndent);
  AddActionItem(Sub, FActOutdent);

  M := AddMenu(FMainMenu.Items, '&View');
  AddActionItem(M, FActOEFilter);
  AddActionItem(M, FActRefreshAll);
  AddSeparator(M);
  AddLayoutMenu(M);
  AddKeymapThemeMenus(M);

  M := AddMenu(FMainMenu.Items, '&Query');
  Sub := AddMenu(M, '&Connection');
  AddActionItem(Sub, FActConnectTab);
  AddActionItem(Sub, FActDisconnect);
  AddActionItem(Sub, FActChangeConn);
  AddSeparator(M);
  AddActionItem(M, FActRunScript);
  AddActionItem(M, FActRunStatement);
  AddActionItem(M, FActCancel);
  AddSeparator(M);
  AddActionItem(M, FActExplain);
  AddSeparator(M);
  Sub := AddMenu(M, 'Results &To');
  // check items from the start: GTK makes the check widget only when the
  // item is created checkable
  for I := 0 to 2 do
  begin
    Item := TMenuItem.Create(Self);
    Item.ShowAlwaysCheckable := True;
    case I of
      0:
        begin
          Item.Action := FActResGrid;
        end;
      1:
        begin
          Item.Action := FActResText;
        end;
    else
      begin
        Item.Action := FActResFile;
      end;
    end;
    Sub.Add(Item);
  end;
  AddSeparator(M);
  AddActionItem(M, FActDescribe);
  AddActionItem(M, FActHistory);
  AddSeparator(M);
  AddActionItem(M, FActPending);
  AddActionItem(M, FActAutoCommit);

  // DBA screens open from Object Explorer, as in SSMS; Tools keeps the log
  M := AddMenu(FMainMenu.Items, '&Tools');
  AddActionItem(M, FActDbaLog);
  AddSeparator(M);
  AddActionItem(M, FActOptions);

  M := AddMenu(FMainMenu.Items, '&Window');
  AddActionItem(M, FActMoveTab);
  AddSeparator(M);
  AddActionItem(M, FActNextTab);
  AddActionItem(M, FActPrevTab);
  AddActionItem(M, FActRenameTab);
  AddActionItem(M, FActCloseTab);

  M := AddMenu(FMainMenu.Items, '&Help');
  AddActionItem(M, FActAbout);
end;

{ Object Explorer on the left with its own bar, no Details under it; the
  SQL Editor toolbar under the main toolbar: Connect, Change Connection,
  the database box, Execute, Stop, ... }
procedure TpgnMainForm.BuildSeattleArea;
var
  I: Integer;
  Saved: string;
begin
  FExplorerTitle.Caption := 'Object Explorer';
  FExplorerRefresh.Align := alNone;
  FExplorerRefresh.SetBounds(-3000, 0, 80, 24);
  // SSMS has no Details panel under Object Explorer
  FDetailsPanel.Align := alNone;
  FDetailsPanel.SetBounds(-5000, 0, 290, 240);
  FDetailsSplitter.Align := alNone;
  FDetailsSplitter.SetBounds(-5000, 0, 10, 5);

  if FOEMenu = nil then
  begin
    FOEMenu := TPopupMenu.Create(Self);
    AddActionItem(FOEMenu.Items, FActConnectOE);
    AddActionItem(FOEMenu.Items, FActNewConn);
  end;
  FOEBar := TpgnToolbar.Create(Self);
  FOEBar.Parent := FExplorerPanel;
  FOEBar.Align := alTop;
  FOEBar.Top := FExplorerHeader.Top + FExplorerHeader.Height + 1;
  FOEBar.Height := Scale96ToScreen(30);
  FOEBar.IconOnly := True;
  FOEBar.AddIconDef('connectmenu', 'Connect', FActConnectOE, icNone, isTwoTone);
  FOEBar.AddIconDef('connect', 'Connect Object Explorer', FActConnectOE, icConnect, isTwoTone);
  FOEBar.AddIconDef('disconnect', 'Disconnect', FActDisconnectOE, icDisconnect, isTwoTone);
  FOEBar.AddIconDef('filter', 'Filter', FActOEFilter, icFilter, isTwoTone);
  FOEBar.AddIconDef('refresh', 'Refresh', FActRefreshAll, icRefresh, isTwoTone);
  FOEBar.AddIconDef('activity', 'Activity Monitor', FActDbaSessions, icActivity, isTwoTone);
  FOEBar.SetDropMenu('connectmenu', FOEMenu);
  FOEBar.DefaultArrangement := 'connectmenu,connect,disconnect,|,filter,refresh,|,activity';
  FOEBar.SetArrangement(FOEBar.DefaultArrangement);
  FOEFilterShown := False;
  PlaceOEFilter;

  // the SQL Editor toolbar
  FSqlHost := TPanel.Create(Self);
  FSqlHost.Parent := Self;
  FSqlHost.Align := alTop;
  FSqlHost.Top := FToolBar.Top + FToolBar.Height + 1;
  FSqlHost.Height := Scale96ToScreen(32);
  FSqlHost.BevelOuter := bvNone;
  FSqlHost.Caption := '';
  FSqlHost.Color := clPgnSurface;
  FSqlHost.ParentColor := False;

  FSqlLeft := TpgnToolbar.Create(Self);
  FSqlLeft.Parent := FSqlHost;
  FSqlLeft.Align := alLeft;
  FSqlLeft.Width := Scale96ToScreen(62);
  FSqlLeft.IconOnly := True;
  FSqlLeft.AddIconDef('connect', 'Connect', FActConnectTab, icConnect, isTwoTone);
  FSqlLeft.AddIconDef('change', 'Change Connection', FActChangeConn, icChangeConn, isTwoTone);
  FSqlLeft.DefaultArrangement := 'connect,change';
  FSqlLeft.SetArrangement(FSqlLeft.DefaultArrangement);

  FPickPanel := TPanel.Create(Self);
  FPickPanel.Parent := FSqlHost;
  FPickPanel.Align := alLeft;
  FPickPanel.Left := FSqlLeft.Left + FSqlLeft.Width + 1;
  FPickPanel.Width := Scale96ToScreen(200);
  FPickPanel.BevelOuter := bvNone;
  FPickPanel.Caption := '';
  FPickPanel.Color := clPgnSurface;
  FPickPanel.ParentColor := False;
  FPickPanel.OnResize := @LayoutPicks;
  for I := 0 to 2 do
  begin
    FPickLabels[I] := TLabel.Create(Self);
    FPickLabels[I].Parent := FPickPanel;
    FPickLabels[I].AutoSize := False;
    FPickLabels[I].Width := 0;
    FPickLabels[I].Caption := '';
    FPicks[I] := TComboBox.Create(Self);
    FPicks[I].Parent := FPickPanel;
    FPicks[I].Style := csDropDownList;
    FPicks[I].AutoSize := False;
    FPicks[I].Tag := I;
    FPicks[I].OnChange := @PickChange;
  end;
  FPicks[1].Hint := 'Available Databases';
  FPicks[1].ShowHint := True;

  FEditorBar := TpgnToolbar.Create(Self);
  FEditorBar.Parent := FSqlHost;
  FEditorBar.Align := alClient;
  FEditorBar.IconOnly := True;
  FEditorBar.AddIconDef('execute', 'Execute', FActRunScript, icRun, isBold, True);
  FEditorBar.AddIconDef('stop', 'Cancel Executing Query', FActCancel, icStop, isBold);
  FEditorBar.AddIconDef('runstatement', 'Execute Current Statement', FActRunStatement, icScript, isBold);
  FEditorBar.AddIconDef('explain', 'Display Estimated Execution Plan', FActExplain, icExplain, isTwoTone);
  FEditorBar.AddIconDef('describe', 'Describe Object', FActDescribe, icDescribe, isTwoTone);
  FEditorBar.AddIconDef('history', 'Query History', FActHistory, icHistory, isTwoTone);
  FEditorBar.AddIconDef('comment', 'Comment Out the Selected Lines', FActComment, icComment, isTwoTone);
  FEditorBar.AddIconDef('uncomment', 'Uncomment the Selected Lines', FActUncomment, icUncomment, isTwoTone);
  FEditorBar.AddIconDef('outdent', 'Decrease Indent', FActOutdent, icOutdent, isTwoTone);
  FEditorBar.AddIconDef('indent', 'Increase Indent', FActIndent, icIndent, isTwoTone);
  FEditorBar.AddIconDef('upper', 'Make Uppercase', FActUpper, icUpper, isTwoTone);
  FEditorBar.AddIconDef('lower', 'Make Lowercase', FActLower, icLower, isTwoTone);
  FEditorBar.AddIconDef('find', 'Find', FActFind, icFind, isTwoTone);
  FEditorBar.AddIconDef('transactions', 'Transactions', FActPending, icCommit, isTwoTone);
  FEditorBar.DefaultArrangement := DefaultToolbar(LayoutSeattle + '.Editor');
  Saved := FSettings.Toolbars.Values[LayoutSeattle + '.Editor'];
  if Saved = '' then
  begin
    Saved := FEditorBar.DefaultArrangement;
  end;
  FEditorBar.SetArrangement(Saved);
  FEditorBar.OnChanged := @EditorBarChanged;

  FMirrorTimer := TTimer.Create(Self);
  FMirrorTimer.Enabled := False;
  FMirrorTimer.Interval := 400;
  FMirrorTimer.OnTimer := @MirrorTimerTick;
end;

{ Takes the Seattle pieces away, giving Plume's Explorer back. }
procedure TpgnMainForm.TearDownSeattle;
var
  I: Integer;
  Root: TTreeNode;
begin
  if FMirrorTimer <> nil then
  begin
    FMirrorTimer.Enabled := False;
    FreeAndNil(FMirrorTimer);
  end;
  FreeAndNil(FSqlHost);      // its toolbars and the database box
  FSqlLeft := nil;
  FEditorBar := nil;
  FPickPanel := nil;
  for I := 0 to 2 do
  begin
    FPicks[I] := nil;
    FPickLabels[I] := nil;
  end;
  FreeAndNil(FOEBar);
  FExplorerTitle.Caption := 'Explorer';
  FExplorerRefresh.Align := alRight;
  FFilterEdit.Align := alTop;
  FFilterEdit.Top := FExplorerHeader.Top + FExplorerHeader.Height + 1;
  FDetailsSplitter.Align := alBottom;
  FDetailsSplitter.Top := FExplorerPanel.ClientHeight + 50;
  for I := 0 to High(FExplorer) do
  begin
    Root := FExplorer[I].Root;
    Root.Visible := True;
    Root.Text := ConnectionLabel(FExplorer[I].Info);
  end;
end;

{ Seattle shows only the servers in use, named as SSMS names them:
  "TEST · HOMEONE (SQL Server 17.0 - randy)". }
procedure TpgnMainForm.SyncSeattleRoots;
var
  I, J: Integer;
  Want: Boolean;
  Txt, Ver: string;
  Root: TTreeNode;
begin
  if not FSea then
  begin
    Exit;
  end;
  for I := 0 to High(FExplorer) do
  begin
    Root := FExplorer[I].Root;
    Want := FExplorer[I].Adapter <> nil;
    for J := 0 to TabCount - 1 do
    begin
      if (not Want) and TabAt(J).IsConnected and (TabAt(J).Info.Id = FExplorer[I].Info.Id) then
      begin
        Want := True;
      end;
    end;
    Txt := FExplorer[I].Info.Name;
    if FExplorer[I].Adapter <> nil then
    begin
      Ver := FExplorer[I].Adapter.ServerVersion;
      if FExplorer[I].Adapter is TpgnMSSQLAdapter then
      begin
        Ver := TpgnMSSQLAdapter(FExplorer[I].Adapter).FullVersion;   // "17.0.1000.7", as SSMS
      end;
      Txt := Txt + ' (' + Trim(EngineCaptions[FExplorer[I].Info.Engine] + ' ' + Ver);
      if FExplorer[I].Adapter.Info.User <> '' then
      begin
        Txt := Txt + ' - ' + FExplorer[I].Adapter.Info.User;
      end;
      Txt := Txt + ')';
    end;
    if FExplorer[I].Info.Environment <> enNone then
    begin
      Txt := EnvironmentShort[FExplorer[I].Info.Environment] + ' ' + #$C2#$B7 + ' ' + Txt;
    end;
    if Root.Text <> Txt then
    begin
      Root.Text := Txt;
    end;
    if Root.Visible <> Want then
    begin
      Root.Visible := Want;
    end;
  end;
end;

{ Object Explorer's filter box shows under its bar while Filter is on. }
procedure TpgnMainForm.PlaceOEFilter;
begin
  if FOEFilterShown then
  begin
    FFilterEdit.Align := alTop;
    FFilterEdit.Top := FOEBar.Top + FOEBar.Height + 1;
  end
  else
  begin
    FFilterEdit.Align := alNone;
    FFilterEdit.SetBounds(-3000, 0, 200, FFilterEdit.Height);
  end;
  FActOEFilter.Checked := FOEFilterShown;
end;

procedure TpgnMainForm.DoOEFilter(Sender: TObject);
begin
  if FOEBar = nil then
  begin
    if FFilterEdit.CanFocus then
    begin
      FFilterEdit.SetFocus;
    end;
    Exit;
  end;
  FOEFilterShown := not FOEFilterShown;
  if not FOEFilterShown then
  begin
    FFilterEdit.Text := '';
  end;
  PlaceOEFilter;
  if FOEFilterShown and FFilterEdit.CanFocus then
  begin
    FFilterEdit.SetFocus;
  end;
end;

procedure TpgnMainForm.DoUndo(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.Undo;
    UpdateActionStates;
  end;
end;

procedure TpgnMainForm.DoRedo(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.Redo;
    UpdateActionStates;
  end;
end;

procedure TpgnMainForm.DoConnectOE(Sender: TObject);
begin
  ShowConnectWindow;
end;

procedure TpgnMainForm.DoDisconnectOE(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ExplorerIndexOfNode(FTree.Selected);
  if (Idx < 0) or (FExplorer[Idx].Adapter = nil) then
  begin
    Exit;
  end;
  DisconnectExplorer(Idx);
  UpdateActionStates;
end;

{ Query > Connection: Connect / Change Connection, for the tab in view. }
procedure TpgnMainForm.DoChangeConn(Sender: TObject);
var
  T: TpgnQueryTab;
  Pick: Integer;
begin
  T := FActiveTab;
  if (T = nil) or T.IsRunning then
  begin
    Exit;
  end;
  Pick := PickConnection;
  if (Pick < 0) or (Pick >= FStore.Count) then
  begin
    Exit;
  end;
  if T.IsConnected and not T.ResolvePendingWork('changing the connection') then
  begin
    Exit;
  end;
  T.ConnectTo(FStore.Items[Pick], FStore.Items[Pick].DefaultDatabase);
  PageOfTab(T).Tab.Caption := T.DisplayCaption;
  SyncSeattleRoots;
  RefreshStatus;
  UpdateActionStates;
  MirrorTimerTick(nil);
  T.FocusEditor;
end;


{ ============================================================ Amphibian }

procedure TpgnMainForm.AddLayoutMenu(AParent: TMenuItem);
const
  Names: array[0..2] of string = (LayoutPlume, LayoutAmphibian, LayoutSeattle);
var
  LM, Item: TMenuItem;
  I: Integer;
begin
  LM := AddMenu(AParent, '&Layout');
  SetLength(FLayoutItems, Length(Names));
  for I := 0 to High(Names) do
  begin
    Item := AddMenu(LM, Names[I]);
    Item.RadioItem := True;
    Item.GroupIndex := 3;
    Item.Tag := I;
    Item.Checked := SameText(Names[I], FSettings.Layout);
    Item.OnClick := @DoSelectLayout;
    FLayoutItems[I] := Item;
  end;
end;

{ True where the window can be rearranged while Pagona runs. On Linux
  (GTK) the menu bar can't be rebuilt in place, so Pagona restarts there to
  be sure everything changes. }
function SwitchInPlace: Boolean;
begin
  {$IFDEF WINDOWS}
  Result := True;
  {$ELSE}
  Result := GetEnvironmentVariable('PAGONA_TEST_INPLACE') <> '';
  {$ENDIF}
end;

{ Rearranges the window for another layout without closing anything: the
  open tabs, their sessions, uncommitted work and remembered passwords all
  stay. }
procedure TpgnMainForm.SwitchLayout(const AWant: string);
var
  OldMenu: TMainMenu;
  ToAmph, ToSea: Boolean;
  I: Integer;
begin
  ToAmph := SameText(AWant, LayoutAmphibian);
  ToSea := SameText(AWant, LayoutSeattle);
  FSettings.Layout := AWant;
  FSettings.Save;
  ApplyLook(EffectiveLook(FSettings.Look, AWant));
  DisableAlign;
  try
    if FAmph and not ToAmph then
    begin
      TearDownAmphibian;
    end;
    if FSea and not ToSea then
    begin
      TearDownSeattle;
    end;
    FAmph := ToAmph;
    FSea := ToSea;
    ApplyActionCaptions;

    OldMenu := FMainMenu;
    Menu := nil;
    BuildMenu;
    OldMenu.Free;

    FreeAndNil(FToolBar);
    BuildToolbar;
    FToolBar.Top := 0;

    if FAmph then
    begin
      BuildAmphibianArea;
    end
    else
    begin
      RestorePlumeArea;
      if FSea then
      begin
        BuildSeattleArea;
      end;
    end;
    for I := 0 to TabCount - 1 do
    begin
      TabAt(I).ApplyLayout(AWant);
      if TabAt(I).IsRoutine then
      begin
        TabAt(I).SetSaveCaption(SaveWord);
      end;
    end;
  finally
    EnableAlign;
  end;
  // moved panels: show them afresh and lay everything out again
  FTabArea.Visible := False;
  FTabArea.Visible := True;
  if not FAmph then
  begin
    FExplorerPanel.Visible := False;
    FExplorerPanel.Visible := True;
  end;
  ReAlign;
  ApplyCurrentKeymap;
  RefreshStatus;
  UpdateActionStates;
  if FAmph then
  begin
    UpdateAmphBars;
    MirrorTimerTick(nil);
    FMirrorTimer.Enabled := True;
    Application.QueueAsyncCall(@AsyncConnectWindow, 0);
  end;
  SyncSeattleRoots;
  if FSea then
  begin
    MirrorTimerTick(nil);
    FMirrorTimer.Enabled := True;
    Application.QueueAsyncCall(@AsyncConnectWindow, 0);
  end;
  for I := 0 to TabCount - 1 do
  begin
    PageOfTab(TabAt(I)).Tab.Caption := TabAt(I).DisplayCaption;
  end;
  RecolorFrame;
  ColorMenu;
  if FActiveTab <> nil then
  begin
    FActiveTab.FocusEditor;
  end;
end;

procedure TpgnMainForm.AsyncSwitchLayout(AData: PtrInt);
begin
  if FPendingLayout <> '' then
  begin
    SwitchLayout(FPendingLayout);
    FPendingLayout := '';
  end;
end;

procedure TpgnMainForm.AsyncConnectWindow(AData: PtrInt);
var
  I: Integer;
begin
  for I := 0 to TabCount - 1 do
  begin
    if TabAt(I).IsConnected then
    begin
      Exit;   // already somewhere
    end;
  end;
  if (FAmph or FSea) and Visible then
  begin
    ShowConnectWindow;
  end;
end;

{ Toad's New Connection window: the saved connections to pick from, with
  New, Edit and Delete. }
procedure TpgnMainForm.ShowConnectWindow;
var
  Pick: Integer;
begin
  Pick := PickConnection;
  if (Pick >= 0) and (Pick < FStore.Count) then
  begin
    ConnectChosen(FStore.Items[Pick]);
  end;
end;

{ The connection window; the store index picked, or -1. }
function TpgnMainForm.PickConnection: Integer;
var
  W: TpgnConnectWindow;
  Id: string;
  Pick: Integer;
begin
  Result := -1;
  Id := '';
  if (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    Id := FActiveTab.Info.Id;
  end;
  W := TpgnConnectWindow.CreateWin(Self, FStore, Id);
  try
    W.OnNewConnection := @WinNewConnection;
    W.OnEditConnection := @WinEditConnection;
    W.OnDeleteConnection := @WinDeleteConnection;
    if FSea then
    begin
      W.Caption := 'Connect to Server';
    end;
    if W.ShowModal <> mrOK then
    begin
      Exit;
    end;
    Pick := W.Chosen;
  finally
    W.Free;
  end;
  Result := Pick;
end;

{ The editor in view takes the connection if it has none yet; otherwise a
  new editor opens on it. }
procedure TpgnMainForm.ConnectChosen(const AInfo: TpgnConnectionInfo);
var
  T: TpgnQueryTab;
  Idx: Integer;
begin
  if FSea then
  begin
    // as SSMS: the server joins Object Explorer, opened and selected
    Idx := ExplorerIndexOfId(AInfo.Id);
    if (Idx >= 0) and EnsureExplorerConnected(Idx) then
    begin
      SyncSeattleRoots;
      FExplorer[Idx].Root.Expand(False);
      FTree.Selected := FExplorer[Idx].Root;
    end;
  end;
  if FBrowserShown then
  begin
    ShowEditorWindow;
  end;
  T := FActiveTab;
  if (T <> nil) and not T.IsConnected and not T.IsRunning and (T.DbaScreen = dsNone) and
    not T.IsRoutine then
  begin
    T.ConnectTo(AInfo, AInfo.DefaultDatabase);
  end
  else
  begin
    NewTabOn(AInfo, AInfo.DefaultDatabase, '');
  end;
  RefreshStatus;
  UpdateActionStates;
  if FAmph or FSea then
  begin
    UpdateAmphBars;
    MirrorTimerTick(nil);
  end;
  if FActiveTab <> nil then
  begin
    FActiveTab.FocusEditor;
  end;
end;

function TpgnMainForm.WinNewConnection: Boolean;
begin
  Result := NewSavedConnection;
end;

function TpgnMainForm.WinEditConnection(AStoreIndex: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  Idx := ExplorerIndexOfId(FStore.Items[AStoreIndex].Id);
  if Idx >= 0 then
  begin
    Result := EditConnectionAt(Idx);
  end;
end;

function TpgnMainForm.WinDeleteConnection(AStoreIndex: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  Idx := ExplorerIndexOfId(FStore.Items[AStoreIndex].Id);
  if Idx >= 0 then
  begin
    Result := DeleteConnectionAt(Idx);
  end;
end;

{ Takes the Amphibian pieces away, giving the tab area and the Details
  panel back first. }
procedure TpgnMainForm.TearDownAmphibian;
var
  I: Integer;
begin
  FMirrorTimer.Enabled := False;
  FreeAndNil(FMirrorTimer);
  FBrowserShown := False;
  FTabArea.Parent := Self;
  FTabArea.Align := alClient;
  FDetailsPanel.Parent := FExplorerPanel;
  FBrowser.OnSelectObject := nil;
  FBrowser.OnAdapter := nil;
  FTxShown := False;
  FreeAndNil(FTxSplitter);
  FreeAndNil(FTxPanel);
  FreeAndNil(FWindowArea);      // the editor window, its toolbar and pickers, the browser
  FBrowser := nil;
  FEditorWindow := nil;
  FEditorBar := nil;
  FPickPanel := nil;
  for I := 0 to 2 do
  begin
    FPicks[I] := nil;
    FPickLabels[I] := nil;
  end;
  FreeAndNil(FSessionBar);
  FreeAndNil(FWindowBar);
end;

{ Plume: the Explorer on the left again, with Details under it. }
procedure TpgnMainForm.RestorePlumeArea;
begin
  FExplorerPanel.Align := alLeft;
  FExplorerPanel.Left := 0;
  FExplorerPanel.Width := 290;
  FDetailsPanel.Parent := FExplorerPanel;
  FDetailsPanel.Align := alBottom;
  FDetailsPanel.Height := Scale96ToScreen(240);
  FDetailsPanel.Top := FExplorerPanel.ClientHeight + 100;
  FDetailsLabel.Height := Scale96ToScreen(24);
  if FExplorerSplitter = nil then
  begin
    FExplorerSplitter := TSplitter.Create(Self);
    FExplorerSplitter.Parent := Self;
    FExplorerSplitter.Align := alLeft;
  end;
  FExplorerSplitter.Left := FExplorerPanel.Left + FExplorerPanel.Width + 1;
  FTabArea.Parent := Self;
  FTabArea.Align := alClient;
end;

procedure TpgnMainForm.DoSelectLayout(Sender: TObject);
const
  Names: array[0..2] of string = (LayoutPlume, LayoutAmphibian, LayoutSeattle);
var
  Want: string;
  P: TProcess;
  I: Integer;
begin
  if FUpdatingChecks then
  begin
    Exit;
  end;
  Want := Names[(Sender as TMenuItem).Tag];
  FUpdatingChecks := True;
  try
    for I := 0 to High(FLayoutItems) do
    begin
      FLayoutItems[I].Checked := SameText(Names[I], FSettings.Layout);
    end;
  finally
    FUpdatingChecks := False;
  end;
  if SameText(Want, FSettings.Layout) then
  begin
    Exit;
  end;
  if SwitchInPlace then
  begin
    // after this click is done: the menu it came from is replaced
    FPendingLayout := Want;
    Application.QueueAsyncCall(@AsyncSwitchLayout, 0);
    Exit;
  end;
  if MessageDlg('Switch to the ' + Want + ' layout?' + LineEnding + LineEnding +
    'Pagona restarts to rearrange its window. Open tabs are closed; you''re asked about ' +
    'unsaved files and uncommitted work first.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    Exit;
  end;
  if not CloseQuery then
  begin
    Exit;
  end;
  FSettings.Layout := Want;
  FSettings.Save;
  P := TProcess.Create(nil);
  try
    P.Executable := ParamStr(0);
    P.Options := [];
    try
      P.Execute;
    except
      on E: Exception do
      begin
        ShowError('Pagona couldn''t restart itself. The ' + Want + ' layout is used the next time ' +
          'you start it.', E);
        Exit;
      end;
    end;
  finally
    P.Free;
  end;
  FCloseChecked := True;
  Close;
end;

procedure TpgnMainForm.BuildAmphibianMenu;
var
  M, Sub: TMenuItem;
begin
  M := AddMenu(FMainMenu.Items, '&File');
  AddActionItem(M, FActNewTab);
  AddActionItem(M, FActOpen);
  AddActionItem(M, FActSave);
  AddActionItem(M, FActSaveAs);
  AddActionItem(M, FActCloseTab);
  AddSeparator(M);
  AddActionItem(M, FActExit);

  M := AddMenu(FMainMenu.Items, '&Edit');
  AddActionItem(M, FActCut);
  AddActionItem(M, FActCopy);
  AddActionItem(M, FActPaste);
  AddActionItem(M, FActSelectAll);
  AddSeparator(M);
  AddActionItem(M, FActUpper);
  AddActionItem(M, FActLower);
  AddSeparator(M);
  AddActionItem(M, FActComment);
  AddActionItem(M, FActUncomment);
  AddActionItem(M, FActToggleComment);
  AddActionItem(M, FActBlockComment);
  AddActionItem(M, FActIndent);
  AddActionItem(M, FActOutdent);
  AddSeparator(M);
  AddActionItem(M, FActOptions);

  M := AddMenu(FMainMenu.Items, '&Search');
  AddActionItem(M, FActFind);
  AddActionItem(M, FActFindNext);
  AddActionItem(M, FActReplace);

  M := AddMenu(FMainMenu.Items, 'Sess&ion');
  AddActionItem(M, FActNewConn);
  AddActionItem(M, FActEditConn);
  AddActionItem(M, FActDeleteConn);
  AddSeparator(M);
  AddActionItem(M, FActDisconnect);
  AddSeparator(M);
  AddActionItem(M, FActCommit);
  AddActionItem(M, FActRollback);
  AddActionItem(M, FActPending);
  AddActionItem(M, FActAutoCommit);

  M := AddMenu(FMainMenu.Items, 'Edi&tor');
  AddActionItem(M, FActRunStatement);
  AddActionItem(M, FActRunScript);
  AddActionItem(M, FActExplain);
  AddActionItem(M, FActCancel);
  AddSeparator(M);
  AddActionItem(M, FActDescribe);
  AddActionItem(M, FActHistory);

  // Toad keeps the browsers and the DBA screens under Database
  FDbaMenu := AddMenu(FMainMenu.Items, '&Database');
  AddActionItem(FDbaMenu, FActSchemaBrowser);
  AddSeparator(FDbaMenu);
  Sub := AddMenu(FDbaMenu, '&Monitor');
  AddActionItem(Sub, FActDbaSessions);
  AddActionItem(Sub, FActDbaLocks);
  Sub := AddMenu(FDbaMenu, 'S&ecurity');
  AddActionItem(Sub, FActDbaUsers);
  AddActionItem(Sub, FActDbaWhoCan);
  AddSeparator(FDbaMenu);
  AddActionItem(FDbaMenu, FActDbaLog);

  M := AddMenu(FMainMenu.Items, '&View');
  AddActionItem(M, FActRefreshAll);
  AddSeparator(M);
  AddLayoutMenu(M);
  AddKeymapThemeMenus(M);

  M := AddMenu(FMainMenu.Items, '&Window');
  AddActionItem(M, FActShowEditor);
  AddActionItem(M, FActSchemaBrowser);
  AddActionItem(M, FActPending);
  AddSeparator(M);
  AddActionItem(M, FActNextTab);
  AddActionItem(M, FActPrevTab);
  AddActionItem(M, FActMoveTab);
  AddActionItem(M, FActRenameTab);

  M := AddMenu(FMainMenu.Items, '&Help');
  AddActionItem(M, FActAbout);
end;

{ Below the main toolbar: the session bar, the window bar, then the window
  in view (the Editor, with its own toolbar, or the Schema Browser). }
procedure TpgnMainForm.BuildAmphibianArea;
const
  PickCaptions: array[0..2] of string = ('Session', 'Database', 'Schema');
var
  BarHost: TPanel;
  I: Integer;
  Saved: string;
begin
  // the Explorer's tree and Details still do the work, out of sight
  FreeAndNil(FExplorerSplitter);
  FExplorerPanel.Align := alNone;
  FExplorerPanel.SetBounds(-4000, 0, 290, 700);

  FSessionBar := TpgnStripBar.Create(Self);
  FSessionBar.Parent := Self;
  FSessionBar.Align := alTop;
  FSessionBar.Top := FToolBar.Top + FToolBar.Height + 1;
  FBrowserShown := False;
  FSessionBar.Height := Scale96ToScreen(32);
  FSessionBar.EmptyText := 'No connection open: Session > New Connection (or the toolbar''s New ' +
    'Connection button) lists your saved connections';
  FSessionBar.OnItemClick := @SessionBarClick;

  FWindowBar := TpgnStripBar.Create(Self);
  FWindowBar.Parent := Self;
  FWindowBar.Align := alTop;
  FWindowBar.Top := FSessionBar.Top + FSessionBar.Height + 1;
  FWindowBar.Height := Scale96ToScreen(30);
  FWindowBar.TabLook := True;
  FWindowBar.OnItemClick := @WindowBarClick;

  FWindowArea := TPanel.Create(Self);
  FWindowArea.Parent := Self;
  FWindowArea.Align := alClient;
  FWindowArea.BevelOuter := bvNone;
  FWindowArea.Caption := '';

  FEditorWindow := TPanel.Create(Self);
  FEditorWindow.Parent := FWindowArea;
  FEditorWindow.Align := alClient;
  FEditorWindow.BevelOuter := bvNone;
  FEditorWindow.Caption := '';

  BarHost := TPanel.Create(Self);
  BarHost.Parent := FEditorWindow;
  BarHost.Align := alTop;
  BarHost.Height := Scale96ToScreen(32);
  BarHost.BevelOuter := bvNone;
  BarHost.Caption := '';
  BarHost.Color := clPgnSurface;
  BarHost.ParentColor := False;

  FPickPanel := TPanel.Create(Self);
  FPickPanel.Parent := BarHost;
  FPickPanel.Align := alRight;
  FPickPanel.Width := Scale96ToScreen(640);
  FPickPanel.BevelOuter := bvNone;
  FPickPanel.Caption := '';
  FPickPanel.Color := clPgnSurface;
  FPickPanel.ParentColor := False;
  FPickPanel.OnResize := @LayoutPicks;
  for I := 0 to 2 do
  begin
    FPickLabels[I] := TLabel.Create(Self);
    FPickLabels[I].Parent := FPickPanel;
    FPickLabels[I].Caption := PickCaptions[I];
    FPicks[I] := TComboBox.Create(Self);
    FPicks[I].Parent := FPickPanel;
    FPicks[I].Style := csDropDownList;
    FPicks[I].AutoSize := False;
    FPicks[I].Tag := I;
    FPicks[I].OnChange := @PickChange;
  end;

  FEditorBar := TpgnToolbar.Create(Self);
  FEditorBar.Parent := BarHost;
  FEditorBar.Align := alClient;
  FEditorBar.IconOnly := True;
  FEditorBar.AddIconDef('open', 'Open File', FActOpen, icOpen, isTwoTone);
  FEditorBar.AddIconDef('save', 'Save', FActSave, icSave, isTwoTone);
  FEditorBar.AddIconDef('saveas', 'Save As', FActSaveAs, icSaveAs, isTwoTone);
  FEditorBar.AddIconDef('run', 'Execute Statement', FActRunStatement, icRun, isBold);
  FEditorBar.AddIconDef('script', 'Execute as Script', FActRunScript, icScript, isBold);
  FEditorBar.AddIconDef('stop', 'Stop Execution', FActCancel, icStop, isBold);
  FEditorBar.AddIconDef('explain', 'Explain Plan', FActExplain, icExplain, isTwoTone);
  FEditorBar.AddIconDef('describe', 'Describe', FActDescribe, icDescribe, isTwoTone);
  FEditorBar.AddIconDef('recall', 'SQL Recall', FActHistory, icHistory, isTwoTone);
  FEditorBar.AddIconDef('comment', 'Comment', FActComment, icComment, isTwoTone);
  FEditorBar.AddIconDef('uncomment', 'Uncomment', FActUncomment, icUncomment, isTwoTone);
  FEditorBar.AddIconDef('upper', 'Uppercase', FActUpper, icUpper, isTwoTone);
  FEditorBar.AddIconDef('lower', 'Lowercase', FActLower, icLower, isTwoTone);
  FEditorBar.AddIconDef('indent', 'Indent', FActIndent, icIndent, isTwoTone);
  FEditorBar.AddIconDef('outdent', 'Unindent', FActOutdent, icOutdent, isTwoTone);
  FEditorBar.AddIconDef('find', 'Find', FActFind, icFind, isTwoTone);
  FEditorBar.DefaultArrangement := DefaultToolbar(LayoutAmphibian + '.Editor');
  Saved := FSettings.Toolbars.Values[LayoutAmphibian + '.Editor'];
  if Saved = '' then
  begin
    Saved := FEditorBar.DefaultArrangement;
  end;
  FEditorBar.SetArrangement(Saved);
  FEditorBar.OnChanged := @EditorBarChanged;

  FTabArea.Parent := FEditorWindow;
  FTabArea.Align := alClient;

  FBrowser := TpgnSchemaBrowser.Create(Self);
  FBrowser.Parent := FWindowArea;
  FBrowser.Align := alNone;
  FBrowser.SetBounds(-5000, 0, 800, 600);
  FBrowser.OnAdapter := @BrowserAdapter;
  FBrowser.OnSelectObject := @BrowserSelect;
  FBrowser.OnOpenObject := @BrowserOpen;
  FBrowser.OnObjectMenu := @BrowserMenu;
  // the Details panel moves into the browser, under its own title
  FDetailsPanel.Parent := FBrowser.DetailsHost;
  FDetailsPanel.Align := alClient;
  FDetailsLabel.Height := 0;

  // the Transactions panel, docked above the status bar, folded until opened
  FTxPanel := TpgnTransactionsPanel.CreatePanel(Self, @PendingTabs, True);
  FTxPanel.Parent := FWindowArea;
  FTxPanel.Align := alBottom;
  FTxPanel.OnCloseClick := @TxCloseClick;
  FTxPanel.OnChanged := @TxChanged;
  FTxSplitter := TSplitter.Create(Self);
  FTxSplitter.Parent := FWindowArea;
  FTxSplitter.Align := alNone;
  FTxSplitter.SetBounds(-3000, 0, 10, 5);
  FTxShown := True;
  HideTxPanel;

  FMirrorTimer := TTimer.Create(Self);
  FMirrorTimer.Enabled := False;
  FMirrorTimer.Interval := 400;
  FMirrorTimer.OnTimer := @MirrorTimerTick;
end;

procedure TpgnMainForm.EditorBarChanged(Sender: TObject);
begin
  FSettings.Toolbars.Values[FSettings.Layout + '.Editor'] := FEditorBar.Arrangement;
  FSettings.Save;
end;

{ Session, Database and Schema pickers at the right of the editor toolbar;
  the database one only where it's a choice, the schema one only where
  the engine has schemas. }
procedure TpgnMainForm.LayoutPicks(Sender: TObject);
const
  Widths: array[0..2] of Integer = (230, 150, 150);
var
  Wanted: array[0..2] of Boolean;
  I, X, H: Integer;
  T: TpgnQueryTab;
begin
  T := FActiveTab;
  Wanted[0] := True;
  Wanted[2] := (T <> nil) and T.IsConnected and T.SchemaWanted;
  Wanted[1] := (T <> nil) and T.IsConnected and ((not T.SchemaWanted) or (FPicks[1].Items.Count > 1));
  if FSea then
  begin
    // SSMS's database box only (and the schema where the engine has them)
    Wanted[0] := False;
    Wanted[1] := True;
  end;
  // the panel is as wide as the pickers it shows
  X := Scale96ToScreen(12);
  for I := 0 to 2 do
  begin
    if Wanted[I] then
    begin
      X := X + FPickLabels[I].Width + Scale96ToScreen(5 + Widths[I] + 14);
    end;
  end;
  if FPickPanel.Width <> X then
  begin
    FPickPanel.Width := X;
  end;
  X := X - Scale96ToScreen(6);
  for I := 2 downto 0 do
  begin
    H := FPicks[I].Height;
    if Wanted[I] then
    begin
      X := X - Scale96ToScreen(Widths[I]);
      FPicks[I].SetBounds(X, (FPickPanel.ClientHeight - H) div 2, Scale96ToScreen(Widths[I]), H);
      X := X - Scale96ToScreen(5) - FPickLabels[I].Width;
      FPickLabels[I].SetBounds(X, (FPickPanel.ClientHeight - FPickLabels[I].Height) div 2,
        FPickLabels[I].Width, FPickLabels[I].Height);
      X := X - Scale96ToScreen(14);
    end
    else
    begin
      FPicks[I].SetBounds(-2000, 0, Scale96ToScreen(Widths[I]), H);
      FPickLabels[I].SetBounds(-2000, 0, FPickLabels[I].Width, FPickLabels[I].Height);
    end;
  end;
  FPickPanel.Invalidate;
end;

{ Keeps the pickers showing what the active tab's band holds. }
procedure TpgnMainForm.MirrorTimerTick(Sender: TObject);
var
  I, J, Idx: Integer;
  Want: TStringList;
  Src: TComboBox;
  T: TpgnQueryTab;
  Differs: Boolean;
begin
  if (FPicks[0] = nil) or FMirroring then
  begin
    Exit;
  end;
  if FPicks[0].DroppedDown or FPicks[1].DroppedDown or FPicks[2].DroppedDown then
  begin
    Exit;
  end;
  T := FActiveTab;
  FMirroring := True;
  Differs := False;
  try
    for I := 0 to 2 do
    begin
      if T = nil then
      begin
        if FPicks[I].Items.Count > 0 then
        begin
          FPicks[I].Items.Clear;
          Differs := True;
        end;
        Continue;
      end;
      Src := T.BandCombo(I);
      if I = 0 then
      begin
        // the saved connections, read straight from the list (same order
        // as the tab's own picker)
        Want := TStringList.Create;
        try
          for J := 0 to FStore.Count - 1 do
          begin
            Want.Add(ConnectionLabel(FStore.Items[J]));
          end;
          if FPicks[0].Items.Text <> Want.Text then
          begin
            FPicks[0].Items.Assign(Want);
            Differs := True;
          end;
        finally
          Want.Free;
        end;
        Idx := -1;
        if T.IsConnected then
        begin
          Idx := FStore.IndexOfId(T.Info.Id);
        end;
        if FPicks[0].ItemIndex <> Idx then
        begin
          FPicks[0].ItemIndex := Idx;
        end;
        FPicks[0].Enabled := Src.Enabled;
        Continue;
      end;
      if FPicks[I].Items.Text <> Src.Items.Text then
      begin
        FPicks[I].Items.Assign(Src.Items);
        Differs := True;
      end;
      if FPicks[I].ItemIndex <> Src.ItemIndex then
      begin
        FPicks[I].ItemIndex := Src.ItemIndex;
      end;
      FPicks[I].Enabled := Src.Enabled;
    end;
  finally
    FMirroring := False;
  end;
  if Differs or (Sender = nil) then
  begin
    LayoutPicks(nil);
  end;
end;

procedure TpgnMainForm.PickChange(Sender: TObject);
var
  W: Integer;
begin
  if FMirroring or (FActiveTab = nil) then
  begin
    Exit;
  end;
  W := (Sender as TComboBox).Tag;
  FActiveTab.PickInBand(W, FPicks[W].ItemIndex);
  MirrorTimerTick(nil);
  UpdateAmphBars;
end;

{ The session bar lists the connections open in editor tabs; the window
  bar the Editor, the Schema Browser and each DBA screen. }
procedure TpgnMainForm.UpdateAmphBars;
var
  I: Integer;
  T: TpgnQueryTab;
  Ids: TStringList;
  ActiveId, Cap: string;
begin
  if FSessionBar = nil then
  begin
    Exit;
  end;
  Ids := TStringList.Create;
  try
    FSessionBar.Clear;
    for I := 0 to TabCount - 1 do
    begin
      T := TabAt(I);
      if T.IsConnected and (Ids.IndexOf(T.Info.Id) < 0) then
      begin
        Ids.Add(T.Info.Id);
        FSessionBar.Add(T.Info.User + '@' + T.Info.Name, T.Info.Id, T.Info.Environment);
      end;
    end;
    if (FBrowser.ConnIndex >= 0) and (Ids.IndexOf(FBrowser.Info.Id) < 0) then
    begin
      FSessionBar.Add(FBrowser.Info.User + '@' + FBrowser.Info.Name, FBrowser.Info.Id,
        FBrowser.Info.Environment);
    end;
  finally
    Ids.Free;
  end;
  ActiveId := '';
  if FBrowserShown and (FBrowser.ConnIndex >= 0) then
  begin
    ActiveId := FBrowser.Info.Id;
  end
  else if (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    ActiveId := FActiveTab.Info.Id;
  end;
  FSessionBar.ActiveIndex := FSessionBar.IndexOfKey(ActiveId);
  FSessionBar.Invalidate;

  FWindowBar.Clear;
  FWindowBar.Add('Editor', 'editor', enNone);
  Cap := 'Schema Browser';
  if FBrowser.ConnIndex >= 0 then
  begin
    Cap := Cap + ' (' + FBrowser.Info.User + '@' + FBrowser.Info.Name + ')';
  end;
  FWindowBar.Add(Cap, 'browser', enNone);
  for I := 0 to TabCount - 1 do
  begin
    T := TabAt(I);
    if T.DbaScreen <> dsNone then
    begin
      FWindowBar.Add(T.DisplayCaption, 'tab:' + IntToStr(PtrUInt(T)), enNone);
    end;
  end;
  if FBrowserShown then
  begin
    FWindowBar.ActiveIndex := 1;
  end
  else if (FActiveTab <> nil) and (FActiveTab.DbaScreen <> dsNone) then
  begin
    FWindowBar.ActiveIndex := FWindowBar.IndexOfKey('tab:' + IntToStr(PtrUInt(FActiveTab)));
  end
  else
  begin
    FWindowBar.ActiveIndex := 0;
  end;
  FWindowBar.Invalidate;
end;

procedure TpgnMainForm.ActivateTab(ATab: TpgnQueryTab);
var
  Group: TExtPageCtrl;
  Idx: Integer;
begin
  if ATab = nil then
  begin
    Exit;
  end;
  Group := GroupOfTab(ATab);
  Idx := Group.IndexOfPage(PageOfTab(ATab));
  if Idx < 0 then
  begin
    Exit;
  end;
  Group.PageIndex := Idx;
  PagesChanged(Group, Idx);
end;

procedure TpgnMainForm.SessionBarClick(Sender: TObject; AIndex: Integer);
var
  Id, Ptr: string;
  I, Idx: Integer;
  T: TpgnQueryTab;
begin
  Id := FSessionBar.KeyAt(AIndex);
  if FBrowserShown then
  begin
    Idx := ExplorerIndexOfId(Id);
    if (Idx >= 0) and EnsureExplorerConnected(Idx) then
    begin
      FBrowser.Attach(Idx, FExplorer[Idx].Info, FExplorer[Idx].Adapter);
    end;
    UpdateAmphBars;
    RefreshStatus;
    Exit;
  end;
  // the tab last used on that connection, else the first one on it
  T := nil;
  Ptr := FLastTabOf.Values[Id];
  for I := 0 to TabCount - 1 do
  begin
    if (Ptr <> '') and (IntToStr(PtrUInt(TabAt(I))) = Ptr) and TabAt(I).IsConnected and
      (TabAt(I).Info.Id = Id) then
    begin
      T := TabAt(I);
    end;
  end;
  if T = nil then
  begin
    for I := 0 to TabCount - 1 do
    begin
      if (T = nil) and TabAt(I).IsConnected and (TabAt(I).Info.Id = Id) then
      begin
        T := TabAt(I);
      end;
    end;
  end;
  ActivateTab(T);
end;

procedure TpgnMainForm.WindowBarClick(Sender: TObject; AIndex: Integer);
var
  Key: string;
  I: Integer;
  T: TpgnQueryTab;
begin
  Key := FWindowBar.KeyAt(AIndex);
  if Key = 'browser' then
  begin
    ShowSchemaBrowser;
  end
  else if Key = 'editor' then
  begin
    ShowEditorWindow;
    if (FActiveTab <> nil) and (FActiveTab.DbaScreen <> dsNone) then
    begin
      for I := 0 to TabCount - 1 do
      begin
        if TabAt(I).DbaScreen = dsNone then
        begin
          ActivateTab(TabAt(I));
          Break;
        end;
      end;
    end;
  end
  else
  begin
    ShowEditorWindow;
    for I := 0 to TabCount - 1 do
    begin
      T := TabAt(I);
      if 'tab:' + IntToStr(PtrUInt(T)) = Key then
      begin
        ActivateTab(T);
      end;
    end;
  end;
  UpdateAmphBars;
end;

procedure TpgnMainForm.ShowEditorWindow;
begin
  if FBrowser = nil then
  begin
    Exit;
  end;
  FBrowserShown := False;
  FBrowser.Align := alNone;
  FBrowser.SetBounds(-5000, 0, FWindowArea.ClientWidth, FWindowArea.ClientHeight);
  FEditorWindow.Align := alClient;
  UpdateAmphBars;
  RefreshStatus;
  if FActiveTab <> nil then
  begin
    FActiveTab.FocusEditor;
  end;
end;

{ The browser opens on the active editor's connection (or the one it showed
  last), using that connection's Explorer session. }
procedure TpgnMainForm.ShowSchemaBrowser;
var
  Idx: Integer;
begin
  if FBrowser = nil then
  begin
    Exit;
  end;
  Idx := -1;
  if (FActiveTab <> nil) and FActiveTab.IsConnected then
  begin
    Idx := ExplorerIndexOfId(FActiveTab.Info.Id);
  end;
  if Idx < 0 then
  begin
    Idx := FBrowser.ConnIndex;
  end;
  if Idx < 0 then
  begin
    MessageDlg('Connect first: pick a connection in the Session box of the Editor, or use ' +
      'Session > New Connection.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if not EnsureExplorerConnected(Idx) then
  begin
    Exit;
  end;
  FBrowser.Attach(Idx, FExplorer[Idx].Info, FExplorer[Idx].Adapter);
  FBrowserShown := True;
  FEditorWindow.Align := alNone;
  FEditorWindow.SetBounds(-5000, 0, FWindowArea.ClientWidth, FWindowArea.ClientHeight);
  FBrowser.Align := alClient;
  UpdateAmphBars;
  RefreshStatus;
end;

procedure TpgnMainForm.DoSchemaBrowser(Sender: TObject);
begin
  if FAmph then
  begin
    ShowSchemaBrowser;
  end
  else if FFilterEdit.CanFocus then
  begin
    // Plume's Explorer is its schema browser
    FFilterEdit.SetFocus;
  end;
end;

procedure TpgnMainForm.DoShowEditor(Sender: TObject);
begin
  if FAmph then
  begin
    ShowEditorWindow;
  end
  else if FActiveTab <> nil then
  begin
    FActiveTab.FocusEditor;
  end;
end;

function TpgnMainForm.BrowserAdapter(AConnIndex: Integer; const ADatabase: string): TpgnAdapter;
begin
  Result := nil;
  if (AConnIndex < 0) or (AConnIndex > High(FExplorer)) then
  begin
    Exit;
  end;
  Result := AdapterFor(AConnIndex, ADatabase);
end;

procedure TpgnMainForm.BrowserSelect(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef);
begin
  ShowDetails(AConnIndex, ARef);
end;

{ Double-click: code opens in an editor tab, ready to change and compile;
  other objects with a definition put it in a new editor. }
procedure TpgnMainForm.BrowserOpen(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef);
var
  SQL, C, Folder: string;
  T: TpgnQueryTab;
begin
  if ARef.Kind = 'Procedure' then
  begin
    OpenRoutineTab(AConnIndex, ARef.Database, ARef.Schema, ARef.Name, rkProcedure);
  end
  else if (ARef.Kind = 'Function') or (ARef.Kind = 'Trigger Function') then
  begin
    OpenRoutineTab(AConnIndex, ARef.Database, ARef.Schema, ARef.Name, rkFunction);
  end
  else if ARef.Kind = 'Trigger' then
  begin
    OpenRoutineTab(AConnIndex, ARef.Database, ARef.Schema, ARef.Name, rkTrigger);
  end
  else if Copy(ARef.Kind, 1, 6) = 'Other:' then
  begin
    Folder := Copy(ARef.Kind, 7, MaxInt);
    C := ARef.Schema;
    if C = '' then
    begin
      C := ARef.Database;
    end;
    try
      SQL := AdapterFor(AConnIndex, ARef.Database).FolderItemSQL(C, Folder, ARef.Name);
    except
      on E: Exception do
      begin
        ShowError('Could not read ' + ARef.Name, E);
        Exit;
      end;
    end;
    if Trim(SQL) = '' then
    begin
      Exit;
    end;
    T := NewTabOn(FExplorer[AConnIndex].Info, ARef.Database, ARef.Name, ARef.Schema);
    if T <> nil then
    begin
      T.SetText(SQL);
    end;
  end;
end;

{ Right-click: the Explorer's menu for the same object, so everything it
  offers (Script As, Copy Definition, Grant, Who Can Do What...) is here. }
procedure TpgnMainForm.BrowserMenu(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef;
  const AScreenPos: TPoint);
var
  Node: TTreeNode;
begin
  Node := nil;
  try
    Node := RevealObject(AConnIndex, ARef);
  except
    on E: Exception do
    begin
      ShowError('Could not find ' + ARef.Name, E);
    end;
  end;
  if Node = nil then
  begin
    Exit;
  end;
  FTree.Selected := Node;
  FTreeMenu.PopUp(AScreenPos.X, AScreenPos.Y);
end;

{ An item of an adapter-named folder (directly under AHolder, or in its
  More folder). }
function TpgnMainForm.RevealOther(AHolder: TTreeNode; const AFolder, AName: string): TTreeNode;
var
  N, More: TTreeNode;
begin
  Result := nil;
  if AHolder = nil then
  begin
    Exit;
  end;
  AHolder.Expand(False);
  N := AHolder.GetFirstChild;
  while N <> nil do
  begin
    if (NodeKind(N) = nkFolderOther) and (FolderBase(N) = AFolder) then
    begin
      N.Expand(False);
      Result := FindChild(N, nkOther, AName);
      Exit;
    end;
    N := N.GetNextSibling;
  end;
  More := FindChild(AHolder, nkFolderMore, '');
  if More <> nil then
  begin
    Result := RevealOther(More, AFolder, AName);
  end;
end;

{ Commit's drop arrow > Pending Statements: what the tab has run since
  its last commit, with Commit All, Roll Back All and Undo From Here. }
procedure TpgnMainForm.DoPending(Sender: TObject);
var
  Focus: TpgnQueryTab;
begin
  Focus := nil;
  if (FActiveTab <> nil) and FActiveTab.IsConnected and (FActiveTab.PendingCount > 0) then
  begin
    Focus := FActiveTab;
  end;
  if FAmph then
  begin
    ShowTxPanel(Focus);
  end
  else
  begin
    ShowTransactionsWindow(Self, @PendingTabs, Focus, @TxChanged);
    RefreshStatus;
    UpdateActionStates;
  end;
end;

{ Review... in the close question: always a window, since the question
  waits for it. }
procedure TpgnMainForm.TabReviewPending(Sender: TObject);
begin
  ShowTransactionsWindow(Self, @PendingTabs, Sender as TpgnQueryTab, @TxChanged);
  RefreshStatus;
  UpdateActionStates;
end;

procedure TpgnMainForm.TxChanged(Sender: TObject);
begin
  RefreshStatus;
  UpdateActionStates;
  if FAmph then
  begin
    UpdateAmphBars;
  end;
end;

procedure TpgnMainForm.TxCloseClick(Sender: TObject);
begin
  HideTxPanel;
end;

{ Amphibian: the Transactions panel opens at the bottom of the window. }
procedure TpgnMainForm.ShowTxPanel(AFocus: TpgnQueryTab);
begin
  if FTxPanel = nil then
  begin
    Exit;
  end;
  if not FTxShown then
  begin
    FTxShown := True;
    FTxPanel.Align := alBottom;
    FTxPanel.SetBounds(0, FWindowArea.ClientHeight - Scale96ToScreen(320), FWindowArea.ClientWidth,
      Scale96ToScreen(320));
    FTxSplitter.Align := alBottom;
    FTxSplitter.Top := FTxPanel.Top - 1;
  end;
  if AFocus <> nil then
  begin
    FTxPanel.ShowTab(AFocus);
  end
  else
  begin
    FTxPanel.Reload;
  end;
end;

procedure TpgnMainForm.HideTxPanel;
begin
  if FTxPanel = nil then
  begin
    Exit;
  end;
  FTxShown := False;
  // parked out of sight rather than hidden (GTK shows hidden panels again,
  // and a docked panel at height 0 still drew on GTK3)
  FTxPanel.Align := alNone;
  FTxPanel.SetBounds(-5000, 0, 900, Scale96ToScreen(320));
  FTxSplitter.Align := alNone;
  FTxSplitter.SetBounds(-3000, 0, 10, 5);
end;

{ Clicking "3 uncommitted statements" in the status bar opens the list. }
procedure TpgnMainForm.StatusSegmentClick(Sender: TObject; AIndex: Integer);
begin
  if (AIndex = 1) and (Length(PendingTabs) > 0) then
  begin
    DoPending(nil);
  end;
end;

{ ------------------------------------------------- find, replace, indent }

procedure TpgnMainForm.DoIndent(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.CommandProcessor(ecBlockIndent, #0, nil);
  end;
end;

procedure TpgnMainForm.DoOutdent(Sender: TObject);
begin
  if FActiveTab <> nil then
  begin
    FActiveTab.Editor.CommandProcessor(ecBlockUnindent, #0, nil);
  end;
end;

procedure TpgnMainForm.SearchEditor(const AText: string; AOptions: TFindOptions; AReplace: Boolean;
  const AWith: string);
var
  Opt: TSynSearchOptions;
  N: Integer;
begin
  if (FActiveTab = nil) or (AText = '') then
  begin
    Exit;
  end;
  Opt := [];
  if frMatchCase in AOptions then
  begin
    Include(Opt, ssoMatchCase);
  end;
  if frWholeWord in AOptions then
  begin
    Include(Opt, ssoWholeWord);
  end;
  if not (frDown in AOptions) then
  begin
    Include(Opt, ssoBackwards);
  end;
  if AReplace then
  begin
    Include(Opt, ssoReplace);
    if frReplaceAll in AOptions then
    begin
      Include(Opt, ssoReplaceAll);
      Include(Opt, ssoEntireScope);
    end;
  end;
  N := FActiveTab.Editor.SearchReplace(AText, AWith, Opt);
  if N = 0 then
  begin
    MessageDlg('"' + AText + '" was not found.', mtInformation, [mbOK], 0);
  end
  else if AReplace and (frReplaceAll in AOptions) then
  begin
    FStatus.Texts[2] := IntToStr(N) + ' replaced';
  end;
end;

procedure TpgnMainForm.DoFind(Sender: TObject);
begin
  if FActiveTab = nil then
  begin
    Exit;
  end;
  if FFindDialog = nil then
  begin
    FFindDialog := TFindDialog.Create(Self);
    FFindDialog.Options := [frDown];
    FFindDialog.OnFind := @FindDialogFind;
  end;
  if FActiveTab.Editor.SelAvail and (Pos(#10, FActiveTab.Editor.SelText) = 0) then
  begin
    FFindDialog.FindText := FActiveTab.Editor.SelText;
  end;
  FFindDialog.Execute;
end;

procedure TpgnMainForm.FindDialogFind(Sender: TObject);
begin
  SearchEditor(FFindDialog.FindText, FFindDialog.Options, False, '');
end;

procedure TpgnMainForm.DoFindNext(Sender: TObject);
begin
  if (FFindDialog = nil) or (FFindDialog.FindText = '') then
  begin
    DoFind(Sender);
    Exit;
  end;
  SearchEditor(FFindDialog.FindText, FFindDialog.Options + [frDown], False, '');
end;

procedure TpgnMainForm.DoReplace(Sender: TObject);
begin
  if FActiveTab = nil then
  begin
    Exit;
  end;
  if FReplaceDialog = nil then
  begin
    FReplaceDialog := TReplaceDialog.Create(Self);
    FReplaceDialog.Options := [frDown];
    FReplaceDialog.OnFind := @ReplaceDialogReplace;
    FReplaceDialog.OnReplace := @ReplaceDialogReplace;
  end;
  if FActiveTab.Editor.SelAvail and (Pos(#10, FActiveTab.Editor.SelText) = 0) then
  begin
    FReplaceDialog.FindText := FActiveTab.Editor.SelText;
  end;
  FReplaceDialog.Execute;
end;

procedure TpgnMainForm.ReplaceDialogReplace(Sender: TObject);
begin
  SearchEditor(FReplaceDialog.FindText, FReplaceDialog.Options,
    (frReplace in FReplaceDialog.Options) or (frReplaceAll in FReplaceDialog.Options),
    FReplaceDialog.ReplaceText);
end;

end.
