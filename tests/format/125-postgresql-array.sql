--@ test: PostgreSQL: an array literal keeps its brackets tight
--@ dialect: postgresql
--@ known-issue: spaces are put around the brackets: array [ 'priority' ]
select c.customer_id from customers c where c.tags @> array['priority', 'vip']
--@ expect
SELECT c.customer_id
FROM customers c
WHERE c.tags @> array['priority', 'vip']
