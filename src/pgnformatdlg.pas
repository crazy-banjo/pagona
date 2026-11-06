// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnFormatDlg;

{ The Format SQL window: a profile and its settings on the left, your own
  SQL (the selection or the whole editor) on the right, formatted as the
  settings change. Format (Enter) puts it in the editor; Cancel changes
  nothing. It opens on the profile used last.

  Profiles: Save, Save As..., Rename..., Delete (your own profiles only;
  a shared profile's file is never deleted by Pagona), Export... and
  Import... of .pagona-format files. Changing a setting without saving is
  fine: Format uses what's on screen, and the profile stays as it was. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs, Math, LCLType,
  SynEdit, SynHighlighterSQL, pgnTypes, pgnSqlFormat, pgnFormatProfiles, pgnSettings, pgnTheme;

{ Shows the window for ASource. True when Format was chosen: AResult is the
  formatted text and ASettings.FormatProfile the profile picked (saved). }
function ShowFormatWindow(AOwner: TComponent; ASettings: TpgnSettings; const ASource: string;
  ADialect: TpgnDialect; out AResult: string; out ALeftAlone: Integer): Boolean;

{ The profile Format uses without the window (Format with "..."). }
function CurrentFormatProfile(ASettings: TpgnSettings): TpgnFormatProfile;

{ A profile as the lists show it: "Pagona Default  (built in)", "Name  (shared)". }
function ProfileCaption(const P: TpgnFormatProfile): string;

implementation

type
  TFormatWindow = class(TForm)
  public
    Settings: TpgnSettings;
    Source: string;
    Dialect: TpgnDialect;
    Profiles: TpgnFormatProfiles;
    Cur: Integer;
    Filling: Boolean;
    CProfile: TComboBox;
    LWhere: TLabel;
    BSave, BSaveAs, BRename, BDelete, BExport, BImport, BFormat: TButton;
    CCase, CIndent, CCommas, CList: TComboBox;
    EWidth: TEdit;
    KAndOr, KJoin, KRiver, KBlank: TCheckBox;
    Preview: TSynEdit;
    Hl: TSynSQLSyn;
    LStatus: TLabel;
    procedure FillProfiles(const ASelectKey: string);
    procedure ShowOpts(const O: TpgnFormatOptions);
    function Read: TpgnFormatOptions;
    function CanWrite(const P: TpgnFormatProfile): Boolean;
    function SharedDir: string;
    procedure Changed(Sender: TObject);
    procedure ProfileChange(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
  end;

function SameOptions(const A, B: TpgnFormatOptions): Boolean;
begin
  Result := (A.KeywordCase = B.KeywordCase) and (A.IndentSize = B.IndentSize) and (A.UseTabs = B.UseTabs) and
    (A.LeadingCommas = B.LeadingCommas) and (A.OneColumnPerLine = B.OneColumnPerLine) and
    ((A.LineWidth = B.LineWidth) or A.OneColumnPerLine) and (A.AndOrNewLine = B.AndOrNewLine) and
    (A.JoinIndented = B.JoinIndented) and (A.River = B.River) and (A.BlankLineBetween = B.BlankLineBetween);
end;

function ProfileCaption(const P: TpgnFormatProfile): string;
begin
  case P.Source of
    psShared:
      begin
        Result := P.Name + '  (shared)';
      end;
    psBuiltIn:
      begin
        Result := P.Name + '  (built in)';
      end;
  else
    begin
      Result := P.Name;
    end;
  end;
end;

function CurrentFormatProfile(ASettings: TpgnSettings): TpgnFormatProfile;
begin
  Result := FindProfile(LoadFormatProfiles(ASettings.SharedFormatFolder), ASettings.FormatProfile);
end;

function TFormatWindow.SharedDir: string;
begin
  Result := Trim(Settings.SharedFormatFolder);
end;

function TFormatWindow.CanWrite(const P: TpgnFormatProfile): Boolean;
begin
  case P.Source of
    psLocal:
      begin
        Result := True;
      end;
    psShared:
      begin
        Result := FolderWritable(ExtractFileDir(P.FileName));
      end;
  else
    begin
      Result := False;
    end;
  end;
end;

procedure TFormatWindow.FillProfiles(const ASelectKey: string);
var
  I: Integer;
begin
  Profiles := LoadFormatProfiles(SharedDir);
  Filling := True;
  try
    CProfile.Items.Clear;
    for I := 0 to High(Profiles) do
    begin
      CProfile.Items.Add(ProfileCaption(Profiles[I]));
    end;
    Cur := ProfileIndex(Profiles, ASelectKey);
    CProfile.ItemIndex := Cur;
  finally
    Filling := False;
  end;
  ShowOpts(Profiles[Cur].Opt);
end;

procedure TFormatWindow.ShowOpts(const O: TpgnFormatOptions);
begin
  Filling := True;
  try
    CCase.ItemIndex := Ord(O.KeywordCase);
    if O.UseTabs then
    begin
      CIndent.ItemIndex := 2;
    end
    else if O.IndentSize <= 2 then
    begin
      CIndent.ItemIndex := 0;
    end
    else
    begin
      CIndent.ItemIndex := 1;
    end;
    if O.LeadingCommas then
    begin
      CCommas.ItemIndex := 1;
    end
    else
    begin
      CCommas.ItemIndex := 0;
    end;
    if O.OneColumnPerLine then
    begin
      CList.ItemIndex := 0;
    end
    else
    begin
      CList.ItemIndex := 1;
    end;
    EWidth.Text := IntToStr(O.LineWidth);
    KAndOr.Checked := O.AndOrNewLine;
    KJoin.Checked := O.JoinIndented;
    KRiver.Checked := O.River;
    KBlank.Checked := O.BlankLineBetween;
  finally
    Filling := False;
  end;
  Changed(nil);
end;

function TFormatWindow.Read: TpgnFormatOptions;
begin
  Result := DefaultFormatOptions;
  Result.KeywordCase := TpgnKeywordCase(Max(0, CCase.ItemIndex));
  case CIndent.ItemIndex of
    0:
      begin
        Result.IndentSize := 2;
        Result.UseTabs := False;
      end;
    2:
      begin
        Result.IndentSize := 4;
        Result.UseTabs := True;
      end;
  else
    begin
      Result.IndentSize := 4;
      Result.UseTabs := False;
    end;
  end;
  Result.LeadingCommas := CCommas.ItemIndex = 1;
  Result.OneColumnPerLine := CList.ItemIndex <> 1;
  Result.LineWidth := EnsureRange(StrToIntDef(Trim(EWidth.Text), 100), 40, 400);
  Result.AndOrNewLine := KAndOr.Checked;
  Result.JoinIndented := KJoin.Checked;
  Result.River := KRiver.Checked;
  Result.BlankLineBetween := KBlank.Checked;
end;

procedure TFormatWindow.Changed(Sender: TObject);
var
  N: Integer;
  P: TpgnFormatProfile;
  Dirty: Boolean;
  Msg: string;
begin
  if Filling then
  begin
    Exit;
  end;
  P := Profiles[Cur];
  EWidth.Enabled := CList.ItemIndex = 1;
  KJoin.Enabled := not KRiver.Checked;
  Preview.Text := FormatSql(Source, Dialect, Read, N);
  Dirty := not SameOptions(Read, P.Opt);
  BSave.Enabled := Dirty and CanWrite(P);
  BRename.Enabled := P.Source = psLocal;
  BDelete.Enabled := P.Source = psLocal;
  case P.Source of
    psShared:
      begin
        LWhere.Caption := 'Shared: ' + ExtractFileDir(P.FileName);
        if not CanWrite(P) then
        begin
          LWhere.Caption := LWhere.Caption + LineEnding + 'Read-only here: Save As makes your own copy.';
        end;
        BDelete.Hint := 'Shared profiles are removed from the shared folder by hand.';
      end;
    psBuiltIn:
      begin
        LWhere.Caption := 'Built in: always there, never changes. Save As makes your own.';
        BDelete.Hint := 'Pagona Default can''t be deleted.';
      end;
  else
    begin
      LWhere.Caption := 'Yours: ' + ExtractFileDir(P.FileName);
      BDelete.Hint := 'Deletes your own copy of this profile.';
    end;
  end;
  Msg := '';
  if Dirty then
  begin
    Msg := P.Name + ': changed, not saved. Format uses what''s on screen; the profile stays as it was ' +
      'unless you Save.';
    Caption := 'Format SQL: ' + P.Name + ' (changed)';
  end
  else
  begin
    Caption := 'Format SQL: ' + P.Name;
  end;
  if N > 0 then
  begin
    if Msg <> '' then
    begin
      Msg := Msg + LineEnding;
    end;
    Msg := Msg + IntToStr(N) + ' statement(s) will be left as written: formatting them would change more ' +
      'than the layout.';
  end;
  LStatus.Caption := Msg;
end;

procedure TFormatWindow.ProfileChange(Sender: TObject);
begin
  if Filling or (CProfile.ItemIndex < 0) then
  begin
    Exit;
  end;
  Cur := CProfile.ItemIndex;
  ShowOpts(Profiles[Cur].Opt);
end;

procedure TFormatWindow.SaveClick(Sender: TObject);
var
  P: TpgnFormatProfile;
begin
  P := Profiles[Cur];
  if not CanWrite(P) then
  begin
    Exit;
  end;
  if P.Source = psShared then
  begin
    if QuestionDlg('Replace a shared profile', 'Replace "' + P.Name + '" in' + LineEnding +
      ExtractFileDir(P.FileName) + LineEnding + 'for everyone who uses it?', mtWarning,
      [mrYes, 'Replace for Everyone', mrNo, 'Don''t Replace', 'IsDefault'], 0) <> mrYes then
    begin
      Exit;
    end;
  end;
  try
    WriteProfileFile(P.FileName, P.Name, Read);
  except
    on E: Exception do
    begin
      MessageDlg('Save', 'Could not save ' + P.FileName + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FillProfiles(ProfileKey(P));
end;

procedure TFormatWindow.SaveAsClick(Sender: TObject);
var
  PName, Dir, FileName, Key: string;
  Answer: TModalResult;
begin
  PName := '';
  if not InputQuery('Save As', 'A name for the profile (e.g. Registrar Reports):', PName) then
  begin
    Exit;
  end;
  PName := Trim(PName);
  if not ValidProfileName(PName) then
  begin
    MessageDlg('Save As', 'Give it a name of its own ("' + DefaultProfileName + '" is the built-in one).',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  Dir := LocalFormatsDir;
  Key := 'local:' + PName;
  // a writable shared folder: yours, or the team's
  if FolderWritable(SharedDir) then
  begin
    Answer := QuestionDlg('Save As', 'Save "' + PName + '" as your own profile, or in the shared folder ' +
      'for everyone?' + LineEnding + SharedDir, mtConfirmation,
      [mrYes, 'My Profiles', mrNo, 'Shared Folder', mrCancel, 'Cancel', 'IsDefault'], 0);
    if Answer = mrCancel then
    begin
      Exit;
    end;
    if Answer = mrNo then
    begin
      Dir := SharedDir;
      Key := 'shared:' + PName;
    end;
  end;
  FileName := ProfileFileName(Dir, PName);
  if FileExists(FileName) then
  begin
    if QuestionDlg('Save As', '"' + PName + '" is already there:' + LineEnding + FileName + LineEnding +
      'Replace it?', mtWarning, [mrYes, 'Replace', mrNo, 'Don''t Replace', 'IsDefault'], 0) <> mrYes then
    begin
      Exit;
    end;
  end;
  try
    WriteProfileFile(FileName, PName, Read);
  except
    on E: Exception do
    begin
      MessageDlg('Save As', 'Could not save ' + FileName + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FillProfiles(Key);
end;

procedure TFormatWindow.RenameClick(Sender: TObject);
var
  P: TpgnFormatProfile;
  PName, FileName: string;
begin
  P := Profiles[Cur];
  if P.Source <> psLocal then
  begin
    Exit;
  end;
  PName := P.Name;
  if not InputQuery('Rename', 'A new name for "' + P.Name + '":', PName) then
  begin
    Exit;
  end;
  PName := Trim(PName);
  if (PName = P.Name) or not ValidProfileName(PName) then
  begin
    Exit;
  end;
  FileName := ProfileFileName(LocalFormatsDir, PName);
  if FileExists(FileName) and not SameText(FileName, P.FileName) then
  begin
    MessageDlg('Rename', 'You already have a profile called "' + PName + '".', mtInformation, [mbOK], 0);
    Exit;
  end;
  try
    // the settings as saved (not unsaved changes on screen)
    WriteProfileFile(FileName, PName, P.Opt);
    if not SameText(FileName, P.FileName) then
    begin
      DeleteLocalProfile(P);
    end;
  except
    on E: Exception do
    begin
      MessageDlg('Rename', 'Could not rename:' + LineEnding + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if SameText(Settings.FormatProfile, ProfileKey(P)) then
  begin
    Settings.FormatProfile := 'local:' + PName;
  end;
  FillProfiles('local:' + PName);
end;

procedure TFormatWindow.DeleteClick(Sender: TObject);
var
  P: TpgnFormatProfile;
begin
  P := Profiles[Cur];
  // only your own, from Pagona's folder; shared files are removed by hand
  if P.Source <> psLocal then
  begin
    Exit;
  end;
  if QuestionDlg('Delete', 'Delete your profile "' + P.Name + '"?', mtConfirmation,
    [mrYes, 'Delete', mrNo, 'Keep It', 'IsDefault'], 0) <> mrYes then
  begin
    Exit;
  end;
  if not DeleteLocalProfile(P) then
  begin
    MessageDlg('Delete', 'Could not delete ' + P.FileName + '.', mtError, [mbOK], 0);
    Exit;
  end;
  if SameText(Settings.FormatProfile, ProfileKey(P)) then
  begin
    Settings.FormatProfile := DefaultProfileKey;
  end;
  FillProfiles(DefaultProfileKey);
end;

procedure TFormatWindow.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
  PName: string;
begin
  PName := Profiles[Cur].Name;
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Export Format Profile';
    D.Filter := 'Pagona format profiles (*' + FormatFileExt + ')|*' + FormatFileExt + '|All files|*';
    D.DefaultExt := Copy(FormatFileExt, 2, MaxInt);
    D.Options := D.Options + [ofOverwritePrompt];
    D.FileName := ExtractFileName(ProfileFileName('', PName));
    if not D.Execute then
    begin
      Exit;
    end;
    try
      // what's on screen, under the profile's name
      WriteProfileFile(D.FileName, PName, Read);
    except
      on E: Exception do
      begin
        MessageDlg('Export', 'Could not write ' + D.FileName + ':' + LineEnding + E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    D.Free;
  end;
end;

procedure TFormatWindow.ImportClick(Sender: TObject);
var
  D: TOpenDialog;
  PName, Err, FileName: string;
  Opt: TpgnFormatOptions;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Import Format Profile';
    D.Filter := 'Pagona format profiles (*' + FormatFileExt + ')|*' + FormatFileExt + '|All files|*';
    if not D.Execute then
    begin
      Exit;
    end;
    if not ReadProfileFile(D.FileName, PName, Opt, Err) then
    begin
      MessageDlg('Import', 'Could not import ' + D.FileName + ': ' + Err, mtError, [mbOK], 0);
      Exit;
    end;
    if not ValidProfileName(PName) then
    begin
      PName := PName + ' (imported)';
    end;
    FileName := ProfileFileName(LocalFormatsDir, PName);
    if FileExists(FileName) then
    begin
      if QuestionDlg('Import', 'You already have a profile called "' + PName + '". Replace it with the ' +
        'imported one?', mtWarning, [mrYes, 'Replace', mrNo, 'Don''t Replace', 'IsDefault'], 0) <> mrYes then
      begin
        Exit;
      end;
    end;
    WriteProfileFile(FileName, PName, Opt);
    FillProfiles('local:' + PName);
  finally
    D.Free;
  end;
end;

function ShowFormatWindow(AOwner: TComponent; ASettings: TpgnSettings; const ASource: string;
  ADialect: TpgnDialect; out AResult: string; out ALeftAlone: Integer): Boolean;
var
  F: TFormatWindow;
  Left, Bottom, Row: TPanel;
  Y, M, W, BW: Integer;
  B: TButton;
  L: TLabel;

  function AddLabel(const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(F);
    Result.Parent := Left;
    Result.Caption := ACaption;
    Result.SetBounds(M, Y, W, Result.Height);
    Inc(Y, F.Scale96ToScreen(18));
  end;

  function AddCombo(const ACaption: string; const AItems: array of string): TComboBox;
  var
    I: Integer;
  begin
    AddLabel(ACaption);
    Result := TComboBox.Create(F);
    Result.Parent := Left;
    Result.Style := csDropDownList;
    for I := Low(AItems) to High(AItems) do
    begin
      Result.Items.Add(AItems[I]);
    end;
    Result.SetBounds(M, Y, W, Result.Height);
    Result.Constraints.MinWidth := W;
    Result.OnChange := @F.Changed;
    Inc(Y, F.Scale96ToScreen(34));
  end;

  function AddCheck(const ACaption: string): TCheckBox;
  begin
    Result := TCheckBox.Create(F);
    Result.Parent := Left;
    Result.Caption := ACaption;
    Result.SetBounds(M, Y, W, Result.Height);
    Result.OnClick := @F.Changed;
    Inc(Y, F.Scale96ToScreen(26));
  end;

  function AddButton(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
    AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(F);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.SetBounds(AX, AY, AW, F.Scale96ToScreen(28));
    Result.OnClick := AClick;
    Result.ShowHint := True;
  end;

begin
  Result := False;
  AResult := ASource;
  ALeftAlone := 0;
  F := TFormatWindow.CreateNew(AOwner);
  try
    SmoothFont(F.Font);
    F.Settings := ASettings;
    F.Source := ASource;
    F.Dialect := ADialect;
    F.Position := poOwnerFormCenter;
    F.Width := F.Scale96ToScreen(1120);
    F.Height := F.Scale96ToScreen(720);
    F.Color := clPgnSurface;
    F.ShowHint := True;
    M := F.Scale96ToScreen(12);
    W := F.Scale96ToScreen(300);
    BW := (W - F.Scale96ToScreen(12)) div 4;

    Bottom := TPanel.Create(F);
    Bottom.Parent := F;
    Bottom.Align := alBottom;
    Bottom.BevelOuter := bvNone;
    Bottom.Caption := '';
    Bottom.Height := F.Scale96ToScreen(64);
    B := TButton.Create(F);
    B.Parent := Bottom;
    B.Caption := 'Cancel';
    B.ModalResult := mrCancel;
    B.Cancel := True;
    B.Anchors := [akTop, akRight];
    B.SetBounds(Bottom.ClientWidth - F.Scale96ToScreen(100) - M, F.Scale96ToScreen(18),
      F.Scale96ToScreen(100), F.Scale96ToScreen(28));
    F.BFormat := TButton.Create(F);
    F.BFormat.Parent := Bottom;
    F.BFormat.Caption := 'Format';
    F.BFormat.ModalResult := mrOK;
    F.BFormat.Default := True;
    F.BFormat.Anchors := [akTop, akRight];
    F.BFormat.SetBounds(B.Left - F.Scale96ToScreen(108), F.Scale96ToScreen(18), F.Scale96ToScreen(100),
      F.Scale96ToScreen(28));
    F.LStatus := TLabel.Create(F);
    F.LStatus.Parent := Bottom;
    F.LStatus.AutoSize := False;
    F.LStatus.WordWrap := True;
    F.LStatus.Anchors := [akLeft, akTop, akRight, akBottom];
    F.LStatus.SetBounds(M, F.Scale96ToScreen(6), F.BFormat.Left - 2 * M, Bottom.ClientHeight - F.Scale96ToScreen(10));

    Left := TPanel.Create(F);
    Left.Parent := F;
    Left.Align := alLeft;
    Left.Width := W + 2 * M;
    Left.BevelOuter := bvNone;
    Left.Caption := '';
    Y := M;
    L := AddLabel('Profile');
    L.Font.Style := [fsBold];
    F.CProfile := TComboBox.Create(F);
    F.CProfile.Parent := Left;
    F.CProfile.Style := csDropDownList;
    F.CProfile.DropDownCount := 20;
    F.CProfile.SetBounds(M, Y, W, F.CProfile.Height);
    F.CProfile.Constraints.MinWidth := W;
    F.CProfile.OnChange := @F.ProfileChange;
    Inc(Y, F.Scale96ToScreen(32));
    Row := Left;
    F.BSave := AddButton(Row, 'Save', M, Y, BW, @F.SaveClick);
    F.BSave.Hint := 'Saves the settings on screen into this profile';
    F.BSaveAs := AddButton(Row, 'Save As...', M + (BW + F.Scale96ToScreen(4)), Y, BW, @F.SaveAsClick);
    F.BSaveAs.Hint := 'A new profile with the settings on screen';
    F.BRename := AddButton(Row, 'Rename...', M + 2 * (BW + F.Scale96ToScreen(4)), Y, BW, @F.RenameClick);
    F.BRename.Hint := 'Renames one of your own profiles';
    F.BDelete := AddButton(Row, 'Delete', M + 3 * (BW + F.Scale96ToScreen(4)), Y, BW, @F.DeleteClick);
    Inc(Y, F.Scale96ToScreen(34));
    F.LWhere := TLabel.Create(F);
    F.LWhere.Parent := Left;
    F.LWhere.AutoSize := False;
    F.LWhere.WordWrap := True;
    F.LWhere.Font.Color := clPgnMuted;
    F.LWhere.SetBounds(M, Y, W, F.Scale96ToScreen(52));
    Inc(Y, F.Scale96ToScreen(58));

    F.CCase := AddCombo('Keyword case', ['UPPER', 'lower', 'As typed']);
    F.CIndent := AddCombo('Indent', ['2 spaces', '4 spaces', 'Tab']);
    F.CCommas := AddCombo('Commas in lists', ['At the end of the line', 'Leading (, col)']);
    F.CList := AddCombo('Select list', ['One column per line', 'Packed to the line width']);
    AddLabel('Line width (packed lists)');
    F.EWidth := TEdit.Create(F);
    F.EWidth.Parent := Left;
    F.EWidth.SetBounds(M, Y, F.Scale96ToScreen(80), F.EWidth.Height);
    F.EWidth.OnChange := @F.Changed;
    Inc(Y, F.Scale96ToScreen(38));
    F.KAndOr := AddCheck('AND / OR start new lines');
    F.KJoin := AddCheck('JOIN indented under FROM');
    F.KRiver := AddCheck('River style (SELECT, FROM, WHERE right-aligned)');
    F.KBlank := AddCheck('Blank line between statements');
    Inc(Y, F.Scale96ToScreen(8));
    F.BExport := AddButton(Left, 'Export...', M, Y, (W - F.Scale96ToScreen(4)) div 2, @F.ExportClick);
    F.BExport.Hint := 'Saves this profile as a file to share (what''s on screen, under its name)';
    F.BImport := AddButton(Left, 'Import...', M + (W - F.Scale96ToScreen(4)) div 2 + F.Scale96ToScreen(4), Y,
      (W - F.Scale96ToScreen(4)) div 2, @F.ImportClick);
    F.BImport.Hint := 'Adds a profile file someone shared to your own profiles';

    F.Hl := TSynSQLSyn.Create(F);
    case ADialect of
      sdOracle:
        begin
          F.Hl.SQLDialect := sqlOracle;
        end;
      sdPostgreSQL:
        begin
          F.Hl.SQLDialect := sqlPostgres;
        end;
      sdTSQL:
        begin
          F.Hl.SQLDialect := sqlMSSQL2K;
        end;
    else
      begin
        F.Hl.SQLDialect := sqlMySQL;
      end;
    end;
    ApplyEditorTheme(F.Hl, ASettings.Theme);
    F.Preview := TSynEdit.Create(F);
    F.Preview.Parent := F;
    F.Preview.Align := alClient;
    F.Preview.BorderSpacing.Top := M;
    F.Preview.BorderSpacing.Right := M;
    F.Preview.ReadOnly := True;
    F.Preview.Highlighter := F.Hl;
    F.Preview.RightEdge := -1;
    {$IFDEF WINDOWS}
    F.Preview.Font.Name := 'Consolas';
    {$ELSE}
    F.Preview.Font.Name := 'Monospace';
    {$ENDIF}
    F.Preview.Font.Size := ASettings.EditorFontSize;
    SmoothFont(F.Preview.Font);
    F.Preview.Color := clPgnWork;
    F.Preview.Gutter.Color := TColor($00FAF8F7);

    F.FillProfiles(ASettings.FormatProfile);
    F.ActiveControl := F.BFormat;
    if F.ShowModal = mrOK then
    begin
      ASettings.FormatProfile := ProfileKey(F.Profiles[F.Cur]);
      AResult := FormatSql(ASource, ADialect, F.Read, ALeftAlone);
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

end.
