// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnAdapters;

{ Adapter factory: maps an engine to its adapter class.
  New engines get one line here plus their own unit. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, pgnTypes, pgnAdapter, pgnAdapterMySQL, pgnAdapterPG, pgnAdapterOracle, pgnAdapterMSSQL;

function CreateAdapter(const AInfo: TpgnConnectionInfo; const APassword: string): TpgnAdapter;

implementation

function CreateAdapter(const AInfo: TpgnConnectionInfo; const APassword: string): TpgnAdapter;
begin
  Result := nil;
  case AInfo.Engine of
    feMySQL, feMariaDB:
      begin
        Result := TpgnMySQLAdapter.Create(AInfo, APassword);
      end;
    fePostgreSQL:
      begin
        Result := TpgnPostgresAdapter.Create(AInfo, APassword);
      end;
    feOracle:
      begin
        Result := TpgnOracleAdapter.Create(AInfo, APassword);
      end;
    feSQLServer:
      begin
        Result := TpgnMSSQLAdapter.Create(AInfo, APassword);
      end;
  end;
  if Result = nil then
  begin
    raise Exception.Create('No adapter for this database engine.');
  end;
end;

end.
