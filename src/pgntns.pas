// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnTns;

{ Reads the aliases of an Oracle tnsnames.ora, the way Toad and SQL*Plus
  find it: a file named in the connection, else $TNS_ADMIN, else the
  client library's folder (Instant Client keeps network\admin there), else
  $ORACLE_HOME/network/admin. The alias is what Pagona hands to the Oracle
  client; the client itself reads the file to find the server. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, pgnTypes;

{ The tnsnames.ora that would be used, or '' if none is found. AFile may
  be a file or a folder; '' looks in the usual places. }
function FindTnsFile(const AFile, AClientLibrary: string): string;

{ The aliases defined in AFileName, sorted, without duplicates. }
function TnsAliases(const AFileName: string): TpgnStringArray;

{ The folder to tell the client about (TNS_ADMIN) for AFileName. }
function TnsFolder(const AFileName: string): string;

implementation

function Existing(const APath: string): string;
begin
  Result := '';
  if (APath <> '') and FileExists(APath) then
  begin
    Result := APath;
  end;
end;

function InFolder(const AFolder: string): string;
begin
  Result := '';
  if AFolder <> '' then
  begin
    Result := Existing(IncludeTrailingPathDelimiter(AFolder) + 'tnsnames.ora');
  end;
end;

function FindTnsFile(const AFile, AClientLibrary: string): string;
var
  LibDir: string;
begin
  Result := '';
  if AFile <> '' then
  begin
    if DirectoryExists(AFile) then
    begin
      Result := InFolder(AFile);
    end
    else
    begin
      Result := Existing(AFile);
    end;
    Exit;   // named but missing: don't silently use another one
  end;
  Result := InFolder(GetEnvironmentVariable('TNS_ADMIN'));
  if Result <> '' then
  begin
    Exit;
  end;
  if AClientLibrary <> '' then
  begin
    LibDir := ExtractFilePath(AClientLibrary);
    Result := InFolder(LibDir + 'network' + PathDelim + 'admin');
    if Result = '' then
    begin
      Result := InFolder(LibDir);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  if GetEnvironmentVariable('ORACLE_HOME') <> '' then
  begin
    Result := InFolder(IncludeTrailingPathDelimiter(GetEnvironmentVariable('ORACLE_HOME')) + 'network' +
      PathDelim + 'admin');
  end;
end;

function TnsFolder(const AFileName: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(AFileName));
end;

{ An alias starts a line (no indent) and is followed by '=': "DEVL =",
  "PROD.WORLD=(DESCRIPTION=...". Several may share one entry: "A, B =".
  Comments start with '#'. Everything inside the parentheses is skipped. }
function TnsAliases(const AFileName: string): TpgnStringArray;
var
  L: TStringList;
  Names: TStringList;
  I, J, Depth, P: Integer;
  S, Head: string;
  Parts: TStringArray;
begin
  Result := nil;
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  L := TStringList.Create;
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    Names.CaseSensitive := False;
    try
      L.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        Exit;
      end;
    end;
    Depth := 0;
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      P := Pos('#', S);
      if P > 0 then
      begin
        S := Copy(S, 1, P - 1);
      end;
      if Trim(S) = '' then
      begin
        Continue;
      end;
      if (Depth = 0) and not (S[1] in [' ', #9, '(', ')']) then
      begin
        P := Pos('=', S);
        if P > 0 then
        begin
          Head := Trim(Copy(S, 1, P - 1));
          Parts := Head.Split([',']);
          for J := 0 to High(Parts) do
          begin
            if Trim(Parts[J]) <> '' then
            begin
              Names.Add(UpperCase(Trim(Parts[J])));
            end;
          end;
        end;
      end;
      for J := 1 to Length(S) do
      begin
        if S[J] = '(' then
        begin
          Inc(Depth);
        end
        else if (S[J] = ')') and (Depth > 0) then
        begin
          Dec(Depth);
        end;
      end;
    end;
    SetLength(Result, Names.Count);
    for I := 0 to Names.Count - 1 do
    begin
      Result[I] := Names[I];
    end;
  finally
    Names.Free;
    L.Free;
  end;
end;

end.
