# Third-party notices

Pagona is Copyright (C) 2026 Randy Morrow and is free software under the
GNU General Public License, version 3 or (at your option) any later
version: see `LICENSE`. It comes with ABSOLUTELY NO WARRANTY.

Pagona is built with, and its Windows release can carry, the software
below. Each keeps its own license; all of them allow being combined with,
or shipped next to, a GPL 3 program.

## Built into pagona.exe

| Component | License | Source |
|---|---|---|
| Free Pascal run-time library (RTL, FCL) | LGPL 2 with the static-linking exception ("modified LGPL") | https://www.freepascal.org |
| Lazarus Component Library (LCL, LazUtils) | LGPL 2 with the static-linking exception ("modified LGPL") | https://www.lazarus-ide.org |
| SynEdit (the editor, part of Lazarus) | MPL 1.1, or GPL 2 or later | https://gitlab.com/freepascal.org/lazarus/lazarus |
| ZeosLib 7.2.14 (database access) | The ZeosLib license (LGPL 2.1 based, with a static-linking exception) | https://github.com/marsupilami79/zeoslib |
| ExtTabCtrls (the tab bars) | LGPL 2.1 | https://github.com/ovidiopr/ExtTabCtrls |

Pagona's pictures (the peahen logo, the app icon, the toolbar icons) are
its own and are covered by its GPL license.

## Database client libraries (optional, Windows)

The installer offers these unticked; the portable zip keeps them in a
`client-libs` folder. They are included unchanged.

| File | From | License | Source |
|---|---|---|---|
| libpq.dll | PostgreSQL 18 | PostgreSQL License (BSD-style) | https://www.postgresql.org/ftp/source/ |
| libintl-9.dll | GNU gettext | LGPL 2.1 or later | https://ftp.gnu.org/gnu/gettext/ |
| libiconv-2.dll | GNU libiconv | LGPL 2.1 or later | https://ftp.gnu.org/gnu/libiconv/ |
| libwinpthread-1.dll | mingw-w64 winpthreads | MIT / ZPL 2.1 | https://sourceforge.net/projects/mingw-w64/ |
| libssl-3-x64.dll, libcrypto-3-x64.dll | OpenSSL 3.5 | Apache License 2.0 | https://www.openssl.org/source/ |
| libmysql.dll | MySQL 8.0.46 client (Oracle) | GPL 2 with the Universal FOSS Exception, which allows shipping it with software under other open-source licenses such as GPL 3 | https://github.com/mysql/mysql-server (tag mysql-8.0.46) |
| vcruntime140.dll | Microsoft Visual C++ runtime | Microsoft Visual C++ Redistributable terms (may be shipped with a program that uses it) | (not open source) |

## Not shipped

Pagona uses these when they are installed on the PC, and does not carry
them: Oracle Instant Client (Oracle's license), Microsoft ODBC Driver for
SQL Server and Windows' own `odbc32.dll` (Microsoft's licenses).
