# Pagona build history

Each change is a git commit.

## 0.1.0: first Windows release
- License: GPL 3 or later (LICENSE, a notice at the top of every source
  file, THIRD-PARTY-NOTICES.md for the libraries).
- Help > About Pagona (all layouts): the peahen, the version, the
  copyright, the license and the source link.
- Version 0.1.0 in pagona.exe's Windows properties.
- Installer (NSIS): all users, Program Files, Start menu and optional
  desktop shortcut, optional PostgreSQL and MySQL client libraries (not
  ticked), license page, uninstaller that keeps settings unless asked.
- Portable zip with the client libraries in client-libs.
- GitHub workflow: a version tag builds both and makes a draft release.
- redist: libmysql.dll (MySQL 8.0.46 client).

## Warning before Oracle or MySQL DDL commits pending changes
- With auto-commit off, running DDL with changes pending asks first:
  Commit and Run, Rollback then Run, Review..., or Cancel. A script that
  changes data and then runs DDL asks once before it starts.
- Tools > Options: "Warn before DDL commits pending changes (Oracle,
  MySQL)", on by default.

## Describe window: one window, several objects
- The window stays in front of Pagona (it went behind the main window when
  you clicked back into the editor, and had no taskbar button to bring it
  back).
- F4 / Alt+F1 adds objects as tabs in the open window; + adds one by name;
  each tab closes with its x.
- Clearer tabs: selected white, bold and marked; the others shaded and
  outlined.

## Describe window
- F4 (Amphibian) and Alt+F1 (Plume, Seattle) open a Describe window for the
  name under the cursor, in the layout's look: Columns, Indexes,
  Constraints, Triggers, Data, Script, Grants, Used By (fewer for views,
  procedures and Oracle packages), and Show in Schema Browser / Object
  Explorer / Explorer.
