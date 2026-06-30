-- ============================================================
-- QUERY 1: Denial rate by payer, trailing 12 months
-- ============================================================

-- BEFORE: works, but scans the full CLAIMS table and joins
-- before filtering. On a claims table in the multi-million-row
-- range, this means the filter happens after the join cost is
-- already paid.

SELECT
    p.payer_name,
    COUNT(*) AS total_claims,
    SUM(CASE WHEN c.claim_status = 'Denied' THEN 1 ELSE 0 END) AS denied_claims,
    ROUND(denied_claims * 100.0 / total_claims, 1) AS denial_rate_pct
FROM claims c
JOIN payers p ON c.payer_id = p.payer_id
WHERE c.claim_date >= DATEADD(month, -12, CURRENT_DATE())
GROUP BY p.payer_name
ORDER BY denial_rate_pct DESC;

-- AFTER: same result, restructured around two things specific
-- to Snowflake rather than a generic RDBMS:
--
-- 1. Snowflake doesn't use traditional indexes -- it prunes
--    micro-partitions based on the clustering key. CLAIMS is
--    clustered on claim_date, so filtering on claim_date BEFORE
--    the join lets Snowflake skip whole partitions instead of
--    scanning them and discarding rows after the join.
-- 2. Pre-aggregating in a CTE before joining to the small PAYERS
--    dimension table means the join only touches one row per
--    payer instead of joining against every claim row twice
--    (once for the count, once for the lookup).

WITH claims_window AS (
    SELECT
        payer_id,
        claim_status
    FROM claims
    WHERE claim_date >= DATEADD(month, -12, CURRENT_DATE())   -- filters first, hits the clustering key
),
payer_summary AS (
    SELECT
        payer_id,
        COUNT(*) AS total_claims,
        SUM(CASE WHEN claim_status = 'Denied' THEN 1 ELSE 0 END) AS denied_claims
    FROM claims_window
    GROUP BY payer_id
)
SELECT
    p.payer_name,
    s.total_claims,
    s.denied_claims,
    ROUND(s.denied_claims * 100.0 / s.total_claims, 1) AS denial_rate_pct
FROM payer_summary s
JOIN payers p ON s.payer_id = p.payer_id
ORDER BY denial_rate_pct DESC;

-- Result on this dataset (12-mo window, 7 payers): runtime improvement
-- is modest at this scale, but the pattern matters more as CLAIMS grows --
-- filter-then-aggregate-then-join scales close to linearly with date
-- range instead of with total table size.


-- ============================================================
-- QUERY 2: AR aging buckets by payer (point-in-time)
-- ============================================================

-- BEFORE: a correlated subquery per row to compute days outstanding,
-- then a second pass with nested CASE statements to bucket it. Works,
-- but the subquery re-evaluates CURRENT_DATE() per row and the bucket
-- logic is unreadable past 4 buckets.

SELECT
    c.claim_id,
    c.payer_id,
    c.billed_amount,
    (SELECT DATEDIFF(day, c.claim_date, CURRENT_DATE())) AS days_outstanding,
    CASE
        WHEN (SELECT DATEDIFF(day, c.claim_date, CURRENT_DATE())) <= 30 THEN '0-30'
        WHEN (SELECT DATEDIFF(day, c.claim_date, CURRENT_DATE())) <= 60 THEN '31-60'
        WHEN (SELECT DATEDIFF(day, c.claim_date, CURRENT_DATE())) <= 90 THEN '61-90'
        ELSE '90+'
    END AS aging_bucket
FROM claims c
WHERE c.claim_status IN ('Pending', 'Denied');

-- AFTER: compute days_outstanding once as a CTE column, then bucket
-- against that single computed value. Same logic, but Snowflake's
-- optimizer only evaluates DATEDIFF once per row instead of three
-- times, and the bucket boundaries live in one place if they ever
-- need to change.

WITH ar_base AS (
    SELECT
        claim_id,
        payer_id,
        billed_amount,
        DATEDIFF(day, claim_date, CURRENT_DATE()) AS days_outstanding
    FROM claims
    WHERE claim_status IN ('Pending', 'Denied')
)
SELECT
    claim_id,
    payer_id,
    billed_amount,
    days_outstanding,
    CASE
        WHEN days_outstanding <= 30 THEN '0-30'
        WHEN days_outstanding <= 60 THEN '31-60'
        WHEN days_outstanding <= 90 THEN '61-90'
        ELSE '90+'
    END AS aging_bucket
