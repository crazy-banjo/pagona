--@ test: the same report: SALES removed, HR renamed
--@ rules: default
--@ schemas: SALES= ; HR=people
WITH regional_targets AS (
    -- CTE to calculate annual targets per region
    SELECT 
        region_id,
        SUM(target_amount) AS annual_target
    FROM sales.sales_targets
    WHERE target_year = TO_CHAR(SYSDATE, 'YYYY')
    GROUP BY region_id
)
SELECT * FROM (
    SELECT 
        r.region_name,
        e.emp_id,
        e.last_name || ', ' || e.first_name AS sales_rep,
        NVL(d.dept_name, 'Unassigned Department') AS department,
        
        -- Classic Oracle DECODE for conditional logic
        DECODE(e.status_code, 
               'A', 'Active', 
               'L', 'On Leave', 
               'Terminated') AS emp_status,
               
        -- Handling NULLs in math operations using NVL
        COUNT(DISTINCT o.order_id) AS total_orders,
        NVL(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue,
        NVL(rt.annual_target, 0) AS region_target,
        
        -- Analytic function to rank reps within their region
        RANK() OVER (
            PARTITION BY r.region_id 
            ORDER BY NVL(SUM(oi.quantity * oi.unit_price), 0) DESC
        ) AS regional_rank,
        
        -- Calculating percentage of regional target met
        ROUND(
            (NVL(SUM(oi.quantity * oi.unit_price), 0) / NULLIF(rt.annual_target, 0)) * 100, 
        2) AS pct_of_region_target

    FROM 
        hr.employees e,
        hr.departments d,
        sales.regions r,
        sales.orders o,
        sales.order_items oi,
        regional_targets rt
    WHERE 
        -- Classic Oracle (+) Outer Joins
        e.dept_id = d.dept_id(+)
        AND d.region_id = r.region_id(+)
        AND e.emp_id = o.sales_rep_id(+)
        AND o.order_id = oi.order_id(+)
        AND r.region_id = rt.region_id(+)
        
        -- Filtering outer-joined tables safely without turning them into inner joins
        AND o.order_date(+) >= TRUNC(SYSDATE, 'YYYY')
        AND o.status(+) != 'CANCELLED'
        AND e.hire_date <= ADD_MONTHS(SYSDATE, -6)
    GROUP BY 
        r.region_id,
        r.region_name,
        e.emp_id,
        e.last_name,
        e.first_name,
        d.dept_name,
        e.status_code,
        rt.annual_target
    HAVING 
        NVL(SUM(oi.quantity * oi.unit_price), 0) > 5000
        OR e.status_code = 'A'
    ORDER BY 
        r.region_name ASC, 
        total_revenue DESC
)
-- Classic Oracle pre-12c row limiting
WHERE ROWNUM <= 50;
--@ expect
WITH regional_targets AS (
    -- CTE to calculate annual targets per region
    SELECT
        region_id,
        SUM(target_amount) AS annual_target
    FROM sales_targets
    WHERE target_year = TO_CHAR(LOCALTIMESTAMP, 'YYYY')
    GROUP BY region_id
)
SELECT * FROM (
    SELECT
        r.region_name,
        e.emp_id,
        e.last_name || ', ' || e.first_name AS sales_rep,
        COALESCE(d.dept_name, 'Unassigned Department') AS department,

        -- Classic Oracle DECODE for conditional logic
        CASE e.status_code WHEN 'A' THEN 'Active' WHEN 'L' THEN 'On Leave' ELSE 'Terminated' END AS emp_status,

        -- Handling NULLs in math operations using NVL
        COUNT(DISTINCT o.order_id) AS total_orders,
        COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue,
        COALESCE(rt.annual_target, 0) AS region_target,

        -- Analytic function to rank reps within their region
        RANK() OVER (
            PARTITION BY r.region_id
            ORDER BY COALESCE(SUM(oi.quantity * oi.unit_price), 0) DESC
        ) AS regional_rank,

        -- Calculating percentage of regional target met
        ROUND(
            (COALESCE(SUM(oi.quantity * oi.unit_price), 0) / NULLIF(rt.annual_target, 0)) * 100,
        2) AS pct_of_region_target

    FROM people.employees e LEFT JOIN people.departments d ON -- Classic Oracle (+) Outer Joins
        e.dept_id = d.dept_id LEFT JOIN regions r ON d.region_id = r.region_id LEFT JOIN orders o ON e.emp_id = o.sales_rep_id AND o.order_date >= TRUNC(LOCALTIMESTAMP, 'YYYY') /* TODO PG: date_trunc('year', LOCALTIMESTAMP) */ AND o.status != 'CANCELLED' LEFT JOIN order_items oi ON o.order_id = oi.order_id LEFT JOIN regional_targets rt ON r.region_id = rt.region_id

        -- Filtering outer-joined tables safely without turning them into inner joins
 WHERE e.hire_date <= ADD_MONTHS(LOCALTIMESTAMP, -6) /* TODO PG: (LOCALTIMESTAMP + INTERVAL '-6 months') */
    GROUP BY
        r.region_id,
        r.region_name,
        e.emp_id,
        e.last_name,
        e.first_name,
        d.dept_name,
        e.status_code,
        rt.annual_target
    HAVING
        COALESCE(SUM(oi.quantity * oi.unit_price), 0) > 5000
        OR e.status_code = 'A'
    ORDER BY
        r.region_name ASC,
        total_revenue DESC
) sub1
-- Classic Oracle pre-12c row limiting
FETCH FIRST 50 ROWS ONLY;
--@ notes
(+) outer joins → LEFT JOIN ... ON: 1.
Converted: e, d, r, o, oi, rt: 5 LEFT JOIN
NVL → COALESCE: 6.
DECODE → CASE: 1. A NULL search becomes IS NULL, since DECODE matches NULL to NULL.
WHERE ROWNUM <= n → FETCH FIRST n ROWS ONLY: 1. Only where it means the same: no ORDER BY, GROUP BY, DISTINCT or aggregate in that query (Oracle applies ROWNUM before those).
SYSDATE → LOCALTIMESTAMP: 3. The date and time now. Left as SYSDATE where a date is subtracted from it (that's flagged).
Names for subqueries in FROM: 1. PostgreSQL before 16 requires one.
TODO PG TRUNC of a date: 1 marked.
TODO PG ADD_MONTHS: 1 marked. Nothing runs on both Oracle 19c and PostgreSQL: left as it is (it still runs on Oracle), with the PostgreSQL form in a /* TODO PG */ comment. At month end they differ: Oracle's Apr 30 + 1 is May 31.
Schema name SALES removed: 4 place(s) (4 tables).
Schema name HR changed to people: 2 place(s) (2 tables).
