// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnSettings;

{ Application settings, stored as JSON in the per-user config folder:
    Windows: %LOCALAPPDATA%\Pagona\settings.json
    Linux:   ~/.config/Pagona/settings.json }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, pgnKeymap, pgnTheme, pgnSqlFormat;

type
  TpgnSettings = class
  public
    Keymap: string;                 // a keymap name, or "Match layout"
    Layout: string;                 // Plume, Amphibian or Seattle
    RowLimit: Integer;              // 0 = no limit
    ConfirmDestructive: Boolean;    // ask before DELETE, TRUNCATE, DROP
    WarnDdlCommit: Boolean;         // Oracle, MySQL: ask before DDL commits pending changes
    Theme: string;                  // editor colors: Plume or Classic
    Look: string;                   // the frame's colors: Match layout, Plume, Amphibian or Seattle
    LogEveryStatement: Boolean;     // long scripts too (otherwise only problems + summary)
    AutoCommitNewTabs: Boolean;     // a tab starts with auto-commit on (default off, as Toad)
    PgErrorRollback: string;        // PostgreSQL, on error roll back the statement: off / interactive / on (psql's ON_ERROR_ROLLBACK)
    CodeCompletion: Boolean;        // the list of columns after a dot, and Complete Code
    AutoCommitSeattle: Boolean;     // Seattle's own: on by default, as SSMS
    DBAMode: Boolean;               // the Explorer shows a DBA's folders too
    EditorFontSize: Integer;        // the SQL editors' text size (zoom), in points
    ReopenTabs: Boolean;            // open last session's tabs again at start
    RecentFiles: TStringList;       // File > Recent Files, newest first
    FormatOpt: TpgnFormatOptions;   // 0.2.0's single format (read once, to become a profile)
    HadFormatOpt: Boolean;          // the settings file had that entry
    FormatProfile: string;          // the profile Format SQL uses: default, local:Name, shared:Name
    SharedFormatFolder: string;     // a team's shared profiles ('' = none)
    { Toolbar buttons per layout, as "Layout=id,id,|,id" (| = separator).
      A layout with no entry uses its default buttons. }
    Toolbars: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function FileName: string;
  end;

const
  DefaultEditorFontSize = 10;
  MinEditorFontSize = 6;
  MaxEditorFontSize = 36;
  MaxRecentFiles = 10;

{ Puts a file at the top of the recent list (once), keeping the newest ten. }
procedure AddRecentFile(AList: TStrings; const AFileName: string);

function PagonaConfigDir: string;
function ReadTextFile(const AFileName: string): string;
procedure WriteTextFile(const AFileName, AText: string);

implementation

procedure AddRecentFile(AList: TStrings; const AFileName: string);
var
  I: Integer;
begin
  if AFileName = '' then
  begin
    Exit;
  end;
  for I := AList.Count - 1 downto 0 do
  begin
    {$IFDEF WINDOWS}
    if SameText(AList[I], AFileName) then
    {$ELSE}
    if AList[I] = AFileName then
    {$ENDIF}
    begin
      AList.Delete(I);
    end;
  end;
  AList.Insert(0, AFileName);
  while AList.Count > MaxRecentFiles do
  begin
    AList.Delete(AList.Count - 1);
  end;
end;

function PagonaConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
end;

