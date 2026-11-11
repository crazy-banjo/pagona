--@ test: numbers compared with _CODE and _ID columns are quoted (off by default)
--@ rules: default +crExplicit
SELECT o.order_id FROM orders o WHERE o.region_code = 1040 AND o.store_id = 14 AND o.quantity = 3
--@ expect
SELECT o.order_id FROM orders o WHERE o.region_code = '1040' AND o.store_id = '14' AND o.quantity = 3
--@ notes
Quote numbers compared with _CODE and _ID columns: 2. Columns named ..._CODE and ..._ID are often text: Oracle converts 1040 for you, PostgreSQL stops with an error. Quoted, '01' no longer matches '1'.
