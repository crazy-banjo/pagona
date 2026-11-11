--@ test: what has no form that runs on both is marked TODO PG
--@ rules: default
SELECT LISTAGG(p.category, ',') WITHIN GROUP (ORDER BY p.category) categories,
       TRUNC(o.order_date) order_day,
       ADD_MONTHS(o.order_date, 6) half_year,
       MONTHS_BETWEEN(SYSDATE, o.order_date) months_old,
       LAST_DAY(o.order_date) month_end,
       NEXT_DAY(o.order_date, 'MONDAY') next_monday,
       TO_CHAR(o.order_date) order_text,
       TO_DATE(o.promised, 'DD-MON-RR') promised,
       REGEXP_SUBSTR(c.email, '[^@]+') mailbox,
       REGEXP_REPLACE(c.phone, '[^0-9]') digits,
       INSTR(c.email, '@') at_pos,
       SUBSTR(c.account_no, -4) last4,
       o.ROWID row_id,
       SYS_CONTEXT('USERENV', 'SESSION_USER') who,
       order_seq.NEXTVAL next_id
FROM orders o, customers c, products p
WHERE c.customer_id = o.customer_id
GROUP BY o.order_date, o.promised, c.email, c.phone, c.account_no, o.ROWID;

SELECT customer_id FROM customers MINUS SELECT customer_id FROM closed_accounts;

SELECT 1 FROM DUAL;

SELECT e.emp_id, LEVEL FROM employees e START WITH e.manager_id IS NULL CONNECT BY PRIOR e.emp_id = e.manager_id;
--@ expect
SELECT LISTAGG(p.category, ',') WITHIN GROUP (ORDER BY p.category) /* TODO PG: string_agg(p.category, ',' ORDER BY p.category) (add ::text if it isn't text) */ categories,
       TRUNC(o.order_date) /* TODO PG: date_trunc('day', o.order_date) */ order_day,
       ADD_MONTHS(o.order_date, 6) /* TODO PG: (o.order_date + INTERVAL '6 months') */ half_year,
       MONTHS_BETWEEN(LOCALTIMESTAMP, o.order_date) /* TODO PG: (EXTRACT(YEAR FROM age(LOCALTIMESTAMP, o.order_date)) * 12 + EXTRACT(MONTH FROM age(LOCALTIMESTAMP, o.order_date))), whole months */ months_old,
       LAST_DAY(o.order_date) /* TODO PG: (date_trunc('month', o.order_date) + INTERVAL '1 month - 1 day' + (o.order_date - date_trunc('day', o.order_date))) */ month_end,
       NEXT_DAY(o.order_date, 'MONDAY') /* TODO PG: (o.order_date + ((1 - EXTRACT(DOW FROM o.order_date)::int + 6) % 7 + 1) * INTERVAL '1 day') */ next_monday,
       TO_CHAR(o.order_date) /* TODO PG: to_char needs a format: to_char(o.order_date, 'MM/DD/YYYY') (or the one you need; runs on both) */ order_text,
       TO_DATE(o.promised, 'DD-MON-RR') /* TODO PG: PG has no RR in formats: use YYYY (or YY) */ promised,
       REGEXP_SUBSTR(c.email, '[^@]+') /* TODO PG: regexp_substr needs PostgreSQL 15 or later; before 15: substring(x from 'pattern') */ mailbox,
       REGEXP_REPLACE(c.phone, '[^0-9]') /* TODO PG: regexp_replace(c.phone, '[^0-9]', '', 'g') */ digits,
       INSTR(c.email, '@') /* TODO PG: strpos(c.email, '@') */ at_pos,
       SUBSTR(c.account_no, -4) /* TODO PG: PG's substr doesn't count from the end: CASE WHEN length(c.account_no) >= 4 THEN right(c.account_no, 4) END */ last4,
       o.ROWID /* TODO PG: PG has no ROWID (ctid changes): use the table's key */ row_id,
       SYS_CONTEXT('USERENV', 'SESSION_USER') /* TODO PG: current_user, inet_client_addr() or current_setting(...) */ who,
       order_seq.NEXTVAL /* TODO PG: nextval('order_seq') */ next_id
FROM orders o, customers c, products p
WHERE c.customer_id = o.customer_id
GROUP BY o.order_date, o.promised, c.email, c.phone, c.account_no, o.ROWID /* TODO PG: PG has no ROWID (ctid changes): use the table's key */;

SELECT customer_id FROM customers MINUS /* TODO PG: EXCEPT */ SELECT customer_id FROM closed_accounts;

SELECT 1 FROM DUAL /* TODO PG: leave out FROM DUAL */;

SELECT e.emp_id, LEVEL FROM employees e START WITH e.manager_id IS NULL CONNECT BY /* TODO PG: rewrite as WITH RECURSIVE; LEVEL, PRIOR and SYS_CONNECT_BY_PATH have no direct form */ PRIOR e.emp_id = e.manager_id;
--@ notes
SYSDATE → LOCALTIMESTAMP: 1. The date and time now. Left as SYSDATE where a date is subtracted from it (that's flagged).
TODO PG LISTAGG: 1 marked.
TODO PG TRUNC of a date: 1 marked.
TODO PG ADD_MONTHS: 1 marked. Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), with the PostgreSQL form in a /* TODO PG */ comment. At month end they differ: Oracle's Apr 30 + 1 is May 31.
TODO PG MONTHS_BETWEEN: 1 marked. Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), with the PostgreSQL form in a /* TODO PG */ comment. The PG form counts whole months; Oracle gives fractions.
TODO PG LAST_DAY: 1 marked.
TODO PG NEXT_DAY: 1 marked.
TODO PG MINUS: 1 marked. Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), with the PostgreSQL form in a /* TODO PG */ comment. Oracle has EXCEPT from 21c.
TODO PG FROM DUAL: 1 marked. Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), with the PostgreSQL form in a /* TODO PG */ comment. PG has no DUAL; Oracle 19c needs a FROM.
TODO PG sequences: 1 marked.
TODO PG CONNECT BY: 1 marked.
TODO PG REGEXP_SUBSTR / INSTR / COUNT / LIKE: 1 marked. The same functions exist in PostgreSQL 15 and later; flagged until the PG version is known.
TODO PG REGEXP_REPLACE: 1 marked. Oracle replaces every match; PostgreSQL only the first unless given 'g'.
TODO PG TO_CHAR / TO_DATE formats: 2 marked. No format (PG needs one), RR (PG has none), or an NLS parameter.
TODO PG ROWID: 2 marked.
TODO PG SYS_CONTEXT / USERENV: 1 marked.
TODO PG INSTR: 1 marked. PostgreSQL has no INSTR (strpos, without a start or occurrence).
TODO PG SUBSTR from the end, or of a date: 1 marked. A negative start counts from the end in Oracle, not in PostgreSQL; SUBSTR of a date depends on Oracle's date format.
