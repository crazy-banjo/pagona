--@ test: stored functions are marked once per statement (no connection: only with a schema or package)
--@ rules: default
SELECT c.customer_id,
       sales.full_name(c.customer_id) full_name,
       sales.full_name(c.rep_id) rep_name,
       order_pkg.open_total(c.customer_id, 'NE') open_total,
       sales.order_pkg.alerts(c.customer_id) alerts,
       discount_rate(c.customer_id) rate,
       UPPER(c.last_name) upper_name
FROM sales.customers c
--@ expect
SELECT c.customer_id,
       sales.full_name(c.customer_id) /* TODO PG: SALES.FULL_NAME (2 calls): PostgreSQL needs its own version */ full_name,
       sales.full_name(c.rep_id) rep_name,
       order_pkg.open_total(c.customer_id, 'NE') /* TODO PG: ORDER_PKG.OPEN_TOTAL: PostgreSQL needs its own version */ open_total,
       sales.order_pkg.alerts(c.customer_id) /* TODO PG: SALES.ORDER_PKG.ALERTS: PostgreSQL needs its own version */ alerts,
       discount_rate(c.customer_id) rate,
       UPPER(c.last_name) upper_name
FROM sales.customers c
--@ notes
ORDER_PKG functions: 1 function(s), 1 call(s), marked TODO PG (one note per function per statement).
SALES functions: 2 function(s), 3 call(s), marked TODO PG (one note per function per statement).
Left as written, package or schema (no Oracle connection to ask): ORDER_PKG.
