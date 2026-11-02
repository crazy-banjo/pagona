// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAmphibian;

{ The pieces of the Amphibian layout (Toad's arrangement, Pagona's look):

    TpgnStripBar       the session bar (one button per open connection,
                       its environment as text) and the window bar
                       (Editor, Schema Browser, DBA screens)
    TpgnSchemaBrowser  Database > Schema Browser: a schema, its object
                       types as buttons, a filtered list, and the details
                       of what's picked (the main window lends its
                       Details panel)

  Both are drawn and laid out by hand, so they look and behave the same on
  Windows and Linux. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls, Buttons, Forms, Math, Menus,
  LCLType, Types, Grids, pgnTypes, pgnTheme, pgnAdapter, pgnResultGrid;

type
  TpgnStripItem = record
    Caption: string;
    Env: TpgnEnvironment;      // enNone: no tag
    Key: string;               // what the owner uses to find it again
  end;

  TpgnStripClickEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { A row of buttons (session bar) or tabs (window bar). }
  TpgnStripBar = class(TCustomControl)
  private
    FItems: array of TpgnStripItem;
    FRects: array of TRect;
    FActive: Integer;
    FHot: Integer;
    FTabLook: Boolean;
    FEmptyText: string;
    FOnItemClick: TpgnStripClickEvent;
    function S(AValue: Integer): Integer;
    procedure Layout;
    function ItemAt(X, Y: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Clear;
    procedure Add(const ACaption, AKey: string; AEnv: TpgnEnvironment);
    function Count: Integer;
    function KeyAt(AIndex: Integer): string;
    function IndexOfKey(const AKey: string): Integer;
    property ActiveIndex: Integer read FActive write FActive;
    property TabLook: Boolean read FTabLook write FTabLook;
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnItemClick: TpgnStripClickEvent read FOnItemClick write FOnItemClick;
  end;

  TpgnBrowserAdapterFunc = function(AConnIndex: Integer; const ADatabase: string): TpgnAdapter of object;
  TpgnBrowserRefEvent = procedure(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef) of object;
  TpgnBrowserMenuEvent = procedure(Sender: TObject; AConnIndex: Integer; const ARef: TpgnObjectRef;
    const AScreenPos: TPoint) of object;

  { One kind of object the browser lists. }
  TpgnBrowserType = record
    Caption: string;
    Kind: string;              // Table, View, Materialized View, Procedure, Function,
                               // Trigger, Trigger Function, Other
    Folder: string;            // Other: the adapter's folder name
    Level: TpgnFolderLevel;    // Other: where the folder lives
    Rare: Boolean;             // offered under More
  end;

  TpgnSchemaBrowser = class(TPanel)
  private
    FConnIndex: Integer;
    FInfo: TpgnConnectionInfo;
    FRoot: TpgnAdapter;
    FTypes: array of TpgnBrowserType;
    FTypeIndex: Integer;
    FAll: TStringList;
    FLeft: TPanel;
    FTop: TPanel;
    FDbLabel: TLabel;
    FDbCombo: TComboBox;
    FSchemaLabel: TLabel;
    FSchemaCombo: TComboBox;
    FRefresh: TButton;
    FTypePanel: TPanel;
    FTypeButtons: array of TSpeedButton;
    FMoreButton: TSpeedButton;
    FMoreMenu: TPopupMenu;
    FFilter: TEdit;
    FList: TpgnResultGrid;
    FShown: TStringList;         // the names in the list, in order
    FCount: TLabel;
    FHeader: TLabel;
    FDetailsHost: TPanel;
    FSelectTimer: TTimer;
    FFilling: Boolean;
    FOnAdapter: TpgnBrowserAdapterFunc;
    FOnSelect: TpgnBrowserRefEvent;
    FOnOpen: TpgnBrowserRefEvent;
    FOnMenu: TpgnBrowserMenuEvent;
    function S(AValue: Integer): Integer;
    function Adapter(const ADatabase: string): TpgnAdapter;
    function Database: string;
    function Schema: string;
    function Container: string;
    procedure BuildTypes;
    procedure LayoutTop(Sender: TObject);
    procedure LayoutTypes(Sender: TObject);
    procedure FillDatabases;
    procedure FillSchemas;
    procedure LoadList;
    procedure ApplyFilter;
    function RefOf(AIndex: Integer): TpgnObjectRef;
    procedure DbChange(Sender: TObject);
    procedure SchemaChange(Sender: TObject);
    procedure TypeClick(Sender: TObject);
    procedure MoreClick(Sender: TObject);
    procedure MoreItemClick(Sender: TObject);
    procedure PickType(AIndex: Integer);
    procedure FilterChange(Sender: TObject);
    procedure ListSelect(Sender: TObject; aCol, aRow: Integer);
    function ListIndex: Integer;
    procedure ListDblClick(Sender: TObject);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SelectTimerTick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows this connection's objects (ARoot is its Explorer session). }
    procedure Attach(AConnIndex: Integer; const AInfo: TpgnConnectionInfo; ARoot: TpgnAdapter);
    procedure Detach;
    procedure Reload;
    { Shows one object: its database and schema, its type, selected in the
      list (the Describe window's Show in Schema Browser). }
    procedure ShowObject(const ARef: TpgnObjectRef);
    property ConnIndex: Integer read FConnIndex;
    property Info: TpgnConnectionInfo read FInfo;
    { The main window puts its Details panel here. }
    property DetailsHost: TPanel read FDetailsHost;
    property Header: TLabel read FHeader;
    property OnAdapter: TpgnBrowserAdapterFunc read FOnAdapter write FOnAdapter;
    property OnSelectObject: TpgnBrowserRefEvent read FOnSelect write FOnSelect;
    property OnOpenObject: TpgnBrowserRefEvent read FOnOpen write FOnOpen;
    property OnObjectMenu: TpgnBrowserMenuEvent read FOnMenu write FOnMenu;
  end;

{ Toad-style filter: with % or _ it's a LIKE pattern (SPR% = starts with
  SPR), otherwise the text may appear anywhere. Case doesn't matter. }
function FilterMatches(const AFilter, AName: string): Boolean;

implementation

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

function LikeMatch(const P, T: string; PI, TI: Integer): Boolean;
begin
  while PI <= Length(P) do
  begin
    if P[PI] = '%' then
    begin
      while (PI <= Length(P)) and (P[PI] = '%') do
      begin
        Inc(PI);
      end;
      if PI > Length(P) then
      begin
        Result := True;
        Exit;
      end;
      while TI <= Length(T) do
      begin
        if LikeMatch(P, T, PI, TI) then
        begin
          Result := True;
          Exit;
        end;
        Inc(TI);
      end;
      Result := False;
      Exit;
    end;
    if TI > Length(T) then
    begin
      Result := False;
      Exit;
    end;
    if (P[PI] <> '_') and (P[PI] <> T[TI]) then
    begin
      Result := False;
      Exit;
    end;
    Inc(PI);
    Inc(TI);
  end;
  Result := TI > Length(T);
end;

function FilterMatches(const AFilter, AName: string): Boolean;
var
  F, N: string;
begin
  F := UpperCase(Trim(AFilter));
  N := UpperCase(AName);
  if F = '' then
  begin
    Result := True;
  end
  else if (Pos('%', F) > 0) or (Pos('_', F) > 0) then
  begin
    Result := LikeMatch(F, N, 1, 1);
  end
  else
  begin
    Result := Pos(F, N) > 0;
  end;
end;

{ ============================================================ strip bar }

constructor TpgnStripBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := -1;
  FHot := -1;
  Color := clPgnBar;
  ParentColor := False;
  DoubleBuffered := True;
  Height := S(32);
end;

function TpgnStripBar.S(AValue: Integer): Integer;
begin
  Result := Scale96ToScreen(AValue);
end;

procedure TpgnStripBar.Clear;
begin
  SetLength(FItems, 0);
  SetLength(FRects, 0);
  FActive := -1;
  FHot := -1;
end;

procedure TpgnStripBar.Add(const ACaption, AKey: string; AEnv: TpgnEnvironment);
var
  N: Integer;
begin
  N := Length(FItems);
  SetLength(FItems, N + 1);
  FItems[N].Caption := ACaption;
  FItems[N].Key := AKey;
  FItems[N].Env := AEnv;
end;

function TpgnStripBar.Count: Integer;
begin
  Result := Length(FItems);
end;

function TpgnStripBar.KeyAt(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FItems)) then
  begin
    Result := FItems[AIndex].Key;
  end;
end;

function TpgnStripBar.IndexOfKey(const AKey: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FItems) do
  begin
    if FItems[I].Key = AKey then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TpgnStripBar.Layout;
var
  I, X, W: Integer;
begin
  SetLength(FRects, Length(FItems));
  Canvas.Font.Assign(Font);
  X := S(4);
  for I := 0 to High(FItems) do
  begin
    Canvas.Font.Style := [fsBold];
    W := Canvas.TextWidth(FItems[I].Caption) + S(24);
    if FItems[I].Env <> enNone then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Size := Max(7, Font.Size - 2);
      W := W + Canvas.TextWidth(EnvironmentShort[FItems[I].Env]) + S(12);
      Canvas.Font.Assign(Font);
    end;
    if FTabLook then
    begin
      FRects[I] := Rect(X, S(4), X + W, Height);
    end
    else
    begin
      FRects[I] := Rect(X, S(4), X + W, Height - S(4));
    end;
    X := X + W + S(3);
  end;
end;

function TpgnStripBar.ItemAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FRects) do
  begin
    if PtInRect(FRects[I], Point(X, Y)) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TpgnStripBar.Paint;
var
  I, X, TH: Integer;
  R, TagR: TRect;
  Look: TpgnEnvLook;
  Back: TColor;
  EnvTag: string;
begin
  Layout;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := clPgnLines;
  Canvas.Line(0, Height - 1, Width, Height - 1);
  if (Length(FItems) = 0) and (FEmptyText <> '') then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := clPgnMuted;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(S(10), (Height - Canvas.TextHeight(FEmptyText)) div 2, FEmptyText);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  for I := 0 to High(FItems) do
  begin
    R := FRects[I];
    if I = FActive then
    begin
      Back := clPgnWork;
    end
    else if I = FHot then
    begin
      Back := clPgnHover;
    end
    else if FTabLook then
    begin
      Back := Mix(clPgnLines, clPgnSurface, 45);
    end
    else
    begin
      Back := clPgnSurface;
    end;
    Canvas.Brush.Color := Back;
    if I = FActive then
    begin
      Canvas.Pen.Color := clPgnAccent;
    end
    else
    begin
      Canvas.Pen.Color := Mix(clPgnLines, clPgnText, 75);
    end;
    if FTabLook then
    begin
      Canvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom + 1);
      if I = FActive then
      begin
        // the selected tab is open to what's below it, with a firm top edge
        Canvas.Pen.Color := Back;
        Canvas.Line(R.Left + 1, R.Bottom - 1, R.Right - 1, R.Bottom - 1);
        Canvas.Pen.Color := clPgnAccent;
        Canvas.Pen.Width := S(2);
        Canvas.Line(R.Left + 1, R.Top + 1, R.Right - 1, R.Top + 1);
        Canvas.Pen.Width := 1;
      end;
    end
    else
    begin
      Canvas.Rectangle(R);
      if I = FActive then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Rectangle(R.Left + 1, R.Top + 1, R.Right - 1, R.Bottom - 1);
        Canvas.Brush.Style := bsSolid;
      end;
    end;
    X := R.Left + S(10);
    if FItems[I].Env <> enNone then
    begin
      Look := EnvironmentLook(FItems[I].Env);
      EnvTag := EnvironmentShort[FItems[I].Env];
      Canvas.Font.Assign(Font);
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Size := Max(7, Font.Size - 2);
      TH := Canvas.TextHeight(EnvTag);
      TagR := Rect(X, (R.Top + R.Bottom - TH) div 2 - S(1), X + Canvas.TextWidth(EnvTag) + S(8),
        (R.Top + R.Bottom + TH) div 2 + S(1));
      Canvas.Brush.Color := Look.Back;
      Canvas.Pen.Color := Look.Border;
      Canvas.Rectangle(TagR);
      Canvas.Font.Color := Look.Text;
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(TagR.Left + S(4), TagR.Top + S(1), EnvTag);
      Canvas.Brush.Style := bsSolid;
      X := TagR.Right + S(6);
    end;
    Canvas.Font.Assign(Font);
    if I = FActive then
    begin
      Canvas.Font.Style := [fsBold];
    end;
    Canvas.Font.Color := clPgnText;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(X, (R.Top + R.Bottom - Canvas.TextHeight(FItems[I].Caption)) div 2, FItems[I].Caption);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TpgnStripBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  H: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  H := ItemAt(X, Y);
  if H <> FHot then
  begin
    FHot := H;
    Invalidate;
  end;
