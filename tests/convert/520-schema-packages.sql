--@ test: packages, aliases, strings and comments are not schema names
--@ rules: none
--@ schemas: SALES=; C=; ORDER_PKG=; DBMS_LOB=
SELECT c.customer_id, -- sales.customers in a comment
       order_pkg.open_total(c.customer_id) open_total,
       'sales.customers' note,
       c.last_name
FROM sales.customers c
WHERE DBMS_LOB.GETLENGTH(c.notes) > 0
--@ expect
SELECT c.customer_id, -- sales.customers in a comment
       order_pkg.open_total(c.customer_id) open_total,
       'sales.customers' note,
       c.last_name
FROM customers c
WHERE DBMS_LOB.GETLENGTH(c.notes) > 0
--@ notes
DBMS_LOB functions: 1 function(s), 1 call(s), not marked.
ORDER_PKG functions: 1 function(s), 1 call(s), not marked.
Schema name SALES removed: 1 place(s) (1 table).
Left as written, package or schema (no Oracle connection to ask): ORDER_PKG.
