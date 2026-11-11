--@ test: WHERE ROWNUM <= n becomes FETCH FIRST n ROWS ONLY
--@ rules: default
SELECT p.product_id, p.product_name FROM products p WHERE p.discontinued = 'N' AND ROWNUM <= 25
--@ expect
SELECT p.product_id, p.product_name FROM products p WHERE p.discontinued = 'N' FETCH FIRST 25 ROWS ONLY
--@ notes
WHERE ROWNUM <= n → FETCH FIRST n ROWS ONLY: 1. Only where it means the same: no ORDER BY, GROUP BY, DISTINCT or aggregate in that query (Oracle applies ROWNUM before those).
