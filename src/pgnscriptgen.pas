// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnScriptGen;

{ "Script as" for the schema tree: builds SELECT / INSERT / UPDATE /
  DELETE templates for a table or view from its column list. Values and
  conditions are left as comments for you to fill in. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, pgnTypes, pgnAdapter;

type
  TpgnScriptKind = (skSelect, skInsert, skUpdate, skDelete);

function ScriptFor(AAdapter: TpgnAdapter; const ADatabase, AObject: string;
  AKind: TpgnScriptKind): string;

implementation

function ScriptFor(AAdapter: TpgnAdapter; const ADatabase, AObject: string;
  AKind: TpgnScriptKind): string;
var
  Cols: TpgnResultSet;
  Name, Names, Values, Sets, Qualified, Sep: string;
  I: Integer;
begin
  Qualified := AAdapter.QuoteIdent(ADatabase) + '.' + AAdapter.QuoteIdent(AObject);
  Names := '';
  Values := '';
  Sets := '';

  Cols := AAdapter.DescribeTable(ADatabase, AObject);
  try
    for I := 0 to Cols.RowCount - 1 do
    begin
      if I = 0 then
      begin
        Sep := '';
      end
      else
      begin
        Sep := ',' + LineEnding;
      end;
      Name := AAdapter.QuoteIdent(Cols.Rows[I].Values[0]);
      Names := Names + Sep + '  ' + Name;
      Values := Values + Sep + '  /* ' + Cols.Rows[I].Values[0] + ' ' + Cols.Rows[I].Values[1] + ' */';
      Sets := Sets + Sep + '  ' + Name + ' = /* ' + Cols.Rows[I].Values[1] + ' */';
    end;
  finally
    Cols.Free;
  end;

  case AKind of
    skSelect:
      begin
        Result := 'SELECT' + LineEnding + Names + LineEnding +
                  'FROM ' + Qualified + ';' + LineEnding;
      end;
    skInsert:
      begin
        Result := 'INSERT INTO ' + Qualified + ' (' + LineEnding + Names + LineEnding +
                  ') VALUES (' + LineEnding + Values + LineEnding + ');' + LineEnding;
      end;
    skUpdate:
      begin
        Result := 'UPDATE ' + Qualified + LineEnding + 'SET' + LineEnding + Sets + LineEnding +
                  'WHERE /* condition */;' + LineEnding;
      end;
    skDelete:
      begin
        Result := 'DELETE FROM ' + Qualified + LineEnding +
                  'WHERE /* condition */;' + LineEnding;
      end;
  else
    begin
      Result := '';
    end;
  end;
end;

end.
