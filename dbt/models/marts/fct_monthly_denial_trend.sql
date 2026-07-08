-- Monthly denial rate with month-over-month comparison. Feeds the denial
-- trend dashboard. Window-function pattern from sql/annotated_queries.sql
-- (query 4): LAG instead of a self-join on the monthly aggregate.

with monthly as (

    select
        claim_month,
        count(*)                                        as claims_submitted,
        count(*) filter (where is_denied)               as denied_claims,
        round(100.0 * count(*) filter (where is_denied) / count(*), 1)
                                                        as denial_rate_pct
    from {{ ref('stg_claims') }}
    group by claim_month

)

select
    claim_month,
    claims_submitted,
    denied_claims,
    denial_rate_pct,
    lag(denial_rate_pct) over (order by claim_month)    as prior_month_rate_pct,
    round(
        denial_rate_pct - lag(denial_rate_pct) over (order by claim_month),
        1
    )                                                   as mom_change_pts
from monthly
order by claim_month
