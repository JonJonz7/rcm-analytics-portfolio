-- Cross-artifact consistency: every metric, score, grade, and rank in the
-- scorecard mart must match the published report JSON that the dashboards
-- render. Returns the disagreeing rows (build fails if any).

with published as (

    select unnest(scorecard, recursive := true)
    from read_json_auto('../data/payer_scorecard_data.json')

),

actual as (

    select * from {{ ref('fct_payer_scorecard') }}

)

select
    a.payer,
    a.composite_score  as actual_score,   p.composite_score  as published_score,
    a.grade            as actual_grade,   p.grade            as published_grade,
    a.payer_rank       as actual_rank,    p.rank             as published_rank
from actual a
join published p using (payer)
where abs(a.denial_rate_pct     - p.denial_rate)         > 0.05
   or abs(a.underpay_rate_pct   - p.underpay_rate)       > 0.05
   or abs(a.avg_days_to_resolve - p.avg_days_to_resolve) > 0.05
   or abs(a.pct_ar_90plus       - p.pct_ar_90plus)       > 0.05
   or abs(a.composite_score     - p.composite_score)     > 0.05
   or abs(a.total_billed        - p.total_billed)        > 1
   or a.grade      != p.grade
   or a.payer_rank != p.rank
