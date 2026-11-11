--@ test: DECODE becomes CASE, a NULL search becomes IS NULL
--@ rules: default
SELECT DECODE(e.status_code, 'A', 'Active', 'L', 'On Leave', NULL, 'Unknown', 'Terminated') emp_status,
       DECODE(o.priority, 'H', 1, 2) priority_no
FROM employees e, orders o
WHERE o.sales_rep_id = e.emp_id
--@ expect
SELECT CASE WHEN e.status_code = 'A' THEN 'Active' WHEN e.status_code = 'L' THEN 'On Leave' WHEN e.status_code IS NULL THEN 'Unknown' ELSE 'Terminated' END emp_status,
       CASE o.priority WHEN 'H' THEN 1 ELSE 2 END priority_no
FROM employees e, orders o
WHERE o.sales_rep_id = e.emp_id
