--@ test: INSERT, UPDATE, DELETE
--@ dialect: oracle
insert into audit_log (id, changed_on, who) values (1, sysdate, 'me');
update customers set active = 'N', closed_on = sysdate where last_order < date '2020-01-01' and active = 'Y';
delete from alerts where cleared_on is not null;
--@ expect
INSERT INTO audit_log (id, changed_on, who)
VALUES (1, sysdate, 'me');

UPDATE customers
SET active = 'N',
    closed_on = sysdate
WHERE last_order < date '2020-01-01'
    AND active = 'Y';

DELETE FROM alerts
WHERE cleared_on IS NOT NULL;
--@ notes
left alone: 0
