# Pagona's tests

Tests for the text engines: the Oracle/PostgreSQL converter, the formatter
and statement splitting. Text in, text out: no database and no window.

## Running them

Free Pascal 3.2.2 is all it takes (no Lazarus):

    mkdir -p tests/lib
    fpc -Fusrc -FUtests/lib -FEtests tests/runtests.pas
    tests/runtests

It prints each failure with its first different line, then a count
("50 passed, 0 failed, 3 known issue(s)."). GitHub runs the same on every
push (.github/workflows/tests.yml).

## A case is a text file

One `.sql` file per case, in `convert/`, `format/` or `split/`. Lines that
start with `--@ ` belong to the test; everything else is SQL.

    --@ test: NVL becomes COALESCE
    --@ rules: default
    SELECT NVL(a, 'N') FROM t
    --@ expect
    SELECT COALESCE(a, 'N') FROM t
    --@ notes
    NVL → COALESCE: 1.

- `--@ test:` what the case shows, in a few words.
- `--@ expect` starts the result the SQL above it must give.
- `--@ notes` (optional) starts the log lines it must give too.

Settings for `convert/`:

- `--@ rules:` `default`, `all` or `none`, then `+rule` and `-rule` by the
  names in src/pgnoracleconvert.pas (`default +rpDual -crNvl`).
- `--@ schemas:` schema names to remove or rename
  (`SALES= ; HR=people`).
- `--@ columns:` a made-up data dictionary for (+) joins
  (`PEOPLE.PERSONS=ID,FULL_NAME; GEO.ADDRESSES=PERSON_REF,CITY`); the notes
  then list the tables that were looked up.

Settings for `format/` and `split/`:

- `--@ dialect:` `oracle` (the default), `postgresql`, `mysql` or `sqlserver`.
- `--@ options:` for `format/`: `lower`, `astyped`, `indent2`, `tabs`,
  `leadingcommas`, `packed`, `river`, `joinindented` (none: Pagona Default).

In `split/` the result is the statements in order, a `--@@ next statement`
line between them; `(empty)` is a statement with nothing in it (Pagona
skips those when it runs a script).

## Adding a case

Write the file with nothing after `--@ expect`, then:

    tests/runtests --update

fills in what the code gives today. Read it before keeping it: the test
then holds the code to exactly that.

## A known issue

When the code gives the wrong result and the fix comes later, write the
*right* result after `--@ expect` and add a line saying what's wrong:

    --@ known-issue: a comment after a column's comma moves to its own line

The case is listed, not failed. When a fix makes it pass, the runner says
to take the line out.

## The SQL in here

Every query is made up for the tests. Don't add SQL from a real system
without making it yours first: other names, other values, nothing that
says where it came from.
