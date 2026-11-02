// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

program pagona;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms,
  pgnMain;

{$R *.res}

begin
  // The UI is built in code, so there are no .lfm form resources to load.
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := 'Pagona';
  Application.Initialize;
  Application.CreateForm(TpgnMainForm, pgnMainForm);
  Application.Run;
end.
