--@ test: MySQL: backticks and LIMIT
--@ dialect: mysql
select `c`.`customer_id`, ifnull(c.nickname, c.first_name) shown from customers c where c.active = 1 order by 1 limit 5, 10
--@ expect
SELECT
    `c`.`customer_id`,
    ifnull(c.nickname, c.first_name) shown
FROM customers c
WHERE c.active = 1
ORDER BY 1
LIMIT 5, 10
--@ notes
left alone: 0
