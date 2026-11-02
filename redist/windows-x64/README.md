# Database client libraries for Windows (64-bit)

Pagona talks to PostgreSQL and MySQL through their own client libraries.
A PC may already have the versions its other software needs, so the
installer offers these as optional components (not ticked), and the
portable zip keeps them in `client-libs`. To use them, they go next to
`pagona.exe`; a connection's "Client library" field can also point at a
copy somewhere else.

## PostgreSQL

`libpq.dll`, `libintl-9.dll`, `libiconv-2.dll`, `libwinpthread-1.dll`,
from the PostgreSQL 18 Windows installer
(`C:\Program Files\PostgreSQL\18\pgAdmin 4\runtime`). They belong together:
replace older copies of the same names rather than mixing versions.

## MySQL

`libmysql.dll` from MySQL Server 8.0.46
(`C:\Program Files\MySQL\MySQL Server 8.0\lib`).

## Shared by both

- `libssl-3-x64.dll` and `libcrypto-3-x64.dll` (OpenSSL 3, for TLS).
- The Microsoft Visual C++ 2015-2022 runtime. `vcruntime140.dll` is here
  (a copy next to the program is a way Microsoft supports). libmysql also
  needs `msvcp140.dll` and `vcruntime140_1.dll`, which come with
  Microsoft's "Visual C++ Redistributable for Visual Studio 2015-2022
  (x64)"; most PCs have it, and the installer says so when one doesn't.

These are 64-bit libraries, so Pagona must be built as a 64-bit program
(the default for 64-bit Lazarus on 64-bit Windows).

Licenses and sources: see `THIRD-PARTY-NOTICES.md` at the top of the
repository.
