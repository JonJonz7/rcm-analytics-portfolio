# Transformation layer (dbt)

A dbt project that turns the raw synthetic claims extract into the tested,
documented marts behind this repo's three dashboards. It exists to show the
production shape of the analysis — staging, metric logic in one place, schema
tests, and lineage — not just the finished numbers.

```
sources.raw.claims  (data/synthetic_claims_data.csv)
        │
   stg_claims  (typed, status flags)
        │
        ├── fct_monthly_denial_trend      → denial trend dashboard
        ├── fct_ar_aging                  → payer scorecard dashboard (aging table)
        ├── fct_payer_scorecard           → payer scorecard dashboard
        └── fct_recovery_opportunities    → revenue recovery report
                └── seeds/appeal_success_rates.csv
```

## Run it

```
python -m venv venv && venv/bin/pip install dbt-duckdb
cd dbt
../venv/bin/dbt build --profiles-dir .
```

No warehouse needed — the profile targets a local DuckDB file and the source
reads the committed CSV directly. `dbt build` runs the seed, five models, and
23 tests in a couple of seconds.

## The tests are the point

Beyond the usual schema tests (unique / not-null keys, accepted values), two
singular tests assert **cross-artifact consistency**: the marts must reproduce
the published report JSONs in `data/` — every payer's scorecard metrics,
composite score, grade, and rank, and the recovery report's summary totals —
or the build fails. Raw CSV to executive dashboard is one tested lineage, not
three artifacts that happen to agree today.

## Relationship to my product work

This mirrors the transformation layer of the AI-assisted denial detection tool
I'm building independently: raw claims land, get staged and typed once, and
tested marts feed the reporting surface. What's deliberately absent is the
same as everywhere else in this repo — the production detection/scoring
models and appeal-rate calibration. The `appeal_success_rates` seed contains
illustrative demo constants (disclosed as a simplification in
`docs/methodology.md`); in production those rates are calibrated against
actual appeal outcomes, and that calibration is the commercially sensitive
part.
