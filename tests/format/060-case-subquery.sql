--@ test: CASE, a subquery in the list and in WHERE
--@ dialect: oracle
select c.customer_id, case when c.lifetime_total >= 10000 then 'gold' when c.lifetime_total >= 1000 then 'silver' else 'bronze' end tier, (select max(o.order_date) from orders o where o.customer_id = c.customer_id) last_order from customers c where c.customer_id in (select x.customer_id from closed_accounts x where x.closed_year = 2025) and exists (select 1 from alerts a where a.customer_id = c.customer_id)
--@ expect
SELECT
    c.customer_id,
    CASE
        WHEN c.lifetime_total >= 10000 THEN 'gold'
        WHEN c.lifetime_total >= 1000 THEN 'silver'
        ELSE 'bronze'
    END tier,
    (
        SELECT max(o.order_date)
        FROM orders o
        WHERE o.customer_id = c.customer_id
    ) last_order
FROM customers c
WHERE c.customer_id IN (
    SELECT x.customer_id
    FROM closed_accounts x
    WHERE x.closed_year = 2025
)
    AND EXISTS (
        SELECT 1
        FROM alerts a
        WHERE a.customer_id = c.customer_id
    )
--@ notes
left alone: 0
