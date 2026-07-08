-- AR aging by payer and bucket, point-in-time as of var('as_of_date').
-- Feeds the payer scorecard dashboard's aging table.
--
-- Aging clock: a denied claim ages from its denial decision (days_to_resolve
-- captures submission -> decision, and the claim re-enters AR at decision),
-- while a pending claim has no decision yet, so it ages from submission.

with ar_base as (

    select
        claim_id,
        payer,
        billed_amount,
        cast(
            coalesce(
                days_to_resolve,
                date_diff('day', claim_date, cast('{{ var("as_of_date") }}' as date))
            ) as integer
        ) as days_outstanding
    from {{ ref('stg_claims') }}
    where is_open_ar

),

bucketed as (

    select
        *,
        case
            when days_outstanding <= 30 then '0-30'
            when days_outstanding <= 60 then '31-60'
            when days_outstanding <= 90 then '61-90'
            else '90+'
        end as aging_bucket
    from ar_base

)

select
    payer,
    aging_bucket,
    case aging_bucket
        when '0-30' then 1 when '31-60' then 2 when '61-90' then 3 else 4
    end                                 as bucket_order,
    count(*)                            as claim_count,
    round(sum(billed_amount), 2)        as billed_in_bucket
from bucketed
group by payer, aging_bucket
order by payer, bucket_order
