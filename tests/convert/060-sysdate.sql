--@ test: SYSDATE and SYSTIMESTAMP
--@ rules: default
SELECT SYSDATE now_date, SYSTIMESTAMP now_ts FROM orders o WHERE o.order_date <= SYSDATE
--@ expect
SELECT LOCALTIMESTAMP now_date, CURRENT_TIMESTAMP now_ts FROM orders o WHERE o.order_date <= LOCALTIMESTAMP
