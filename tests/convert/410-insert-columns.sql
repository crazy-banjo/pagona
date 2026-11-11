--@ test: INSERT INTO schema.table (columns) is not a function call
--@ rules: default
INSERT INTO sales.customers (customer_id, last_name) VALUES ('C0001', 'Rivera');
INSERT INTO run_log (run_date) SELECT SYSDATE FROM customers WHERE ROWNUM <= 1;
--@ expect
INSERT INTO sales.customers (customer_id, last_name) VALUES ('C0001', 'Rivera');
INSERT INTO run_log (run_date) SELECT LOCALTIMESTAMP FROM customers FETCH FIRST 1 ROWS ONLY;
--@ notes
WHERE ROWNUM <= n → FETCH FIRST n ROWS ONLY: 1. Only where it means the same: no ORDER BY, GROUP BY, DISTINCT or aggregate in that query (Oracle applies ROWNUM before those).
SYSDATE → LOCALTIMESTAMP: 1. The date and time now. Left as SYSDATE where a date is subtracted from it (that's flagged).
