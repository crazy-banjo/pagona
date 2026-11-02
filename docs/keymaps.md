# Keymaps: target lists and status

Goal: Amphibian matches Toad for Oracle's default keys and Seattle matches
SSMS's default keys, as closely as Pagona's features allow. Keys only, no
names, icons or artwork.

Status column:

- **Have**: works in Pagona today.
- **Now**: the feature exists or is small; only the key (or a tiny command) is missing.
- **Feature**: needs a feature Pagona doesn't have yet.
- **Later**: belongs to something far off or out of scope (debugger, designers, projects).

Sources:

- SSMS: Microsoft's official list, "SQL Server Management Studio keyboard
  shortcuts" (learn.microsoft.com, updated 2025-10-30).
- Toad: Randy's own Toad for Oracle, default keys (he doesn't customize),
  exported from Toad's shortcut list on 2026-10-21.

## Found while building the lists

1. **The "common" keys clash.** Pagona gives every keymap Ctrl+T new tab,
   Ctrl+W close tab and Ctrl+Shift+S save as. In SSMS Ctrl+T is results to
   text, Ctrl+W selects a word and Ctrl+Shift+S is Save All; in Toad Ctrl+T
   is the pick-list dropdown and Ctrl+PgUp / Ctrl+PgDn move between
   Navigator nodes. Tab and file keys must move into each keymap.
2. **The editor's own defaults leak into every keymap.** SynEdit ships keys
   of its own (Ctrl+U unindent, Ctrl+Shift+U, Ctrl+Shift+digits bookmarks,
   and others). An exact match means each keymap clears those and binds only
   its own list.
3. **Same key, different meaning by panel.** In SSMS, F5 refreshes Activity
   Monitor and F6 cycles panels. Keys will need a "where the focus is" rule,
   not one global table.

## Amphibian (Toad for Oracle)

From Randy's own Toad for Oracle (default keys, printed from Toad's
shortcut list, 2026-10-21). Only actions that have a key are listed.

### Running and results

| Key | Toad action | Pagona status |
|---|---|---|
| F9 | Execute Statement | Have |
| F5 | Execute as Script | Have |
| Shift+F9 | Execute Snippet (the selected text) | Now |
| Ctrl+\\ | Execute Statement and Pin Data Grid | Feature (pinned result grids) |
| Ctrl+Alt+P | Pin Data Grid | Feature (pinned result grids) |
| Ctrl+E | Explain Plan Current SQL | Have |
| Ctrl+F9 | Describe (Parse) Select Query | Feature |
| F6 | Toggle Focus Top/Bottom (editor / results) | Now |
| F2 | Toggle Full Screen Editor | Now |
| Shift+F2 | Toggle Full Screen Grid | Now |
| Ctrl+F2 | Split Size Horizontally | Now |
| F8 | SQL Recall | Have |
| Alt+Up / Alt+Down | Previous / next SQL Recall statement | Now |
| Ctrl+N | Insert Saved SQL statement | Feature (saved SQL) |
| Ctrl+H | Highlight Snippet | Now |

### Describe and objects

| Key | Toad action | Pagona status |
|---|---|---|
| F4 | Describe | Have: the Describe window, Toad-style tabs |
| Alt+Enter | Describe | Now |
| Ctrl+D | Quick Describe | Now |
| Shift+F4 | Action Console | Later |
| Ctrl+PgUp / Ctrl+PgDn | Previous / next Navigator node | Feature (Navigator) |

### Editing

