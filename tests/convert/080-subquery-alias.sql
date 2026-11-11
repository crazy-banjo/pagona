--@ test: a subquery in FROM gets a name
--@ rules: default
SELECT COUNT(*) FROM (SELECT o.order_id FROM orders o WHERE o.status = 'OPEN')
--@ expect
SELECT COUNT(*) FROM (SELECT o.order_id FROM orders o WHERE o.status = 'OPEN') sub1