end;

procedure TpgnStripBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
  begin
    Exit;
  end;
  I := ItemAt(X, Y);
  if (I >= 0) and Assigned(FOnItemClick) then
  begin
    FOnItemClick(Self, I);
  end;
end;

procedure TpgnStripBar.MouseLeave;
begin
  inherited MouseLeave;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

{ ======================================================= schema browser }

constructor TpgnSchemaBrowser.Create(AOwner: TComponent);
var
  Split: TSplitter;
  Right: TPanel;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FConnIndex := -1;
  FAll := TStringList.Create;
  FShown := TStringList.Create;
  FTypeIndex := 0;

  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self;
  FLeft.Align := alLeft;
  FLeft.Width := S(360);
  FLeft.BevelOuter := bvNone;
  FLeft.Caption := '';

  FTop := TPanel.Create(Self);
  FTop.Parent := FLeft;
  FTop.Align := alTop;
  FTop.Height := S(36);
  FTop.BevelOuter := bvNone;
  FTop.Caption := '';
  FTop.Color := clPgnBar;
  FTop.ParentColor := False;
  FTop.OnResize := @LayoutTop;

  FDbLabel := TLabel.Create(Self);
  FDbLabel.Parent := FTop;
  FDbLabel.Caption := 'Database';
  FDbCombo := TComboBox.Create(Self);
  FDbCombo.Parent := FTop;
  FDbCombo.Style := csDropDownList;
  FDbCombo.AutoSize := False;
  FDbCombo.OnChange := @DbChange;
  FSchemaLabel := TLabel.Create(Self);
  FSchemaLabel.Parent := FTop;
  FSchemaLabel.Caption := 'Schema';
  FSchemaCombo := TComboBox.Create(Self);
  FSchemaCombo.Parent := FTop;
  FSchemaCombo.Style := csDropDownList;
  FSchemaCombo.AutoSize := False;
  FSchemaCombo.OnChange := @SchemaChange;
  FRefresh := TButton.Create(Self);
  FRefresh.Parent := FTop;
  FRefresh.Caption := 'Refresh';
  FRefresh.OnClick := @RefreshClick;

  FTypePanel := TPanel.Create(Self);
  FTypePanel.Parent := FLeft;
  FTypePanel.Align := alTop;
  FTypePanel.Top := FTop.Top + FTop.Height + 1;
  FTypePanel.Height := S(60);
  FTypePanel.BevelOuter := bvNone;
  FTypePanel.Caption := '';
  FTypePanel.OnResize := @LayoutTypes;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FLeft;
  FFilter.Align := alTop;
  FFilter.Top := FTypePanel.Top + FTypePanel.Height + 1;
  FFilter.TextHint := 'Filter, e.g. SPR% (starts with SPR) or HOLD (contains HOLD)';
  FFilter.BorderSpacing.Around := S(4);
  FFilter.OnChange := @FilterChange;

  FCount := TLabel.Create(Self);
  FCount.Parent := FLeft;
  FCount.AutoSize := False;
  FCount.Align := alBottom;
  FCount.Height := S(22);
  FCount.Layout := tlCenter;
  FCount.BorderSpacing.Left := S(6);
  FCount.Font.Color := clPgnMuted;
  FCount.Caption := '';

  FList := TpgnResultGrid.Create(Self);
  FList.Parent := FLeft;
  FList.Align := alClient;
  FList.Options := FList.Options + [goRowSelect];
  FList.OnSelection := @ListSelect;
  FList.OnDblClick := @ListDblClick;
  FList.OnMouseUp := @ListMouseUp;
  FList.OnKeyDown := @ListKeyDown;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alLeft;
  Split.Left := FLeft.Left + FLeft.Width + 1;

  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alClient;
  Right.BevelOuter := bvNone;
  Right.Caption := '';

  FHeader := TLabel.Create(Self);
  FHeader.Parent := Right;
  FHeader.AutoSize := False;
  FHeader.Align := alTop;
  FHeader.Height := S(30);
  FHeader.Layout := tlCenter;
  FHeader.BorderSpacing.Left := S(8);
  FHeader.Font.Style := [fsBold];
  FHeader.Caption := 'Pick an object on the left';

  FDetailsHost := TPanel.Create(Self);
  FDetailsHost.Parent := Right;
  FDetailsHost.Align := alClient;
  FDetailsHost.BevelOuter := bvNone;
  FDetailsHost.Caption := '';

  FSelectTimer := TTimer.Create(Self);
  FSelectTimer.Enabled := False;
  FSelectTimer.Interval := 250;
  FSelectTimer.OnTimer := @SelectTimerTick;
