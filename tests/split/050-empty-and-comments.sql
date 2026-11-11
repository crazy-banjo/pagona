--@ test: empty statements and comment-only text
--@ dialect: oracle
;;
-- only a comment
SELECT 1;
/* a block ; comment */
;
SELECT 2;
--@ expect
(empty)
--@@ next statement
(empty)
--@@ next statement
-- only a comment
SELECT 1
--@@ next statement
/* a block ; comment */
--@@ next statement
SELECT 2
--@@ next statement
(empty)
--@ notes
statements: 6
