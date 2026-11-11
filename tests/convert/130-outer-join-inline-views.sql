--@ test: (+) joins to inline views, with a plain join beside them
--@ rules: default
SELECT e.emp_id, last_o.order_date, tot.revenue
FROM employees e,
     (SELECT o.sales_rep_id, MAX(o.order_date) order_date FROM orders o GROUP BY o.sales_rep_id) last_o,
     (SELECT o.sales_rep_id, SUM(oi.quantity * oi.unit_price) revenue
        FROM orders o, order_items oi WHERE oi.order_id = o.order_id GROUP BY o.sales_rep_id) tot,
     departments d
WHERE last_o.sales_rep_id(+) = e.emp_id
  AND tot.sales_rep_id(+) = e.emp_id
  AND d.dept_id = e.dept_id
--@ expect
SELECT e.emp_id, last_o.order_date, tot.revenue
FROM employees e LEFT JOIN (SELECT o.sales_rep_id, MAX(o.order_date) order_date FROM orders o GROUP BY o.sales_rep_id) last_o ON last_o.sales_rep_id = e.emp_id LEFT JOIN (SELECT o.sales_rep_id, SUM(oi.quantity * oi.unit_price) revenue
        FROM orders o, order_items oi WHERE oi.order_id = o.order_id GROUP BY o.sales_rep_id) tot ON tot.sales_rep_id = e.emp_id JOIN departments d ON d.dept_id = e.dept_id
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: e, last_o, tot, d: 2 LEFT JOIN, 1 JOIN
