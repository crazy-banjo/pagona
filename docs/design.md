# Pagona design decisions

Running record of look-and-feel decisions. Mockups were reviewed in chat.

## Language

U.S. English everywhere in the program and its docs (color, gray,
canceled, recognize, license).

## Settings vocabulary

- **Layout**: where things are and which buttons show (Plume, Amphibian, Seattle).
- **Keymap**: which keys do what. Default "Match layout".
- **Theme**: colors. Plume (default) and Classic (today's look) to start; dark later.
- **Mode**: Developer or DBA, the kind of work.

## Feel

A calm, quiet workbench: gray-white surfaces, one blue accent, color saved
for things that mean something. Dense like Toad, with a bit more spacing and
fewer borders. Pagona draws its own toolbar, tabs, environment band and
status bar (same on Windows and Linux); menus and dialogs stay native.

Color is never the only signal: environment and outcome colors always have
words beside them, and editor colors keep bold / italic.

## Editor colors: Plume theme (approved 2026-10-21)

| Kind | Color | Style |
|---|---|---|
| Keywords | #1D4E9E blue | bold |
| Comments | #2E6B30 green | italic |
| Strings | #A3420F rust | |
| Numbers | #6E3FA3 purple | |
| Built-in functions | #7A5200 brown | |
| Data types | #00657A teal | |
| Your objects (tables, views, procedures, functions from the connection) | #9B1F5C plum | |
| Variables (:id, @x, &term) | #5C6400 olive | bold |
| Everything else | #1A1A1A | |

All at least 6:1 contrast on white. Object names come from the connection's
metadata, so a misspelled table stays black.

The current look is kept as the **Classic** theme.

## Interface colors (approved 2026-10-21)

| Role | Color |
|---|---|
| Surface (panels, bars) | #F7F8FA |
| Work area (editor, grid) | #FFFFFF |
| Lines (borders) | #D7DBE1 |
| Accent (Pagona blue) | #1D4E9E |
| Selection | #DCE7F7 |
| Danger: PROD, errors, uncommitted | #B02A2A |
| Caution: TEST, warnings | #A8730B |
| Safe: DEV, success | #2E6B30 |

## Toolbar (approved 2026-10-21: option B, "quiet, one accent")

Flat buttons, small symbol + word, text always present.
Groups: New Tab | Run, Run Script, Cancel | Commit, Rollback | Explain,
Describe | Comment, Uncomment. Only Run is filled (Pagona blue). Commit and
Rollback are outlined because they change data. Icons: open-licensed or our
own; nothing resembling Toad's or SSMS's.

## Plume window (mockup reviewed 2026-10-21, details still open)

1. Toolbar as above.
2. Explorer with a filter box; Details panel (columns, indexes, keys,
   grants) under it for the selected object.
3. Tab names carry the environment: `PROD devdb · Query 1`.
4. Environment band per tab: environment in words, connection, schema /
   database, auto-commit state.
5. The statement Run will execute is shaded, with a margin bar; follows the
   selection when there is one.
6. Bottom: Results tabs (Results 1, 2... for several result sets, Plan,
   History), with Messages stacked underneath behind a draggable
   divider, always in view (decided 2026-10-21, as in Toad).
7. Status bar: connection and server version, uncommitted work in words,
   rows and time, caret position.
8. Session menu for connect, disconnect, commit, rollback.

Decided 2026-10-21:

- Toolbar buttons can be moved (reorder, add, remove), saved per user per
  layout, with "Reset to layout default".
- Details panel sits under the Explorer and follows the Explorer
  selection, not the active tab.
- The environment band is always shown, for every environment, so it can
  be confirmed at a glance.
- Environment labels come from each connection's Environment setting
  (Production / Test / Development / None) in the connection dialog.

Open: Explorer filter scope; tab name length.
Docking / floating panels: wait until all three layouts exist.

## Stored procedures, functions, triggers (decided and built 2026-10-21)

- Explorer, per database: Tables, Views, Procedures, Functions, Triggers.
- Details panel: Table = Columns | Indexes | Triggers | Grants;
  View = Columns | Definition; Procedure / Function = Parameters |
  Definition | Grants. Triggers listed with timing and event;
  double-click opens one (Toad needs a separate table window for this).
- A routine opens in its own tab: full definition, no DELIMITER needed.
  Save replaces it safely (test copy first, then drop and create, then
  re-apply EXECUTE grants; warn if grants can't be read). Execute asks
  for parameters. Revert reloads. Errors go to Messages with the line,
  and the cursor jumps there. "Read-only: your login can't alter this
  routine" when that's the case.
- New Procedure / Function form: name, parameters (name, IN/OUT/INOUT,
  type), return type; writes the skeleton.
- Grants: a readable Grants tab, and Grant... (who, which rights) for
  anyone the database allows to grant (e.g. Randy in DEVDB). DBA > Users and
  Roles is the fuller screen across objects.
- Button wording follows the layout: Plume "Save", Amphibian "Compile",
  Seattle "Save". Keys follow the keymap.
- Built notes: the Details tabs are a tab strip over one area (not
  hidden pages), because GTK3 mixes up pages when sheets are hidden. The
  New form uses plain fields per parameter row, not a grid.
- Known on Linux (GTK3) only: a query tab opened after the window is
  shown draws blank. Windows is not affected. To fix with the Linux
  build (priority 6).

## PostgreSQL Explorer (decided and built 2026-10-21)

Mapped from PostgreSQL's own catalog (as pgAdmin groups it); folder names
are PostgreSQL's terms, no icons copied.

```
Connection
├─ Databases (n)
│  └─ database
│     ├─ Schemas (n)
│     │  └─ schema
│     │     ├─ Tables (each table: Columns, Indexes, Triggers)
│     │     ├─ Views, Materialized Views
│     │     ├─ Functions (overloads shown with types: f(integer, text))
│     │     ├─ Procedures, Trigger Functions, Sequences, Domains, Types
│     │     └─ More: Aggregates, Collations, Foreign Tables, FTS objects,
│     │        Operators
│     ├─ Catalogs (pg_catalog, information_schema)
│     ├─ Extensions
│     └─ More: Casts, Event Triggers, Foreign Data Wrappers, Languages,
│        Publications, Subscriptions
├─ Login/Group Roles
└─ Tablespaces
```

- Schema level always shown, even with only `public`.
- Triggers sit under their table (PostgreSQL triggers belong to a table),
  in both modes. MySQL keeps its per-database Triggers folder.
- Folders show counts: "Tables (12)".
- Tab band for PostgreSQL: Database (changing it reconnects the tab's
  session) and Schema (search_path). Oracle: Schema only.
- The adapter says which levels it has (database, schema); one tree code
  path builds whichever apply. Object references carry the schema.
- Functions are identified by name + argument types for Open, Save, Drop,
  Grant. PostgreSQL Save uses CREATE OR REPLACE (grants stay).
- Per-connection "schemas to show" list: added when it fits (needed for
  Oracle databases with many schemas).

## Oracle (built 2026-10-22, not yet tried against a server)

Connecting: a TNS alias picked from tnsnames.ora (what Randy uses with
Toad), or host, port and service name (Easy Connect). tnsnames.ora is
found as Toad finds it: the file named in the connection, else
TNS_ADMIN, else the client library's folder (network/admin), else
ORACLE_HOME/network/admin. Needs the Oracle client (Instant Client).

```
Connection
├─ Databases (1)
│  └─ DEVDB
│     └─ Schemas (system schemas hidden; Show System Objects shows them)
│        └─ SALES
│           ├─ Tables (Columns, Indexes, Triggers), Views,
│           │  Materialized Views
│           ├─ Functions, Procedures, Triggers
│           ├─ Packages (spec and body open together), Sequences,
│           │  Synonyms, Types, Invalid Objects
│           └─ More: Database Links, Scheduler Jobs, Materialized View Logs
├─ Users, Roles, Tablespaces
└─ More: Profiles, Directories
```

- Catalog reads use ALL_* views (whatever the login can see); DBA
  screens use DBA_* and V$ views, and say which right is missing.
- Scripts run as SQL*Plus runs them: "/" ends PL/SQL, SET SERVEROUTPUT,
  EXEC, PROMPT, SHOW ERRORS understood; other SQL*Plus settings skipped.
- DBMS_OUTPUT always on; printed lines come back as a "DBMS Output"
  result after the statement's own results.
- CREATE OR REPLACE of code replaces even when it doesn't compile; Pagona
  then reports the ALL_ERRORS lines and that the object is INVALID.
- Dropping a user who owns objects needs CASCADE, which the Drop dialog
  asks for with its own checkbox (Oracle can't reassign).

## SQL Server (built 2026-10-23, not yet tried against a server)

Through ODBC, Pagona's own small client (pgnOdbc), loaded at run time:
Microsoft's ODBC Driver 18, then 17, for SQL Server; Windows' own "SQL
Server" driver; FreeTDS on Linux. ZeosLib 7.2's SQL Server options were
ruled out: ADO is COM (unsafe from Pagona's query threads) and DB-Library
needs a driver that's no longer shipped. ODBC also gives Windows
Authentication, TLS and cancel from another thread.

- Connection fields as SSMS's Connect dialog: server name, Windows / SQL
  Server Authentication, Encrypt (Mandatory, Optional, Strict), Trust
  server certificate. The client library field may name an ODBC driver.
- Explorer as PostgreSQL's: Databases > database > Schemas > dbo > Tables,
  Views, Functions, Procedures, Triggers (+ Sequences, Synonyms, User-Defined
  Types); database Users and Database Roles; server Logins, Server Roles,
  Linked Servers, SQL Server Agent Jobs. A session per database the
  Explorer opens. (SSMS lists dbo.table straight under Tables; doing that
  would need the tree to take schema-qualified names: later, if wanted.)
- No schema picker (SQL Server has no current schema to set).
- Batches at GO lines, sent whole. Messages: PRINT, "(n rows affected)",
  errors as "Msg n, Level n, State n, Line n".
- Transactions: implicit transactions when auto-commit is off; SAVE
  TRANSACTION for Undo From Here; DDL is transactional.
- Save: CREATE OR ALTER (2016 SP1 on), keeps grants.

## Amphibian layout (mockup approved and built 2026-10-22)

Toad's arrangement, Pagona's look; things Pagona doesn't have yet (Debug,
Team Coding, Rerun, Workspaces, Auto Trace, Query Viewer, Code Analysis
rule sets) are left out rather than shown dead.

```
APPUSER@DEVDB - Pagona - [Editor (Query 1)]
File Edit Search Session Editor Database View Window
[main toolbar: icons]
[TEST APPUSER@DEVDB] [PROD APPUSER@PROD]          <- session bar
[Editor] [Object Browser (APPUSER@DEVDB)] [Sessions] <- window bar
[editor toolbar: icons ............ Session [ ] Database [ ] Schema [ ]]
[Query 1 x] [Procedure X x] [+]                     <- editor tabs
editor
Data Grid
[Messages] [Data Grid] [DBMS Output] [Explain Plan] [History]
status bar
```

- Layout is chosen in View > Layout. Windows rearranges in place, keeping
  tabs, sessions and remembered passwords; Linux restarts (GTK3 can't swap
  the menu bar or re-lay out moved panels at runtime; decided 2026-10-22
  that a restart there is fine).
- The tab's environment band is replaced by the pickers in the editor
  toolbar; the session bar and status bar carry the environment as text.
- Database menu: Object Browser (Toad: Schema Browser); Monitor > Session Browser, Locks;
  Security > Users and Roles, Who Can Do What; Pagona DBA Log.
- Object Browser: object types as buttons (rare ones under More), a filter
  (SPR% = starts with), the list, Details tabs on the right; double-click
  opens code; right-click is the Explorer's menu for that object.
- Session > New Connection: Toad's login window, the saved connections in a
  list (environment, name, user, database / TNS alias, engine, server) with
  Connect, New, Edit, Delete. Opens by itself when nothing is connected.
- Toad's "Top 20" box (Code Analysis rule set) is left out: Pagona has no
  code analysis. The row limit stays in Edit > Options.

## Transactions (decided and built 2026-10-22)

As Toad's Transactions panel: rows are sessions (tabs), not statements,
because each tab has its own transaction and a database commits a
transaction whole. Tick sessions: Commit Selected Sessions / Rollback
Selected Sessions (with none ticked, the highlighted session); or
Commit All / Rollback All in Transaction. The picked session's statements
are listed below with Undo From Here (savepoints Pagona sets before each
change while auto-commit is off). Amphibian docks it at the bottom (as
Toad); Plume uses a window. Auto-commit is off for new tabs by default
(Edit > Options). PostgreSQL DDL counts as pending; Oracle and MySQL DDL
commits by itself and clears the list. The tab the panel is for is ticked
again whenever it comes back with new work. Committing a single statement
out of a session (roll back and re-run the rest) was left out: re-running
is unsafe with triggers, sequences and time-based values. Randy (2026-10-22): Toad's user base
is huge, so Amphibian matching its places and words is about adoption.

## Seattle layout (mockup approved and built 2026-10-23)

SSMS 22's arrangement (from Randy's screenshots, default settings), Pagona's
look and icons. SSMS things Pagona doesn't have (Git, Project, Extensions,
Search box, Sign in, What's new, XEvent Profiler, Replication, Always On)
are left out rather than shown dead.

```
SQLQuery1.sql - HOMEONE.tester (homeone\randyw (83))* - Pagona
File Edit View Query Tools Window Help
[back fwd | New v save saveall | New Query, new query same connection | undo redo | Activity Monitor]
[Connect, Change Connection, [database v] Execute Stop Parse | est. plan, actual plan | comment uncomment outdent indent]
Object Explorer       | [TEST SQLQuery1....andyw (83))* x] [SQLQuery2... x]
 Connect v + x stop   | editor
 filter refresh AM    | [100% v] problems found          Ln, Ch | TABS | CRLF | UTF-8
 HOMEONE (SQL Server  | [Results] [Messages] [History]
  17.0.1000.7 - login)| grids, several result sets stacked in the one tab
                      | ok Query executed successfully.  TEST  server (17.0 RTM)  login (spid)  db  time  Row, Col  rows
Ready
```

- Query menu always present (Linux can't add a menu once the window is
  up); in SSMS it appears with a query window. It holds Execute, Cancel,
  Parse, the plan items, Change Connection, Transactions (n waiting)...
- No DBA menu: as in SSMS, DBA screens open from Object Explorer (server
  right-click: Activity Monitor = Sessions and Locks; Security > Logins =
  Users and Roles; object right-click: Who Can Do What) and the Activity
  Monitor buttons. Tools holds Options... and the Pagona DBA Log.
- Server folders Pagona can open: Databases, Security, Server Objects,
  Management, SQL Server Agent. Database folders: Tables, Views, Synonyms,
  Programmability (Stored Procedures, Functions, Database Triggers, Types,
  Sequences), Storage, Security. Other engines keep their own folders.
- Query status bar as SSMS's, colored by environment (SSMS's default is
  yellow for all) with the environment word.

Decided 2026-10-23:

1. Several result sets are stacked in the one Results tab, as SSMS does
   (Plume and Amphibian keep Results 1, 2, ... tabs).
2. Commit and Rollback: as SSMS, no toolbar buttons. Transactions stays
   reachable from the Query menu and the status bar.
3. Auto-commit: its own setting for Seattle, "Seattle tabs start with
   auto-commit on", on by default (SSMS runs with implicit transactions
   off, so each statement commits unless BEGIN TRAN). Plume and Amphibian
   keep "New tabs start with auto-commit on", off by default. Closing with
   an open transaction asks SSMS's question: "There are uncommitted
   transactions. Do you wish to commit these transactions before closing
   the window?"
