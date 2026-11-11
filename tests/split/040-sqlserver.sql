--@ test: SQL Server: batches end at GO lines
--@ dialect: sqlserver
SELECT 1
SELECT 2;
GO
CREATE PROCEDURE one_step AS
BEGIN
  SELECT 'GO' AS word;
  SELECT 3
END
GO
PRINT 'done'
--@ expect
SELECT 1
SELECT 2;
--@@ next statement
CREATE PROCEDURE one_step AS
BEGIN
  SELECT 'GO' AS word;
  SELECT 3
END
--@@ next statement
PRINT 'done'
--@ notes
statements: 3
