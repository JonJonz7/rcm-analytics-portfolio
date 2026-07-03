# RCM Analytics Portfolio

Independent, applied analytics work in healthcare revenue cycle management (RCM) — denial pattern detection, underpayment recovery analysis, and payer performance scoring, built on a synthetic claims dataset designed to mirror real RCM data structure.

This repository is a demonstration portfolio, not a product. It exists to show working methodology — data modeling, SQL query design and optimization, and dashboard/reporting design — in a domain I have three years of direct professional experience in. It is intentionally separate from any production system; no proprietary logic, client data, or business-model detail is included here.

## Why this exists

I work in healthcare RCM analytics and I'm independently building an AI-assisted denial detection and underpayment recovery tool. This repo is the public-facing slice of that work: the parts that are useful to show — data structure, query patterns, report design — without exposing anything client-specific or commercially sensitive.

It's also directly relevant to a question I'm interested in: how AI-driven automation changes labor demand and task composition in structured back-office knowledge work. RCM is a clean case study for that question — highly structured (standardized codes, payer rules), economically significant, and currently mid-transition with no dominant automated incumbent. Building detection logic for this domain has meant making concrete decisions about which tasks a model can fully replace and which still require human judgment — the applied version of a question I'd want to study more rigorously.

## What's in this repo

```
sql/
  annotated_queries.sql       Four query patterns (denial rate, AR aging, underpayment
                               detection, month-over-month trend), each shown as an
                               initial working version and an optimized rewrite, with
                               the reasoning for each rewrite explained inline.

data/
  synthetic_claims_data.csv    A 4,800-row synthetic claims dataset (clearly synthetic,
                                built to mirror realistic RCM data structure: payers,
                                specialties, denial codes, billed/paid amounts, status).
  payer_scorecard_data.json    Pre-aggregated payer performance metrics.
  recovery_opportunities_data.json   Ranked recovery opportunity data.

dashboards/
  denial_trend_dashboard.html       Interactive denial rate trend report.
  revenue_recovery_report.html      Executive-style recovery opportunity report.
  payer_scorecard_dashboard.html    Payer performance scorecard + AR aging analysis.
                                     Open any of these directly in a browser — no
                                     server or dependencies required beyond an
                                     internet connection (charts load from a CDN).

docs/
  methodology.md     Explains the data model, the scoring/recovery logic, and the
                      reasoning behind each report's design choices.

demo-app/
  app.py             Runnable Streamlit demo dashboard (denial rate by insurer,
                      monthly trend, charged vs. remitted) over synthetic data.
  auth.py            Minimal env-driven password gate.
  db/                PostgreSQL/Supabase schema with row-level security, plus
                      synthetic seed data. Demo only — no production logic;
                      see demo-app/README.md.
```

## Validation

The SQL in `sql/annotated_queries.sql` was tested end-to-end against the dataset in `data/synthetic_claims_data.csv` using DuckDB before being included here — every optimized query was confirmed to return correct, non-empty results consistent with the dataset's known totals. This isn't just syntactically plausible SQL; it executes and produces the numbers shown in the dashboards.

## What's intentionally not here

This repo does not include the production detection/scoring algorithms, pricing logic, client data, or business-specific tuning used in my actual product work. The goal here is to demonstrate methodology and technical approach, not to publish a commercial system.

## Background

Three years in healthcare RCM analytics (denial pattern analysis, payer behavior, claims reconciliation). Currently pursuing a Georgia Tech M.S. in Analytics (regression, time series, ML methods). Technical background: Python, SQL (including Snowflake), Power BI, Tableau.
