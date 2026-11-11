--@ test: plain SQL is returned unchanged
--@ rules: default
SELECT c.customer_id, COALESCE(c.nickname, c.first_name) shown_name
FROM customers c
LEFT JOIN addresses a ON a.customer_id = c.customer_id
WHERE c.active = 'Y'
ORDER BY c.customer_id
FETCH FIRST 10 ROWS ONLY
--@ expect
SELECT c.customer_id, COALESCE(c.nickname, c.first_name) shown_name
FROM customers c
LEFT JOIN addresses a ON a.customer_id = c.customer_id
WHERE c.active = 'Y'
ORDER BY c.customer_id
FETCH FIRST 10 ROWS ONLY
--@ notes

