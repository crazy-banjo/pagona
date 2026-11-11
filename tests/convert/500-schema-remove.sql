--@ test: a schema name comes off tables, functions, columns and sequences
--@ rules: none
--@ schemas: SALES=
SELECT c.customer_id, sales.full_name(c.customer_id) name, sales.customers.last_name,
       "SALES".code_of(1) code
FROM sales.customers c, sales.orders o, billing.invoices i
WHERE o.customer_id = c.customer_id AND i.customer_id = c.customer_id;

INSERT INTO sales.audit_log (id) SELECT sales.audit_seq.NEXTVAL FROM customers;
UPDATE sales.customers SET active = 'N';
DELETE sales.orders WHERE 1 = 0;
--@ expect
SELECT c.customer_id, full_name(c.customer_id) name, customers.last_name,
       code_of(1) code
FROM customers c, orders o, billing.invoices i
WHERE o.customer_id = c.customer_id AND i.customer_id = c.customer_id;

INSERT INTO audit_log (id) SELECT audit_seq.NEXTVAL FROM customers;
UPDATE customers SET active = 'N';
DELETE orders WHERE 1 = 0;
--@ notes
SALES functions: 1 function(s), 1 call(s), not marked.
Schema name SALES removed: 9 place(s) (5 tables, 2 functions, 2 columns or sequences).
