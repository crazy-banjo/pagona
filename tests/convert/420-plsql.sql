--@ test: PL/SQL blocks are marked and left alone
--@ rules: default
SELECT NVL(a, 1) FROM t;

BEGIN
  UPDATE customers SET active = NVL(active, 'N') WHERE ROWNUM <= 5;
  sales.refresh_totals;
END;
/

CREATE OR REPLACE FUNCTION one RETURN NUMBER IS
BEGIN
  RETURN NVL(NULL, 1);
END;
/
--@ expect
SELECT COALESCE(a, 1) FROM t;

/* TODO PG: PL/SQL: rewrite in PL/pgSQL */
BEGIN
  UPDATE customers SET active = NVL(active, 'N') WHERE ROWNUM <= 5;
  sales.refresh_totals;
END;
/

/* TODO PG: PL/SQL: rewrite in PL/pgSQL */
CREATE OR REPLACE FUNCTION one RETURN NUMBER IS
BEGIN
  RETURN NVL(NULL, 1);
END;
/
--@ notes
NVL → COALESCE: 1.
TODO PG PL/SQL blocks: 2 marked. Left alone: PostgreSQL needs them rewritten in PL/pgSQL.
