// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnZeos;

{ Runs user SQL through Zeos's plain statement interface (text protocol)
  and lets the server say what came back: rows, a row count, or several
  result sets (a CALL can return more than one). Shared by every adapter
  built on Zeos, so none of them has to guess from the SQL's first word. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ZConnection, ZDbcIntfs, pgnTypes;

{ Runs one statement. Every result set comes back (each up to ARowLimit
  rows, 0 = no limit): the first in the result, later ones chained on
  Next. With no result set, RowsAffected holds the row count. }
function RunStatement(AConn: TZConnection; const ASQL: string; ARowLimit: Integer): TpgnResultSet;

implementation

procedure CopyResultSet(ARS: IZResultSet; ARowLimit: Integer; AResult: TpgnResultSet);
var
  Meta: IZResultSetMetadata;
  I, N, Count, Cap, Col: Integer;
  SqlType: TZSQLType;
begin
  Meta := ARS.GetMetadata;
  N := Meta.GetColumnCount;
  SetLength(AResult.Columns, N);
  for I := 0 to N - 1 do
  begin
    AResult.Columns[I] := Meta.GetColumnLabel(I + FirstDbcIndex);
  end;

  Count := 0;
  Cap := 0;
  AResult.Rows := nil;
  while ((ARowLimit <= 0) or (Count < ARowLimit)) and ARS.Next do
  begin
    if Count >= Cap then
    begin
      if Cap = 0 then
      begin
        Cap := 256;
      end
      else
      begin
        Cap := Cap * 2;
      end;
      SetLength(AResult.Rows, Cap);
    end;
    SetLength(AResult.Rows[Count].Values, N);
    SetLength(AResult.Rows[Count].Nulls, N);
    for I := 0 to N - 1 do
    begin
      Col := I + FirstDbcIndex;
      AResult.Rows[Count].Nulls[I] := ARS.IsNull(Col);
      if AResult.Rows[Count].Nulls[I] then
      begin
        AResult.Rows[Count].Values[I] := '';
      end
      else
      begin
        SqlType := Meta.GetColumnType(Col);
        if SqlType in [stBytes, stBinaryStream] then
        begin
          AResult.Rows[Count].Values[I] := Format('(binary, %d bytes)', [Length(ARS.GetBytes(Col))]);
        end
        else
        begin
          AResult.Rows[Count].Values[I] := ARS.GetString(Col);
        end;
      end;
    end;
    Inc(Count);
  end;
  SetLength(AResult.Rows, Count);

  // stopped at the limit: is there anything after it?
  if (ARowLimit > 0) and (Count >= ARowLimit) then
  begin
    AResult.HasMoreRows := ARS.Next;
  end
  else
  begin
    AResult.HasMoreRows := False;
  end;
  AResult.ReturnsRows := True;
end;

function RunStatement(AConn: TZConnection; const ASQL: string; ARowLimit: Integer): TpgnResultSet;
var
  Stmt: IZStatement;
  RS: IZResultSet;
  Affected, Cnt: Integer;
  GotRows: Boolean;
  Last, Extra: TpgnResultSet;
begin
  Last := nil;
  Result := TpgnResultSet.Create;
  try
    Stmt := AConn.DbcConnection.CreateStatement;
    try
      Stmt.Execute(UTF8Decode(ASQL));
      GotRows := False;
      Affected := 0;
      repeat
        RS := Stmt.GetResultSet;
        if RS <> nil then
        begin
          if not GotRows then
          begin
            CopyResultSet(RS, ARowLimit, Result);
            GotRows := True;
            Last := Result;
          end
          else
          begin
            Extra := TpgnResultSet.Create;
            CopyResultSet(RS, ARowLimit, Extra);
            Last.Next := Extra;
            Last := Extra;
          end;
          RS.Close;
          RS := nil;
        end
        else
        begin
          Cnt := Stmt.GetUpdateCount;
          if Cnt > 0 then
          begin
            Affected := Affected + Cnt;
          end;
        end;
        // every result has to be read, or the next statement on this
        // session fails with "commands out of sync"
      until not Stmt.GetMoreResults;

      if not GotRows then
      begin
        Result.ReturnsRows := False;
        Result.RowsAffected := Affected;
      end;
    finally
      Stmt.Close;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
