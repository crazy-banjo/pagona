--@ test: the PostgreSQL only forms (the result no longer runs on Oracle 19c)
--@ rules: default +rpDual +rpListagg +rpMinus +rpSequence +rpRegexpReplace +rpInstr +rpSubstrRight +rpTruncDate +rpLastDay +rpNextDay
SELECT LISTAGG(p.category, ',') WITHIN GROUP (ORDER BY p.category) categories,
       TRUNC(o.order_date) order_day,
       TRUNC(o.order_date, 'MM') order_month,
       LAST_DAY(o.order_date) month_end,
       NEXT_DAY(o.order_date, 'MONDAY') next_monday,
       REGEXP_REPLACE(c.phone, '[^0-9]') digits,
       INSTR(c.email, '@') at_pos,
       SUBSTR(c.account_no, -4) last4,
       order_seq.NEXTVAL next_id
FROM orders o, customers c, products p
WHERE c.customer_id = o.customer_id
GROUP BY o.order_date, c.phone, c.email, c.account_no;

SELECT customer_id FROM customers MINUS SELECT customer_id FROM closed_accounts;

SELECT 1 FROM DUAL;
--@ expect
SELECT string_agg(p.category, ',' ORDER BY p.category) categories,
       date_trunc('day', o.order_date) order_day,
       date_trunc('month', o.order_date) order_month,
       (date_trunc('month', o.order_date) + INTERVAL '1 month - 1 day' + (o.order_date - date_trunc('day', o.order_date))) month_end,
       (o.order_date + ((1 - EXTRACT(DOW FROM o.order_date)::int + 6) % 7 + 1) * INTERVAL '1 day') next_monday,
       regexp_replace(c.phone, '[^0-9]', '', 'g') digits,
       strpos(c.email, '@') at_pos,
       CASE WHEN length(c.account_no) >= 4 THEN right(c.account_no, 4) END last4,
       nextval('order_seq') next_id
FROM orders o, customers c, products p
WHERE c.customer_id = o.customer_id
GROUP BY o.order_date, c.phone, c.email, c.account_no;

SELECT customer_id FROM customers EXCEPT SELECT customer_id FROM closed_accounts;

SELECT 1 ;
--@ notes
PostgreSQL only, Remove FROM DUAL: 1.
PostgreSQL only, LISTAGG → string_agg: 1. The exact PostgreSQL form: the result no longer runs on Oracle 19c. Text values only: a number needs CAST(x AS TEXT).
PostgreSQL only, MINUS → EXCEPT: 1.
PostgreSQL only, seq.NEXTVAL → nextval('seq'): 1.
PostgreSQL only, REGEXP_REPLACE → regexp_replace(..., 'g'): 1. The exact PostgreSQL form: the result no longer runs on Oracle 19c. Replaces every match, as Oracle does.
PostgreSQL only, INSTR(x, y) → strpos(x, y): 1.
PostgreSQL only, SUBSTR(x, -n) → right(x, n): 1. The exact PostgreSQL form: the result no longer runs on Oracle 19c. NULL when x is shorter than n, as in Oracle.
PostgreSQL only, TRUNC(date) → date_trunc: 2. The exact PostgreSQL form: the result no longer runs on Oracle 19c. Day, month, year, quarter, hour, minute and ISO week; other week formats stay marked.
PostgreSQL only, LAST_DAY → date_trunc + interval: 1. The exact PostgreSQL form: the result no longer runs on Oracle 19c. Keeps the time of day, as Oracle does.
PostgreSQL only, NEXT_DAY → date + days: 1. The exact PostgreSQL form: the result no longer runs on Oracle 19c. English day names; keeps the time of day.
