--@ test: columns packed to the line width
--@ dialect: oracle
--@ options: packed
select c.customer_id, c.last_name, count(*) as order_count, sum(oi.quantity) items from customers c join orders o on o.customer_id = c.customer_id left join order_items oi on oi.order_id = o.order_id and oi.returned = 'N' where c.active = 'Y' and (o.region_code = 'NE' or o.region_code = 'SW') group by c.customer_id, c.last_name having count(*) > 2 order by c.last_name, c.customer_id
--@ expect
SELECT c.customer_id, c.last_name, count(*) AS order_count, sum(oi.quantity) items
FROM customers c
JOIN orders o
    ON o.customer_id = c.customer_id
LEFT JOIN order_items oi
    ON oi.order_id = o.order_id
    AND oi.returned = 'N'
WHERE c.active = 'Y'
    AND (o.region_code = 'NE' OR o.region_code = 'SW')
GROUP BY c.customer_id, c.last_name
HAVING count(*) > 2
ORDER BY c.last_name, c.customer_id
--@ notes
left alone: 0
