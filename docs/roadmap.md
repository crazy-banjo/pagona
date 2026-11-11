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

## Versions (Randy, 2026-11-10)

- 0.3.0: code completion (functions and procedures after a schema, Oracle
  package members), with what was planned for 0.2.6 (never released):
  schema names and Format in the Compatibility window, code views in the
  editor's font size, the window opening without a connection. Released
  for Windows first.
- Then the Linux build of 0.3.0 and its release: still 0.3.0, since
  making it work on Linux isn't a new feature. No RC builds: a release is
  the release.

## Found by the tests (2026-11-11), not fixed yet

- Formatter: a comment after a column's comma (col, -- note) moves to its
  own line, so it reads as the next column's. Every column of a long
  report shifts by one. tests/format/085 (known issue).
- Formatter, PostgreSQL: array['a'] becomes array [ 'a' ].
  tests/format/125 (known issue).
- Converter: the TODO PG form for date - date keeps Oracle's TRUNC:
  (trunc(LOCALTIMESTAMP))::date - (trunc(x))::date. PostgreSQL has no
  TRUNC of a date; CURRENT_DATE - (x)::date says the same.
- Converter: NVL with two types isn't caught when the number comes from a
  built-in function (NVL(LENGTH(x), 'none')): only number literals, text
  functions and looked-up stored functions are known.
- Converter: a function called through a quoted schema ("SALES".f(1))
  isn't listed with the stored functions.
- Converter: a DATE '2025-01-01' literal in a filter on an outer-joined
  table: the word DATE is taken for a column and the whole (+) join is
  left as written. tests/convert/115 (known issue).
- Converter: WHERE ROWNUM <= n around a subquery with ORDER BY becomes
  FETCH FIRST n on the outer query. Oracle keeps the subquery's order;
  PostgreSQL doesn't promise to. Mark it, or move the ORDER BY out.
  tests/convert/900.
- Converter: a recursive WITH is written WITH RECURSIVE in PostgreSQL;
  Oracle writes plain WITH. Mark it TODO PG.

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
- Done 2026-11-06: Object Browser (Amphibian; Object Explorer in Seattle,
  the Explorer in Plume): the font size couldn't be changed where it shows
  code. The Definition page and the Describe window's Script page now use
  the editor's font and size and zoom with it (Ctrl+wheel too).
- Done 2026-11-11: Oracle/PostgreSQL Compatibility, Run Both and Compare:
  a savepoint around the PostgreSQL run (auto-commit off), the whole error
  in the grid, "Not run: ..." when it doesn't run, questions over the
  window. The window opens first and converts once; column lookups are
  kept while it's open.
- Oracle/PostgreSQL Compatibility: "Connect..." in the Oracle and
  PostgreSQL drop-downs, so a session doesn't depend on a tab holding it
  (switching a tab's session closes the one it held). Open: whether the new
  session stays in the Explorer / Object Browser after the window closes,
  and which version it goes in.

## Before release

- Done 2026-10-22: Release build mode in pagona.lpi (Default stays the debug build). Release: no debugger
  info (-g off), strip symbols (-Xs), optimization level 2 (-O2), smart
  linking (-CX, -XX). Measured 2026-10-21: 68.8 MB -> 7.9 MB.
  Build with `lazbuild --build-mode=Release pagona.lpi`.
