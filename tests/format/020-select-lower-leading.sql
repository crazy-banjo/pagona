--@ test: lower-case keywords, leading commas, 2 spaces
--@ dialect: oracle
--@ options: lower leadingcommas indent2
select c.customer_id, c.last_name, count(*) as order_count, sum(oi.quantity) items from customers c join orders o on o.customer_id = c.customer_id left join order_items oi on oi.order_id = o.order_id and oi.returned = 'N' where c.active = 'Y' and (o.region_code = 'NE' or o.region_code = 'SW') group by c.customer_id, c.last_name having count(*) > 2 order by c.last_name, c.customer_id
--@ expect
select
  c.customer_id
  , c.last_name
  , count(*) as order_count
  , sum(oi.quantity) items
from customers c
join orders o
  on o.customer_id = c.customer_id
left join order_items oi
  on oi.order_id = o.order_id
  and oi.returned = 'N'
where c.active = 'Y'
  and (o.region_code = 'NE' or o.region_code = 'SW')
group by c.customer_id, c.last_name
having count(*) > 2
order by c.last_name, c.customer_id
--@ notes
left alone: 0
