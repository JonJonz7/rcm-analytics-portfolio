-- One row per recoverable claim, ranked by dollar value. Feeds the revenue
-- recovery report. Two opportunity categories (see docs/methodology.md):
--
--   Underpayment:  paid claims below 95% of the expected contracted amount;
--                  recovery = the precomputed gap to the contracted rate.
--   Denial appeal: denied claims weighted by a per-reason appeal success
--                  rate (seeds/appeal_success_rates.csv) so the estimate
--                  reflects realistic recovery, not the full billed amount.
--                  Reasons with negligible viability (patient deductible)
--                  carry a 0 rate and are excluded here.

with claims as (

    select * from {{ ref('stg_claims') }}

),

underpayments as (

    select
        claim_id,
        claim_date,
        payer,
        specialty,
        'Underpayment'                          as category,
        'Exceeds contracted rate'               as reason,
        billed_amount,
        paid_amount,
        round(underpayment_gap, 2)              as recovery_potential,
        'High'                                  as recovery_confidence,
        'Resubmit for rate correction'          as recommended_action
    from claims
    where is_underpaid

),

denial_appeals as (

    select
        c.claim_id,
        c.claim_date,
        c.payer,
        c.specialty,
        'Denial appeal'                         as category,
        r.denial_reason_label                   as reason,
        c.billed_amount,
        c.paid_amount,
        round(c.billed_amount * r.appeal_success_rate, 2)
                                                as recovery_potential,
        case
            when r.appeal_success_rate >= 0.50 then 'High'
            when r.appeal_success_rate >= 0.25 then 'Medium'
            else 'Low'
        end                                     as recovery_confidence,
        'File appeal'                           as recommended_action
    from claims c
    join {{ ref('appeal_success_rates') }} r
        on r.denial_code = c.denial_code
    where c.is_denied
      and r.appeal_success_rate > 0

),

unioned as (

    select * from underpayments
    union all
    select * from denial_appeals

)

select
    row_number() over (order by recovery_potential desc)   as opportunity_rank,
    *
from unioned
order by opportunity_rank
