-- Cross-artifact consistency: recovery mart totals must reproduce the
-- summary block of the published recovery report JSON. Returns one row
-- per disagreeing measure (build fails if any).

with published as (

    select
        summary.total_recovery_potential    as total_recovery_potential,
        summary.underpayment_recovery       as underpayment_recovery,
        summary.appeal_recovery             as appeal_recovery,
        summary.high_confidence_recovery    as high_confidence_recovery,
        summary.n_opportunities             as n_opportunities
    from read_json_auto('../data/recovery_opportunities_data.json')

),

actual as (

    select
        round(sum(recovery_potential))                                          as total_recovery_potential,
        round(sum(recovery_potential) filter (where category = 'Underpayment')) as underpayment_recovery,
        round(sum(recovery_potential) filter (where category = 'Denial appeal')) as appeal_recovery,
        round(sum(recovery_potential) filter (where recovery_confidence = 'High')) as high_confidence_recovery,
        count(*)                                                                as n_opportunities
    from {{ ref('fct_recovery_opportunities') }}

),

diffs as (

    select 'total_recovery_potential' as measure, a.total_recovery_potential as actual, p.total_recovery_potential as published
    from actual a, published p where abs(a.total_recovery_potential - p.total_recovery_potential) > 1
    union all
    select 'underpayment_recovery', a.underpayment_recovery, p.underpayment_recovery
    from actual a, published p where abs(a.underpayment_recovery - p.underpayment_recovery) > 1
    union all
    select 'appeal_recovery', a.appeal_recovery, p.appeal_recovery
    from actual a, published p where abs(a.appeal_recovery - p.appeal_recovery) > 1
    union all
    select 'high_confidence_recovery', a.high_confidence_recovery, p.high_confidence_recovery
    from actual a, published p where abs(a.high_confidence_recovery - p.high_confidence_recovery) > 1
    union all
    select 'n_opportunities', a.n_opportunities, p.n_opportunities
    from actual a, published p where a.n_opportunities != p.n_opportunities

)

select * from diffs
