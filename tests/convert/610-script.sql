--@ test: a script: each statement converted, SQL*Plus lines left alone
--@ rules: default
SET PAGESIZE 0
SPOOL report.txt
SELECT NVL(a, 'x') FROM t1;
PROMPT done with the first
SELECT DECODE(b, 1, 'one', 'other') FROM t2 WHERE ROWNUM <= 3;
SPOOL OFF
--@ expect
SET PAGESIZE 0
SPOOL report.txt
SELECT COALESCE(a, 'x') FROM t1;
PROMPT done with the first
SELECT CASE b WHEN 1 THEN 'one' ELSE 'other' END FROM t2 FETCH FIRST 3 ROWS ONLY;
SPOOL OFF
--@ notes
NVL → COALESCE: 1.
DECODE → CASE: 1. A NULL search becomes IS NULL, since DECODE matches NULL to NULL.
WHERE ROWNUM <= n → FETCH FIRST n ROWS ONLY: 1. Only where it means the same: no ORDER BY, GROUP BY, DISTINCT or aggregate in that query (Oracle applies ROWNUM before those).