| Key | Toad action | Pagona status |
|---|---|---|
| Ctrl+B | Comment Block | Have |
| Ctrl+Shift+B | Uncomment Block | Have |
| Ctrl+U | Upper Case | Now (command exists, no key) |
| Ctrl+L | Lower Case | Now (command exists, no key) |
| Ctrl+I | Initial Caps | Now |
| Ctrl+Shift+F | Format Code | Feature (formatter) |
| F7 | Clear All | Now |
| F10 | Popup Menu | Now |
| Ctrl+Shift+L | Swap This/Prev Lines | Now |
| Ctrl+Shift+T | Line copy | Now |
| Ctrl+Shift+Y | Line cut | Now |
| Ctrl+Y | Line delete | Now |
| Ctrl+Shift+BkSp / Ctrl+Shift+Del | Line delete left / right | Now |
| Ctrl+BkSp / Ctrl+Del | Word delete left / right | Have (editor) |
| Ctrl+T | Pick-list dropdown | Feature (completion) |
| Ctrl+Shift+C | Code completion | Feature (completion) |
| Ctrl+Space | Insert code template | Feature (snippets) |
| Ctrl+Shift+Up | Jump to code complement (matching BEGIN/END etc.) | Feature |
| Ctrl+M | Make Code Statement | Feature (small) |
| Ctrl+Shift+M | Strip Code Statement | Feature (small) |
| Ctrl+F12 | Load in External Editor | Feature (small) |
| Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V | Select all, copy, cut, paste | Have |
| Ctrl+Z / Ctrl+Shift+Z | Undo / Redo | Have (editor) |
| Shift+Tab | Tab back | Have (editor) |
| Ins | Toggle insert/overwrite | Have (editor) |
| Ctrl+/ | Zoom set (reset zoom) | Now |
| Ctrl+Num + / Ctrl+Num - | Zoom in / out | Now |
| Ctrl+Shift+PgUp / PgDn | Previous / next Code Analysis violation | Later |

### Moving and selecting (editor)

| Key | Toad action | Pagona status |
|---|---|---|
| Arrows, Home, End, PgUp, PgDn (with Shift to select) | Move / select | Have (editor) |
| Ctrl+Left / Ctrl+Right (with Shift) | Word left / right (select) | Have (editor) |
| Ctrl+Home / Ctrl+End (with Shift) | Document start / end (select) | Have (editor) |
| Ctrl+Up / Ctrl+Down | Line scroll up / down | Now (check editor default) |
| Alt+Shift+arrows, Alt+Shift+Home/End/PgUp/PgDn | Block (column) select | Now (editor supports it) |
| Alt+Home | Home display | Now |
| Alt+End | Line end | Now |

### Search and files

| Key | Toad action | Pagona status |
|---|---|---|
| Ctrl+F | Find | Have |
| F3 / Shift+F3 | Find Next / Find Previous | Have F3 (Find Previous: Now) |
| Ctrl+R | Replace | Have |
| Ctrl+G | Goto Line | Now |
| Ctrl+O | Open File | Have |
| Ctrl+S / Ctrl+Shift+S | Save File / Save As | Have |
| Ctrl+P / Ctrl+Shift+P | Print / Print Preview | Feature |
| Ctrl+' | Focus Toolbars | Now |

### Schema Browser (when it has focus)

| Key | Toad action | Pagona status |
|---|---|---|
| F3 | Send Query To Editor | Now (Explorer: Select Top) |
| Ctrl+F3 | Send Editable Query To Editor | Feature (editable grid) |
| F2 | Rename Object | Feature |

### PL/SQL debugger

| Key | Toad action | Pagona status |
|---|---|---|
| F11 / F12 | Run / Run to Cursor | Later |
| Shift+F5 | Set Breakpoint | Later |
| Shift+F7 / Shift+F8 / Shift+F10 | Trace Into / Step Over / Trace Out | Later |
| Ctrl+F5 | Add Watch at Cursor | Later |
| Ctrl+Shift+F9 | Set Parameters | Later |
| Ctrl+Alt+B / C / D / E / W | Breakpoints / Call Stack / DBMS Output / Evaluate-Modify / Watches | Later |

### Pagona keys Toad doesn't have

These are bound in Amphibian today but aren't in Toad's list. To match
exactly, they come out of Amphibian (or stay as harmless extras, Randy's
call):

- Ctrl+Enter (run statement). In Toad Ctrl+Enter isn't bound to running.
- Ctrl+T (new tab). In Toad Ctrl+T is the pick-list dropdown.
- Ctrl+W (close tab), Ctrl+Tab / Ctrl+Shift+Tab (switch tabs): not in
  Toad's list (Ctrl+Tab may come from Windows itself).
- Ctrl+PgUp / Ctrl+PgDn (switch tabs). In Toad these move between
  Navigator nodes.

## Seattle (SSMS)