FROM ar_base;

-- Aggregated version for the payer scorecard report, built on the same CTE:

WITH ar_base AS (
    SELECT
        claim_id, payer_id, billed_amount,
        DATEDIFF(day, claim_date, CURRENT_DATE()) AS days_outstanding
    FROM claims
    WHERE claim_status IN ('Pending', 'Denied')
),
bucketed AS (
    SELECT *,
        CASE
            WHEN days_outstanding <= 30 THEN '0-30'
            WHEN days_outstanding <= 60 THEN '31-60'
            WHEN days_outstanding <= 90 THEN '61-90'
            ELSE '90+'
        END AS aging_bucket
    FROM ar_base
)
SELECT
    p.payer_name,
    b.aging_bucket,
    COUNT(*) AS claim_count,
    SUM(b.billed_amount) AS billed_in_bucket
FROM bucketed b
JOIN payers p ON b.payer_id = p.payer_id
GROUP BY p.payer_name, b.aging_bucket
ORDER BY p.payer_name,
    CASE b.aging_bucket WHEN '0-30' THEN 1 WHEN '31-60' THEN 2 WHEN '61-90' THEN 3 ELSE 4 END;


-- ============================================================
-- QUERY 3: Underpayment detection (paid claims below contracted rate)
-- ============================================================

-- BEFORE: a nested subquery in the WHERE clause to compare each
-- claim's paid amount against an expected-rate lookup table. Correct,
-- but Snowflake has to re-resolve the subquery's join logic for
-- every outer row -- this is the classic N+1 pattern translated into SQL.

SELECT
    c.claim_id,
    c.payer_id,
    c.billed_amount,
    c.paid_amount
FROM claims c
WHERE c.claim_status = 'Paid'
  AND c.paid_amount < (
        SELECT er.expected_rate * c.billed_amount
        FROM expected_rates er
        WHERE er.payer_id = c.payer_id
          AND er.specialty = c.specialty
  ) * 0.95;   -- 5% tolerance band

-- AFTER: convert the correlated subquery into an explicit JOIN.
-- Same result set, but Snowflake can now use a standard hash join
-- against expected_rates instead of re-executing a subquery per row.
-- This is usually the single highest-leverage rewrite in any RCM
-- query set, since rate-lookup logic is exactly where correlated
-- subqueries tend to creep in.

SELECT
    c.claim_id,
    c.payer_id,
    c.billed_amount,
    c.paid_amount,
    er.expected_rate,
    ROUND(c.billed_amount * er.expected_rate - c.paid_amount, 2) AS underpayment_gap
FROM claims c
JOIN expected_rates er
    ON er.payer_id = c.payer_id
   AND er.specialty = c.specialty
WHERE c.claim_status = 'Paid'              -- in production this is the only "paid"
                                             -- status; underpayment is something the
                                             -- query detects, not a status the source
                                             -- system pre-labels
  AND c.paid_amount < (er.expected_rate * c.billed_amount) * 0.95
ORDER BY underpayment_gap DESC;


-- ============================================================
-- QUERY 4: Month-over-month denial trend with running comparison
-- ============================================================

-- A window function pattern used directly in the Denial Trend
-- dashboard's data prep -- computing each month's denial rate
-- alongside the prior month's, without a self-join.

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', claim_date) AS claim_month,
        COUNT(*) AS total_claims,
        SUM(CASE WHEN claim_status = 'Denied' THEN 1 ELSE 0 END) AS denied_claims
    FROM claims
    GROUP BY claim_month
)
SELECT
    claim_month,
    total_claims,
    denied_claims,
    ROUND(denied_claims * 100.0 / total_claims, 1) AS denial_rate_pct,
    ROUND(
        denied_claims * 100.0 / total_claims
        - LAG(denied_claims * 100.0 / total_claims) OVER (ORDER BY claim_month),
    1) AS pct_change_vs_prior_month
FROM monthly
ORDER BY claim_month;

-- LAG() avoids a self-join against the same monthly CTE, which is
-- the move that matters here -- a self-join would require Snowflake
-- to materialize and scan the aggregated result twice.
