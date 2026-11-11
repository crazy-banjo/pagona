--@ test: CAST to VARCHAR2 / NUMBER, TO_NUMBER
--@ rules: default
SELECT CAST(e.emp_id AS VARCHAR2(9)) id_text,
       CAST(oi.unit_price AS NUMBER(9,2)) price,
       TO_NUMBER(r.region_code) region_no
FROM employees e, order_items oi, regions r
--@ expect
SELECT CAST(e.emp_id AS VARCHAR(9)) id_text,
       CAST(oi.unit_price AS NUMERIC(9,2)) price,
       CAST(r.region_code AS NUMERIC) region_no
FROM employees e, order_items oi, regions r
