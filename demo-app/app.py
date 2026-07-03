"""RCM Analytics Demo — Streamlit entry point.

DEMO ONLY. A small claims-analytics dashboard over synthetic data: denial
rate by insurer, monthly denial trend, and charged vs. remitted amounts.
Descriptive analytics only — no product-specific analytical logic.

Data source: reads from DATABASE_URL when set (see db/schema.sql and
db/seed_synthetic.sql); otherwise generates a deterministic synthetic
dataset in memory so the app runs with no setup at all.
"""
from __future__ import annotations

import os

import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from auth import require_auth

# Validated chart palette (light surface)
SERIES_1 = "#2a78d6"   # blue
SERIES_2 = "#1baf7a"   # aqua
INK_MUTED = "#898781"
GRIDLINE = "#e1e0d9"
BASELINE = "#c3c2b7"

INSURERS = ["Acme Health Plan", "Umbrella Insurance Co", "Northwind Mutual", "Globex Benefits"]
PROCEDURES = ["90001", "90002", "90003", "90004"]


@st.cache_data
def load_claims() -> pd.DataFrame:
    """Load claim records from the database when configured, else synthesize them."""
    db_url = os.getenv("DATABASE_URL", "")
    if db_url:
        from sqlalchemy import create_engine  # optional dependency, only for DB mode

        engine = create_engine(db_url)
        return pd.read_sql("select * from claim_records", engine, parse_dates=["service_date"])
    return _synthetic_claims()


def _synthetic_claims(n: int = 600) -> pd.DataFrame:
    """Build a deterministic synthetic claims dataset (clearly fake, seeded RNG)."""
    rng = np.random.default_rng(seed=7)
    service_dates = pd.to_datetime("2026-01-01") + pd.to_timedelta(
        rng.integers(0, 180, size=n), unit="D"
    )
    charge = rng.integers(120, 600, size=n).astype(float)
    status = rng.choice(["paid", "denied", "pending"], size=n, p=[0.74, 0.18, 0.08])
    remit = np.where(status == "paid", (charge * rng.uniform(0.6, 0.9, size=n)).round(2), 0.0)
    return pd.DataFrame(
        {
            "external_ref": [f"DEMO-{i:04d}" for i in range(n)],
            "service_date": service_dates,
            "procedure_code": rng.choice(PROCEDURES, size=n),
            "insurer_name": rng.choice(INSURERS, size=n),
            "charge_amount": charge,
            "remit_amount": remit,
            "record_status": status,
        }
    )


def _base_layout(fig: go.Figure, title: str) -> go.Figure:
    """Apply shared chart chrome: recessive grid and axes, muted labels."""
    fig.update_layout(
        title=dict(text=title, font=dict(size=15)),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(family="system-ui, -apple-system, Segoe UI, sans-serif", color=INK_MUTED, size=12),
        margin=dict(l=8, r=8, t=48, b=8),
        hovermode="x unified",
    )
    fig.update_xaxes(showgrid=False, linecolor=BASELINE, ticks="outside", tickcolor=BASELINE)
    fig.update_yaxes(gridcolor=GRIDLINE, gridwidth=1, zeroline=False, linecolor="rgba(0,0,0,0)")
    return fig


def denial_rate_by_insurer(df: pd.DataFrame) -> go.Figure:
    decided = df[df["record_status"].isin(["paid", "denied"])]
    rate = (
        decided.groupby("insurer_name")["record_status"]
        .apply(lambda s: (s == "denied").mean() * 100)
        .sort_values()
    )
    fig = go.Figure(
        go.Bar(
            x=rate.values,
            y=rate.index,
            orientation="h",
            marker=dict(color=SERIES_1, cornerradius=4),
            width=0.55,
            text=[f"{v:.1f}%" for v in rate.values],
            textposition="outside",
            textfont=dict(color=INK_MUTED),
            hovertemplate="%{y}: %{x:.1f}% denied<extra></extra>",
        )
    )
    fig = _base_layout(fig, "Denial rate by insurer")
    fig.update_xaxes(title="", ticksuffix="%", showgrid=True, gridcolor=GRIDLINE)
    fig.update_yaxes(showgrid=False)
    fig.update_layout(hovermode="closest")
    return fig


def monthly_denial_trend(df: pd.DataFrame) -> go.Figure:
    decided = df[df["record_status"].isin(["paid", "denied"])].copy()
    decided["month"] = decided["service_date"].dt.to_period("M").dt.to_timestamp()
    rate = decided.groupby("month")["record_status"].apply(lambda s: (s == "denied").mean() * 100)
    fig = go.Figure(
        go.Scatter(
            x=rate.index,
            y=rate.values,
            mode="lines+markers",
            line=dict(color=SERIES_1, width=2),
            marker=dict(size=8, color=SERIES_1),
            hovertemplate="%{x|%b %Y}: %{y:.1f}% denied<extra></extra>",
        )
    )
    fig = _base_layout(fig, "Monthly denial rate")
    fig.update_yaxes(ticksuffix="%", rangemode="tozero")
    return fig


def charged_vs_remitted(df: pd.DataFrame) -> go.Figure:
    monthly = (
        df.assign(month=df["service_date"].dt.to_period("M").dt.to_timestamp())
        .groupby("month")[["charge_amount", "remit_amount"]]
        .sum()
    )
    fig = go.Figure(
        [
            go.Bar(
                name="Charged",
                x=monthly.index,
                y=monthly["charge_amount"],
                marker=dict(color=SERIES_1, cornerradius=4),
                hovertemplate="Charged: $%{y:,.0f}<extra></extra>",
            ),
            go.Bar(
                name="Remitted",
                x=monthly.index,
                y=monthly["remit_amount"],
                marker=dict(color=SERIES_2, cornerradius=4),
                hovertemplate="Remitted: $%{y:,.0f}<extra></extra>",
            ),
        ]
    )
    fig = _base_layout(fig, "Charged vs. remitted by month")
    fig.update_layout(
        barmode="group",
        bargap=0.35,
        bargroupgap=0.15,
        legend=dict(orientation="h", yanchor="bottom", y=1.0, xanchor="right", x=1.0),
    )
    fig.update_yaxes(tickprefix="$", tickformat=",.0f")
    return fig


def main() -> None:
    st.set_page_config(page_title="RCM Analytics Demo", page_icon="📄", layout="wide")
    require_auth()

    st.title("RCM Analytics Demo")
    st.caption(
        "Demonstration app, not production software. All data is synthetic — "
        "see the README for what this demo does and does not include."
    )

    df = load_claims()
    decided = df[df["record_status"].isin(["paid", "denied"])]
    denial_pct = (decided["record_status"] == "denied").mean() * 100 if len(decided) else 0.0

    k1, k2, k3, k4 = st.columns(4)
    k1.metric("Claims", f"{len(df):,}")
    k2.metric("Charged", f"${df['charge_amount'].sum():,.0f}")
    k3.metric("Remitted", f"${df['remit_amount'].sum():,.0f}")
    k4.metric("Denial rate", f"{denial_pct:.1f}%")

    c1, c2 = st.columns(2)
    with c1:
        st.plotly_chart(denial_rate_by_insurer(df), use_container_width=True)
    with c2:
        st.plotly_chart(monthly_denial_trend(df), use_container_width=True)

    st.plotly_chart(charged_vs_remitted(df), use_container_width=True)

    with st.expander("View data table"):
        st.dataframe(df.sort_values("service_date"), use_container_width=True, hide_index=True)


if __name__ == "__main__":
    main()
