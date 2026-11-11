--@ test: ROWNUM with ORDER BY in the same query is marked, not converted
--@ rules: default
SELECT p.product_id, p.product_name FROM products p WHERE ROWNUM <= 10 ORDER BY p.product_name
--@ expect
SELECT p.product_id, p.product_name FROM products p WHERE ROWNUM /* TODO PG: ROWNUM: ORDER BY is applied after ROWNUM here; PG has no ROWNUM: ROW_NUMBER() OVER (...) or FETCH FIRST */ <= 10 ORDER BY p.product_name
--@ notes
TODO PG ROWNUM that can't convert: 1 marked. ROWNUM in a query with ORDER BY, GROUP BY or DISTINCT, or outside a WHERE limit: PG has no ROWNUM.
