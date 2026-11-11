--@ test: a comment after each column stays on its column's line
--@ dialect: oracle
--@ known-issue: a comment after a column's comma moves to its own line, above the next column
select 'H' line_type, -- Line type
       c.customer_id, -- Customer number
       null, -- Filler
       c.last_name -- Last name
  from customers c -- the customer list
 where c.active = 'Y' -- current only
--@ expect
SELECT
    'H' line_type, -- Line type
    c.customer_id, -- Customer number
    NULL, -- Filler
    c.last_name -- Last name
FROM customers c -- the customer list
WHERE c.active = 'Y' -- current only
