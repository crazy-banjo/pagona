--@ test: PostgreSQL: casts, a function body left alone
--@ dialect: postgresql
select c.customer_id::text, now() - c.signed_up_on as since from customers c where c.active limit 10;
create function one() returns int language sql as $$ select   1 $$;
--@ expect
SELECT
    c.customer_id::text,
    now() - c.signed_up_on AS since
FROM customers c
WHERE c.active
LIMIT 10;

create function one() returns int language sql as $$ select   1 $$;
--@ notes
left alone: 0
