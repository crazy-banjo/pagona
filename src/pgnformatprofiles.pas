// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnFormatProfiles;

{ Named format profiles for Format SQL.

  A profile is a small JSON file, Name.pagona-format, so it can be emailed,
  posted, committed to a repository or kept in a shared folder:

    "pagonaFormat": 1, "name": "Registrar Reports",
    "options": ( "keywordCase": "upper", "indent": 4, ... )   (in braces)

  Three places a profile comes from:
    - Pagona Default: built in, never changes.
    - Your own: in the formats folder next to Pagona's settings. Save,
      Rename and Delete work on these.
    - Shared: the files in the shared profiles folder (Options), if one is
      set: a team's standard kept in one place. Pagona never deletes a file
      there; replacing one asks first (when the folder can be written).

  A profile is named by a key: 'default', 'local:Name' or 'shared:Name'. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser, LazFileUtils, pgnSqlFormat;

const
  FormatFileExt = '.pagona-format';
  DefaultProfileName = 'Pagona Default';
  DefaultProfileKey = 'default';

type
  TpgnProfileSource = (psBuiltIn, psLocal, psShared);

  TpgnFormatProfile = record
    Name: string;
    Source: TpgnProfileSource;
    FileName: string;    // '' for the built-in one
    Opt: TpgnFormatOptions;
  end;
  TpgnFormatProfiles = array of TpgnFormatProfile;

{ Where your own profiles live (created when needed). }
function LocalFormatsDir: string;

{ Pagona Default, then your own (by name), then the shared folder's. }
function LoadFormatProfiles(const ASharedDir: string): TpgnFormatProfiles;

function ProfileKey(const AProfile: TpgnFormatProfile): string;
{ The profile with this key, or Pagona Default. }
function FindProfile(const AProfiles: TpgnFormatProfiles; const AKey: string): TpgnFormatProfile;
function ProfileIndex(const AProfiles: TpgnFormatProfiles; const AKey: string): Integer;

{ Writes a profile file; the file name follows the profile name. }
procedure WriteProfileFile(const AFileName, AName: string; const AOpt: TpgnFormatOptions);
{ Reads a profile file; False (and AError) if it isn't one. }
function ReadProfileFile(const AFileName: string; out AName: string; out AOpt: TpgnFormatOptions;
  out AError: string): Boolean;

{ A name made safe for a file name. }
function ProfileFileName(const ADir, AName: string): string;
{ True when a name has something usable in it. }
function ValidProfileName(const AName: string): Boolean;

{ True when files can be written in the folder. }
function FolderWritable(const ADir: string): Boolean;

{ Deletes one of your own profiles (never a file outside your formats folder). }
function DeleteLocalProfile(const AProfile: TpgnFormatProfile): Boolean;

{ The options as JSON and back (also used for the old settings entry). }
function OptionsToJson(const AOpt: TpgnFormatOptions): TJSONObject;
function OptionsFromJson(AObj: TJSONObject): TpgnFormatOptions;

implementation

uses
  pgnSettings;

function LocalFormatsDir: string;
begin
  Result := IncludeTrailingPathDelimiter(PagonaConfigDir + 'formats');
end;

function OptionsToJson(const AOpt: TpgnFormatOptions): TJSONObject;
begin
  Result := TJSONObject.Create;
  case AOpt.KeywordCase of
    kcLower:
      begin
        Result.Add('keywordCase', 'lower');
      end;
    kcAsTyped:
      begin
        Result.Add('keywordCase', 'asTyped');
      end;
  else
    begin
      Result.Add('keywordCase', 'upper');
    end;
  end;
  Result.Add('indent', AOpt.IndentSize);
  Result.Add('tabs', AOpt.UseTabs);
  Result.Add('leadingCommas', AOpt.LeadingCommas);
  Result.Add('oneColumnPerLine', AOpt.OneColumnPerLine);
  Result.Add('lineWidth', AOpt.LineWidth);
  Result.Add('andOrNewLine', AOpt.AndOrNewLine);
  Result.Add('joinIndented', AOpt.JoinIndented);
  Result.Add('river', AOpt.River);
  Result.Add('blankLineBetween', AOpt.BlankLineBetween);
end;

function OptionsFromJson(AObj: TJSONObject): TpgnFormatOptions;
begin
  Result := DefaultFormatOptions;
  if AObj = nil then
  begin
    Exit;
  end;
  case AObj.Get('keywordCase', 'upper') of
    'lower':
      begin
        Result.KeywordCase := kcLower;
      end;
    'asTyped':
      begin
        Result.KeywordCase := kcAsTyped;
      end;
  else
    begin
      Result.KeywordCase := kcUpper;
    end;
  end;
  Result.IndentSize := EnsureRange(AObj.Get('indent', Result.IndentSize), 1, 8);
  Result.UseTabs := AObj.Get('tabs', Result.UseTabs);
  Result.LeadingCommas := AObj.Get('leadingCommas', Result.LeadingCommas);
  Result.OneColumnPerLine := AObj.Get('oneColumnPerLine', Result.OneColumnPerLine);
  Result.LineWidth := EnsureRange(AObj.Get('lineWidth', Result.LineWidth), 40, 400);
  Result.AndOrNewLine := AObj.Get('andOrNewLine', Result.AndOrNewLine);
  Result.JoinIndented := AObj.Get('joinIndented', Result.JoinIndented);
  Result.River := AObj.Get('river', Result.River);
  Result.BlankLineBetween := AObj.Get('blankLineBetween', Result.BlankLineBetween);
end;

procedure WriteProfileFile(const AFileName, AName: string; const AOpt: TpgnFormatOptions);
var
  O: TJSONObject;
begin
  O := TJSONObject.Create;
  try
    O.Add('pagonaFormat', 1);
    O.Add('name', AName);
    O.Add('options', OptionsToJson(AOpt));
    ForceDirectories(ExtractFileDir(AFileName));
    WriteTextFile(AFileName, O.FormatJSON);
  finally
    O.Free;
  end;
end;

function ReadProfileFile(const AFileName: string; out AName: string; out AOpt: TpgnFormatOptions;
  out AError: string): Boolean;
var
  Data: TJSONData;
  O: TJSONObject;
begin
  Result := False;
  AName := '';
  AOpt := DefaultFormatOptions;
  AError := '';
  try
    Data := GetJSON(ReadTextFile(AFileName));
    try
      if not (Data is TJSONObject) or (TJSONObject(Data).Find('pagonaFormat') = nil) then
      begin
        AError := 'it isn''t a Pagona format profile';
        Exit;
      end;
      O := TJSONObject(Data);
      AName := Trim(O.Get('name', ''));
      if AName = '' then
      begin
        AName := ExtractFileNameOnly(AFileName);
      end;
      if O.Find('options') is TJSONObject then
      begin
        AOpt := OptionsFromJson(TJSONObject(O.Find('options')));
      end;
      Result := True;
    finally
      Data.Free;
    end;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function ValidProfileName(const AName: string): Boolean;
begin
  Result := (Trim(AName) <> '') and not SameText(Trim(AName), DefaultProfileName);
end;

function ProfileFileName(const ADir, AName: string): string;
var
  I: Integer;
  S: string;
begin
  S := Trim(AName);
  for I := 1 to Length(S) do
  begin
    if S[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then
    begin
      S[I] := '_';
    end;
  end;
  Result := IncludeTrailingPathDelimiter(ADir) + S + FormatFileExt;
end;

function FolderWritable(const ADir: string): Boolean;
begin
  Result := (ADir <> '') and DirectoryExistsUTF8(ADir) and DirectoryIsWritable(ADir);
end;

procedure AddFolder(var AList: TpgnFormatProfiles; const ADir: string; ASource: TpgnProfileSource);
var
  SR: TSearchRec;
  Names: TStringList;
  I, N: Integer;
  Name, Err: string;
  Opt: TpgnFormatOptions;
begin
  if (ADir = '') or not DirectoryExistsUTF8(ADir) then
  begin
    Exit;
  end;
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.CaseSensitive := False;
    Names.Duplicates := dupAccept;
    if FindFirstUTF8(IncludeTrailingPathDelimiter(ADir) + '*' + FormatFileExt, faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Attr and faDirectory) = 0 then
          begin
            Names.Add(SR.Name);
          end;
        until FindNextUTF8(SR) <> 0;
      finally
        FindCloseUTF8(SR);
      end;
    end;
    for I := 0 to Names.Count - 1 do
    begin
      if ReadProfileFile(IncludeTrailingPathDelimiter(ADir) + Names[I], Name, Opt, Err) then
      begin
        N := Length(AList);
        SetLength(AList, N + 1);
        AList[N].Name := Name;
        AList[N].Source := ASource;
        AList[N].FileName := IncludeTrailingPathDelimiter(ADir) + Names[I];
        AList[N].Opt := Opt;
      end;
    end;
  finally
    Names.Free;
  end;
end;

function LoadFormatProfiles(const ASharedDir: string): TpgnFormatProfiles;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].Name := DefaultProfileName;
  Result[0].Source := psBuiltIn;
  Result[0].FileName := '';
  Result[0].Opt := DefaultFormatOptions;
  AddFolder(Result, LocalFormatsDir, psLocal);
  // the shared folder, unless it's the same as your own
  if (Trim(ASharedDir) <> '') and not SameText(IncludeTrailingPathDelimiter(ExpandFileName(Trim(ASharedDir))),
    ExpandFileName(LocalFormatsDir)) then
  begin
    AddFolder(Result, Trim(ASharedDir), psShared);
  end;
end;

function ProfileKey(const AProfile: TpgnFormatProfile): string;
begin
  case AProfile.Source of
    psLocal:
      begin
        Result := 'local:' + AProfile.Name;
      end;
    psShared:
      begin
        Result := 'shared:' + AProfile.Name;
      end;
  else
    begin
      Result := DefaultProfileKey;
    end;
  end;
end;

function ProfileIndex(const AProfiles: TpgnFormatProfiles; const AKey: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(AProfiles) do
  begin
    if SameText(ProfileKey(AProfiles[I]), AKey) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function FindProfile(const AProfiles: TpgnFormatProfiles; const AKey: string): TpgnFormatProfile;
begin
  Result := AProfiles[ProfileIndex(AProfiles, AKey)];
end;

function DeleteLocalProfile(const AProfile: TpgnFormatProfile): Boolean;
begin
  Result := False;
  // only your own, and only a file inside your own formats folder
  if (AProfile.Source <> psLocal) or (AProfile.FileName = '') then
  begin
    Exit;
  end;
  if not SameText(IncludeTrailingPathDelimiter(ExtractFileDir(ExpandFileName(AProfile.FileName))),
    ExpandFileName(LocalFormatsDir)) then
  begin
    Exit;
  end;
  Result := DeleteFileUTF8(AProfile.FileName);
end;

end.
