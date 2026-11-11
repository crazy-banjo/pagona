--@ test: date plus days becomes INTERVAL; date minus date is marked
--@ rules: default
SELECT o.order_date + 7 first_week_end,
       o.due_date - 1 last_day,
       o.shipped_date - o.order_date days_to_ship,
       SYSDATE - 400 long_ago
FROM orders o
--@ expect
SELECT o.order_date + INTERVAL '7' DAY first_week_end,
       o.due_date - INTERVAL '1' DAY last_day,
       o.shipped_date - o.order_date /* TODO PG: date - date is days in Oracle, an interval for timestamps in PG: (o.shipped_date)::date - (o.order_date)::date for whole days */ days_to_ship,
       LOCALTIMESTAMP - 400 /* TODO PG: LOCALTIMESTAMP - INTERVAL '400 days' */ long_ago
FROM orders o
--@ notes
date ± n → date ± INTERVAL 'n' DAY: 2. Whole days up to 99 (Oracle needs DAY(3) for more, which PostgreSQL won't read).
SYSDATE → LOCALTIMESTAMP: 1. The date and time now. Left as SYSDATE where a date is subtracted from it (that's flagged).
TODO PG date arithmetic to check: 2 marked. date - date (days in Oracle, an interval in PG), more than 99 days, or fractions of a day: left as it is, with the PG form in a TODO PG comment.