4. Results to Text / File left out for now; exporting and copying from the
   grid to be discussed as their own piece.

Built notes:

- Object Explorer lists only the servers in use (connected in Object
  Explorer or in a tab); Connect to Server (the connection window) adds
  one, connects it, opens and selects it, and the empty first tab connects
  too. New Query opens on what's selected in Object Explorer.
- No Details panel under Object Explorer; Filter shows the filter box under
  the bar.
- Database box: the tab's database (and PostgreSQL's schema next to it).
- Stacked result sets: one grid per possible result set (20) is made when
  the tab is built, because GTK3 draws a grid made later at its first size.
- Seattle keys: Ctrl+N new query, Ctrl+F4 close, Alt+Break cancel (Ctrl+T
  and Ctrl+W still work).
- Help is left out (nothing to put in it yet).

## DDL warning (built 2026-11-02)

Oracle and MySQL commit the open transaction when they run DDL (CREATE,
ALTER, DROP, TRUNCATE, RENAME, GRANT, REVOKE, COMMENT). With auto-commit off
and changes waiting, Pagona asks before anything runs:

- Changes pending in the tab: the question names the DDL and up to three
  pending statements ("...and N more"). Commit and Run / Rollback, then Run
  / Review... (opens the Transactions panel; nothing runs) / Cancel.
