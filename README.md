# Pagona

A fast, native, open-source database client for Windows and Linux, built with Lazarus / Free Pascal.

Pagona connects directly from your machine to your databases (including cloud databases), with no server in between. It aims to cover what developers and DBAs use every day, with optional Toad-compatible keyboard shortcuts.

## What works now

- **Query tabs.** Each tab has its own connection, database, session, editor, results and messages. Tabs are labeled in text, e.g. `PROD · MySQL · finaid-db: Query 1`. Ctrl+T opens a tab on the current connection, Ctrl+W closes, Ctrl+Tab / Ctrl+Shift+Tab switch.
- **SQL files.** Ctrl+O opens a file (into the current tab if it's empty, otherwise a new tab on the same connection), Ctrl+S saves, Ctrl+Shift+S saves as. The tab is titled by the file name, with `*` when there are unsaved changes. Closing a tab or Pagona with unsaved changes asks Save / Don't save / Cancel.
- **Close buttons** on every tab, a **+** for a new tab, middle-click to close, and drag to reorder (drawn by Pagona, so they look the same on Windows and Linux).
- **Side by side.** Right-click a tab > Side by Side to show it next to the others, each on its own connection; uncheck it to bring the tab back.
- **Explorer** with every saved connection. Expanding one connects it (password asked once, remembered in memory until Pagona closes, never written to disk). Databases > Tables / Views > columns.
- **Environment labels** (Production / Test / Development) shown as text on tabs, the tab's connection band, the window title and the confirmations. Colors are optional and purely personal.
- **The tree stays current.** CREATE / DROP / ALTER / RENAME of databases, tables and views refresh the Explorer and the database lists automatically. Refresh All is on every right-click menu and at the top of the Explorer.
- **Right-click menus.** Tables: Select Top Rows, Describe and Show DDL each open a new tab; Script As opens a new tab too (Explorer actions never touch the tab you're working in); Truncate / Drop run in a tab of their own so you can see what ran. Editor: run, explain, cut/copy/paste, comment lines, change case, describe. Tabs: new, close, rename, split.
- TLS on by default, with an optional CA certificate file.
- SQL editor with MySQL highlighting; it starts empty with the cursor ready. `DELIMITER` works as in the mysql client.
- Queries run on a background thread per tab; Cancel stops the running statement on the server.
- Auto-commit toggle per tab, with Commit and Rollback. With auto-commit off, Pagona asks before closing the tab, switching its connection, or closing Pagona.
- Confirmation before DELETE, TRUNCATE and DROP, naming the connection; can be turned off in Edit > Options.
- Edit > Options: row limit (0 = no limit), confirmations, keymap. Keymaps: Default and Toad.

- **SQL Server** (written, first runs on a real server still to come): Windows Authentication or SQL Server Authentication, Encrypt (Mandatory / Optional / Strict) and Trust server certificate, as in SSMS's Connect dialog. Scripts are cut into batches at `GO` lines; PRINT and "(n rows affected)" go to Messages; several result sets come back together; Ctrl+L (Seattle) shows the estimated plan; Alt+F1 runs `sp_help`. Object Explorer: Databases > a database's Schemas > Tables, Views, Functions, Procedures, Triggers, Sequences, Synonyms, User-Defined Types; server Logins, Server Roles, Linked Servers, SQL Server Agent Jobs. Procedures, functions and triggers save with `CREATE OR ALTER`, keeping grants. Needs an SQL Server ODBC driver: Microsoft's "ODBC Driver 18 for SQL Server" (Windows: usually installed with SQL Server; Pagona falls back to 17, then Windows' own "SQL Server" driver); on Linux unixODBC with msodbcsql18 or FreeTDS.

Pagona doesn't restrict what you can run. Whatever your database privileges allow, Pagona runs; whatever the server refuses, you see the server's own error.

### Keymaps

### Layouts

View > Layout picks how the window is arranged. On Windows it switches on the spot, keeping your open tabs, connections and remembered passwords; on Linux Pagona restarts to be sure everything changes:

- **Plume** (the default): the Explorer on the left, query tabs on the right, each tab with its environment band.
- **Amphibian**: Toad's arrangement and wording. Session > New Connection lists your saved connections, as Toad's login window does (it opens by itself at start). A small-icon main toolbar; a session bar with one button per open connection; a window bar with Editor, Schema Browser and each DBA screen; the Editor with its own toolbar and the Session / Database / Schema pickers; Toad's result tabs (Messages, Data Grid, DBMS Output, Explain Plan, History); Database > Schema Browser with object types, a Toad-style filter (`SPR%`) and the details of what's picked. Menus use Toad's names (Execute Statement, Execute as Script, Session Browser, ...).
- **Seattle**: SSMS's arrangement and wording. Connect to Server opens at start; Object Explorer on the left lists the servers you've connected, named as SSMS names them, with Connect, Disconnect, Filter, Refresh and Activity Monitor on its own bar (right-click a server for Activity Monitor, Locks and Blocking, Users and Roles). Under the main toolbar, SSMS's SQL Editor toolbar: Connect, Change Connection, the database box, Execute, Cancel, the estimated plan, comment and indent. Query tabs are named as SSMS names them (`SQLQuery1.sql - server.database (login (session id))`), with a Ln / Ch line under the editor; Results (several result sets stacked, as SSMS), Messages, Execution Plan and History; and SSMS's query status bar, in the environment's color with the environment in words. Seattle tabs start with auto-commit on, as SSMS (Edit > Options has its own setting); closing with uncommitted work asks SSMS's question. There's no DBA menu, as in SSMS: those screens open from Object Explorer; Tools has the DBA log and Options.

Edit > Find (Ctrl+F), Find Next (F3) and Replace work in every layout.

View > Look colors the frame around your work to match: Plume's quiet gray-white, Amphibian's warmer Windows grays, Seattle's light blue with a dark status bar. **Match layout** (the default) follows the layout; pick one by name to keep it. The editor, grids and environment colors are the same in every look.

### Keymaps

Layout and keymap are separate choices (View > Keymap, or Edit > Options). **Match layout** (the default) uses the keymap that comes with the layout; pick a keymap by name to keep it whatever the layout, e.g. the Plume layout with Amphibian keys.

| Command | Pagona | Amphibian (Toad keys) | Seattle (SSMS keys) |
|---|---|---|---|
| Run statement at cursor (or selection) | F5, Ctrl+Enter | F9, Ctrl+Enter | (select it, then F5) |
| Run whole editor (or selection) as script | Shift+F5, Ctrl+Shift+Enter | F5 | F5, Ctrl+E |
| Comment lines | (Toggle) | Ctrl+B | Ctrl+K, Ctrl+C |
| Uncomment lines | (Toggle) | Ctrl+Shift+B | Ctrl+K, Ctrl+U |
| Toggle comment | Ctrl+/ | | |
| Block comment `/* */` | Ctrl+Shift+/ | | |
| Describe object at cursor | Alt+F1 | F4 | Alt+F1 |
| SQL history | Ctrl+H | F8 | |
| Explain plan | (menu) | Ctrl+E | Ctrl+L |
| New tab / close tab | Ctrl+T / Ctrl+W | same | Ctrl+N / Ctrl+F4 (Ctrl+T / Ctrl+W too) |
| Cancel running query | (menu) | (menu) | Alt+Break |
| Next / previous tab | Ctrl+Tab or Ctrl+PgDn / Ctrl+Shift+Tab or Ctrl+PgUp | same | same |
| Open / Save / Save As | Ctrl+O / Ctrl+S / Ctrl+Shift+S | same | same |

With a selection, "Run statement" runs exactly the selection. Comment commands work on every line the selection touches (or the caret line) and are undone with a single Undo. Comment and Uncomment are also on the toolbar.

## Installing (Windows)

Download from the project's Releases page:

- **`Pagona-0.1.0-setup.exe`**, the installer. It installs Pagona for
  everyone on the PC into Program Files, so it asks for an administrator.
  It adds a Start menu shortcut (a desktop one is optional) and an entry in
  Windows' installed apps for uninstalling. The PostgreSQL and MySQL client
  libraries are optional and not ticked: tick one only if the PC doesn't
  already have the client library its other software needs. Uninstalling
  keeps your settings and saved connections unless you tick the box for
  them.
- **`Pagona-0.1.0-win64.zip`**, the portable copy: unzip and run
  `pagona.exe`. The optional client libraries are in `client-libs`.

Oracle needs Oracle Instant Client (64-bit), and SQL Server needs
Microsoft's "ODBC Driver 18 for SQL Server". Neither can be shipped with
Pagona, and a PC using those databases usually has them already.

Pagona isn't code-signed, so the first time it runs Windows SmartScreen
warns about an unrecognized app: choose **More info → Run anyway** (or
right-click the downloaded file > Properties > **Unblock**). Instead of a
paid certificate, every release is built from this repository's source by
GitHub Actions (the build log is public on the Actions tab), and each
release lists the SHA-256 checksum of its files in `SHA256SUMS.txt`. To
check a download, in PowerShell:

```
Get-FileHash .\Pagona-0.1.0-setup.exe
```

and compare the hash with the one in `SHA256SUMS.txt`.

## Making a release (maintainer)

1. Set the version in `src/pgntypes.pas` (`PagonaVersion`) and in
   `pagona.lpi` (Project Options → Version Info), and add it to
   `CHANGELOG.md`.
2. Tag the commit and push the tag: `git tag v0.1.0` then
   `git push origin v0.1.0`.
3. GitHub builds the Release `pagona.exe`, the installer and the zip
   (`.github/workflows/release.yml`) and makes a draft release with both.
   Check it, then publish it. "Run workflow" on the Actions page builds the
   same files without a release, to try the build.

## Building

1. Install the current **Lazarus** release (it includes Free Pascal).
2. In Lazarus: **Package → Online Package Manager**, install **ZeosLib** (the `zcomponent` package) and **ExtTabCtrls** (the tab bar: close buttons, "+", drag to reorder, the same on Windows and Linux).
3. Install the MySQL client library:
   - Windows: copy `redist/windows-x64/libmysql.dll` (and the OpenSSL DLLs there) next to `pagona.exe`, or set its path in the connection's "Client library path".
   - Linux: install your distro's `libmariadb` package (for example `libmariadb3` on Debian/Ubuntu).
   For PostgreSQL, the client library is `libpq`:
   - Windows: copy the DLLs in `redist/windows-x64` next to `pagona.exe` (the README there lists them and their licenses).
   - Linux: install `libpq5`.
4. Open `pagona.lpi` in Lazarus and press F9 (Run), or build from the command line:
   ```
   lazbuild pagona.lpi
   ```
   The executable goes to `bin/`.
5. For a copy to hand to someone (small, no debugger information), pick the **Release** build mode (Project > Project Options > Compiler Options > Build modes, or the build-mode box on the toolbar) and build, or:
   ```
   lazbuild --build-mode=Release pagona.lpi
   ```
   About 8 MB instead of about 69. Oracle needs ZeosLib's Oracle driver switched on (`ZEOS_DISABLE_ORACLE` not defined in `Zeos.inc`) and an Oracle client of the same bitness as `pagona.exe` (64-bit Pagona: 64-bit Instant Client).

Settings and saved connections live in the per-user config folder (`%LOCALAPPDATA%\Pagona\` on Windows, `~/.config/Pagona/` on Linux).

## Layout of the code

There are no designer forms (`.lfm` files): every window is built in code,
so the IDE has no form to toggle to (F12). Three layouts rearrange the same
pieces, which is simpler in code, and changes stay readable in git. To see a
window, run the program; to change it, look for `BuildUI` / `BuildLayout` in
the unit below.

| Unit | Purpose |
|---|---|
| `pgnTypes` | Connection profile record, result set |
| `pgnAdapter` | The adapter contract every database engine implements |
| `pgnAdapterMySQL` | MySQL / MariaDB adapter (ZeosLib) |
| `pgnAdapterPG` | PostgreSQL adapter (ZeosLib, libpq): schemas, a session per database |
| `pgnAdapterOracle` | Oracle adapter (ZeosLib, Oracle client): TNS aliases, DBMS_OUTPUT, PL/SQL |
| `pgnTns` | Finds tnsnames.ora and reads its aliases |
| `pgnAdapterMSSQL` | SQL Server adapter: GO batches, PRINT messages, implicit transactions, CREATE OR ALTER |
| `pgnOdbc` | A small ODBC client (loaded at run time): result sets, messages, cancel |
| `pgnPendingWin` | Pending Statements: what waits for Commit, with Commit All / Roll Back All / Undo From Here |
| `pgnConnectWin` | Amphibian's New Connection window: the saved connections to pick from |
| `pgnAmphibian` | Amphibian layout pieces: session and window bars, Schema Browser |
| `pgnIcons` | Small two-tone and bold toolbar icons, drawn from shapes |
| `pgnAdapters` | Factory: engine → adapter class |
| `pgnSqlSplit` | Statement splitting (quotes and comments aware) |
| `pgnQueryThread` | Background query execution |
| `pgnKeymap` | Keyboard profiles |
| `pgnConnections`, `pgnSettings` | JSON-backed storage |
| `pgnConnectDlg` | Connection editor dialog |
| `pgnOptionsDlg` | Edit > Options dialog |
| `pgnScriptGen` | "Script as" templates for the tree menu |
| `pgnColors` | Connection color presets |
| `pgnTheme` | Editor themes (Plume, Classic) and the interface colors |
| `pgnToolbar` | The toolbar, drawn by Pagona; movable buttons |
| `pgnStatusBar` | The status bar, drawn by Pagona |
| `pgnResultGrid` | Result grids, drawn by Pagona (bold titles, NULL shown, Ctrl+C) |
| `pgnRoutineDlg` | New Procedure/Function, Execute (parameters) and Grant forms |
| `pgnDbaLog` | The Pagona DBA log: one line per DBA action (dba-log.txt) |
| `pgnUsersScreen` | DBA > Users and Roles: accounts, settings, roles, grants, new/drop |
| `pgnWhoCanScreen` | DBA > Who Can Do What: everyone who can use one object, and how |
| `pgnZeos` | Runs one statement through Zeos and collects its results |
| `pgnQueryTab` | One query tab: environment band, editor, results, messages (`BuildUI`) |
| `pgnMain` | Main window: menus, toolbar, Explorer, tabs, status bar (`BuildMenu`, `BuildToolbar`, `BuildLayout`) |

The UI only talks to `TpgnAdapter`. Adding SQL Server means writing one adapter unit and adding it to `pgnAdapters`.

Code style: every branch and loop body is wrapped in `begin ... end`, even single statements.

## Next

- SQL Server: first runs against a real server.
- Fetch rows as you scroll instead of up front.
- Binary column viewer.
- Optional password storage in the OS keychain.
- SSH tunnels and cloud identity logins.
- CI builds for Linux, and code signing.

## License

Copyright (C) 2026 Randy Morrow.

Pagona is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version. It is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See `LICENSE` for the
full text, and `THIRD-PARTY-NOTICES.md` for the libraries Pagona uses and
their licenses.
