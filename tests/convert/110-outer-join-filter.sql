--@ test: filters on the optional table move into ON
--@ rules: default
SELECT e.emp_id, o.order_id
FROM employees e, orders o
WHERE e.emp_id = o.sales_rep_id(+)
  AND o.status(+) != 'CANCELLED'
  AND o.channel(+) = 'WEB'
  AND e.status_code = 'A'
--@ expect
SELECT e.emp_id, o.order_id
FROM employees e LEFT JOIN orders o ON e.emp_id = o.sales_rep_id AND o.status != 'CANCELLED' AND o.channel = 'WEB' WHERE e.status_code = 'A'
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: e, o: 1 LEFT JOIN
