--@ test: COALESCE in || concatenation (off by default)
--@ rules: default +crConcatNull
SELECT e.last_name || ', ' || e.first_name || ' ' || e.middle_name full_name FROM employees e
--@ expect
SELECT COALESCE(e.last_name, '') || ', ' || COALESCE(e.first_name, '') || ' ' || COALESCE(e.middle_name, '') full_name FROM employees e
--@ notes
COALESCE(x, '') in || concatenation: 3. Oracle skips a NULL in a || b; PostgreSQL makes the whole string NULL. Columns and text functions are wrapped (not columns named like numbers or dates); a number wrapped this way fails on Oracle too: Run Both shows it.
