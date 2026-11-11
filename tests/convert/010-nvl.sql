--@ test: NVL becomes COALESCE
--@ rules: default
SELECT NVL(e.middle_name, ' ') middle, NVL(NVL(a.email, b.email), 'none') email
FROM employees e, contacts a, contacts b
WHERE e.emp_id = a.emp_id AND e.emp_id = b.emp_id
--@ expect
SELECT COALESCE(e.middle_name, ' ') middle, COALESCE(COALESCE(a.email, b.email), 'none') email
FROM employees e, contacts a, contacts b
WHERE e.emp_id = a.emp_id AND e.emp_id = b.emp_id
--@ notes
NVL → COALESCE: 3.
