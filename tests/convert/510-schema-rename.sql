--@ test: a schema name is changed, with quotes when the new name needs them
--@ rules: none
--@ schemas: SALES=central; BILLING=Bill Data; SUPPORT=HELP
SELECT c.customer_id, i.balance
FROM sales.customers c, "BILLING"."INVOICES" i, support.tickets t
WHERE i.customer_id = c.customer_id AND t.customer_id = c.customer_id
--@ expect
SELECT c.customer_id, i.balance
FROM central.customers c, "Bill Data"."INVOICES" i, HELP.tickets t
WHERE i.customer_id = c.customer_id AND t.customer_id = c.customer_id
--@ notes
Schema name SALES changed to central: 1 place(s) (1 table).
Schema name BILLING changed to "Bill Data": 1 place(s) (1 table).
Schema name SUPPORT changed to HELP: 1 place(s) (1 table).
