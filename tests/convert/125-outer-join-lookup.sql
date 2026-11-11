--@ test: unqualified columns are tied to their tables by the data dictionary, asked for by schema.table
--@ rules: default
--@ columns: HR.PEOPLE=ID,FULL_NAME; HR.LOCATIONS=PERSON_REF,CITY
SELECT full_name, city
FROM hr.people, hr.locations
WHERE person_ref(+) = id
--@ expect
SELECT full_name, city
FROM hr.people LEFT JOIN hr.locations ON person_ref = id
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: people, locations: 1 LEFT JOIN
tables looked up: HR.PEOPLE,HR.LOCATIONS
