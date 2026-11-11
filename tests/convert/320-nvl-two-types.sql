--@ test: NVL of text with a number is marked, not converted
--@ rules: default
SELECT NVL(TRIM(c.nickname), 0) mixed, NVL(oi.quantity, 0) plain FROM customers c, order_items oi
--@ expect
SELECT NVL(TRIM(c.nickname), 0) /* TODO PG: NVL kept: COALESCE needs one type on both sides, e.g. COALESCE(CAST(TRIM(c.nickname) AS NUMERIC), 0) or a text value for 0 */ mixed, COALESCE(oi.quantity, 0) plain FROM customers c, order_items oi
--@ notes
NVL → COALESCE: 1.
TODO PG NVL with two types: 1 marked. NVL converts one side to the other's type; COALESCE needs both the same, on Oracle too. Left as NVL.
