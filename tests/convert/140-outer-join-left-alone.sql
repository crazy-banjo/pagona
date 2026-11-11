--@ test: (+) on both sides of one condition is left, with the reason
--@ rules: default
SELECT a.id, b.id FROM alpha a, beta b WHERE a.id(+) = b.id(+)
--@ expect
SELECT a.id, b.id
/* TODO PG: (+) left as written: (+) on two tables in one condition */
FROM alpha a, beta b WHERE a.id(+) = b.id(+)
--@ notes
Left as written: (+) on two tables in one condition
