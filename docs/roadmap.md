# Pagona roadmap

Priority order set by Randy (2026-10-21, reordered 2026-10-23).

## Done

- The interface makes sense (Plume layout).
- Manage stored procedures and functions, as far as the login's database
  permissions allow (MySQL, PostgreSQL).
- Connects to PostgreSQL and Oracle. Oracle working at Randy's work
  (2026-10-22), side by side with PostgreSQL, through a TNS alias. TLS
  works: the office PostgreSQL server forces SSL (2026-10-23).
- The other layouts: Amphibian (2026-10-22), Seattle (2026-10-23), with
  looks per layout.

## Next, in this order (Randy, 2026-10-23)

1. The list:
   - SQL Server adapter - written 2026-10-23 (ODBC); first runs on Randy's
     SQL Server 2025 Enterprise Developer at home. Its DBA screens come with
     the DBA work.
   - Exporting and copying from the grid (with SSMS's Results to Text and
     Results to File) - built 2026-10-23.
   - Peahen logo and app icons - done 2026-10-23 (board E, icon on #1E8DBC).
   - Warning before Oracle or MySQL DDL commits pending work - built 2026-11-02.
   - Release packaging: NSIS installer and a GitHub release workflow - built 2026-11-02 (0.1.0, GPL 3 or later).
   - Table designer: a form to create and change tables, with the CREATE /
     ALTER TABLE it will run shown beside it as you edit.
   - Plume Dark: a dark theme for Plume only; environment and syntax
     colors re-tuned for contrast on dark.
2. DBA controls: the rest of the DBA menu (design.md). Built so far:
   Sessions, Locks and Blocking, DBA log, Users and Roles, Who Can Do What
   (MySQL, PostgreSQL). Oracle DBA screens (dba_* / v$) not yet tried;
   depends on one of the DBAs being willing to try them.
3. Bug hunt the Linux build (known: GTK3 file dialogs crash inside the LCL
   (CreateOpenDialogFilter), so Save, Open, Browse... and Results to File
   fail on Linux; new query tabs draw blank on GTK3;
   a second result set's grid in Plume and Amphibian may draw at its first
   size, as Seattle's did before its fix).
4. AI assistant (plan: ai-assistant-plan.md).
5. Saving passwords to the Windows credential store.

## Consider for the next release

- Oracle/PostgreSQL Compatibility window: make the Before and After panes
  editable, like the query editor (undo, find, comment/uncomment with the
  keymap's keys), so a line can be commented out and Run Both tried again
  without converting from the start. Kept read-only in 0.2.5 (Randy,
  2026-11-06). Sketch: Run Both runs what the panes hold; a Convert Again
  button re-converts Before with the current ticks; changing a tick or
  Convert Again asks before replacing hand edits in After; Copy and Save
  As take After as edited; the report says when After was edited by hand.
  Open question: with a selection, run only the selection (as F5 does)?
- Object browser: the font size can't be changed where it shows code (a
  table's CREATE statement is very small). Needs a way to change it
  (Randy, 2026-11-06).
- Oracle/PostgreSQL Compatibility, Run Both and Compare: the run uses the
  tab's own session without a savepoint, so with auto-commit off a query
  that fails on PostgreSQL leaves the tab's transaction aborted (Roll Back
  needed). Fix: a savepoint around each run, rolled back to afterward.
  The error also only shows on hover; show it in the window.

## Before release

- Done 2026-10-22: Release build mode in pagona.lpi (Default stays the debug build). Release: no debugger
  info (-g off), strip symbols (-Xs), optimization level 2 (-O2), smart
  linking (-CX, -XX). Measured 2026-10-21: 68.8 MB -> 7.9 MB.
  Build with `lazbuild --build-mode=Release pagona.lpi`.
