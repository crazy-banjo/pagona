--@ test: a DATE '...' literal in a filter on the optional table
--@ rules: default
--@ known-issue: the word DATE is taken for a column, and the whole (+) join is left as written
SELECT e.emp_id, o.order_id
FROM employees e, orders o
WHERE e.emp_id = o.sales_rep_id(+)
  AND o.order_date(+) >= DATE '2025-01-01'
  AND e.status_code = 'A'
--@ expect
SELECT e.emp_id, o.order_id
FROM employees e LEFT JOIN orders o ON e.emp_id = o.sales_rep_id AND o.order_date >= DATE '2025-01-01' WHERE e.status_code = 'A'
