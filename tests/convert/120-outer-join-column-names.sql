--@ test: unqualified columns are tied to their tables by their names (table_column)
--@ rules: default
SELECT customer_name, address_city, invoice_total
FROM sales.customer, sales.address, billing.invoice
WHERE customer_closed IS NULL
  AND address_customer(+) = customer_no
  AND invoice_customer(+) = customer_no
--@ expect
SELECT customer_name, address_city, invoice_total
FROM sales.customer LEFT JOIN sales.address ON address_customer = customer_no LEFT JOIN billing.invoice ON invoice_customer = customer_no WHERE customer_closed IS NULL
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: customer, address, invoice: 2 LEFT JOIN
