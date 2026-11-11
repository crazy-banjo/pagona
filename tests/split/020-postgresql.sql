--@ test: PostgreSQL: dollar-quoted function bodies hold semicolons
--@ dialect: postgresql
SELECT 1;
CREATE FUNCTION one() RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  PERFORM 1;
  RETURN 2;
END;
$body$;
SELECT 'x;y', $$a;b$$;
SELECT 3
--@ expect
SELECT 1
--@@ next statement
CREATE FUNCTION one() RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  PERFORM 1;
  RETURN 2;
END;
$body$
--@@ next statement
SELECT 'x;y', $$a;b$$
--@@ next statement
SELECT 3
--@ notes
statements: 4