- Names are found as the database finds them: Oracle through your schema,
  private and public synonyms (Banner's SATURN.SPRIDEN from "spriden"),
  case-insensitively; PostgreSQL through the search_path. Nothing found
  now says so.
- Oracle: Select Top Rows uses FETCH FIRST (it used LIMIT).

## Peahen logo and app icon
- Logo and app icon (the peahen on #1E8DBC) in art/, with PNGs from 16 to
  512 px; pagona.ico is the program's icon on Windows and Linux.

## Exporting and copying from the grid
- Grid right-click menu: Copy, Copy with Headers (Ctrl+Shift+C), Copy As
  (CSV, INSERT statements, IN list, JSON, column names), Select All,
  Save Results As (Export Dataset in Amphibian).
- Save Results As: CSV, tab-delimited, JSON or INSERT statements, the rows
  shown or all rows (runs the query again with no row limit).
- Seattle: Query > Results To > Grid (Ctrl+D), Text (Ctrl+T), File
  (Ctrl+Shift+F). Ctrl+T no longer opens a new tab in Seattle (Ctrl+N does).
- Side by Side keeps the tabs' order, and brings them back together from
  either side.

## MySQL / MariaDB: fresh reads with auto-commit off
- A tab with auto-commit off and nothing pending now ends its reads-only
  transaction before each run, so it sees what other sessions have
  committed (MySQL's REPEATABLE READ otherwise keeps showing the data as of
  the tab's first SELECT). A tab with pending changes, or one that ran
  SELECT ... FOR UPDATE / LOCK IN SHARE MODE, LOCK TABLES or CALL, keeps
  its transaction until Commit or Rollback.

## SQL Server: first real runs (SQL Server 2025, ODBC Driver 18)
- Connects with Windows Authentication, Encrypt Mandatory and Trust server
  certificate; GO batches, two result sets, Alt+F1 and the plan checked.
- The estimated plan uses SHOWPLAN_ALL: one grid with the operation tree and
  SSMS's tooltip columns (Physical Operation, Logical Operation, Estimated
  Number of Rows and Executions, I/O, CPU and Subtree Cost, Warnings).
- Msg 262 (no SHOWPLAN permission) adds a line saying how a DBA grants it.
- Seattle and Amphibian: a failed plan request now shows Messages.

## SQL Server adapter
- New database type SQL Server, through ODBC (Microsoft's ODBC Driver 18 or
  17 for SQL Server, Windows' own "SQL Server" driver, or FreeTDS on Linux),
  loaded at run time; pgnOdbc is Pagona's own small ODBC client.
- Connection: server name (HOST, HOST\INSTANCE, host,port), Windows
  Authentication (no password asked) or SQL Server Authentication, Encrypt
  Mandatory / Optional / Strict, Trust server certificate.
- GO splits batches (GO n too); each batch is sent whole. PRINT, "(n rows
  affected)" and other server messages go to Messages; errors read as SSMS
  writes them ("Msg 208, Level 16, State 1, Line 3"), and the editor jumps
  to the line.
- Explorer: Databases > Schemas > Tables (Columns, Indexes, Triggers),
  Views, Indexed views, Functions, Procedures, Triggers, Sequences,
  Synonyms, User-Defined Types; Users, Database Roles; server Logins,
  Server Roles, Linked Servers, SQL Server Agent Jobs. Details: columns
  (identity, defaults, descriptions), indexes, triggers, grants.
- Routines open from OBJECT_DEFINITION and save with CREATE OR ALTER
  (grants kept; an unqualified name goes to the schema it's in). New
  procedure / function / trigger templates; Execute writes EXEC with
  OUTPUT parameters, or SELECT for functions.
- Explain: SET SHOWPLAN_TEXT (estimated plan). Describe: sp_help. Select
  Top Rows: SELECT TOP (n).
- Auto-commit off = implicit transactions; savepoints = SAVE TRANSACTION;
  DDL waits for Commit too. Tabs switch database with USE.
- Seattle: the server's full version in Object Explorer, login (session id)
  in the query status bar. Windows Authentication shows the Windows login.
- Connection dialog in two columns (it had grown taller than a laptop
  screen).
- Result sets can carry server messages (PostgreSQL notices could use it
  later).

## Looks per layout
- View > Look: Match Layout (default), Plume, Amphibian, Seattle. The frame
  (toolbars, panel headers, title strips, status bar, panels) takes the
  look's colors: Amphibian's warmer Windows grays, Seattle's light blue
  with a dark status bar. Changes on the spot.
- Windows: the menu bar takes the look's color too.
- Editor, grids and environment colors unchanged in every look.
- Linux: Keymap and Look menus use check marks (GTK's radio groups
  reported their own first item as a click and reset the choice).

## Seattle layout (SSMS)
- View > Layout > Seattle: SSMS 22's arrangement and wording, Pagona's look
  and icons (see the README and design.md).
- Connect to Server at start; Object Explorer with its own bar (Connect,
  Disconnect, Filter, Refresh, Activity Monitor) showing the servers in use,
  named "server (engine version - login)"; right-click a server for New
  Query, Activity Monitor, Locks and Blocking, Users and Roles.
- Standard toolbar (open, save, New Query, undo, redo, Activity Monitor)
  and SQL Editor toolbar (Connect, Change Connection, database box,
  Execute, Cancel, estimated plan, comment, indent).
- Menus File, Edit, View, Query, Tools, Window with SSMS's words; no DBA
  menu (as SSMS).
- Query tabs named as SSMS (SQLQuery1.sql - server.database (login (id)));
  Ln / Ch line under the editor; Results with several result sets stacked,
  Messages, Execution Plan, History; switches to Messages on an error or
  when there's nothing to show.
- SSMS's query status bar in the environment's color, with the environment
  in words, server (version), login (session id), database, time, rows.
- Seattle tabs start with auto-commit on (Edit > Options: "Seattle tabs
  start with auto-commit on"); closing with uncommitted work asks SSMS's
  question (Yes commits, No rolls back).
- Adapters report their own session id (PostgreSQL pid, MySQL connection
  id, Oracle SID).
- Seattle keys: Ctrl+N, Ctrl+F4, Alt+Break.

## Transactions panel fixes
- Commit Selected Sessions / Rollback Selected Sessions (were "Selected"):
  rows are sessions. With none ticked, the highlighted session is used.
- The tab the panel is for (docked: the active tab) is ticked again when it
  comes back with new work, so the buttons aren't left greyed out after a
  commit.
- The statements heading says they are committed or rolled back together;
  the question names the tab and count ("Commit 2 statements in Query 1 on
  TEST reports-db?").
- Docked panel parked out of sight when closed (at height 0 it still drew on
  GTK3).

## Transactions panel (as Toad's)
- Pending Statements becomes Transactions: every tab with work waiting
  (environment, connection, tab, connected, in transaction since, how many
  statements), tick sessions and Commit Selected / Rollback Selected, or
  Commit All / Rollback All in Transaction. Each tab is its own session, so
  whole sessions commit or roll back; nothing is re-run.
- Below it, the statements of the session picked, with Undo From Here.
- Amphibian docks it at the bottom of the window, above the status bar, as
  Toad does (Close folds it away); Plume shows it in a window. Review... in
  the close question always opens the window.
- Commit's drop arrow, Session and Window menus: Transactions (n waiting).

## Auto-commit off by default; pending work across tabs
- New tabs start with auto-commit off, as in Toad (Edit > Options: "New
  tabs start with auto-commit on" to change it).
- PostgreSQL DDL (ALTER, CREATE, DROP, ...) counts as pending: PostgreSQL
  keeps it in the transaction until Commit. Oracle and MySQL commit DDL by
  themselves, so there it clears the list.
- Commit, Rollback and Commit's menu stay enabled while any tab has work
  waiting. On a tab with nothing pending they open Pending Statements on
  the tabs that do; with several, a picker at the top switches tabs.
- Closing a tab, switching its connection or exiting asks about commit
  only when statements are actually waiting (with auto-commit now off by
  default, it no longer asks after DDL on Oracle or MySQL, which commits
  by itself).
- The status bar says when work waits in another tab ("Nothing pending
  here · 2 waiting in Query 1").

## Pending Statements (auto-commit off)
- Commit has a drop arrow, as in Toad: Commit, Roll Back, Pending
  Statements (n). Also in the Session menu, and clicking "n uncommitted
  statements" in the status bar opens it.
- Pending Statements lists what the tab ran since its last commit (time,
  rows changed, statement) with Commit All, Roll Back All and Undo From
  Here. A transaction commits as a whole, so Undo From Here undoes the
  selected statement and every one after it, keeping the earlier ones.
- With auto-commit off Pagona sets a savepoint before each statement that
  changes data. A statement that fails is undone on its own and earlier
  pending work stays (PostgreSQL no longer throws the whole transaction
  away on one error).
- Closing a tab, switching its connection, or exiting with uncommitted
  work now says how many statements wait, with Review..., Commit, Roll
  Back and Cancel.

## Smoother text, readable grids, tab order kept
- All of Pagona's text asks Windows for ClearType smoothing (editor,
  Messages, grids, menus, toolbars, dialogs), whatever the system's own
  setting: no more jagged letters.
- Grid lines are much darker (#A0A8B4, and #7F8894 under the titles), in
  every grid: results, Details, Schema Browser, DBA screens, connection
  list.
- Side by Side keeps the tab order: a tab moved to the right sits among
  the right-hand tabs in the order they had, and moving it back puts it
  where it was.

## Release build mode
- pagona.lpi has a Release build mode: optimized (-O2), smart-linked
  (-CX, -XX), no debugger information, symbols stripped (-Xs). About 8 MB
  instead of 69. Default stays the debugging build.

## Amphibian: the New Connection window
- Session > New Connection (and the toolbar button) opens Toad's kind of
  login window: every saved connection listed with its environment in
  words, name, user, database or TNS alias, engine and server. Connect,
  double-click or Enter connects; New..., Edit... and Delete... change the
  saved list right there.
- The editor in view takes the connection if it has none yet; otherwise a
  new editor opens on it.
- Amphibian opens the window when it starts (or is switched to) with
  nothing connected, as Toad does.
- Session > Edit / Delete Connection work in Amphibian (they needed the
  Explorer before).
- The Session picker reads the saved list directly.

## Layout switch without a restart (Windows)
- View > Layout now rearranges the window on the spot on Windows: menus,
  toolbars, bars and panels are rebuilt while open tabs, their sessions,
  uncommitted work and remembered passwords stay. On Linux (GTK) Pagona
  still restarts, since GTK can't swap the menu bar or re-lay out moved
  panels reliably while running.
- The Layout menu shows the right layout checked on Linux.
- The Session / Database / Schema pickers size their panel to fit.

## Amphibian layout (Toad's arrangement)
- View > Layout: Plume or Amphibian (Seattle to come). Pagona restarts to
  rearrange the window, asking about unsaved work first.
- Amphibian, top to bottom as in Toad: menus File, Edit, Search, Session,
  Editor, Database, View, Window; a small-icon main toolbar (New Editor,
  Schema Browser, New / End Connection, Session Browser, Commit,
  Rollback, Users and Roles, Locks); a session bar, one button per open
  connection (USER@NAME with its environment as text); a window bar
  (Editor, Schema Browser, each DBA screen); the Editor's own toolbar
  with Session, Database and Schema pickers at the right; editor tabs;
  Toad's result tabs: Messages, Data Grid, DBMS Output, Explain Plan,
  History. Messages come forward on an error or when there are no rows.
- Toad's words for commands: Execute Statement, Execute as Script, Stop
  Execution, SQL Recall, End Connection, Session Browser, Compile.
- Database > Schema Browser: database and schema pickers, object types as
  buttons (rare ones under More), a Toad-style filter (SPR% starts with
  SPR, HOLD contains HOLD), the list, and the Details tabs for what's
  picked. Double-click opens code in the Editor; right-click has the
  Explorer's full menu.
- Toolbar icons drawn by Pagona: Run, Execute as Script and Stop bold and
  filled; the rest two-tone (the action part in its group's color).
  Both toolbars can be rearranged (right-click).
- Title bar as in Toad: RLMORROW@DEV9 - Pagona - [Editor (Query 1)].
- DBMS_OUTPUT from Oracle lands in the DBMS Output tab.
- Every layout: Edit (Search in Amphibian) > Find (Ctrl+F), Find Next (F3),
  Replace (Ctrl+R; Ctrl+H in Seattle); Indent / Unindent lines.

## Oracle (first version, not yet tried against a server)
- Oracle connections through the Oracle client (Instant Client, as Toad
  uses): pick a TNS alias from your tnsnames.ora, or give host, port and
  service name. Pagona finds tnsnames.ora the way Toad does (TNS_ADMIN,
  the client's folder, ORACLE_HOME), or you point it at one; the dialog
  says how many aliases it found.
- Explorer: the database, then schemas (Banner's GENERAL, SATURN, ...,
  system schemas hidden) with Tables, Views, Materialized Views,
  Functions, Procedures, Triggers, Packages, Sequences, Synonyms, Types,
  Invalid Objects; More holds Database Links, Scheduler Jobs and
  Materialized View Logs. Server level: Users, Roles, Tablespaces; More:
  Profiles, Directories. Packages open spec and body together.
- The editor understands SQL*Plus-style scripts: PL/SQL blocks and
  CREATE PROCEDURE/PACKAGE/TRIGGER end at a "/" line, q'[...]' quotes,
  SET SERVEROUTPUT ON/OFF, EXEC, PROMPT, SHOW ERRORS; other SQL*Plus
  settings (SET ECHO, SPOOL, ...) are skipped.
- DBMS_OUTPUT is on for every tab; what a block prints comes back as a
  "DBMS Output" result.
- Code that saves but doesn't compile is reported with its errors and
  lines ("Saved, but it doesn't compile: ... is now INVALID").
- Explain plan (EXPLAIN PLAN + DBMS_XPLAN), Cancel (ALTER SYSTEM CANCEL
  SQL, Oracle 18c on), Oracle keywords in the editor.
- DBA: Sessions and Locks (V$SESSION), Kill; Users and Roles (lock,
  expire, profile, tablespaces, roles, object and system privileges, DDL
  without the password hash); Who Can Do What; drop a user with CASCADE
  (asked for explicitly).

## DBA: Who Can Do What
- DBA > Who Can Do What (MySQL, PostgreSQL): pick a table or view,
  schema, sequence, function, procedure or database and see everyone who
  can use it: what they can do, how (direct, through role X, whole
  database, whole server, owner, superuser) and whether they can pass it
  on. "Include access through roles" on by default; "Show owners and
  superusers" and "Show system accounts" off.
- What PUBLIC (everyone) may do is called out above the list, e.g.
  "Everyone can EXECUTE this (granted to PUBLIC)", with Revoke from
  PUBLIC.
- Grant... (pick who and what on this object), Revoke Selected (direct
  grants; for the rest it says where the access comes from), Open Account
  (Users and Roles on that account; double-click does the same) and Copy.
- Explorer right-click on a table, view, function, procedure, schema or
  database: Who Can Do What, opened on it.

## Look, but can't touch
- DBA Mode is gone. The DBA menu is always there (Windows and Linux),
  every Explorer folder is shown, and the DBA toolbar buttons are always
  offered. What a login can change is up to the database's privileges.
- The rarely used PostgreSQL folders sit inside a collapsed "More" folder
  (Casts, Event Triggers, Foreign Data Wrappers, Languages, Publications,
  Subscriptions; per schema Aggregates, Collations, Foreign Tables, FTS
  objects, Operators). Extensions, Domains, Types, Login/Group Roles and
  Tablespaces are shown with the rest.
- Without the right, buttons that change things are grayed and say what's
  missing: Users and Roles becomes look-only (needs CREATEROLE / CREATE
  USER); Cancel and Kill work on your own sessions only (others need
  pg_signal_backend / CONNECTION_ADMIN).
- Sessions on PostgreSQL now lists other users' sessions for a login
  without pg_read_all_stats (they were left out); their hidden details
  show as (hidden) / <insufficient privilege>.
- Explorer right-click: Copy Definition puts the CREATE statement of a
  table, view, procedure, function or trigger on the clipboard.
- Options moved to the Edit menu; the Tools menu is gone.
- Grant dialog: the privilege boxes take only the room they need and the
  window grows or shrinks with them; narrower pickers, "Let <account> grant these to others
  (WITH GRANT OPTION)" under the privileges, a taller Will run box, and
  MySQL's own databases (information_schema, performance_schema, mysql,
  sys) are no longer offered.

## Users and Roles: Grant
- The Privileges tab has a Grant... button. Choose what it's on (MySQL:
  a whole database, a table or view, a procedure, a function, or
  everything on the server; PostgreSQL: a table or view, all tables in a
  schema, a schema, a sequence, a function, a procedure, or a database),
  then which one, then tick the privileges; the boxes offered fit what
  was chosen. "Can pass them on" adds WITH GRANT OPTION. Will run shows
  the statement; it asks first and goes to the DBA log.

## DBA: Users and Roles
- DBA > Users and Roles (MySQL, PostgreSQL) opens a tab with the accounts
  on the left (Users and roles / Users only / Roles only, a filter, and
  "Show system accounts", off at first) and the one picked on the right:
  - General: its settings, the engine's own (PostgreSQL: log in,
    superuser, create databases/roles, inherit, replication, bypass RLS,
    connection limit, password valid until; MySQL: locked, password
    expiry and lifetime, connection and query limits, requires TLS).
    Nothing runs until Apply; "Will run:" shows the SQL as you change
    things.
  - Member Of / Members: Grant Role, Revoke, Add Member, Remove.
  - Privileges: every object grant, with Revoke Selected.
  - SQL: the statements to make the account again (no password), with
    Copy.
- New User / New Role, with "Copy access from" another account (its roles
  and grants; not its settings or password).
- Change Password. Passwords are shown and logged as ****.
- Drop lists what the account owns first. PostgreSQL: give it to another
  role (REASSIGN OWNED) or delete it, all in one transaction. MySQL:
  shows what it is definer of.
- Every change asks first (default No) and goes to the Pagona DBA log.
- Toolbar: a Users button can be added in DBA Mode.

## DBA Mode: Sessions, Locks and Blocking
- View > DBA Mode adds a DBA menu (before Tools), and DBA buttons to the
  toolbar's Add Button list. Off again, they're gone. It never limits
  anything; the database's privileges decide what you can do.
- DBA > Sessions (MySQL, PostgreSQL): who is connected, from where, with
  which program, doing what and for how long. Refresh or auto-refresh
  every 5 to 60 seconds. Show Statement, Cancel Query, Kill Session.
  Pagona's own sessions are marked "this tab" and can't be killed from
  here.
- DBA > Locks and Blocking: who is waiting, on whom, for how long, on
  which table, and whether the blocker is the head of the chain. Show the
  blocker's statement, cancel it, or kill the blocker.
- Kill and cancel ask first, naming the environment, the connection and
  the user affected (default No).
- DBA > Pagona DBA Log: every DBA action Pagona carries out is written to
  dba-log.txt in the settings folder: when, where, as whom, what, and the
  exact statement.
- Connection dialog: choosing the database type sets the port to that
  type's default; a port you typed yourself stays.
- TLS against a server that doesn't offer it now says so in plain words.

## PostgreSQL
- New database type: PostgreSQL (port 5432; TLS "require", or
  "verify-full" with a CA file). Needs libpq (see README).
- Explorer, laid out the way PostgreSQL itself groups things:
  Databases > database > Schemas > schema > Tables, Views, Materialized
  Views, Functions, Procedures, Trigger Functions, Sequences. The system
  schemas (pg_catalog, information_schema) are under Catalogs.
  - A table opens to Columns, Indexes and Triggers; double-click a
    trigger to open it.
  - Functions show their argument types, so two with the same name can
    be told apart: calc_hours(integer) and calc_hours(integer, text).
  - Each database you open gets its own session (PostgreSQL can't look
    across databases from one).
- Folders show how many things they hold: "Tables (12)". (MySQL too.)
- View > DBA Mode adds the folders a DBA needs: Login/Group Roles and
  Tablespaces; Casts, Event Triggers, Extensions, Foreign Data Wrappers,
  Languages, Publications, Subscriptions; and per schema Aggregates,
  Collations, Domains, Foreign Tables, FTS objects, Operators, Types.
  Details shows a definition for sequences, domains, enum types,
  extensions and roles.
- Query tabs on PostgreSQL have a Schema picker next to Database.
  Choosing a database reconnects the tab (it asks first if work is
  waiting for Commit); choosing a schema sets where unqualified names are
  found.
- Run and Run Script understand $$ ... $$ function bodies, E'...'
  strings, and that # and backticks mean nothing special in PostgreSQL.
- Routine tabs on PostgreSQL: Save uses CREATE OR REPLACE (one step,
  grants kept); a trigger is replaced inside one transaction. Errors
  jump to the line PostgreSQL names. If the return type changed, it says
  to drop the function first.
- Execute, New Procedure/Function, New Trigger, Grant and Drop write
  PostgreSQL's own SQL (CALL / SELECT * FROM, $$ bodies, roles instead of
  user@host, DROP FUNCTION name(types)).
- Describe works on PostgreSQL (it has no DESCRIBE statement).
- Fix: the connection, database and schema pickers keep their width.

## Procedures, functions and triggers
- Explorer: each database now has Procedures, Functions and Triggers
  folders next to Tables and Views. Double-click one (or right-click >
  Open) to open it in its own tab; if it is already open, that tab comes
  forward.
- Routine tab: a bar above the editor names what is being edited and has
  Save, Execute... and Revert. The button says Compile in the Amphibian
  layout (Toad's word) and Save in Plume and Seattle.
  - No DELIMITER lines needed; if they are there, they are understood.
  - Save checks the new version first under a test name, then replaces
    the old one and gives back the grants it had. If anything fails,
    nothing changes (or the old version is put back), Messages says why,
    and the cursor goes to the line the error names.
  - Read-only when your login can't see the definition, and it says so.
  - Revert reloads it from the database.
- Execute...: a form with one field per parameter (and a NULL box); OUT
  parameters come back as @name. Runs in a tab of its own.
- New Procedure... / New Function...: name, parameters (name, IN/OUT/
  INOUT, type) and, for functions, the return type; opens a ready-to-fill
  routine tab. New Trigger... on a table opens a trigger skeleton.
- Grant...: on tables, views, procedures and functions. Pick who and which
  rights; the database decides whether your login may grant them.
- Script As > CREATE and Drop on routines and triggers.
- Details panel, by kind of object:
  - Table: Columns | Indexes | Triggers | Grants (double-click a trigger
    to open it)
  - View: Columns | Definition
  - Procedure or function: Parameters | Definition | Grants
  - Trigger: Definition
  When your login can't read the grants, the Grants tab says so.
- The Explorer filter opens procedures, functions and triggers too.
- An empty folder fills in after you CREATE the first object in it.
- Tab titles are shortened by characters, not bytes, so a long title no
  longer shows a broken symbol.
- Fix: crash on exit ("Access violation ... extpagectrl.pas line 410").
  The tab groups are now released before their pages.
- Dialog buttons are sized to their words: SQL History's "Put in Editor"
  (was "Insert", which reads like a database INSERT) and the new forms.

## Results, Plan, History, Explorer filter, Details
- Every result set comes back: a CALL or a script with several SELECTs
  shows Result 1, Result 2, ... inside the Results tab (up to 20).
- Results grids are drawn by Pagona: bold column titles on a shaded row,
  row numbers, NULL shown as gray italic "(null)", columns sized to fit.
  Ctrl+C copies the selected cells, tab-separated (with titles when whole
  rows are selected).
- Explain puts the plan in its own Plan tab and leaves the results alone.
- History tab: every statement run this session, newest first;
  double-click puts one back in the editor.
- Scripts: the status bar shows "Running statement N of M" while a script
  runs, and Messages ends with one line that says how it went: "Script
  finished: 1,042 statements in 3.8 s, no errors" (green), or where it
  stopped (red), or that it was canceled. Scripts over 50 statements
  log only problems and that summary; Tools > Options can show every
  statement.
- Explorer filter: type part of a name. What the tree has loaded shows
  at once; a moment later every connected connection is searched
  (tables, views, procedures, functions). Double-click (or Enter) opens
  the tree to the object. Esc clears the filter.
- Details panel under the Explorer: the columns and indexes of the table
  or view selected in the Explorer or the filter results.

## Errors stand out in Messages
- Errors are red and bold on a light red background; warnings (canceled,
  not run, could not ...) are amber and bold. The words still say what
  they are ("ERROR:", "Cancel requested").
- A message of several lines stays together, its later lines indented
  under the time.
- Messages can be selected and copied as before.

## Cursor stops at the end of the line
- Clicking past the end of a line (or anywhere on a blank line) puts the
  cursor at the end of the text, as in Toad and SSMS, instead of out in
  empty space.

## Messages under the results
- Messages are no longer a tab: they sit under the results, always in
  view, with a divider you can drag to change the height (as in Toad).
- The shaded statement no longer draws marker lines between characters.

## Plume look, first part
- New editor colors (the Plume theme): keywords blue and bold, comments
  green and italic, strings, numbers, functions, data types and variables
  each with their own color. Your own tables, views, procedures and
  functions are colored too; the names come from the connection, so a
  misspelled table stays black. View > Theme > Classic brings back the
  old look.
- The statement Run will execute is shaded as the cursor moves.
- New toolbar, drawn by Pagona: flat buttons with a symbol and a word;
  Run filled in blue; Commit and Rollback outlined. Drag a button to move
  it; right-click to remove one, add one back, add a separator, or reset.
  The arrangement is saved.
- The connection controls and the environment are now one band at the top
  of each tab: PRODUCTION / TEST / DEVELOPMENT in words, in that
  environment's color, always shown. Auto-commit reads "on" or "OFF".
- Tab names start with the environment: "PROD dev9 · Query 1".
- New status bar, drawn by Pagona: environment label, connection and
  server version; uncommitted statements in red, in words; rows and time;
  cursor position.
- New Session menu: New / Edit / Delete Connection, Disconnect This Tab,
  Commit, Rollback, Auto-commit.

## Comment commands, keymaps named after layouts
- Comment, Uncomment, Toggle Comment and Block Comment (/* */) on the Edit
  menu, the editor's right-click menu, and Comment / Uncomment on the
  toolbar. They work on every selected line, with one Undo.
- Seattle's Ctrl+K Ctrl+C / Ctrl+K Ctrl+U are now recognized by the editor
  itself, so they work every time (the window-level watcher missed keys
  the editor had already taken). The second key works with or without
  Ctrl held, and the status bar shows when Ctrl+K is waiting.
- Commenting a blank line (or an empty editor) adds "-- " with the caret
  after it, ready to type.
- With no selection, commenting leaves the caret in place and nothing
  selected (a stray Enter can't wipe the line); a selection stays selected.
- Keymaps are now Pagona, Amphibian (Toad keys) and Seattle (SSMS keys).
  Amphibian: Ctrl+B / Ctrl+Shift+B. Seattle: Ctrl+K Ctrl+C / Ctrl+K Ctrl+U,
  F5 / Ctrl+E run, Ctrl+L explain. Pagona: Ctrl+/ toggle, Ctrl+Shift+/ block.
- Keymap setting can be "Match layout" (the default) or a keymap by name,
  so any layout can use any keymap. Old "Default" / "Toad" settings carry
  over.

## Comments are never run
- F5 on a commented-out line runs nothing (Messages says why), instead of
  running the statement after it.
- Statements that are only comments are skipped in scripts.
- MySQL executable comments (/*! ... */, MariaDB /*M! ... */) count as
  code, so mysqldump files run completely.

## CALL shows a procedure's rows
- Statements now run as text through Zeos's plain statement interface,
  and the server's answer decides whether there are rows. CALL shows the
  rows a procedure returns; if it returns several result sets, the first
  is shown and Messages says how many more there were.
- No more guessing from the first word of a statement.

## Newest messages first, Side by Side, Script As in a new tab
- The Messages tab shows the newest line at the top.
- The tab menu's "Split Right / Move to Other Side" is now a checkable
  "Side by Side".
- Script As always opens a new tab; no Explorer action changes the tab
  you're working in.

## F5 runs the statement (Default keymap)
- Default keymap: F5 runs the statement under the cursor (or the
  selection); Shift+F5 runs the whole editor as a script. Ctrl+Enter and
  Ctrl+Shift+Enter still work. The Toad keymap is unchanged.

## Tab bar drawn by Pagona
- Tabs use ExtTabCtrls (new package requirement) instead of the native
  tab control, which on Windows can't show close buttons.
- Close button on every tab, "+" for a new tab, middle-click close, drag
  to reorder; same look on Windows and Linux.

## Files, close buttons, refresh logging
- Open / Save / Save As SQL files; tabs are titled by file name with * for
  unsaved changes; Save / Don't save / Cancel on close and on exit.
- Close button on each tab; middle-click closes too.
- After CREATE / DROP / ALTER / RENAME the tab's Messages say whether the
  Explorer was updated, or why not.
- Ctrl+PageDown / Ctrl+PageUp also switch tabs (Linux convention).
- Client library hint in the connection dialog matches the OS.

## Query tabs, split view, Explorer, environments
- Every query gets its own tab with its own connection, database, session,
  editor, results and messages. Ctrl+T / Ctrl+W / Ctrl+Tab.
- Split view: a tab can be moved to a second group on the right.
- Explorer lists all saved connections; expanding one connects it.
  Passwords are remembered in memory for the session only.
- Environment label (Production / Test / Development) on connections,
  shown as text everywhere; color is optional.
- Explorer and database lists refresh automatically after CREATE / DROP /
  ALTER / RENAME of databases, tables and views; Refresh All everywhere.
- Select Top Rows, Describe and Show DDL open new tabs.

## Right-click menus, colors, transactions, options
- Right-click menus on the schema tree and in the editor.
- Connection colors, shown as a band with the connection name.
- DELIMITER support, so procedures and triggers run as one statement.
- Auto-commit toggle with Commit and Rollback; asks before disconnecting
  or closing with auto-commit off.
- Confirmation before DELETE, TRUNCATE and DROP (can be turned off).
- Tools > Options: row limit (0 = no limit), confirmations, keymap.
- F5 runs the selection or whole editor in the Default keymap too.
- Explain plan (Ctrl+E in the Toad keymap); Ctrl+/ comments lines.

## DDL runs as plain text
- Statements that don't return rows (CREATE, ALTER, DROP, INSERT, UPDATE,
  DELETE, ...) are sent as plain text instead of prepared statements, so
  DDL the prepared protocol rejects now runs.

## Database picker and USE
- New Database picker on the toolbar; choosing a database runs USE on the
  session, and it stays in effect for the statements that follow.
- A USE statement typed in the editor now sticks (it is sent as plain text
  instead of a prepared statement) and updates the picker.
- Selecting a node in the schema tree no longer changes the current database.

## Editor starts empty
- The SQL editor opens blank with the caret at the beginning and the focus
  in the editor, so you can start typing immediately.

## Build 3
- Fix compile error: `ShortCutToText` needs `LCLProc` in `pgnKeymap`.
- Fix warning: initialize the result in `pgnSqlSplit.StatementList`.

## Build 2
- Renamed the project from Frog to Pagona; units use the `pgn` prefix.

## Build 1
- First skeleton as "Frog": MySQL/MariaDB adapter, schema tree, background
  queries with cancel, results grid, Default and Toad keymaps.
