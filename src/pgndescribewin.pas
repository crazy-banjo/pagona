// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnDescribeWin;

{ The Describe window, as Toad's F4 opens it: everything about the
  objects you ask about, in one window that stays in front of Pagona while
  you work (it closes only with Close, Esc, or its last object's x).

    +-----------------------------------------------------------+
    | SALES.CUSTOMER                                            |  <- header
    | Table, via public synonym CUSTOMER · DEVDB                |
    +-----------------------------------------------------------+
    | [SALES.CUSTOMER x] [SALES.ORDERS x] [+]                   |  <- objects
    | [Columns] [Indexes] [Constraints] [Triggers] [Data] ...   |  <- pages
    |  (a grid, or the script)                                  |
    +-----------------------------------------------------------+
    | [Show in Object Browser]                 [Refresh] [Close]|
    +-----------------------------------------------------------+

  F4 (Amphibian) or Alt+F1 (Plume, Seattle) adds an object to the open
  window; + opens a search box (names show as you type). Each page is read when first shown, from the
  connection's Explorer session (never the tab's, which may be running a
  query). The tab rows are drawn by Pagona: the selected tab is white,
  bold, marked along its top and joined to the page; the others are
  shaded and outlined. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs, LCLType, LCLIntf, Math, Grids,
  SynEdit, SynEditTypes, SynHighlighterSQL,
  pgnTypes, pgnAdapter, pgnTheme, pgnResultGrid;

type
  TpgnDescribeAdapterFunc = function(const AConnId, ADatabase: string): TpgnAdapter of object;
  TpgnDescribeRevealEvent = procedure(const AConnId: string; const ARef: TpgnObjectRef) of object;
  { Looks a typed name up on a connection (the + button). }
  TpgnDescribeResolveFunc = function(const AConnId, AName: string; out ARef: TpgnObjectRef;
    out AVia: string): Boolean of object;
  TpgnTabEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TpgnDescribePage = (dwColumns, dwIndexes, dwConstraints, dwTriggers, dwArguments, dwData,
    dwScript, dwGrants, dwUsedBy, dwUses);

  { A row of tabs drawn so they read as tabs on every look. }
  TpgnTabStrip = class(TCustomControl)
  private
    FTabs: TStringList;
    FTabIndex: Integer;
    FClosable: Boolean;
    FShowAdd: Boolean;
    FBig: Boolean;
    FRects: array of TRect;
    FCloseRects: array of TRect;
    FAddRect: TRect;
    FOnChange: TNotifyEvent;
    FOnCloseTab: TpgnTabEvent;
    FOnAdd: TNotifyEvent;
    procedure SetTabIndex(AValue: Integer);
    procedure Measure;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Changed;
    property Tabs: TStringList read FTabs;
    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property Closable: Boolean read FClosable write FClosable;
    property ShowAdd: Boolean read FShowAdd write FShowAdd;
    property Big: Boolean read FBig write FBig;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCloseTab: TpgnTabEvent read FOnCloseTab write FOnCloseTab;
    property OnAdd: TNotifyEvent read FOnAdd write FOnAdd;
  end;

  { One object in the window: its pages and the controls that show them. }
  TpgnDescribedObject = class
  public
    ConnId: string;
    ConnName: string;
    Ref: TpgnObjectRef;
    Via: string;
    Dialect: TpgnDialect;
    Pages: array of TpgnDescribePage;
    PageIndex: Integer;
    Grids: array[TpgnDescribePage] of TpgnResultGrid;
    Script: TSynEdit;
    Highlighter: TSynSQLSyn;
    Loaded: set of TpgnDescribePage;
    destructor Destroy; override;
    function Container: string;
    function FullName: string;
  end;

  { Ctrl+wheel over the Script page: one step bigger (1) or smaller (-1). }
  TpgnDescribeZoomEvent = procedure(Sender: TObject; ADirection: Integer) of object;

  TpgnDescribeWindow = class(TForm)
  private
    FLayout: string;
    FEditorTheme: string;
    FFontSize: Integer;           // the Script page's text: the editor's size
    FOnZoom: TpgnDescribeZoomEvent;
    FOnAdapter: TpgnDescribeAdapterFunc;
    FOnReveal: TpgnDescribeRevealEvent;
    FOnResolve: TpgnDescribeResolveFunc;
    FObjects: TFPList;            // TpgnDescribedObject
    FCurrent: TpgnDescribedObject;
    FShown: TControl;
    FHeader: TPanel;
    FTitle: TLabel;
    FSub: TLabel;
    FObjTabs: TpgnTabStrip;
    FPageTabs: TpgnTabStrip;
    FBody: TPanel;
    FBar: TPanel;
    FReveal: TButton;
    FRefresh: TButton;
    FClose: TButton;
    function S(AValue: Integer): Integer;
    function ObjectAt(AIndex: Integer): TpgnDescribedObject;
    function IndexOfRef(const AConnId: string; const ARef: TpgnObjectRef): Integer;
    procedure BuildPages(AObj: TpgnDescribedObject);
    procedure MakeControls(AObj: TpgnDescribedObject);
    procedure SelectObject(AIndex: Integer);
    procedure FillObjTabs;
    procedure ObjTabChange(Sender: TObject);
    procedure ObjTabClose(Sender: TObject; AIndex: Integer);
    procedure ObjTabAdd(Sender: TObject);
    procedure PageTabChange(Sender: TObject);
    procedure BodyResize(Sender: TObject);
    procedure ShowPage(APage: TpgnDescribePage);
    procedure LoadPage(APage: TpgnDescribePage);
    procedure RevealClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure WindowClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure WindowKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BarResize(Sender: TObject);
    procedure ScriptWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
  public
    { AOwner is Pagona's main window: this one stays in front of it.
      ALayout picks the words (Object Browser, Object Explorer, Explorer);
      the colors come from the look in use. }
    constructor CreateIn(AOwner: TCustomForm; const ALayout, AEditorTheme: string; AFontSize: Integer;
      AOnAdapter: TpgnDescribeAdapterFunc; AOnReveal: TpgnDescribeRevealEvent;
      AOnResolve: TpgnDescribeResolveFunc);
    destructor Destroy; override;
    { The Script pages' text size (follows the editor's). }
    procedure SetFontSize(ASize: Integer);
    property OnZoom: TpgnDescribeZoomEvent read FOnZoom write FOnZoom;
    { Adds an object as a tab (or brings its tab forward if it's there). }
    procedure AddObject(const AConnId, AConnName: string; const ARef: TpgnObjectRef;
      const AVia: string; ADialect: TpgnDialect);
  end;

implementation

const
  PageCaptions: array[TpgnDescribePage] of string = ('Columns', 'Indexes', 'Constraints',
    'Triggers', 'Arguments', 'Data', 'Script', 'Grants', 'Used By', 'Uses');
  DataRows = 100;

{ A one-column result holding a note, for a page with nothing to show. }
function Note(const ATitle, AText: string): TpgnResultSet;
begin
  Result := TpgnResultSet.Create;
  Result.ReturnsRows := True;
  SetLength(Result.Columns, 1);
  Result.Columns[0] := ATitle;
  SetLength(Result.Rows, 1);
  SetLength(Result.Rows[0].Values, 1);
  SetLength(Result.Rows[0].Nulls, 1);
  Result.Rows[0].Values[0] := AText;
  Result.Rows[0].Nulls[0] := False;
end;

function Mix(A, B: TColor; AWeightA: Integer): TColor;
var
  CA, CB: LongInt;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  Result := RGBToColor(
    (Red(CA) * AWeightA + Red(CB) * (100 - AWeightA)) div 100,
    (Green(CA) * AWeightA + Green(CB) * (100 - AWeightA)) div 100,
    (Blue(CA) * AWeightA + Blue(CB) * (100 - AWeightA)) div 100);
end;

{ ------------------------------------------------------------ tab strip }

constructor TpgnTabStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabs := TStringList.Create;
  FTabIndex := -1;
  FClosable := False;
  FShowAdd := False;
  FBig := False;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TpgnTabStrip.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

procedure TpgnTabStrip.Changed;
begin
  if FTabIndex >= FTabs.Count then
  begin
    FTabIndex := FTabs.Count - 1;
  end;
  Invalidate;
end;

procedure TpgnTabStrip.SetTabIndex(AValue: Integer);
begin
  if AValue = FTabIndex then
  begin
    Exit;
  end;
  FTabIndex := AValue;
  Invalidate;
end;

procedure TpgnTabStrip.Measure;
var
  I, X, W, Pad, CloseW, TabTop: Integer;
begin
  Canvas.Font.Assign(Font);
  Pad := Scale96ToScreen(14);
  CloseW := 0;
  if FClosable then
  begin
    CloseW := Scale96ToScreen(20);
  end;
  TabTop := Scale96ToScreen(4);
  SetLength(FRects, FTabs.Count);
  SetLength(FCloseRects, FTabs.Count);
  X := Scale96ToScreen(6);
  for I := 0 to FTabs.Count - 1 do
  begin
    Canvas.Font.Style := [fsBold];   // room for the bold selected caption
    W := Canvas.TextWidth(FTabs[I]) + 2 * Pad + CloseW;
    FRects[I] := Rect(X, TabTop, X + W, ClientHeight);
    if FClosable then
    begin
      FCloseRects[I] := Rect(X + W - Pad div 2 - Scale96ToScreen(16), TabTop + (ClientHeight - TabTop) div 2 -
        Scale96ToScreen(8), X + W - Pad div 2, TabTop + (ClientHeight - TabTop) div 2 + Scale96ToScreen(8));
    end
    else
    begin
      FCloseRects[I] := Rect(0, 0, 0, 0);
    end;
    X := X + W + Scale96ToScreen(3);
  end;
  if FShowAdd then
  begin
    FAddRect := Rect(X, TabTop, X + Scale96ToScreen(30), ClientHeight);
  end
  else
  begin
    FAddRect := Rect(0, 0, 0, 0);
  end;
end;

procedure TpgnTabStrip.Paint;
var
  I, TY, Mid, Arm: Integer;
  R, CR: TRect;
  Sel: Boolean;
  Edge, Shade: TColor;
begin
  Measure;
  Edge := clPgnGridHead;                      // a firm outline in every look
  Shade := Mix(clPgnLines, clPgnSurface, 70);  // unselected tabs: shaded
  Canvas.Brush.Color := clPgnSurface;
  Canvas.FillRect(ClientRect);
  // the line the tabs stand on
  Canvas.Pen.Color := Edge;
  Canvas.Pen.Width := 1;
  Canvas.Line(0, ClientHeight - 1, ClientWidth, ClientHeight - 1);
  for I := 0 to FTabs.Count - 1 do
  begin
    R := FRects[I];
    Sel := I = FTabIndex;
    if Sel then
    begin
      Canvas.Brush.Color := clPgnWork;
    end
    else
    begin
      Canvas.Brush.Color := Shade;
      R.Top := R.Top + Scale96ToScreen(2);   // a little lower than the selected one
    end;
    Canvas.FillRect(Rect(R.Left, R.Top, R.Right, R.Bottom - 1));
    Canvas.Pen.Color := Edge;
    Canvas.Line(R.Left, R.Bottom - 1, R.Left, R.Top);
    Canvas.Line(R.Left, R.Top, R.Right - 1, R.Top);
    Canvas.Line(R.Right - 1, R.Top, R.Right - 1, R.Bottom - 1);
    if Sel then
    begin
      // joined to the page: no line under it, and marked along its top
      Canvas.Pen.Color := clPgnWork;
      Canvas.Line(R.Left + 1, R.Bottom - 1, R.Right - 1, R.Bottom - 1);
      Canvas.Brush.Color := clPgnAccent;
      Canvas.FillRect(Rect(R.Left, R.Top, R.Right, R.Top + Scale96ToScreen(3)));
    end;
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := clPgnText;
    if Sel then
    begin
      Canvas.Font.Style := [fsBold];
    end
    else
    begin
      Canvas.Font.Style := [];
    end;
    Canvas.Brush.Style := bsClear;
    TY := R.Top + (R.Bottom - R.Top - Canvas.TextHeight('Ag')) div 2 + Scale96ToScreen(1);
    Canvas.TextOut(R.Left + Scale96ToScreen(14), TY, FTabs[I]);
    Canvas.Brush.Style := bsSolid;
    if FClosable then
    begin
      // an x, drawn
      CR := FCloseRects[I];
      Mid := (CR.Left + CR.Right) div 2;
      TY := (CR.Top + CR.Bottom) div 2;
      Arm := Scale96ToScreen(4);
      Canvas.Pen.Color := clPgnText;
      Canvas.Pen.Width := Max(1, Scale96ToScreen(2) - 1);
      Canvas.Line(Mid - Arm, TY - Arm, Mid + Arm + 1, TY + Arm + 1);
      Canvas.Line(Mid - Arm, TY + Arm, Mid + Arm + 1, TY - Arm - 1);
      Canvas.Pen.Width := 1;
    end;
  end;
  if FShowAdd then
  begin
    R := FAddRect;
    R.Top := R.Top + Scale96ToScreen(2);
    Canvas.Brush.Color := Shade;
    Canvas.FillRect(Rect(R.Left, R.Top, R.Right, R.Bottom - 1));
    Canvas.Pen.Color := Edge;
    Canvas.Line(R.Left, R.Bottom - 1, R.Left, R.Top);
    Canvas.Line(R.Left, R.Top, R.Right - 1, R.Top);
    Canvas.Line(R.Right - 1, R.Top, R.Right - 1, R.Bottom - 1);
    Mid := (R.Left + R.Right) div 2;
    TY := (R.Top + R.Bottom) div 2;
    Arm := Scale96ToScreen(5);
    Canvas.Pen.Color := clPgnText;
    Canvas.Pen.Width := Max(1, Scale96ToScreen(2) - 1);
    Canvas.Line(Mid - Arm, TY, Mid + Arm + 1, TY);
    Canvas.Line(Mid, TY - Arm, Mid, TY + Arm + 1);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TpgnTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  P: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Measure;
  P := Point(X, Y);
  if FShowAdd and PtInRect(FAddRect, P) and (Button = mbLeft) then
  begin
    if Assigned(FOnAdd) then
    begin
      FOnAdd(Self);
    end;
    Exit;
  end;
  for I := 0 to High(FRects) do
  begin
    if PtInRect(FRects[I], P) then
    begin
      // middle-click or the x closes; a click selects
      if FClosable and ((Button = mbMiddle) or PtInRect(FCloseRects[I], P)) then
      begin
        if Assigned(FOnCloseTab) then
        begin
          FOnCloseTab(Self, I);
        end;
      end
      else if (Button = mbLeft) and (I <> FTabIndex) then
      begin
        FTabIndex := I;
        Invalidate;
        if Assigned(FOnChange) then
        begin
          FOnChange(Self);
        end;
      end;
      Exit;
    end;
  end;
end;

{ --------------------------------------------------------- one object }

destructor TpgnDescribedObject.Destroy;
var
  P: TpgnDescribePage;
begin
  for P := Low(TpgnDescribePage) to High(TpgnDescribePage) do
  begin
    FreeAndNil(Grids[P]);
  end;
  FreeAndNil(Script);
  FreeAndNil(Highlighter);
  inherited Destroy;
end;

function TpgnDescribedObject.Container: string;
begin
  Result := Ref.Schema;
  if Result = '' then
  begin
    Result := Ref.Database;
  end;
end;

function TpgnDescribedObject.FullName: string;
begin
  if Container <> '' then
  begin
    Result := Container + '.' + Ref.Name;
  end
  else
  begin
    Result := Ref.Name;
  end;
end;

{ ------------------------------------------------------------- window }

procedure TpgnDescribeWindow.SetFontSize(ASize: Integer);
var
  I: Integer;
begin
  FFontSize := ASize;
  for I := 0 to FObjects.Count - 1 do
  begin
    if ObjectAt(I).Script <> nil then
    begin
      ObjectAt(I).Script.Font.Size := ASize;
    end;
  end;
end;

{ Ctrl+wheel: bigger or smaller, the same as in the editor. }
procedure TpgnDescribeWindow.ScriptWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  if (ssCtrl in Shift) and not (ssShift in Shift) and not (ssAlt in Shift) then
  begin
    if Assigned(FOnZoom) and (WheelDelta <> 0) then
    begin
      FOnZoom(Self, Sign(WheelDelta));
    end;
    Handled := True;
  end;
end;

constructor TpgnDescribeWindow.CreateIn(AOwner: TCustomForm; const ALayout, AEditorTheme: string; AFontSize: Integer;
  AOnAdapter: TpgnDescribeAdapterFunc; AOnReveal: TpgnDescribeRevealEvent;
  AOnResolve: TpgnDescribeResolveFunc);
begin
  inherited CreateNew(AOwner);
  FLayout := ALayout;
  FEditorTheme := AEditorTheme;
  FFontSize := AFontSize;
  FOnAdapter := AOnAdapter;
  FOnReveal := AOnReveal;
  FOnResolve := AOnResolve;
  FObjects := TFPList.Create;
  FCurrent := nil;
  FShown := nil;
  SmoothFont(Font);
  Color := clPgnSurface;
  KeyPreview := True;
  OnKeyDown := @WindowKeyDown;
  OnClose := @WindowClose;
  // in front of Pagona while you work in the editor, as Toad's is; it
  // doesn't go behind the main window when that window is clicked
  PopupMode := pmExplicit;
  PopupParent := AOwner;
  ShowInTaskBar := stNever;
  Position := poOwnerFormCenter;
  Width := S(880);
  Height := S(580);
  Caption := 'Describe';

  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.Height := S(54);
  FHeader.BevelOuter := bvNone;
  FHeader.Caption := '';
  FHeader.Color := clPgnHeader;
  FHeader.ParentColor := False;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FHeader;
  FTitle.Font.Size := 12;
  FTitle.Font.Style := [fsBold];
  FTitle.Font.Color := clPgnHeaderText;
  FTitle.SetBounds(S(12), S(6), S(840), S(22));
  FSub := TLabel.Create(Self);
  FSub.Parent := FHeader;
  FSub.Font.Color := clPgnHeaderText;
  FSub.SetBounds(S(12), S(30), S(840), S(18));

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alBottom;
  FBar.Height := S(44);
  FBar.BevelOuter := bvNone;
  FBar.Caption := '';
  FBar.Color := clPgnBar;
  FBar.ParentColor := False;
  FBar.OnResize := @BarResize;
  FReveal := TButton.Create(Self);
  FReveal.Parent := FBar;
  if SameText(ALayout, 'Amphibian') then
  begin
    FReveal.Caption := 'Show in Object Browser';
  end
  else if SameText(ALayout, 'Seattle') then
  begin
    FReveal.Caption := 'Show in Object Explorer';
  end
  else
  begin
    FReveal.Caption := 'Show in Explorer';
  end;
  FReveal.OnClick := @RevealClick;
  FReveal.Enabled := Assigned(FOnReveal);
  FRefresh := TButton.Create(Self);
  FRefresh.Parent := FBar;
  FRefresh.Caption := 'Refresh';
  FRefresh.OnClick := @RefreshClick;
  FClose := TButton.Create(Self);
  FClose.Parent := FBar;
  FClose.Caption := 'Close';
  FClose.OnClick := @CloseClick;

  // objects across the top, each object's pages under them
  FObjTabs := TpgnTabStrip.Create(Self);
  FObjTabs.Parent := Self;
  FObjTabs.Align := alTop;
  FObjTabs.Top := FHeader.Top + FHeader.Height + 1;
  FObjTabs.Height := S(34);
  FObjTabs.Big := True;
  FObjTabs.Closable := True;
  FObjTabs.ShowAdd := Assigned(FOnResolve);
  FObjTabs.OnChange := @ObjTabChange;
  FObjTabs.OnCloseTab := @ObjTabClose;
  FObjTabs.OnAdd := @ObjTabAdd;
  FPageTabs := TpgnTabStrip.Create(Self);
  FPageTabs.Parent := Self;
  FPageTabs.Align := alTop;
  FPageTabs.Top := FObjTabs.Top + FObjTabs.Height + 1;
  FPageTabs.Height := S(30);
  FPageTabs.OnChange := @PageTabChange;
  FBody := TPanel.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BevelOuter := bvNone;
  FBody.Caption := '';
  FBody.Color := clPgnWork;
  FBody.ParentColor := False;
  FBody.OnResize := @BodyResize;
end;

destructor TpgnDescribeWindow.Destroy;
var
  I: Integer;
begin
  for I := 0 to FObjects.Count - 1 do
  begin
    TpgnDescribedObject(FObjects[I]).Free;
  end;
  FObjects.Free;
  inherited Destroy;
end;

function TpgnDescribeWindow.S(AValue: Integer): Integer;
begin
  Result := Scale96ToScreen(AValue);
end;

function TpgnDescribeWindow.ObjectAt(AIndex: Integer): TpgnDescribedObject;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FObjects.Count) then
  begin
    Result := TpgnDescribedObject(FObjects[AIndex]);
  end;
end;

function TpgnDescribeWindow.IndexOfRef(const AConnId: string; const ARef: TpgnObjectRef): Integer;
var
  I: Integer;
  O: TpgnDescribedObject;
begin
  Result := -1;
  for I := 0 to FObjects.Count - 1 do
  begin
    O := ObjectAt(I);
    if (O.ConnId = AConnId) and SameText(O.Ref.Database, ARef.Database) and
      SameText(O.Ref.Schema, ARef.Schema) and SameText(O.Ref.Name, ARef.Name) and
      (O.Ref.Kind = ARef.Kind) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TpgnDescribeWindow.AddObject(const AConnId, AConnName: string; const ARef: TpgnObjectRef;
  const AVia: string; ADialect: TpgnDialect);
var
  I: Integer;
  O: TpgnDescribedObject;
begin
  I := IndexOfRef(AConnId, ARef);
  if I < 0 then
  begin
    O := TpgnDescribedObject.Create;
    O.ConnId := AConnId;
    O.ConnName := AConnName;
    O.Ref := ARef;
    O.Via := AVia;
    O.Dialect := ADialect;
    O.PageIndex := 0;
    O.Loaded := [];
    BuildPages(O);
    MakeControls(O);
    FObjects.Add(O);
    I := FObjects.Count - 1;
  end;
  FillObjTabs;
  SelectObject(I);
end;

{ The pages a kind of object has, as Toad shows them. }
procedure TpgnDescribeWindow.BuildPages(AObj: TpgnDescribedObject);

  procedure Add(APage: TpgnDescribePage);
  begin
    SetLength(AObj.Pages, Length(AObj.Pages) + 1);
    AObj.Pages[High(AObj.Pages)] := APage;
  end;

begin
  AObj.Pages := nil;
  if AObj.Ref.Kind = 'Table' then
  begin
    Add(dwColumns);
    Add(dwIndexes);
    Add(dwConstraints);
    Add(dwTriggers);
    Add(dwData);
    Add(dwScript);
    Add(dwGrants);
    Add(dwUsedBy);
  end
  else if (AObj.Ref.Kind = 'View') or (AObj.Ref.Kind = 'Materialized View') then
  begin
    Add(dwColumns);
    Add(dwData);
    Add(dwScript);
    Add(dwGrants);
    Add(dwUses);
    Add(dwUsedBy);
  end
  else if AObj.Ref.Kind = 'Package' then
  begin
    Add(dwScript);
    Add(dwGrants);
    Add(dwUses);
    Add(dwUsedBy);
  end
  else
  begin
    Add(dwArguments);
    Add(dwUses);
    Add(dwScript);
    Add(dwGrants);
    Add(dwUsedBy);
  end;
end;

{ The object's page controls, made now and kept out of sight until shown
  (GTK3 draws a control made later at its first size). }
procedure TpgnDescribeWindow.MakeControls(AObj: TpgnDescribedObject);
var
  I: Integer;
  P: TpgnDescribePage;
begin
  for P := Low(TpgnDescribePage) to High(TpgnDescribePage) do
  begin
    AObj.Grids[P] := nil;
  end;
  AObj.Script := nil;
  AObj.Highlighter := nil;
  for I := 0 to High(AObj.Pages) do
  begin
    P := AObj.Pages[I];
    if P = dwScript then
    begin
      AObj.Highlighter := TSynSQLSyn.Create(nil);
      case AObj.Dialect of
        sdPostgreSQL:
          begin
            AObj.Highlighter.SQLDialect := sqlPostgres;
          end;
        sdOracle:
          begin
            AObj.Highlighter.SQLDialect := sqlOracle;
          end;
        sdTSQL:
          begin
            AObj.Highlighter.SQLDialect := sqlMSSQL2K;
          end;
      else
        begin
          AObj.Highlighter.SQLDialect := sqlMySQL;
        end;
      end;
      ApplyEditorTheme(AObj.Highlighter, FEditorTheme);
      AObj.Script := TSynEdit.Create(nil);
      AObj.Script.Parent := FBody;
      AObj.Script.Align := alNone;
      // the query editor's font and size
      {$IFDEF WINDOWS}
      AObj.Script.Font.Name := 'Consolas';
      {$ELSE}
      AObj.Script.Font.Name := 'Monospace';
      {$ENDIF}
      AObj.Script.Font.Size := FFontSize;
      SmoothFont(AObj.Script.Font);
      AObj.Script.OnMouseWheel := @ScriptWheel;
      AObj.Script.ReadOnly := True;
      AObj.Script.Highlighter := AObj.Highlighter;
      AObj.Script.RightEdge := -1;
      AObj.Script.Options := AObj.Script.Options - [eoScrollPastEol];
      AObj.Script.SetBounds(-6000, 0, 300, 200);
    end
    else
    begin
      AObj.Grids[P] := TpgnResultGrid.Create(nil);
      AObj.Grids[P].Parent := FBody;
      AObj.Grids[P].Align := alNone;
      AObj.Grids[P].Dialect := AObj.Dialect;
      AObj.Grids[P].SetBounds(-6000, 0, 300, 200);
    end;
  end;
end;

procedure TpgnDescribeWindow.FillObjTabs;
var
  I: Integer;
begin
  FObjTabs.Tabs.Clear;
  for I := 0 to FObjects.Count - 1 do
  begin
    FObjTabs.Tabs.Add(ObjectAt(I).FullName);
  end;
  FObjTabs.Changed;
end;

procedure TpgnDescribeWindow.SelectObject(AIndex: Integer);
var
  O: TpgnDescribedObject;
  I: Integer;
  Sub: string;
begin
  O := ObjectAt(AIndex);
  if O = nil then
  begin
    Exit;
  end;
  if (FShown <> nil) then
  begin
    FShown.SetBounds(-6000, 0, 300, 200);
    FShown := nil;
  end;
  FCurrent := O;
  FObjTabs.TabIndex := AIndex;
  FTitle.Caption := O.FullName;
  Sub := O.Ref.Kind;
  if O.Via <> '' then
  begin
    Sub := Sub + ', ' + O.Via;
  end;
  if O.ConnName <> '' then
  begin
    Sub := Sub + '  ' + #$C2#$B7 + '  ' + O.ConnName;
  end;
  FSub.Caption := Sub;
  if SameText(FLayout, 'Amphibian') then
  begin
    Caption := 'Describe: ' + O.FullName;
  end
  else
  begin
    Caption := O.FullName + ' - Describe';
  end;
  FPageTabs.Tabs.Clear;
  for I := 0 to High(O.Pages) do
  begin
    FPageTabs.Tabs.Add(PageCaptions[O.Pages[I]]);
  end;
  FPageTabs.TabIndex := O.PageIndex;
  FPageTabs.Changed;
  if (O.PageIndex >= 0) and (O.PageIndex <= High(O.Pages)) then
  begin
    ShowPage(O.Pages[O.PageIndex]);
  end;
end;

procedure TpgnDescribeWindow.ObjTabChange(Sender: TObject);
begin
  SelectObject(FObjTabs.TabIndex);
end;

procedure TpgnDescribeWindow.ObjTabClose(Sender: TObject; AIndex: Integer);
var
  O: TpgnDescribedObject;
  NextIdx: Integer;
begin
  O := ObjectAt(AIndex);
  if O = nil then
  begin
    Exit;
  end;
  if FCurrent = O then
  begin
    FCurrent := nil;
    FShown := nil;
  end;
  FObjects.Delete(AIndex);
  O.Free;
  if FObjects.Count = 0 then
  begin
    Close;   // the last one: the window goes too
    Exit;
  end;
  NextIdx := FObjTabs.TabIndex;
  if NextIdx >= AIndex then
  begin
    NextIdx := NextIdx - 1;
  end;
  NextIdx := EnsureRange(NextIdx, 0, FObjects.Count - 1);
  FillObjTabs;
  SelectObject(NextIdx);
end;

{ ------------------------------------------------------ the + search box }

type
  { Names show as you type (each one containing the text, from the
    connection's own search); Enter or a double-click takes the highlighted
    one. A name typed in full and not in the list (a synonym, say) is looked
    up as typed. }
  TpgnObjectPicker = class(TForm)
  public
    Adapter: TpgnAdapter;
    Edit: TEdit;
    Hits: TpgnResultGrid;
    Status: TLabel;
    Timer: TTimer;
    Found: TpgnObjectRefs;
    Picked: Integer;            // the row taken, -1 for the typed name
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HitsDblClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure OKClick(Sender: TObject);
  end;

procedure TpgnObjectPicker.EditChange(Sender: TObject);
begin
  Timer.Enabled := False;
  Timer.Enabled := True;
end;

procedure TpgnObjectPicker.TimerTick(Sender: TObject);
var
  T, Where: string;
  R: TpgnResultSet;
  I: Integer;
begin
  Timer.Enabled := False;
  T := Trim(Edit.Text);
  if Pos('.', T) > 0 then
  begin
    T := Copy(T, LastDelimiter('.', T) + 1, MaxInt);
  end;
  T := Unquoted(T);
  Found := nil;
  if Length(T) >= 2 then
  begin
    Screen.Cursor := crHourGlass;
    try
      try
        Found := Adapter.SearchObjects(T, 200);
      except
        on E: Exception do
        begin
          Found := nil;
          Status.Caption := 'Could not search: ' + E.Message;
        end;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  R := TpgnResultSet.Create;
  SetLength(R.Columns, 3);
  R.Columns[0] := 'Name';
  R.Columns[1] := 'Schema';
  R.Columns[2] := 'Type';
  SetLength(R.Rows, Length(Found));
  for I := 0 to High(Found) do
  begin
    Where := Found[I].Schema;
    if Where = '' then
    begin
      Where := Found[I].Database;
    end;
    SetLength(R.Rows[I].Values, 3);
    SetLength(R.Rows[I].Nulls, 3);
    R.Rows[I].Values[0] := Found[I].Name;
    R.Rows[I].Values[1] := Where;
    R.Rows[I].Values[2] := Found[I].Kind;
  end;
  R.ReturnsRows := True;
  Hits.ShowData(R);
  if Length(T) < 2 then
  begin
    Status.Caption := 'Type two or more letters of the name.';
  end
  else if Length(Found) = 0 then
  begin
    Status.Caption := 'Nothing found. Enter looks the name up as typed (a synonym works too).';
  end
  else if Length(Found) >= 200 then
  begin
    Status.Caption := 'The first 200 names. Type more to narrow them.';
  end
  else
  begin
    Status.Caption := FormatFloat('#,##0', Length(Found)) + ' found. Down to pick, Enter to add.';
  end;
end;

procedure TpgnObjectPicker.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and (Length(Found) > 0) and Hits.CanFocus then
  begin
    Hits.SetFocus;
    Hits.Row := 1;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    OKClick(nil);
    Key := 0;
  end;
end;

procedure TpgnObjectPicker.HitsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    HitsDblClick(nil);
    Key := 0;
  end
  else if (Key = VK_UP) and (Hits.Row <= 1) and Edit.CanFocus then
  begin
    Edit.SetFocus;
    Key := 0;
  end;
end;

procedure TpgnObjectPicker.HitsDblClick(Sender: TObject);
begin
  if (Hits.Row >= 1) and (Hits.Row <= Length(Found)) then
  begin
    Picked := Hits.Row - 1;
    ModalResult := mrOK;
  end;
end;

{ OK (or Enter in the box): the search runs now if it hasn't; a name that
  matches one hit exactly takes it, otherwise the typed name is looked up. }
procedure TpgnObjectPicker.OKClick(Sender: TObject);
var
  I, Match: Integer;
  T: string;
begin
  if Trim(Edit.Text) = '' then
  begin
    Exit;
  end;
  if Timer.Enabled then
  begin
    TimerTick(nil);
  end;
  T := Unquoted(Trim(Edit.Text));
  Match := -1;
  for I := 0 to High(Found) do
  begin
    if SameText(Found[I].Name, T) then
    begin
      if Match >= 0 then
      begin
        Match := -1;    // the same name in two schemas: the lookup decides
        Break;
      end;
      Match := I;
    end;
  end;
  if (Match < 0) and (Length(Found) = 1) then
  begin
    Match := 0;
  end;
  Picked := Match;
  ModalResult := mrOK;
end;

{ 0: cancelled; 1: look up AText; 2: ARef was picked from the list. }
function PickObject(AOwner: TCustomForm; AAdapter: TpgnAdapter; const AConnName: string;
  out AText: string; out ARef: TpgnObjectRef): Integer;
var
  F: TpgnObjectPicker;
  L: TLabel;
  BOK, BCancel: TButton;
  Bottom: TPanel;
  M: Integer;
begin
  Result := 0;
  AText := '';
  ARef.Database := '';
  ARef.Schema := '';
  ARef.Name := '';
  ARef.Kind := '';
  F := TpgnObjectPicker.CreateNew(AOwner);
  try
    F.Adapter := AAdapter;
    F.Picked := -1;
    F.Caption := 'Describe: add an object';
    F.BorderStyle := bsSizeable;
    F.Position := poOwnerFormCenter;
    M := F.Scale96ToScreen(10);
    F.Width := F.Scale96ToScreen(560);
    F.Height := F.Scale96ToScreen(440);
    F.KeyPreview := False;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Align := alTop;
    L.BorderSpacing.Around := M;
    L.Caption := 'Table, view, procedure or package on ' + AConnName + ' (part of the name finds it):';

    F.Edit := TEdit.Create(F);
    F.Edit.Parent := F;
    F.Edit.Align := alTop;
    F.Edit.Top := L.Top + L.Height + 1;
    F.Edit.BorderSpacing.Left := M;
    F.Edit.BorderSpacing.Right := M;
    F.Edit.OnChange := @F.EditChange;
    F.Edit.OnKeyDown := @F.EditKeyDown;

    Bottom := TPanel.Create(F);
    Bottom.Parent := F;
    Bottom.Align := alBottom;
    Bottom.BevelOuter := bvNone;
    Bottom.Caption := '';
    Bottom.Height := F.Scale96ToScreen(44);

    BCancel := TButton.Create(F);
    BCancel.Parent := Bottom;
    BCancel.Caption := 'Cancel';
    BCancel.ModalResult := mrCancel;
    BCancel.Cancel := True;
    BCancel.Anchors := [akRight, akTop];
    BCancel.SetBounds(Bottom.ClientWidth - F.Scale96ToScreen(96) - M, F.Scale96ToScreen(8),
      F.Scale96ToScreen(96), F.Scale96ToScreen(28));

    BOK := TButton.Create(F);
    BOK.Parent := Bottom;
    BOK.Caption := 'Add';
    BOK.Default := True;
    BOK.OnClick := @F.OKClick;
    BOK.Anchors := [akRight, akTop];
    BOK.SetBounds(BCancel.Left - F.Scale96ToScreen(96) - F.Scale96ToScreen(8), F.Scale96ToScreen(8),
      F.Scale96ToScreen(96), F.Scale96ToScreen(28));

    F.Status := TLabel.Create(F);
    F.Status.Parent := F;
    F.Status.Align := alBottom;
    F.Status.BorderSpacing.Left := M;
    F.Status.BorderSpacing.Top := F.Scale96ToScreen(4);
    F.Status.Font.Color := clPgnMuted;
    F.Status.Caption := 'Type two or more letters of the name.';
    F.Status.Top := Bottom.Top - 1;   // above the buttons

    F.Hits := TpgnResultGrid.Create(F);
    F.Hits.Parent := F;
    F.Hits.Align := alClient;
    F.Hits.BorderSpacing.Around := M;
    F.Hits.Options := F.Hits.Options + [goRowSelect];
    F.Hits.OnDblClick := @F.HitsDblClick;
    F.Hits.OnKeyDown := @F.HitsKeyDown;

    F.Timer := TTimer.Create(F);
    F.Timer.Enabled := False;
    F.Timer.Interval := 300;
    F.Timer.OnTimer := @F.TimerTick;

    F.ActiveControl := F.Edit;
    if F.ShowModal <> mrOK then
    begin
      Exit;
    end;
    AText := Trim(F.Edit.Text);
    if (F.Picked >= 0) and (F.Picked <= High(F.Found)) then
    begin
      ARef := F.Found[F.Picked];
      Result := 2;
    end
    else if AText <> '' then
    begin
      Result := 1;
    end;
  finally
    F.Free;
  end;
end;

{ + : a name typed in, looked up on the shown object's connection. }
procedure TpgnDescribeWindow.ObjTabAdd(Sender: TObject);
var
  ObjName, Via: string;
  Ref: TpgnObjectRef;
  Found: Boolean;
  A: TpgnAdapter;
begin
  if (FCurrent = nil) or not Assigned(FOnResolve) then
  begin
    Exit;
  end;
  A := nil;
  if Assigned(FOnAdapter) then
  begin
    A := FOnAdapter(FCurrent.ConnId, FCurrent.Ref.Database);
  end;
  if A = nil then
  begin
    MessageDlg('Describe', FCurrent.ConnName + ' is closed. Connect it again first.', mtInformation,
      [mbOK], 0);
    Exit;
  end;
  case PickObject(Self, A, FCurrent.ConnName, ObjName, Ref) of
    0:
      begin
        Exit;
      end;
    2:
      begin
        AddObject(FCurrent.ConnId, FCurrent.ConnName, Ref, '', FCurrent.Dialect);
        Exit;
      end;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      Found := FOnResolve(FCurrent.ConnId, ObjName, Ref, Via);
    except
      on E: Exception do
      begin
        Screen.Cursor := crDefault;
        MessageDlg('Describe', 'Could not look up ' + ObjName + ':' + LineEnding + E.Message,
          mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if not Found then
  begin
    MessageDlg('Describe', ObjName + ': there is no table, view, synonym or procedure by that name ' +
      'that your login can see on ' + FCurrent.ConnName + '.', mtInformation, [mbOK], 0);
    Exit;
  end;
  AddObject(FCurrent.ConnId, FCurrent.ConnName, Ref, Via, FCurrent.Dialect);
end;

procedure TpgnDescribeWindow.PageTabChange(Sender: TObject);
begin
  if (FCurrent <> nil) and (FPageTabs.TabIndex >= 0) and (FPageTabs.TabIndex <= High(FCurrent.Pages)) then
  begin
    FCurrent.PageIndex := FPageTabs.TabIndex;
    ShowPage(FCurrent.Pages[FPageTabs.TabIndex]);
  end;
end;

procedure TpgnDescribeWindow.BodyResize(Sender: TObject);
begin
  if FShown <> nil then
  begin
    FShown.SetBounds(0, 0, FBody.ClientWidth, FBody.ClientHeight);
  end;
end;

procedure TpgnDescribeWindow.BarResize(Sender: TObject);
var
  H, Y, Gap, W: Integer;
begin
  H := S(30);
  Gap := S(8);
  Y := (FBar.ClientHeight - H) div 2;
  FReveal.SetBounds(S(12), Y, Length(FReveal.Caption) * S(8) + S(24), H);
  W := S(90);
  FClose.SetBounds(FBar.ClientWidth - S(12) - W, Y, W, H);
  FRefresh.SetBounds(FClose.Left - Gap - W, Y, W, H);
end;

procedure TpgnDescribeWindow.ShowPage(APage: TpgnDescribePage);
var
  C: TControl;
begin
  if FCurrent = nil then
  begin
    Exit;
  end;
  if not (APage in FCurrent.Loaded) then
  begin
    LoadPage(APage);
  end;
  if APage = dwScript then
  begin
    C := FCurrent.Script;
  end
  else
  begin
    C := FCurrent.Grids[APage];
  end;
  if (FShown <> nil) and (FShown <> C) then
  begin
    FShown.SetBounds(-6000, 0, 300, 200);
  end;
  FShown := C;
  if FShown <> nil then
  begin
    FShown.SetBounds(0, 0, FBody.ClientWidth, FBody.ClientHeight);
  end;
end;

procedure TpgnDescribeWindow.LoadPage(APage: TpgnDescribePage);
var
  O: TpgnDescribedObject;
  A: TpgnAdapter;
  R: TpgnResultSet;
  C, Q, Txt: string;
  Kind: TpgnRoutineKind;
begin
  O := FCurrent;
  Include(O.Loaded, APage);
  A := nil;
  if Assigned(FOnAdapter) then
  begin
    A := FOnAdapter(O.ConnId, O.Ref.Database);
  end;
  if A = nil then
  begin
    if APage = dwScript then
    begin
      O.Script.Lines.Text := '-- The connection is closed. Connect it again, then Refresh.';
    end
    else
    begin
      O.Grids[APage].ShowData(Note(PageCaptions[APage],
        'The connection is closed. Connect it again, then Refresh.'));
    end;
    Exclude(O.Loaded, APage);
    Exit;
  end;
  C := O.Container;
  Screen.Cursor := crHourGlass;
  try
    if APage = dwScript then
    begin
      try
        if O.Ref.Kind = 'Table' then
        begin
          Txt := A.GetDDL(C, O.Ref.Name, okTable);
        end
        else if O.Ref.Kind = 'View' then
        begin
          Txt := A.GetDDL(C, O.Ref.Name, okView);
        end
        else if O.Ref.Kind = 'Materialized View' then
        begin
          Txt := A.GetDDL(C, O.Ref.Name, okMatView);
        end
        else if O.Ref.Kind = 'Package' then
        begin
          Txt := A.ObjectScript(C, O.Ref.Name, O.Ref.Kind);
        end
        else if Pos('.', O.Ref.Name) > 0 then
        begin
          // a package member: its package
          Txt := A.ObjectScript(C, Copy(O.Ref.Name, 1, Pos('.', O.Ref.Name) - 1), 'Package');
        end
        else
        begin
          if O.Ref.Kind = 'Procedure' then
          begin
            Kind := rkProcedure;
          end
          else
          begin
            Kind := rkFunction;
          end;
          Txt := A.GetRoutineSQL(C, O.Ref.Name, Kind);
        end;
        if Trim(Txt) = '' then
        begin
          Txt := '-- Your login can''t see this definition.';
        end;
      except
        on E: Exception do
        begin
          Txt := '-- Could not read the definition: ' + E.Message;
        end;
      end;
      O.Script.Lines.Text := Txt;
      O.Script.CaretXY := Point(1, 1);
      O.Script.TopLine := 1;
      Exit;
    end;
    try
      case APage of
        dwColumns:
          begin
            R := A.DescribeTable(C, O.Ref.Name);
          end;
        dwIndexes:
          begin
            R := A.DescribeIndexes(C, O.Ref.Name);
          end;
        dwConstraints:
          begin
            R := A.DescribeConstraints(C, O.Ref.Name);
          end;
        dwTriggers:
          begin
            R := A.DescribeTriggers(C, O.Ref.Name);
          end;
        dwArguments:
          begin
            R := A.DescribeParameters(C, O.Ref.Name);
          end;
        dwUses:
          begin
            R := A.DescribeUses(C, O.Ref.Name);
          end;
        dwData:
          begin
            Q := A.SelectTopSQL(A.QuoteIdent(C) + '.' + A.QuoteIdent(O.Ref.Name), DataRows);
            R := A.Execute(Q, DataRows);
          end;
        dwGrants:
          begin
            if Pos('.', O.Ref.Name) > 0 then
            begin
              // a package member: grants are on its package
              R := A.DescribeGrants(C, Copy(O.Ref.Name, 1, Pos('.', O.Ref.Name) - 1), 'PACKAGE');
            end
            else if O.Ref.Kind = 'Table' then
            begin
              R := A.DescribeGrants(C, O.Ref.Name, 'TABLE');
            end
            else if (O.Ref.Kind = 'View') or (O.Ref.Kind = 'Materialized View') then
            begin
              R := A.DescribeGrants(C, O.Ref.Name, 'VIEW');
            end
            else if O.Ref.Kind = 'Procedure' then
            begin
              R := A.DescribeGrants(C, O.Ref.Name, 'PROCEDURE');
            end
            else if O.Ref.Kind = 'Package' then
            begin
              R := A.DescribeGrants(C, O.Ref.Name, 'PACKAGE');
            end
            else
            begin
              R := A.DescribeGrants(C, O.Ref.Name, 'FUNCTION');
            end;
          end;
      else
        begin
          if Pos('.', O.Ref.Name) > 0 then
          begin
            R := A.DescribeUsedBy(C, Copy(O.Ref.Name, 1, Pos('.', O.Ref.Name) - 1));
          end
          else
          begin
            R := A.DescribeUsedBy(C, O.Ref.Name);
          end;
        end;
      end;
      if R = nil then
      begin
        R := Note(PageCaptions[APage], 'Pagona can''t show this for this database yet.');
      end
      else if R.RowCount = 0 then
      begin
        if APage = dwUsedBy then
        begin
          R.Free;
          R := Note(PageCaptions[APage], 'Nothing that Pagona can see depends on it.');
        end
        else if APage = dwUses then
        begin
          R.Free;
          R := Note(PageCaptions[APage], 'It uses nothing your login can see.');
        end
        else if APage in [dwIndexes, dwConstraints, dwTriggers, dwGrants] then
        begin
          R.Free;
          R := Note(PageCaptions[APage], 'None.');
        end;
      end;
    except
      on E: Exception do
      begin
        R := Note(PageCaptions[APage], 'Could not read this: ' + E.Message);
      end;
    end;
    O.Grids[APage].ShowData(R);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TpgnDescribeWindow.RevealClick(Sender: TObject);
begin
  if Assigned(FOnReveal) and (FCurrent <> nil) then
  begin
    FOnReveal(FCurrent.ConnId, FCurrent.Ref);
  end;
end;

{ The shown object read again: this page now, its others when shown. }
procedure TpgnDescribeWindow.RefreshClick(Sender: TObject);
begin
  if FCurrent = nil then
  begin
    Exit;
  end;
  FCurrent.Loaded := [];
  if (FCurrent.PageIndex >= 0) and (FCurrent.PageIndex <= High(FCurrent.Pages)) then
  begin
    ShowPage(FCurrent.Pages[FCurrent.PageIndex]);
  end;
end;

procedure TpgnDescribeWindow.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TpgnDescribeWindow.WindowClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

procedure TpgnDescribeWindow.WindowKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    Close;
  end
  else if (Key = VK_F5) and (Shift = []) then
  begin
    Key := 0;
    RefreshClick(nil);
  end;
end;

end.