| Key | SSMS action | Pagona status |
|---|---|---|
| F5 / Ctrl+E | Run selection, or whole editor | Have |
| Ctrl+L | Estimated execution plan | Have |
| Alt+F1 | sp_help (describe) on the word at the cursor | Have: opens Pagona's Describe window (Seattle look) |
| Ctrl+K, Ctrl+C / Ctrl+K, Ctrl+U | Comment / uncomment | Have |
| Ctrl+O / Ctrl+S | Open / Save | Have |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous window | Have |
| Ctrl+A, C, V, X, Z, Y | Select all, copy, paste, cut, undo, redo | Have (editor) |
| Ctrl+N | New query window (same connection) | Have (Seattle) |
| Ctrl+F4 | Close window | Have (Seattle; Ctrl+W too) |
| Ctrl+Shift+S | Save All | Now (Pagona uses it for Save As) |
| Alt+Break | Cancel running query | Have |
| Ctrl+R | Show / hide results pane | Now |
| F6 | Toggle query editor / results | Now |
| Ctrl+Shift+U / Ctrl+Shift+L | Uppercase / lowercase | Now (command exists, no key) |
| Ctrl+G | Go to line | Now |
| Ctrl+F / Ctrl+H | Find / replace | Now |
| F3 / Shift+F3 | Find next / previous | Now |
| Ctrl+W | Select current word | Now |
| Ctrl+Up / Ctrl+Down | Scroll one line | Now (check editor default) |
| Shift+Alt+arrows | Column (box) selection | Now (editor supports it) |
| Ctrl+Delete / Ctrl+Backspace | Delete word right / left | Have (editor) |
| Ctrl+Enter / Ctrl+Shift+Enter | Insert blank line above / below | Now |
| Shift+Alt+T | Move line down | Now |
| Ctrl+Shift+Delete | Delete all text | Now |
| Ctrl+K, Ctrl+\ | Delete whitespace | Now |
| Ctrl+K, Ctrl+K | Toggle bookmark | Now (editor has bookmarks) |
| Ctrl+K, Ctrl+N / Ctrl+K, Ctrl+P | Next / previous bookmark | Now |
| Ctrl+K, Ctrl+L | Clear bookmarks | Now |
| Shift+Alt+Enter | Full screen | Now |
| Ctrl+F6 / Ctrl+Shift+F6 | Cycle windows | Now |
| F8 | Show Object Explorer | Now (show Explorer panel) |
| Ctrl+1 | sp_who (sessions) | Now (MySQL: SHOW PROCESSLIST) |
| Ctrl+Shift+C | Copy results with headers | Now |
| Shift+F10 | Context menu | Have (Windows standard) |
| Ctrl+F5 | Parse only | Feature (per database) |
| Ctrl+M | Include actual execution plan | Feature |
| Ctrl+D / Ctrl+T / Ctrl+Shift+F | Results to grid / text / file | Have (Seattle; Ctrl+T is no longer New Query there) |
| Ctrl+2 | sp_lock (locks) | Feature |
| Ctrl+J | List members (IntelliSense) | Feature (completion) |
| Ctrl+Shift+R | Refresh IntelliSense cache | Feature (completion) |
| Ctrl+K, Ctrl+X / Ctrl+K, Ctrl+S / Ctrl+K, Ctrl+B | Snippets / surround-with / snippet manager | Feature (snippets) |
| Ctrl+Shift+M | Fill in template parameters | Feature (templates) |
| Ctrl+M, Ctrl+M / Ctrl+M, Ctrl+L | Outlining (fold) | Feature (folding) |
| Ctrl+- / Ctrl+Shift+- | Navigate back / forward | Feature |
| F7 | Object Explorer Details | Feature (Details panel) |
| F4 | Properties window | Feature |
| Ctrl+Alt+G | Registered Servers | Feature (≈ connection list) |
| Ctrl+Alt+A | Activity Monitor | Feature (DBA mode) |
| Ctrl+K, Ctrl+W | Bookmarks window | Feature |
| Ctrl+Alt+T / Ctrl+Alt+L / Ctrl+Shift+Q / Ctrl+Alt+P | Template Explorer / Solution Explorer / Query Designer / Profiler | Later |
| F1 | Help | Later |