function ReadTextFile(const AFileName: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(AFileName);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure WriteTextFile(const AFileName, AText: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  L := TStringList.Create;
  try
    L.Text := AText;
    L.SaveToFile(AFileName);
  finally
    L.Free;
  end;
end;

constructor TpgnSettings.Create;
begin
  inherited Create;
  Keymap := KeymapMatchLayout;
  Layout := LayoutPlume;
  RowLimit := 1000;
  ConfirmDestructive := True;
  WarnDdlCommit := True;
  Theme := ThemePlume;
  LogEveryStatement := False;
  AutoCommitNewTabs := False;
  PgErrorRollback := 'off';
  CodeCompletion := True;
  AutoCommitSeattle := True;
  Look := 'Match layout';
  DBAMode := False;
  EditorFontSize := DefaultEditorFontSize;
  ReopenTabs := True;
  FormatOpt := DefaultFormatOptions;
  HadFormatOpt := False;
  FormatProfile := 'default';
  SharedFormatFolder := '';
  Toolbars := TStringList.Create;
  RecentFiles := TStringList.Create;
end;

destructor TpgnSettings.Destroy;
begin
  Toolbars.Free;
  RecentFiles.Free;
  inherited Destroy;
end;

function TpgnSettings.FileName: string;
begin
  Result := PagonaConfigDir + 'settings.json';
end;

procedure TpgnSettings.Load;
var
  Data: TJSONData;
  O, T, FO: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  if not FileExists(FileName) then
  begin
    Exit;
  end;
  try
    Data := GetJSON(ReadTextFile(FileName));
    try
      if Data is TJSONObject then
      begin
        O := TJSONObject(Data);
        Keymap := NormalizeKeymapSetting(O.Get('keymap', Keymap));
        Layout := O.Get('layout', Layout);
        RowLimit := O.Get('rowLimit', RowLimit);
        ConfirmDestructive := O.Get('confirmDestructive', ConfirmDestructive);
        WarnDdlCommit := O.Get('warnDdlCommit', WarnDdlCommit);
        Theme := NormalizeThemeName(O.Get('theme', Theme));
        LogEveryStatement := O.Get('logEveryStatement', LogEveryStatement);
        AutoCommitNewTabs := O.Get('autoCommitNewTabs', AutoCommitNewTabs);
        PgErrorRollback := LowerCase(O.Get('pgErrorRollback', PgErrorRollback));
        if (PgErrorRollback <> 'off') and (PgErrorRollback <> 'interactive') and (PgErrorRollback <> 'on') then
        begin
          PgErrorRollback := 'off';
        end;
        CodeCompletion := O.Get('codeCompletion', CodeCompletion);
        AutoCommitSeattle := O.Get('autoCommitSeattle', AutoCommitSeattle);
        Look := O.Get('look', Look);
        DBAMode := O.Get('dbaMode', DBAMode);
        EditorFontSize := O.Get('editorFontSize', EditorFontSize);
        if (EditorFontSize < MinEditorFontSize) or (EditorFontSize > MaxEditorFontSize) then
        begin
          EditorFontSize := DefaultEditorFontSize;
        end;
        ReopenTabs := O.Get('reopenTabs', ReopenTabs);
        RecentFiles.Clear;
        if O.Find('recentFiles') is TJSONArray then
        begin
          A := TJSONArray(O.Find('recentFiles'));
          for I := 0 to A.Count - 1 do
          begin
            if (A.Items[I] is TJSONString) and (RecentFiles.Count < MaxRecentFiles) then
            begin
              RecentFiles.Add(A.Items[I].AsString);
            end;
          end;
        end;
        FormatProfile := O.Get('formatProfile', FormatProfile);
        SharedFormatFolder := O.Get('sharedFormatFolder', SharedFormatFolder);
        if O.Find('format') is TJSONObject then
        begin
          HadFormatOpt := True;
          FO := TJSONObject(O.Find('format'));
          case FO.Get('keywordCase', 'upper') of
            'lower':
              begin
                FormatOpt.KeywordCase := kcLower;
              end;
            'asTyped':
              begin
                FormatOpt.KeywordCase := kcAsTyped;
              end;
          else
            begin
              FormatOpt.KeywordCase := kcUpper;
            end;
          end;
          FormatOpt.IndentSize := EnsureRange(FO.Get('indent', FormatOpt.IndentSize), 1, 8);
          FormatOpt.UseTabs := FO.Get('tabs', FormatOpt.UseTabs);
          FormatOpt.LeadingCommas := FO.Get('leadingCommas', FormatOpt.LeadingCommas);
          FormatOpt.OneColumnPerLine := FO.Get('oneColumnPerLine', FormatOpt.OneColumnPerLine);
          FormatOpt.LineWidth := EnsureRange(FO.Get('lineWidth', FormatOpt.LineWidth), 40, 400);
          FormatOpt.AndOrNewLine := FO.Get('andOrNewLine', FormatOpt.AndOrNewLine);
          FormatOpt.JoinIndented := FO.Get('joinIndented', FormatOpt.JoinIndented);
          FormatOpt.River := FO.Get('river', FormatOpt.River);
          FormatOpt.BlankLineBetween := FO.Get('blankLineBetween', FormatOpt.BlankLineBetween);
        end;
        Toolbars.Clear;
        if O.Find('toolbars') is TJSONObject then
        begin
          T := TJSONObject(O.Find('toolbars'));
          for I := 0 to T.Count - 1 do
          begin
            Toolbars.Values[T.Names[I]] := T.Items[I].AsString;
          end;
        end;
      end;
    finally
      Data.Free;
    end;
  except
    on E: Exception do
    begin
      // A damaged settings file should never stop Pagona from starting.
    end;
  end;
end;

procedure TpgnSettings.Save;
var
  O, T: TJSONObject;
  A: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  try
    O.Add('keymap', Keymap);
    O.Add('layout', Layout);
    O.Add('rowLimit', RowLimit);
    O.Add('confirmDestructive', ConfirmDestructive);
    O.Add('warnDdlCommit', WarnDdlCommit);
    O.Add('theme', Theme);
    O.Add('logEveryStatement', LogEveryStatement);
    O.Add('autoCommitNewTabs', AutoCommitNewTabs);
    O.Add('pgErrorRollback', PgErrorRollback);
    O.Add('codeCompletion', CodeCompletion);
    O.Add('autoCommitSeattle', AutoCommitSeattle);
    O.Add('look', Look);
    O.Add('dbaMode', DBAMode);
    O.Add('editorFontSize', EditorFontSize);
    O.Add('reopenTabs', ReopenTabs);
    A := TJSONArray.Create;
    for I := 0 to RecentFiles.Count - 1 do
    begin
      A.Add(RecentFiles[I]);
    end;
    O.Add('recentFiles', A);
    O.Add('formatProfile', FormatProfile);
    O.Add('sharedFormatFolder', SharedFormatFolder);
    T := TJSONObject.Create;
    for I := 0 to Toolbars.Count - 1 do
    begin
      T.Add(Toolbars.Names[I], Toolbars.ValueFromIndex[I]);
    end;
    O.Add('toolbars', T);
    WriteTextFile(FileName, O.FormatJSON);
  finally
    O.Free;
  end;
end;

end.
