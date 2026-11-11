--@ test: a PL/SQL block indents by its blocks
--@ dialect: oracle
begin
for r in (select customer_id from customers where active = 'Y') loop
if r.customer_id is not null then
update customers set checked = 'Y' where customer_id = r.customer_id;
else
null;
end if;
end loop;
end;
--@ expect
BEGIN
    FOR r IN (
        SELECT customer_id
        FROM customers
        WHERE active = 'Y'
    ) LOOP
        IF r.customer_id IS NOT NULL THEN
            UPDATE customers
            SET checked = 'Y'
            WHERE customer_id = r.customer_id;
        ELSE
            NULL;
        END IF;
    END LOOP;
END;
--@ notes
left alone: 0
