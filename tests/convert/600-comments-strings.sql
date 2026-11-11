--@ test: comments, hints and strings are left as written
--@ rules: default
SELECT /*+ INDEX(c customers_pk) */ c.customer_id, -- NVL(x, y) in a comment
       'NVL(a, b) and SYSDATE in a string' txt,
       /* DECODE(a, 1, 2) in a block comment */ NVL(c.nickname, c.first_name) shown_name,
       "NVL" quoted_name
FROM customers c
--@ expect
SELECT /*+ INDEX(c customers_pk) */ c.customer_id, -- NVL(x, y) in a comment
       'NVL(a, b) and SYSDATE in a string' txt,
       /* DECODE(a, 1, 2) in a block comment */ COALESCE(c.nickname, c.first_name) shown_name,
       "NVL" quoted_name
FROM customers c
