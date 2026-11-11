--@ test: comments, hints, strings and quoted names stay as written
--@ dialect: oracle
select /*+ full(c) */ c.customer_id,
  'two  spaces   kept' txt, "Mixed Case" col /* block */ from customers c -- trailing
where c.active = 'Y'
--@ expect
SELECT /*+ full(c) */
    c.customer_id,
    'two  spaces   kept' txt,
    "Mixed Case" col /* block */
FROM customers c -- trailing
WHERE c.active = 'Y'
--@ notes
left alone: 0