end;

destructor TpgnSchemaBrowser.Destroy;
begin
  FAll.Free;
  FShown.Free;
  inherited Destroy;
end;

function TpgnSchemaBrowser.S(AValue: Integer): Integer;
begin
  Result := Scale96ToScreen(AValue);
end;

function TpgnSchemaBrowser.Adapter(const ADatabase: string): TpgnAdapter;
begin
  Result := nil;
  if Assigned(FOnAdapter) and (FConnIndex >= 0) then
  begin
    Result := FOnAdapter(FConnIndex, ADatabase);
  end;
end;

function TpgnSchemaBrowser.Database: string;
begin
  Result := '';
  if FDbCombo.ItemIndex >= 0 then
  begin
    Result := FDbCombo.Items[FDbCombo.ItemIndex];
  end;
end;

function TpgnSchemaBrowser.Schema: string;
begin
  Result := '';
  if (FRoot <> nil) and FRoot.HasSchemas and (FSchemaCombo.ItemIndex >= 0) then
  begin
    Result := FSchemaCombo.Items[FSchemaCombo.ItemIndex];
  end;
end;

function TpgnSchemaBrowser.Container: string;
begin
  Result := Schema;
  if Result = '' then
  begin
    Result := Database;
  end;
end;

{ Database and schema pickers, one row each; the database one only when
  there's a choice (one database per Oracle connection). }
procedure TpgnSchemaBrowser.LayoutTop(Sender: TObject);
var
  X, CH, Y, W, LW, RowH: Integer;
  ShowDb, ShowSchema: Boolean;
begin
  // one row per picker, each label in a column of its own width
  CH := FDbCombo.Height;
  ShowSchema := (FRoot <> nil) and FRoot.HasSchemas;
  ShowDb := (not ShowSchema) or (FDbCombo.Items.Count > 1);
  LW := Max(FDbLabel.Width, FSchemaLabel.Width);
  RowH := CH + S(6);
  X := S(6) + LW + S(8);
  W := Max(FTop.ClientWidth - X - FRefresh.Width - S(14), S(80));
  Y := S(4);
  if ShowDb then
  begin
    FDbLabel.SetBounds(S(6), Y + (CH - FDbLabel.Height) div 2, FDbLabel.Width, FDbLabel.Height);
    FDbCombo.SetBounds(X, Y, W, CH);
    Y := Y + RowH;
  end
  else
  begin
    FDbLabel.SetBounds(-2000, 0, FDbLabel.Width, FDbLabel.Height);
    FDbCombo.SetBounds(-2000, 0, W, CH);
  end;
  if ShowSchema then
  begin
    FSchemaLabel.SetBounds(S(6), Y + (CH - FSchemaLabel.Height) div 2, FSchemaLabel.Width,
      FSchemaLabel.Height);
    FSchemaCombo.SetBounds(X, Y, W, CH);
    Y := Y + RowH;
  end
  else
  begin
    FSchemaLabel.SetBounds(-2000, 0, FSchemaLabel.Width, FSchemaLabel.Height);
    FSchemaCombo.SetBounds(-2000, 0, W, CH);
  end;
  FRefresh.SetBounds(FTop.ClientWidth - FRefresh.Width - S(6), S(4), FRefresh.Width, CH);
  if FTop.Height <> Y + S(2) then
  begin
    FTop.Height := Y + S(2);
  end;
end;

{ The type buttons wrap onto as many rows as they need. }
procedure TpgnSchemaBrowser.LayoutTypes(Sender: TObject);
var
  I, X, Y, W, H, Gap, Want: Integer;
  C: TCanvas;
  B: TSpeedButton;
begin
  if Length(FTypeButtons) = 0 then
  begin
    Exit;
  end;
  C := FTypeButtons[0].Canvas;
  Gap := S(3);
  H := S(24);
  X := S(4);
  Y := S(4);
  for I := 0 to Length(FTypeButtons) do
  begin
    if I < Length(FTypeButtons) then
    begin
      B := FTypeButtons[I];
    end
    else
    begin
      B := FMoreButton;
    end;
    if B = nil then
    begin
      Continue;
    end;
    C.Font.Assign(B.Font);
    C.Font.Style := [fsBold];
    W := C.TextWidth(B.Caption) + S(16);
    if (X + W > FTypePanel.ClientWidth - S(4)) and (X > S(4)) then
    begin
      X := S(4);
      Y := Y + H + Gap;
    end;
    B.SetBounds(X, Y, W, H);
    X := X + W + Gap;
  end;
  Want := Y + H + S(4);
  if FTypePanel.Height <> Want then
  begin
    FTypePanel.Height := Want;
  end;
end;

procedure TpgnSchemaBrowser.BuildTypes;
var
  I: Integer;
  B: TSpeedButton;
  Item: TMenuItem;
  Extra: TpgnStringArray;

  procedure AddType(const ACaption, AKind, AFolder: string; ALevel: TpgnFolderLevel; ARare: Boolean);
  var
    N: Integer;
  begin
    N := Length(FTypes);
    SetLength(FTypes, N + 1);
    FTypes[N].Caption := ACaption;
    FTypes[N].Kind := AKind;
    FTypes[N].Folder := AFolder;
    FTypes[N].Level := ALevel;
    FTypes[N].Rare := ARare;
  end;

  procedure AddExtra(ALevel: TpgnFolderLevel; ARare: Boolean);
  var
    J: Integer;
  begin
    Extra := FRoot.ExtraFolders(ALevel, ARare);
    for J := 0 to High(Extra) do
    begin
      AddType(Extra[J], 'Other', Extra[J], ALevel, ARare);
    end;
  end;

begin
  for I := 0 to High(FTypeButtons) do
  begin
    FTypeButtons[I].Free;
  end;
  SetLength(FTypeButtons, 0);
  FreeAndNil(FMoreButton);
  if FMoreMenu <> nil then
  begin
    FMoreMenu.Items.Clear;
  end;
  SetLength(FTypes, 0);
  if FRoot = nil then
  begin
    Exit;
  end;
  AddType('Tables', 'Table', '', flSchema, False);
  AddType('Views', 'View', '', flSchema, False);
  if FRoot.HasSchemas then
  begin
    AddType('Mat. Views', 'Materialized View', '', flSchema, False);
  end;
  AddType('Procedures', 'Procedure', '', flSchema, False);
  AddType('Functions', 'Function', '', flSchema, False);
  if FRoot.Dialect = sdPostgreSQL then
  begin
    AddType('Trigger Functions', 'Trigger Function', '', flSchema, False);
  end
  else
  begin
    AddType('Triggers', 'Trigger', '', flSchema, False);
  end;
  AddExtra(flSchema, False);
  if FRoot.HasSchemas then
  begin
    AddExtra(flDatabase, False);
  end;
  AddExtra(flServer, False);
  AddExtra(flSchema, True);
  if FRoot.HasSchemas then
  begin
    AddExtra(flDatabase, True);
  end;
  AddExtra(flServer, True);
  if FTypeIndex > High(FTypes) then
  begin
    FTypeIndex := 0;
  end;
  for I := 0 to High(FTypes) do
  begin
    if FTypes[I].Rare then
    begin
      // the rarely used ones wait in a menu behind "More"
      if FMoreMenu = nil then
      begin
        FMoreMenu := TPopupMenu.Create(Self);
      end;
      Item := TMenuItem.Create(FMoreMenu);
      Item.Caption := FTypes[I].Caption;
      Item.Tag := I;
      Item.OnClick := @MoreItemClick;
      FMoreMenu.Items.Add(Item);
      if FMoreButton = nil then
      begin
        FMoreButton := TSpeedButton.Create(Self);
        FMoreButton.Parent := FTypePanel;
        FMoreButton.GroupIndex := 1;
        FMoreButton.AllowAllUp := False;
        FMoreButton.OnClick := @MoreClick;
        FMoreButton.Caption := 'More...';
      end;
      Continue;
    end;
    B := TSpeedButton.Create(Self);
    B.Parent := FTypePanel;
    B.Caption := FTypes[I].Caption;
    B.GroupIndex := 1;
    B.AllowAllUp := False;
    B.Tag := I;
    B.OnClick := @TypeClick;
    SetLength(FTypeButtons, Length(FTypeButtons) + 1);
    FTypeButtons[High(FTypeButtons)] := B;
  end;
  PickType(FTypeIndex);
end;

{ Marks the type in view: its button down and bold (a More type shows its
  name on the More button). }
procedure TpgnSchemaBrowser.PickType(AIndex: Integer);
var
  I: Integer;
begin
  FTypeIndex := AIndex;
  for I := 0 to High(FTypeButtons) do
  begin
    FTypeButtons[I].Down := FTypeButtons[I].Tag = AIndex;
    if FTypeButtons[I].Down then
    begin
      FTypeButtons[I].Font.Style := [fsBold];
    end
    else
    begin
      FTypeButtons[I].Font.Style := [];
    end;
  end;
  if FMoreButton <> nil then
  begin
    if (AIndex <= High(FTypes)) and FTypes[AIndex].Rare then
    begin
      FMoreButton.Caption := 'More: ' + FTypes[AIndex].Caption;
      FMoreButton.Down := True;
      FMoreButton.Font.Style := [fsBold];
    end
    else
    begin
      FMoreButton.Caption := 'More...';
      FMoreButton.Down := False;
      FMoreButton.Font.Style := [];
    end;
  end;
  LayoutTypes(nil);
end;

procedure TpgnSchemaBrowser.MoreClick(Sender: TObject);
var
  P: TPoint;
begin
  // the button stays as it was until a type is picked from the menu
  PickType(FTypeIndex);
  P := FMoreButton.ClientToScreen(Point(0, FMoreButton.Height));
  FMoreMenu.PopUp(P.X, P.Y);
end;

procedure TpgnSchemaBrowser.MoreItemClick(Sender: TObject);
begin
  PickType((Sender as TMenuItem).Tag);
  LoadList;
end;

procedure TpgnSchemaBrowser.Attach(AConnIndex: Integer; const AInfo: TpgnConnectionInfo; ARoot: TpgnAdapter);
begin
  if (AConnIndex = FConnIndex) and (ARoot = FRoot) then
  begin
    Exit;
  end;
  FConnIndex := AConnIndex;
  FInfo := AInfo;
  FRoot := ARoot;
  FAll.Clear;
  FShown.Clear;
  FList.ShowData(nil);
  FHeader.Caption := 'Pick an object on the left';
  BuildTypes;
  FillDatabases;
  LayoutTop(nil);
  LoadList;
end;

procedure TpgnSchemaBrowser.Detach;
begin
  FConnIndex := -1;
  FRoot := nil;
  FAll.Clear;
  FShown.Clear;
  FList.ShowData(nil);
  FDbCombo.Items.Clear;
  FSchemaCombo.Items.Clear;
  BuildTypes;
  FCount.Caption := '';
  FHeader.Caption := 'Not connected';
end;

procedure TpgnSchemaBrowser.FillDatabases;
var
  Names: TpgnStringArray;
  I, Pick: Integer;
  Want: string;
begin
  FFilling := True;
  try
    FDbCombo.Items.Clear;
    if FRoot = nil then
    begin
      Exit;
    end;
    try
      Names := FRoot.ListDatabases;
    except
      on E: Exception do
      begin
        Names := nil;
        FHeader.Caption := 'Could not list the databases: ' + E.Message;
      end;
    end;
    Want := FRoot.CurrentDatabase;
    if Want = '' then
    begin
      Want := FInfo.DefaultDatabase;
    end;
    Pick := 0;
    for I := 0 to High(Names) do
    begin
      FDbCombo.Items.Add(Names[I]);
      if SameText(Names[I], Want) then
      begin
        Pick := I;
      end;
    end;
    if FDbCombo.Items.Count > 0 then
    begin
      FDbCombo.ItemIndex := Pick;
    end;
  finally
    FFilling := False;
  end;
  FillSchemas;
end;

procedure TpgnSchemaBrowser.FillSchemas;
var
  A: TpgnAdapter;
  Names: TpgnStringArray;
  I, Pick: Integer;
  Want: string;
begin
  FFilling := True;
  try
    FSchemaCombo.Items.Clear;
    if (FRoot = nil) or not FRoot.HasSchemas then
    begin
      Exit;
    end;
    A := Adapter(Database);
    if A = nil then
    begin
      Exit;
    end;
    try
      Names := A.ListSchemas(False);
    except
      on E: Exception do
      begin
        Names := nil;
        FHeader.Caption := 'Could not list the schemas: ' + E.Message;
      end;
    end;
    Want := A.CurrentSchema;
    Pick := 0;
    for I := 0 to High(Names) do
    begin
      FSchemaCombo.Items.Add(Names[I]);
      if SameText(Names[I], Want) then
      begin
        Pick := I;
      end;
    end;
    if FSchemaCombo.Items.Count > 0 then
    begin
      FSchemaCombo.ItemIndex := Pick;
    end;
  finally
    FFilling := False;
  end;
end;

procedure TpgnSchemaBrowser.LoadList;
var
  A: TpgnAdapter;
  Names: TpgnStringArray;
  T: TpgnBrowserType;
  C, Db: string;
  I: Integer;
begin
  FAll.Clear;
  if (FRoot = nil) or (FTypeIndex > High(FTypes)) then
  begin
    ApplyFilter;
    Exit;
  end;
  T := FTypes[FTypeIndex];
  Db := Database;
  C := Container;
  if (T.Kind = 'Other') and (T.Level = flServer) then
  begin
    Db := '';
    C := '';
  end
  else if (T.Kind = 'Other') and (T.Level = flDatabase) then
  begin
    C := Db;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      A := Adapter(Db);
      if A = nil then
      begin
        Names := nil;
      end
      else if T.Kind = 'Table' then
      begin
        Names := A.ListObjects(C, okTable);
      end
      else if T.Kind = 'View' then
      begin
        Names := A.ListObjects(C, okView);
      end
      else if T.Kind = 'Materialized View' then
      begin
        Names := A.ListObjects(C, okMatView);
      end
      else if T.Kind = 'Procedure' then
      begin
        Names := A.ListRoutines(C, rkProcedure);
      end
      else if T.Kind = 'Function' then
      begin
        Names := A.ListRoutines(C, rkFunction);
      end
      else if T.Kind = 'Trigger' then
      begin
        Names := A.ListRoutines(C, rkTrigger);
      end
      else if T.Kind = 'Trigger Function' then
      begin
        Names := A.ListFolder(C, 'Trigger Functions');
      end
      else
      begin
        Names := A.ListFolder(C, T.Folder);
      end;
      for I := 0 to High(Names) do
      begin
        FAll.Add(Names[I]);
      end;
    except
      on E: Exception do
      begin
        FHeader.Caption := 'Could not list ' + LowerCase(T.Caption) + ': ' + E.Message;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  ApplyFilter;
end;

procedure TpgnSchemaBrowser.ApplyFilter;
var
  I: Integer;
  Word: string;
  R: TpgnResultSet;
begin
  FShown.Clear;
  for I := 0 to FAll.Count - 1 do
  begin
    if FilterMatches(FFilter.Text, FAll[I]) then
    begin
      FShown.Add(FAll[I]);
    end;
  end;
  Word := '';
  if FTypeIndex <= High(FTypes) then
  begin
    Word := FTypes[FTypeIndex].Caption + ': ';
  end;
  R := TpgnResultSet.Create;
  R.ReturnsRows := True;
  SetLength(R.Columns, 1);
  R.Columns[0] := 'Name';
  SetLength(R.Rows, FShown.Count);
  for I := 0 to FShown.Count - 1 do
  begin
    SetLength(R.Rows[I].Values, 1);
    SetLength(R.Rows[I].Nulls, 1);
    R.Rows[I].Values[0] := FShown[I];
  end;
  FList.ShowData(R);   // the grid keeps it
  // one column, as wide as the list
  if FList.ColCount > 1 then
  begin
    FList.ColWidths[FList.ColCount - 1] := Max(FList.ColWidths[FList.ColCount - 1],
      FList.ClientWidth - FList.ColWidths[0] - S(4));
  end;
  if Trim(FFilter.Text) = '' then
  begin
    FCount.Caption := Word + FormatFloat('#,##0', FAll.Count);
  end
  else
  begin
    FCount.Caption := Word + FormatFloat('#,##0', FAll.Count) + ' ' + #$C2#$B7 + ' ' +
      FormatFloat('#,##0', FShown.Count) + ' shown';
  end;
end;

function TpgnSchemaBrowser.ListIndex: Integer;
begin
  Result := FList.Row - 1;
  if (Result < 0) or (Result >= FShown.Count) then
  begin
    Result := -1;
  end;
end;

function TpgnSchemaBrowser.RefOf(AIndex: Integer): TpgnObjectRef;
var
  T: TpgnBrowserType;
begin
  Result.Database := Database;
  Result.Schema := Schema;
  Result.Name := FShown[AIndex];
  T := FTypes[FTypeIndex];
  if T.Kind = 'Other' then
  begin
    Result.Kind := 'Other:' + T.Folder;
    if T.Level = flServer then
    begin
      Result.Database := '';
      Result.Schema := '';
    end
    else if T.Level = flDatabase then
    begin
      Result.Schema := '';
    end;
  end
  else
  begin
    Result.Kind := T.Kind;
  end;
end;

procedure TpgnSchemaBrowser.ShowObject(const ARef: TpgnObjectRef);
var
  I, T: Integer;
begin
  if FRoot = nil then
  begin
    Exit;
  end;
  I := FDbCombo.Items.IndexOf(ARef.Database);
  if (ARef.Database <> '') and (I >= 0) and (I <> FDbCombo.ItemIndex) then
  begin
    FFilling := True;
    try
      FDbCombo.ItemIndex := I;
    finally
      FFilling := False;
    end;
    FillSchemas;
    LayoutTop(nil);
  end;
  if (ARef.Schema <> '') and FRoot.HasSchemas then
  begin
    I := FSchemaCombo.Items.IndexOf(ARef.Schema);
    if I < 0 then
    begin
      I := FSchemaCombo.Items.Add(ARef.Schema);   // a schema the list leaves out
    end;
    FFilling := True;
    try
      FSchemaCombo.ItemIndex := I;
    finally
      FFilling := False;
    end;
  end;
  T := -1;
  for I := 0 to High(FTypes) do
  begin
    if SameText(FTypes[I].Kind, ARef.Kind) then
    begin
      T := I;
      Break;
    end;
  end;
  if T >= 0 then
  begin
    PickType(T);
  end;
  FFilling := True;
  try
    FFilter.Text := '';
  finally
    FFilling := False;
  end;
  LoadList;
  I := FShown.IndexOf(ARef.Name);
  if I >= 0 then
  begin
    FList.Row := I + 1;
    if FList.CanFocus then
    begin
      FList.SetFocus;
    end;
  end;
end;

procedure TpgnSchemaBrowser.DbChange(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  FillSchemas;
  LayoutTop(nil);
  LoadList;
end;

procedure TpgnSchemaBrowser.SchemaChange(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  LoadList;
end;

procedure TpgnSchemaBrowser.TypeClick(Sender: TObject);
begin
  PickType((Sender as TSpeedButton).Tag);
  LoadList;
end;

procedure TpgnSchemaBrowser.FilterChange(Sender: TObject);
begin
  ApplyFilter;
end;

procedure TpgnSchemaBrowser.ListSelect(Sender: TObject; aCol, aRow: Integer);
begin
  FSelectTimer.Enabled := False;
  FSelectTimer.Enabled := True;
end;

procedure TpgnSchemaBrowser.SelectTimerTick(Sender: TObject);
var
  R: TpgnObjectRef;
  Where, Word: string;
begin
  FSelectTimer.Enabled := False;
  if ListIndex < 0 then
  begin
    Exit;
  end;
  R := RefOf(ListIndex);
  Where := R.Schema;
  if Where = '' then
  begin
    Where := R.Database;
  end;
  if FTypes[FTypeIndex].Kind = 'Other' then
  begin
    Word := FTypes[FTypeIndex].Caption;
  end
  else
  begin
    Word := LowerCase(FTypes[FTypeIndex].Kind);
  end;
  if Where <> '' then
  begin
    FHeader.Caption := Where + '.' + R.Name + '   (' + Word + ')';
  end
  else
  begin
    FHeader.Caption := R.Name + '   (' + Word + ')';
  end;
  if Assigned(FOnSelect) then
  begin
    FOnSelect(Self, FConnIndex, R);
  end;
end;

procedure TpgnSchemaBrowser.ListDblClick(Sender: TObject);
begin
  if (ListIndex >= 0) and Assigned(FOnOpen) then
  begin
    FOnOpen(Self, FConnIndex, RefOf(ListIndex));
  end;
end;

procedure TpgnSchemaBrowser.ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  C, R: Integer;
begin
  if Button <> mbRight then
  begin
    Exit;
  end;
  FList.MouseToCell(X, Y, C, R);
  if (R < 1) or (R > FShown.Count) then
  begin
    Exit;
  end;
  FList.Row := R;
  if Assigned(FOnMenu) then
  begin
    FOnMenu(Self, FConnIndex, RefOf(R - 1), FList.ClientToScreen(Point(X, Y)));
  end;
end;

procedure TpgnSchemaBrowser.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ListIndex >= 0) then
  begin
    ListDblClick(nil);
    Key := 0;
  end;
end;

procedure TpgnSchemaBrowser.RefreshClick(Sender: TObject);
begin
  Reload;
end;

procedure TpgnSchemaBrowser.Reload;
begin
  LoadList;
end;

end.
