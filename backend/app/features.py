"""Weekly feature construction — the same code as the notebook, in one place.

This is a line-for-line port of the aggregation in
``notebooks/data_preprocess.ipynb`` so the service feeds the pickled models
exactly what they were trained on. If the notebook changes, change this too;
the two must agree or the model is being served something it never saw.

The eight features, in the order the scaler expects them:

    total_spend, transaction_count, avg_transaction, max_transaction,
    4week_avg, 4week_max, spend_vs_avg, week_of_month_num
"""

from __future__ import annotations

from typing import Iterable, Mapping

import pandas as pd

FEATURES = [
    "total_spend",
    "transaction_count",
    "avg_transaction",
    "max_transaction",
    "4week_avg",
    "4week_max",
    "spend_vs_avg",
    "week_of_month_num",
]

# Fewer weeks than this and the rolling features are mostly padding.
MIN_WEEKS = 4


def weekly_features(transactions: Iterable[Mapping]) -> pd.DataFrame:
    """Aggregate raw transactions to one row per week with the model's features.

    ``transactions`` is any iterable of mappings with ``date`` (parseable) and
    ``amount`` (numeric). Non-positive amounts are dropped, as in the notebook.
    Returns the weekly frame ordered by week, most recent last.
    """
    df = pd.DataFrame(list(transactions))
    if df.empty or not {"date", "amount"} <= set(df.columns):
        return pd.DataFrame(columns=["week", *FEATURES])

    df = df.copy()
    df["amount"] = pd.to_numeric(df["amount"], errors="coerce")
    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df = df.dropna(subset=["amount", "date"])
    df = df[df["amount"] > 0]
    if df.empty:
        return pd.DataFrame(columns=["week", *FEATURES])

    df["week"] = df["date"].dt.to_period("W")

    # Verbatim from the notebook.
    weekly = (
        df.groupby("week")
        .agg(
            total_spend=("amount", "sum"),
            transaction_count=("amount", "count"),
            avg_transaction=("amount", "mean"),
            max_transaction=("amount", "max"),
        )
        .reset_index()
        .sort_values("week")
    )
    weekly["4week_avg"] = weekly["total_spend"].rolling(4, min_periods=1).mean()
    weekly["4week_max"] = weekly["total_spend"].rolling(4, min_periods=1).max()
    weekly["spend_vs_avg"] = weekly["total_spend"] / (weekly["4week_avg"] + 1)
    weekly["week_of_month_num"] = weekly["week"].apply(
        lambda w: (pd.Period(str(w), "W").start_time.day - 1) // 7 + 1
    )
    return weekly.reset_index(drop=True)


def latest_feature_row(weekly: pd.DataFrame) -> pd.DataFrame:
    """The single most recent week, as a one-row frame in model column order."""
    return weekly.tail(1)[FEATURES]