- Nothing pending yet, but the script itself changes data before its DDL:
  one question before the run, naming the statement: Run Anyway / Cancel.
- PostgreSQL and SQL Server keep DDL in the transaction: never asked.
- Tools > Options: "Warn before DDL commits pending changes (Oracle,
  MySQL)", on by default (json warnDdlCommit).

## Describe window (asked for 2026-10-23, after the first demo)

A Toad user pressed F4 on a table in another schema in Amphibian and nothing showed:
the old Describe looked only in the login's own schema, by the exact text,
and put rows in the grid. Now F4 (Amphibian) and Alt+F1 (Plume, Seattle)
open one Describe window, in the layout's look (header, bar and surface
colors), for the name under the cursor.

- Lookup, on the connection's Explorer session (never the tab's):
  - Oracle as Oracle resolves names: the schema written (or the tab's),
    its private synonyms, public synonyms, then any schema the login can
    see; unquoted names upper-cased. The header says "via public synonym X".
  - PostgreSQL: the schema written, else the tab's schema and the
    search_path, then any user schema; unquoted names lower-cased.
  - MySQL, SQL Server: by name, the tab's database or schema first.
  - Nothing found: a line in Messages and the status ("X: nothing by that
    name"), never silence.
- Pages (read when first shown; Refresh or F5 reads again; Esc closes):
  - Table: Columns, Indexes, Constraints, Triggers, Data (first 100 rows),
    Script, Grants, Used By.
  - View, materialized view: Columns, Data, Script, Grants, Used By.
  - Procedure, function: Arguments, Script, Grants, Used By.
  - Oracle package: Script (spec and body), Grants, Used By.
- Used By: Oracle all_dependencies plus foreign keys; PostgreSQL views
  (pg_depend) and foreign keys; SQL Server sys.sql_expression_dependencies
  and foreign keys; MySQL views, foreign keys and routines whose text
  mentions the name.
- "Show in Object Browser" (Amphibian), "Show in Object Explorer"
  (Seattle), "Show in Explorer" (Plume) selects the object there.
- One window, several objects (Randy, 2026-11-02): F4 / Alt+F1 adds the
  object as a tab in the open window (or brings its tab forward); + asks
  for a name; each object tab has an x (middle-click works too) and the
  window closes with the last one. Pages sit in a second row under the
  objects.
- The window belongs to the main window (PopupParent), so clicking back
  into Pagona doesn't send it behind; it closes only with Close, Esc or
  its last x.
- Tabs are drawn by Pagona so they read as tabs in every look: the
  selected tab is white, bold, joined to the page and marked along its top
  in Pagona blue; the others are shaded, outlined and sit a little lower;
  a line runs under each row. Not by color alone.

## Logo and app icon (chosen 2026-10-23)

Pagona means peahen, so the mark is a peahen, drawn as she really looks
(Randy raised a pair): no train, a short fan crest of bare pale shafts with
brown, green-edged tips that droop back, a chestnut crown and a brown band
behind a big round eye, a white face and throat, and a green neck that fades
to brown-gray lower down. Concepts and rounds are on the "Pagona Peahen Logo
Concepts" canvas (board E is the chosen one, board F the icon blues).

- Logo: art/pagona-logo.svg (art/pagona-logo-512.png).
- App icon: the same peahen on #1E8DBC (two steps lighter than #016795;
  Randy: "1 is too dark, 4 is almost azure"). art/pagona-icon.svg for 32 px
  and up, art/pagona-icon-small.svg, a simpler drawing (three crest tips,
  cap, eye, beak, neck), for 16 and 24 px.
- pagona.ico (16, 24, 32, 48, 64, 128, 256) sits beside pagona.lpi, which
  names it (Icon 0), so it becomes the program's icon: window, taskbar,
  Explorer. Every size inside it is a plain 32-bit bitmap: the LCL can't
  read PNG-compressed icon entries ("Bitmap with unknown compression").
  PNGs for Linux and the installer: art/icons/pagona-<size>.png.

## Exporting and copying from the grid (sketched and built 2026-10-23)

- Right-click menu on every result grid, all layouts: Copy (Ctrl+C, tab-
  separated; titles when whole rows are selected), Copy with Headers
  (Ctrl+Shift+C), Copy As (CSV, INSERT Statements..., IN List, JSON, Column
  Names), Select All (Ctrl+A), Save Results As... (Export Dataset... in
  Amphibian). A right-click outside the selection selects that cell first.
- One cell selected: Copy As takes the whole result; IN List takes the whole
  column. IN lists skip NULLs and repeats.
- Values are text in Pagona's result sets, so INSERT statements and IN lists
  quote every value but NULL; names are quoted as the engine quotes them
  (` [ ] " ) only when they need it; SQL Server text with accents gets N'...'.
  INSERT asks for the table, guessed from the query's first FROM.
- Save Results As: CSV, tab-delimited, JSON or INSERT statements; column
  names first (CSV, tab), NULL as nothing or the word NULL, UTF-8 with BOM
  (on by default, for Excel). No Excel file for now (Randy: CSV is enough).
- Rows: the rows shown, or all rows: runs the query again with no row limit
  and no extra question ("it's their database"). Not offered when the
  query (or SQL Server batch) has a word that changes something (INSERT,
  UPDATE, DELETE, EXEC, CREATE, INTO, LOCK, ...), when the tab is busy, or
  when every row is already shown.
- Seattle only (the words are SSMS's): Query > Results To > Results to
  Grid (Ctrl+D), Text (Ctrl+T), File (Ctrl+Shift+F), kept per tab. Text is
  SSMS's fixed-width layout with "(n rows affected)"; File asks for a .rpt
  before the run and writes the same text (UTF-8 with BOM).

## Looks per layout (mockup approved and built 2026-10-23)

The frame around the work takes each layout's feel: menu bar, toolbars,
panel headers, tab strips, status bar. The editor, grids, syntax colors and
environment colors are the same in every look. Setting: Look, "Match
layout" by default, or any look by name (as keymaps).

| Role | Plume | Amphibian (Toad's older Windows) | Seattle (SSMS 22) |
|---|---|---|---|
| Surface | #F7F8FA | #ECE9E2 | #EEF3F9 |
| Menu bar | #F7F8FA | #F0F0F0 | #C9D8EA |
| Toolbars | #F7F8FA | #E4E1DA | #D9E4F1 |
| Lines | #D7DBE1 | #ADA9A0 | #A9BCD3 |
| Panel headers / title strips | #F7F8FA | #D6DEE8 | #D9E4F1 |
| Status bar | #F7F8FA, dark text | #E4E1DA, dark text | #3C4654, white text |

Seattle's query status bar keeps the environment color. Every pair gets
the contrast check the editor colors had.

Built notes: View > Look (Match Layout, Plume, Amphibian, Seattle) changes
the colors on the spot. The menu bar takes the look's color on Windows
only (other desktops draw it from their theme). Grid titles and row
numbers, the editor gutter and the editor stay Plume's in every look. On
Linux the Keymap and Look menus use check marks instead of radio items
(GTK checked a group's first item by itself and reported it as a click,
which also reset the keymap choice).

Later: Plume Dark, for Plume only, with environment and syntax colors
re-tuned for dark (own mockup).

## Amphibian toolbar icons (decided 2026-10-22)

Pagona's own drawings at 16 px. Run, Run as Script and Stop are bold
filled (white shape, heavier outline, the action part solid color). All
other buttons are two-tone: ink outline, with the part that says what the
button does in its group's color (run green, session orange, DBA purple,
cancel/rollback red, files and editor blue, text tools gray). Shapes carry
the meaning; color only helps the eye. Every button has a tooltip with its
name and key.

## DBA menu: look, but can't touch (decided 2026-10-22)

There is no DBA Mode any more. Everyone gets the DBA menu, every Explorer
folder (the rarely used ones inside a collapsed "More" folder), and the
DBA buttons in the toolbar's Add Button list, on Windows and Linux alike.
Anyone can look; what a login can change is decided by the database's
privileges alone. Where Pagona can tell the login lacks a right, the
buttons that change things are grayed and their tooltip names the right
(adapter MissingRight: 'kill', 'accounts'); one's own sessions can always
be canceled or ended. When it can't tell (e.g. a MySQL login with
roles), the button stays on and the server's answer decides.
(First built as a View > DBA Mode toggle; replaced the same day.)

Rules for every DBA screen:

- Opens as a tab on the connection selected in the Explorer (when the
  Explorer has focus) or else the active tab's connection.
- A bar under the band: Refresh, Auto-refresh (off, 5, 10, 30, 60 s), the
  screen's actions, and a plain-words line saying what's shown and what
  the buttons will act on.
- Anything that changes the server asks first, naming the environment,
  the connection and the person affected; the default answer is No.
- Every such action is written to the Pagona DBA Log (DBA > Pagona DBA
  Log; `dba-log.txt` in the settings folder): when, where, as whom, what,
  and the exact statement.
- Done through SQL only. Never: editing conf files (pg_hba.conf,
  my.cnf, ...), OS service control, or server shell credentials.
- Engine-specific items are grayed out on other engines, with a tooltip
  saying which engine has them.

The DBA menu (planned; built items marked):

```
DBA
├─ Morning Check
├─ Sessions                      built (MySQL, PostgreSQL)
├─ Locks and Blocking            built (MySQL, PostgreSQL)
├─ Activity
├─ Users and Roles               built (MySQL, PostgreSQL)
├─ Who Can Do What               built (MySQL, PostgreSQL)
├─ Copy Access
├─ Storage and Growth
├─ Server Settings
├─ Server Log
├─ Jobs
├─ Replication
├─ Maintenance ▸  Vacuum/Analyze/Reindex · Optimize/Check · Recompile Invalid
├─ Schema Compare
├─ Export ▸       Data Pump · pg_dump · mysqldump
├─ Oracle ▸       Tablespaces · Alert Log · RMAN Backups · Data Guard ·
│                 Recycle Bin · AWR Report (license note: Diagnostics Pack)
└─ Pagona DBA Log                built
```

Server-side tasks that are safe through SQL and planned for these screens:
reading the server/alert log and trace files; pg_file_settings,
pg_hba_file_rules (read-only), pg_stat_archiver; ALTER SYSTEM, SET
PERSIST, ALTER SYSTEM ... SCOPE, pg_reload_conf, log rotation; MySQL
RESTART (strong confirmation); maintenance; dropping inactive replication
slots; purging binlogs; adding datafiles; replica start/stop; flashback
from the recycle bin; Data Pump; AWR.

Sessions: Session, User, Machine, Program, Database, State, Time,
Statement, Note ("this tab" marks Pagona's own sessions, which Kill
refuses). Buttons: Show Statement, Cancel Query, Kill Session.

Locks and Blocking: one row per waiting session: Waiting, Waiting user,
Waiting for, Blocked by, Blocker user, Blocker state, Blocker time, Head of
chain, Object, Waiting statement, Blocker statement. The buttons act on
the blocker: Show Statement, Cancel Blocker's Query, Kill Blocker.
PostgreSQL uses pg_blocking_pids and pg_locks (waitstart on 14+); MySQL
uses sys.innodb_lock_waits, falling back to information_schema's InnoDB
tables (MariaDB, older MySQL). Without the privilege to see other users'
statements the server says so in the cell ("<insufficient privilege>").

GTK3 (Linux build): the menu bar can't add, show or hide a top-level
menu once the window is up; with the DBA menu always there, this no
longer matters.

Menus: File, Edit (Options... at the bottom), Query, Session, View, DBA.
There is no Tools menu.

## Users and Roles (sketch approved and built 2026-10-22)

- Left: accounts list (Name, Kind, Login; MySQL adds Host). Show: Users /
  Roles / All, plus a "Show system accounts" checkbox, off by default
  (hides mysql.sys and friends, pg_* roles).
- Right: tabs General, Member Of, Members, Privileges, SQL.
- Edits are staged; a "Will run:" box shows the SQL live; Apply confirms
  (environment, connection, account; default No) and logs to the DBA log
  with passwords written as ****.
- New User has "Copy access from" (roles and grants of an existing
  account); the Copy Access screen offers the same.
- Privileges tab: Grant... (what kind of thing, which one, privilege
  boxes that fit it, WITH GRANT OPTION) and Revoke Selected.
- Drop first lists what the account owns; on PostgreSQL it offers
  REASSIGN OWNED BY ... TO another role, then DROP OWNED, then DROP ROLE.
- MySQL: account locked, password expiry, per-hour limits, require TLS;
  roles on 8.0+ (grayed with a tooltip on older servers).
- Oracle later: profile, default/temporary tablespace, quotas, system
  privileges.
- Built as: the adapter describes an account's settings (TpgnAccountAttr:
  bool, number, text or choice), so each engine shows its own on General
  without new screen code. MySQL roles need 8.0 (grayed with a note
  otherwise); a granted MySQL role is also made a default role (SET
  DEFAULT ROLE ALL) so it works at login. PostgreSQL grants shown are the
  current database's (each database keeps its own).

## Who Can Do What (sketch approved and built 2026-10-22)

- Pick an object (PostgreSQL: table/view, schema, sequence, function,
  procedure, database; MySQL: database, table/view, procedure, function);
  the grid lists Who, Kind, Can do, How, Can grant.
- How: direct; through role X (untick "Include access through roles" for
  direct only); whole database / whole server (MySQL db.* and *.*);
  owner / superuser (shown only with "Show owners and superusers"
  ticked); PUBLIC.
- PUBLIC is called out in a line above the grid ("Everyone can EXECUTE
  this", like the Everyone group on a Windows share), with Revoke from
  PUBLIC offered.
- Grant... reuses the Grant dialog with the object filled in (pick who);
  Revoke Selected works on direct grants only (a role row says which
  role to revoke); Open Account jumps to Users and Roles; Copy puts the
  list on the clipboard.
- Explorer right-click on a table, view, function, procedure or schema:
  Who Can Do What, opened on that object.
- Built as: adapter ObjectAccess / PublicAccess / RevokePublicSQL.
  PostgreSQL reads the object's ACL (or acldefault when none was ever
  set, which is where PUBLIC's EXECUTE on functions comes from) and walks
  pg_auth_members for roles; the owner is one "everything / owner" row.
  MySQL reads information_schema's privilege tables plus mysql.procs_priv,
  counts db.* and *.* grants for each table, and follows mysql.role_edges.
