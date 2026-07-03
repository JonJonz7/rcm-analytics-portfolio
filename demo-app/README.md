# RCM Analytics Demo App

**This is a demo, not production software.** It exists to show working structure —
a multi-tenant claims data model with row-level security, a small Streamlit
dashboard, and a minimal auth gate — over entirely synthetic data.

## What this is

A self-contained slice of a healthcare revenue cycle analytics app:

- **`app.py`** — Streamlit dashboard: denial rate by insurer, monthly denial
  trend, charged vs. remitted amounts, and a data table view.
- **`auth.py`** — single shared-password gate (constant-time comparison,
  session state, secret read from the environment).
- **`db/schema.sql`** — PostgreSQL/Supabase schema: organizations, users,
  claim records, and saved analysis runs, with row-level security policies
  scoping every read to the caller's organization and denying user writes to
  analytical output by default.
- **`db/seed_synthetic.sql`** — fabricated seed rows: fictional insurers,
  placeholder adjustment codes, arbitrary amounts.
- **`.env.example`** — the two optional environment variables.

## What this is not

- Not connected to any real system, client, or dataset.
- No production analytical logic: the dashboard computes plain descriptive
  aggregates (counts, sums, simple percentages) and nothing else. All
  product-specific analysis has been removed by design.
- Not a template for handling real healthcare data — a production system
  needs de-identification, validation, audit logging, and a signed BAA
  before any real claims file is touched.

## Run it

```bash
pip install -r requirements.txt
streamlit run app.py
```

With no environment variables set, the app generates a deterministic
synthetic dataset in memory and skips the login gate — it runs with zero
setup. To point it at a database instead, apply `db/schema.sql` and
`db/seed_synthetic.sql` to a Postgres instance and set `DATABASE_URL`
(plus the optional dependencies noted in `requirements.txt`).
