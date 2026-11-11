--@ test: MySQL: DELIMITER, backslash escapes in strings
--@ dialect: mysql
SELECT 1;
DELIMITER //
CREATE PROCEDURE one_step()
BEGIN
  SELECT 'a\';b';
  SELECT 2;
END//
DELIMITER ;
SELECT 3;
--@ expect
SELECT 1
--@@ next statement
(empty)
--@@ next statement
CREATE PROCEDURE one_step()
BEGIN
  SELECT 'a\';b';
  SELECT 2;
END
--@@ next statement
(empty)
--@@ next statement
SELECT 3
--@@ next statement
(empty)
--@ notes
statements: 6
