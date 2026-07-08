-- Payer performance scorecard: four normalized metrics combined into a
-- composite score (weights disclosed in docs/methodology.md: denial rate
-- 35%, underpayment rate 25%, avg days to resolve 20%, AR 90+ share 20%).
-- Feeds the payer scorecard dashboard; tested against the published report
-- in tests/assert_scorecard_matches_published_report.sql.

with claims as (

    select * from {{ ref('stg_claims') }}

),

ar as (

    -- Same aging clock as fct_ar_aging (denied claims age from decision,
    -- pending from submission). 90+ share is claim-count based.
    select
        payer,
        count(*)                                        as ar_claims,
        count(*) filter (
            where coalesce(
                days_to_resolve,
                date_diff('day', claim_date, cast('{{ var("as_of_date") }}' as date))
            ) > 90
        )                                               as ar_claims_90plus
    from claims
    where is_open_ar
    group by payer

),

per_payer as (

    select
        c.payer,
        count(*)                                        as total_claims,
        round(sum(c.billed_amount))                     as total_billed,
        round(sum(c.paid_amount))                       as total_paid,
        -- Metrics are rounded to reporting precision *before* normalization
        -- so the composite is reproducible from the published one-decimal
        -- figures rather than from hidden extra digits.
        round(100.0 * count(*) filter (where c.is_denied)    / count(*), 1) as denial_rate_pct,
        round(100.0 * count(*) filter (where c.is_underpaid) / count(*), 1) as underpay_rate_pct,
        round(avg(c.days_to_resolve), 1)                                    as avg_days_to_resolve,
        round(100.0 * ar.ar_claims_90plus / ar.ar_claims, 1)                as pct_ar_90plus
    from claims c
    join ar on ar.payer = c.payer
    group by c.payer, ar.ar_claims_90plus, ar.ar_claims

),

-- Min-max normalize each metric across payers (lower is better for all
-- four), then weight. nullif guards the degenerate all-equal case.
scored as (

    select
        *,
        100 * (
              0.35 * (max(denial_rate_pct)     over () - denial_rate_pct)
                   / nullif(max(denial_rate_pct)     over () - min(denial_rate_pct)     over (), 0)
            + 0.25 * (max(underpay_rate_pct)   over () - underpay_rate_pct)
                   / nullif(max(underpay_rate_pct)   over () - min(underpay_rate_pct)   over (), 0)
            + 0.20 * (max(avg_days_to_resolve) over () - avg_days_to_resolve)
                   / nullif(max(avg_days_to_resolve) over () - min(avg_days_to_resolve) over (), 0)
            + 0.20 * (max(pct_ar_90plus)       over () - pct_ar_90plus)
                   / nullif(max(pct_ar_90plus)       over () - min(pct_ar_90plus)       over (), 0)
        ) as composite_score
    from per_payer

)

select
    -- Rank on the reported (rounded) score; ties break toward the lower
    -- denial rate, the heaviest-weighted and most actionable metric.
    row_number() over (
        order by round(composite_score, 1) desc, denial_rate_pct asc
    )                                       as payer_rank,
    payer,
    case
        when round(composite_score, 1) >= 80 then 'A'
        when round(composite_score, 1) >= 65 then 'B'
        when round(composite_score, 1) >= 50 then 'C'
        else 'D'
    end                                     as grade,
    round(composite_score, 1)               as composite_score,
    round(denial_rate_pct, 1)               as denial_rate_pct,
    round(underpay_rate_pct, 1)             as underpay_rate_pct,
    round(avg_days_to_resolve, 1)           as avg_days_to_resolve,
    round(pct_ar_90plus, 1)                 as pct_ar_90plus,
    total_claims,
    total_billed,
    total_paid
from scored
order by payer_rank
