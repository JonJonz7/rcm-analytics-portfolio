# Methodology

## Dataset

`data/synthetic_claims_data.csv` is a synthetically generated, 4,800-row claims dataset built to mirror the structure of real RCM data: seven payers (commercial and government), five clinical specialties, eight standard CARC-style denial codes, and a realistic outcome distribution (approximately 62% paid clean, 14% paid but underpaid relative to contracted rate, 17.5% denied, the remainder pending). These rates were chosen to be realistic for a mid-size multi-specialty clinic, not engineered to produce a flattering result.

The dataset is fully synthetic — generated with a fixed random seed, no real patient or claims data of any kind.

## Underpayment detection logic

A claim is flagged as underpaid when the amount paid falls below 95% of the expected contracted rate (billed amount × expected payer rate). The 5% tolerance band avoids flagging trivial rounding or adjustment differences as a meaningful underpayment.

## Denial appeal recovery estimation

Rather than treating every denied claim's full billed amount as "recoverable" (which would overstate the opportunity), each denial reason code is assigned a realistic appeal-success-rate, and recovery potential is estimated as billed amount × that rate. Reasons with negligible appeal viability (e.g. patient deductible) are excluded entirely from the recovery opportunity list. This is a deliberate design choice: a recovery estimate that's accurate but smaller is more useful to a stakeholder than an inflated number that erodes trust once real appeal outcomes come in lower.

## Payer scorecard composite scoring

Each payer receives a composite score (0–100) combining four normalized metrics:
- Denial rate (35% weight) — directly blocks revenue from entering
- Underpayment rate (25% weight) — recoverable, but requires active resubmission effort
- Average days to resolve (20% weight) — an operational lag indicator
- Percentage of AR in the 90+ day aging bucket (20% weight) — a lagging indicator of unresolved problems

The weighting reflects a judgment call about which problems are most actionable and most upstream — denial rate is weighted heaviest because it's the most direct lever, while aging is weighted lightest because it's largely a downstream symptom of the other three. In a production setting, these weights should be calibrated against actual recovery outcomes rather than set by hand — this is a deliberate, disclosed simplification for a demonstration project.

## SQL optimization patterns

The four query rewrites in `sql/annotated_queries.sql` are general patterns relevant to any claims-scale dataset, not specific to this synthetic data:

1. **Filter before join** — filtering on a clustering-relevant column (date) before joining to a dimension table, rather than after, so the database can prune data early rather than discard it late.
2. **Compute once, reference many** — replacing a value recomputed three times in a CASE statement with a single CTE column.
3. **Correlated subquery → explicit JOIN** — converting a per-row subquery lookup into a single hash join, which is usually the highest-leverage rewrite available in a claims-rate-lookup pattern.
4. **Window function instead of self-join** — using `LAG()` to compare a value to its prior period without materializing and scanning the same aggregation twice.

Each was validated by running both the "before" and "after" versions against the actual dataset and confirming identical results.

## Report design philosophy

The three dashboards in this repo are deliberately built for different audiences and decisions, not as three variations on the same chart:

- **Denial trend dashboard** answers "are things getting better or worse over time" — an operational monitoring tool, dense with filters, meant to be checked repeatedly.
- **Revenue recovery report** answers "how much money is recoverable and where" — an executive document, leads with one headline number and a ranked action list, meant to be read once and acted on.
- **Payer scorecard** answers "which payer is the problem right now" — a comparative ranking tool meant to direct where limited appeal/follow-up resources should go first.
