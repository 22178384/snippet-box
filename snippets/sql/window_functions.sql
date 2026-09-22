-- Window functions: the queries I look up every single time.
--
-- Runs on PostgreSQL 12+. The whole file is wrapped in a transaction that we
-- ROLLBACK at the end, so it's safe to run in psql against any database:
--     psql -d mydb -f window_functions.sql
--
-- If you're on MySQL 8+, most of this works too. MariaDB before 10.2 does not
-- have window functions at all.

BEGIN;

CREATE TABLE sales (
    id         SERIAL PRIMARY KEY,
    region     TEXT NOT NULL,
    sold_on    DATE NOT NULL,
    amount     NUMERIC(10, 2) NOT NULL
);

INSERT INTO sales (region, sold_on, amount) VALUES
    ('north', '2026-01-05', 100.00),
    ('north', '2026-01-19', 250.00),
    ('north', '2026-02-02',  75.00),
    ('south', '2026-01-05', 400.00),
    ('south', '2026-01-26', 150.00),
    ('south', '2026-02-09', 300.00),
    ('east',  '2026-01-12', 220.00),
    ('east',  '2026-02-16', 180.00);

-- ---------------------------------------------------------------------------
-- 1. Running total per region.
--    The frame clause is the part people forget. Without ORDER BY in the
--    OVER(), SUM() sums the whole partition instead of running. Default frame
--    with ORDER BY is RANGE UNBOUNDED PRECEDING TO CURRENT ROW, which is what
--    you want here. I write it out anyway so it's obvious.
-- ---------------------------------------------------------------------------
SELECT
    region,
    sold_on,
    amount,
    SUM(amount) OVER (
        PARTITION BY region
        ORDER BY sold_on
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM sales
ORDER BY region, sold_on;

-- ---------------------------------------------------------------------------
-- 2. Rank within each region. RANK leaves gaps on ties (1,1,3); DENSE_RANK
--    doesn't (1,1,2); ROW_NUMBER always breaks ties arbitrarily but uniquely.
-- ---------------------------------------------------------------------------
SELECT
    region,
    sold_on,
    amount,
    ROW_NUMBER() OVER (PARTITION BY region ORDER BY amount DESC) AS rn,
    RANK()       OVER (PARTITION BY region ORDER BY amount DESC) AS rnk,
    DENSE_RANK() OVER (PARTITION BY region ORDER BY amount DESC) AS dense_rnk
FROM sales
ORDER BY region, rnk;

-- ---------------------------------------------------------------------------
-- 3. Previous / next row (LAG / LEAD). Common for "change since last time".
--    The default offset is 1; pass a second arg to look further back. The
--    third arg is the value to use when there's no previous row (else NULL).
-- ---------------------------------------------------------------------------
SELECT
    region,
    sold_on,
    amount,
    LAG(amount, 1, 0) OVER (PARTITION BY region ORDER BY sold_on)  AS prev_amount,
    amount - LAG(amount, 1, 0) OVER (
        PARTITION BY region ORDER BY sold_on
    ) AS delta
FROM sales
ORDER BY region, sold_on;

-- ---------------------------------------------------------------------------
-- 4. Each region's share of the grand total.
--    Empty OVER() = whole result set. This is how you avoid a self-join to a
--    subquery just to get the total.
-- ---------------------------------------------------------------------------
SELECT
    region,
    amount,
    ROUND(100.0 * amount / SUM(amount) OVER (), 1) AS pct_of_total
FROM sales
ORDER BY pct_of_total DESC;

-- ---------------------------------------------------------------------------
-- 5. Top N per group. You can't put a window function in WHERE (it's evaluated
--    after WHERE), so wrap it in a subquery or CTE.
-- ---------------------------------------------------------------------------
WITH ranked AS (
    SELECT
        region,
        sold_on,
        amount,
        ROW_NUMBER() OVER (PARTITION BY region ORDER BY amount DESC) AS rn
    FROM sales
)
SELECT region, sold_on, amount
FROM ranked
WHERE rn <= 2
ORDER BY region, amount DESC;

-- ---------------------------------------------------------------------------
-- 6. First value in each partition, carried onto every row. Handy for
--    "first sale date" alongside each row without a separate query.
-- ---------------------------------------------------------------------------
SELECT
    region,
    sold_on,
    FIRST_VALUE(sold_on) OVER (
        PARTITION BY region ORDER BY sold_on
    ) AS first_sale_date
FROM sales
ORDER BY region, sold_on;

-- Clean up. Everything above was inside this transaction.
ROLLBACK;
