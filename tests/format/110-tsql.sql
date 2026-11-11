--@ test: T-SQL: IF / ELSE and BEGIN TRY
--@ dialect: sqlserver
if exists (select 1 from customers where active = 'Y') begin select count(*) from customers end else begin print 'none' end
--@ expect
IF EXISTS (
    SELECT 1
    FROM customers
    WHERE active = 'Y'
)
BEGIN
    SELECT count(*)
    FROM customers
END
ELSE
BEGIN
    PRINT 'none'
END
--@ notes
left alone: 0
