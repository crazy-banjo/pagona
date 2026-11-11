--@ test: Oracle: semicolons, a PL/SQL block ended by /, SQL*Plus lines
--@ dialect: oracle
SET PAGESIZE 0
SELECT 1 FROM dual;
SELECT 'a;b' txt, -- a ; in a comment
       2 FROM dual;
BEGIN
  UPDATE t SET a = 1;
  COMMIT;
END;
/
CREATE OR REPLACE PROCEDURE one_step IS
BEGIN
  NULL;
END;
/
SELECT 3 FROM dual
--@ expect
SET PAGESIZE 0
--@@ next statement
SELECT 1 FROM dual
--@@ next statement
SELECT 'a;b' txt, -- a ; in a comment
       2 FROM dual
--@@ next statement
BEGIN
  UPDATE t SET a = 1;
  COMMIT;
END;
--@@ next statement
CREATE OR REPLACE PROCEDURE one_step IS
BEGIN
  NULL;
END;
--@@ next statement
SELECT 3 FROM dual
--@ notes
statements: 6
