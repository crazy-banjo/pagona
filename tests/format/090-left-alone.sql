--@ test: statements Pagona doesn't lay out are left exactly as written
--@ dialect: oracle
grant select on customers to   reporting;
alter table customers   add (nickname varchar2(30));
select 1   from dual;
--@ expect
grant select on customers to   reporting;

alter table customers   add (nickname varchar2(30));

SELECT 1
FROM dual;
--@ notes
left alone: 0
