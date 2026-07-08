-- Typed, flagged view over the raw claims landing table. All downstream
-- marts read from here so status semantics live in exactly one place.

with source as (

    select * from {{ source('raw', 'claims') }}

)

select
    claim_id,
    cast(claim_date as date)                            as claim_date,
    date_trunc('month', cast(claim_date as date))       as claim_month,
    payer,
    specialty,
    cast(billed_amount as double)                       as billed_amount,
    cast(paid_amount as double)                         as paid_amount,
    status,
    denial_code,
    denial_reason,
    cast(days_to_resolve as double)                     as days_to_resolve,
    cast(underpayment_gap as double)                    as underpayment_gap,

    status = 'Denied'                                   as is_denied,
    status = 'Paid - Underpaid'                         as is_underpaid,
    -- Open AR = anything not yet collected: pending claims and denials
    -- awaiting appeal/write-off.
    status in ('Pending', 'Denied')                     as is_open_ar

from source
