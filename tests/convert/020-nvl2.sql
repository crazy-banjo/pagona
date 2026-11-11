--@ test: NVL2 becomes CASE
--@ rules: default
SELECT NVL2(o.shipped_date, 'shipped', 'open') state FROM orders o
--@ expect
SELECT CASE WHEN o.shipped_date IS NOT NULL THEN 'shipped' ELSE 'open' END state FROM orders o
