--@ test: (+) join becomes LEFT JOIN
--@ rules: default
SELECT e.emp_id, d.dept_name
FROM employees e, departments d
WHERE e.dept_id = d.dept_id(+)
  AND e.status_code = 'A'
--@ expect
SELECT e.emp_id, d.dept_name
FROM employees e LEFT JOIN departments d ON e.dept_id = d.dept_id WHERE e.status_code = 'A'
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: e, d: 1 LEFT JOIN
