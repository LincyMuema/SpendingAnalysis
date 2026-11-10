"""
Analysis routes.

GET /analysis/{user_id}
Runs spending pattern analysis, anomaly detection, predictions,
and generates user-friendly insights and recommendations.
"""

import json
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import get_db
from security import get_current_user_id, require_same_user
from main import models


router = APIRouter()

# Must match encoder_category.classes_ from the training notebook EXACTLY
CATEGORY_CLASSES = [
    "Airtime and Data", "Cash Advance", "Crypto Purchase", "Electronics Upgrade",
    "Entertainment", "Foreign Transfer", "Gambling", "Groceries",
    "Household Help", "Jewellery", "Luxury Goods", "Medical", "Rent",
    "Savings", "School Fees", "Transport", "Utilities",
]

# Database (app) categories -> closest training category
DB_TO_TRAINING_CATEGORY = {
    "Bills & Utilities": "Utilities",
    "Business":          "Groceries",
    "Crypto":            "Crypto Purchase",
    "Education":         "School Fees",
    "Entertainment":     "Entertainment",
    "Food & Dining":     "Groceries",
    "Gambling":          "Gambling",
    "Government":        "Utilities",
    "Healthcare":        "Medical",
    "Insurance":         "Utilities",
    "Investments":       "Savings",
    "Other":             "Groceries",
    "Personal Care":     "Groceries",
    "Shopping":          "Groceries",
    "Transfer":          "Foreign Transfer",
    "Transport":         "Transport",
    "Travel":            "Transport",
}
FALLBACK_CATEGORY = "Groceries"

# Anomaly display rules (applied after the Isolation Forest, no retraining).
# The first days of a user's history have no baseline, so every category
# looks "new" and every amount looks unusual. Scores just below zero are
# borderline, so only clearer cases are shown.
ANOMALY_WARMUP_DAYS = 14
ANOMALY_SCORE_CUTOFF = -0.03
# Anomalies are alerts, so only recent ones are shown, recurring payments
# (e.g. monthly rent) are skipped, and only the most unusual few are listed.
ANOMALY_RECENT_DAYS = 30
ANOMALY_MAX_SHOWN = 5
RECURRING_GAP_DAYS = (25, 35)      # about a month apart
RECURRING_AMOUNT_TOLERANCE = 0.10  # within 10% of each other

# Time-of-day features (must match the preprocessing notebook)
UNKNOWN_TIME_HOUR = 12          # payments with no recorded time are placed at midday
NIGHT_HOURS = (22, 5)           # 22:00 to 04:59 counts as night
MAX_GAP_MINUTES = 10080         # one week; longer gaps (and the first payment) are capped here
# Median of log_mins_since_prev in the training data, used when the exact
# time of a payment is not known
UNKNOWN_LOG_MINS = 6.83

SOURCE_MAP = {
    "CARD": 0,
    "CASH": 1,
    "MPESA": 2,
    "WALLET": 3,
}


# ── Encoding helpers ────────────────────────────────────────────────────────

def encode_category(name: str) -> int:
    """Encode a category using the same codes as training."""
    name = str(name or "Other").strip()
    if name in CATEGORY_CLASSES:
        return CATEGORY_CLASSES.index(name)
    mapped = DB_TO_TRAINING_CATEGORY.get(name, FALLBACK_CATEGORY)
    return CATEGORY_CLASSES.index(mapped)


def encode_source(source: str) -> int:
    """Encode a transaction source using the training mapping."""
    return SOURCE_MAP.get(str(source or "").upper().strip(), SOURCE_MAP["MPESA"])


# ── Database access ─────────────────────────────────────────────────────────

def fetch_user_transactions(user_id: int, db: Session) -> pd.DataFrame:
    """Fetch and prepare one user's transactions."""
    rows = db.execute(
        text(
            """
            SELECT
                t.transaction_id,
                t.amount,
                t.date,
                t.occurred_at,
                t.transaction_type,
                t.source,
                t.counterparty,
                c.name AS category_name,
                COALESCE(t.anomaly_dismissed, FALSE) AS anomaly_dismissed
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.category_id
            WHERE t.user_id = :user_id
            ORDER BY t.date ASC, t.occurred_at ASC NULLS FIRST, t.transaction_id ASC
            """
        ),
        {"user_id": user_id},
    ).fetchall()

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(
        rows,
        columns=[
            "transaction_id",
            "amount",
            "date",
            "occurred_at",
            "transaction_type",
            "source",
            "counterparty",
            "category_name",
            "anomaly_dismissed",
        ],
    )

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df["amount"] = pd.to_numeric(df["amount"], errors="coerce")
    df["category_name"] = df["category_name"].fillna("Other")
    df["source"] = df["source"].fillna("MPESA")
    df["counterparty"] = df["counterparty"].fillna("").astype(str).str.strip().str.upper()
    df["transaction_type"] = df["transaction_type"].fillna("expense")

    df = df.dropna(subset=["date", "amount"])
    df = df[df["amount"] > 0].copy()

    # Full date and time of each payment. Older rows (and manual entries for
    # past days) have no time, so they are placed at midday and marked, and the
    # time features that need an exact time are neutralised for them.
    occurred = pd.to_datetime(df["occurred_at"], errors="coerce")
    df["time_known"] = occurred.notna()
    df["ts"] = occurred.where(df["time_known"], df["date"] + pd.Timedelta(hours=UNKNOWN_TIME_HOUR))

    # Payments are kept in time order; ties keep the order they were recorded,
    # so results do not change when rows are updated (e.g. an anomaly is dismissed).
    df = df.sort_values(["ts", "transaction_id"], kind="mergesort").reset_index(drop=True)

    return df


# ── Feature engineering ─────────────────────────────────────────────────────

def add_transaction_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add the features used by the clustering and anomaly models."""
    df = df.copy()

    df["category_encoded"] = df["category_name"].apply(encode_category)
    df["source_encoded"] = df["source"].apply(encode_source)

    df["day_of_week"] = df["date"].dt.dayofweek
    df["week_of_month"] = (df["date"].dt.day - 1) // 7 + 1
    df["is_weekend"] = (df["day_of_week"] >= 5).astype(int)

    # These rolling features use only earlier transactions, not the current one.
    df = df.sort_values(["ts", "transaction_id"], kind="mergesort").reset_index(drop=True)
    known = df["time_known"].to_numpy()
    ts_indexed_amounts = df.set_index("ts")["amount"]

    df["7day_spend"] = (
        ts_indexed_amounts.rolling("7D", closed="left").sum().to_numpy()
    )
    df["30day_avg"] = (
        ts_indexed_amounts.rolling("30D", closed="left").mean().to_numpy()
    )

    df["7day_spend"] = df["7day_spend"].fillna(0.0)
    df["30day_avg"] = df["30day_avg"].fillna(df["amount"])

    df["spending_velocity"] = (
        df["amount"] / df["30day_avg"].replace(0, np.nan)
    ).replace([np.inf, -np.inf], np.nan).fillna(1.0)

    # Category behaviour features. They describe how this user uses a category,
    # not which category it is, so they work for ANY category (including
    # categories a user creates). Only earlier transactions are used.
    prior_total = np.arange(len(df))                                   # transactions before this one
    prior_in_cat = df.groupby("category_name").cumcount().to_numpy()   # earlier ones in this category
    df["cat_share"] = np.where(prior_total > 0, prior_in_cat / np.maximum(prior_total, 1), 0.0)

    prev_cat_mean = df.groupby("category_name")["amount"].transform(
        lambda s: s.expanding().mean().shift(1)
    )
    df["cat_amount_ratio"] = (
        df["amount"] / prev_cat_mean.replace(0, np.nan)
    ).replace([np.inf, -np.inf], np.nan).fillna(1.0)

    df["is_new_category"] = (prior_in_cat == 0).astype(int)

    # Time of day, as a point on a 24-hour circle (so 23:00 and 01:00 are close)
    hour = df["ts"].dt.hour + df["ts"].dt.minute / 60
    df["hour"] = hour
    df["hour_sin"] = np.sin(2 * np.pi * hour / 24)
    df["hour_cos"] = np.cos(2 * np.pi * hour / 24)
    df["is_night"] = (((hour >= NIGHT_HOURS[0]) | (hour < NIGHT_HOURS[1])) & known).astype(int)

    # How many payments were made in the previous 1 hour and 24 hours
    df["tx_count_1h"] = ts_indexed_amounts.rolling("1h", closed="left").count().to_numpy()
    df["tx_count_24h"] = ts_indexed_amounts.rolling("24h", closed="left").count().to_numpy()
    df["tx_count_1h"] = df["tx_count_1h"].fillna(0.0)
    df["tx_count_24h"] = df["tx_count_24h"].fillna(0.0)

    # Minutes since the previous payment (log scale, capped at one week)
    mins = df["ts"].diff().dt.total_seconds() / 60
    df["log_mins_since_prev"] = np.log1p(mins.fillna(MAX_GAP_MINUTES).clip(upper=MAX_GAP_MINUTES))

    # Same amount in the same category within the previous hour
    gap_same = df.groupby(["category_name", "amount"])["ts"].diff().dt.total_seconds() / 60
    df["dup_1h"] = (gap_same <= 60).astype(int)

    # Without an exact time these cannot be measured, so they are set to
    # "nothing unusual" instead of treating midday as a real time.
    df.loc[~known, "tx_count_1h"] = 0.0
    df.loc[~known, "dup_1h"] = 0
    same_day_unknown = (~known) & (mins.fillna(MAX_GAP_MINUTES) < 24 * 60).to_numpy()
    df.loc[same_day_unknown, "log_mins_since_prev"] = UNKNOWN_LOG_MINS

    return df


def build_weekly_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Aggregate expense transactions into weekly rows.
    The current Random Forest model expects these eight features.
    """
    df = df.copy()
    df["week"] = df["date"].dt.to_period("W")

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
        .reset_index(drop=True)
    )

    # Historical features are shifted so the current week is not included
    # in its own historical average or maximum.
    weekly["4week_avg"] = (
        weekly["total_spend"]
        .rolling(4, min_periods=1)
        .mean()
        .shift(1)
        .fillna(0.0)
    )
    weekly["4week_max"] = (
        weekly["total_spend"]
        .rolling(4, min_periods=1)
        .max()
        .shift(1)
        .fillna(0.0)
    )

    weekly["spend_vs_avg"] = (
        weekly["total_spend"] / weekly["4week_avg"].replace(0, np.nan)
    ).replace([np.inf, -np.inf], np.nan).fillna(1.0)

    weekly["week_of_month_num"] = weekly["week"].apply(
        lambda period: (period.start_time.day - 1) // 7 + 1
    )

    return weekly


# ── K-Means spending pattern analysis ───────────────────────────────────────

HABIT_PERIODS = [30, 90, 180, 365]  # the periods the Habits tab can switch between


def run_clustering(df: pd.DataFrame, period_start=None) -> dict:
    """
    Assign transactions to the trained K-Means spending clusters.
    Features are built from the whole history (so comparisons with earlier
    spending are correct), but only the selected period is described.
    """
    kmeans = models["kmeans_model"]
    scaler = models["scaler_clustering"]

    # Must match features_clustering in the training notebook (same order)
    clustering_features = [
        "amount",
        "cat_share",
        "cat_amount_ratio",
        "is_new_category",
        "day_of_week",
        "week_of_month",
        "is_weekend",
        "7day_spend",
        "30day_avg",
        "spending_velocity",
        "hour_sin",
        "hour_cos",
    ]

    featured_df = add_transaction_features(df)
    x = featured_df[clustering_features].values
    x_scaled = scaler.transform(x)
    featured_df["cluster"] = kmeans.predict(x_scaled)
    end = featured_df["date"].max()

    # Habits for each period the app can show, so switching is instant
    by_period = {}
    for days in HABIT_PERIODS:
        window = featured_df[featured_df["date"] >= end - pd.Timedelta(days=days - 1)]
        by_period[str(days)] = {
            "days": days,
            "transaction_count": int(len(window)),
            "total_spend_kes": round(float(window["amount"].sum()), 2),
            "clusters": describe_clusters(window) if len(window) else {},
        }

    if period_start is not None:
        featured_df = featured_df[featured_df["date"] >= period_start]
    if featured_df.empty:
        return {"cluster_count": 0, "model_cluster_count": int(kmeans.n_clusters),
                "clusters": {}, "by_period": by_period}

    return {
        "cluster_count": int(featured_df["cluster"].nunique()),  # habits this user actually has
        "model_cluster_count": int(kmeans.n_clusters),
        "clusters": describe_clusters(featured_df),
        "by_period": by_period,
    }


DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
SOURCE_LABELS = {"MPESA": "M-Pesa", "CARD": "card", "CASH": "cash", "WALLET": "wallet"}


PARTS_OF_DAY = [  # (name, from hour, to hour)
    ("morning", 5, 12),
    ("afternoon", 12, 17),
    ("evening", 17, 22),
    ("night", 22, 29),   # 22:00 to 04:59 (hours after midnight are +24)
]


def _part_of_day(hours: pd.Series) -> tuple:
    """Main part of the day for a group of payments, and its share (0-100)."""
    if hours.empty:
        return "", 0.0
    h = hours.where(hours >= 5, hours + 24)
    shares = {name: float(((h >= lo) & (h < hi)).mean() * 100) for name, lo, hi in PARTS_OF_DAY}
    name = max(shares, key=shares.get)
    return name, shares[name]


def _typical_time(hours: pd.Series) -> str | None:
    """'around 10:30 AM' from the median clock time of the payments."""
    if hours.empty:
        return None
    # Circular mean, so payments at 23:00 and 01:00 average to midnight
    angle = np.arctan2(np.sin(2 * np.pi * hours / 24).mean(), np.cos(2 * np.pi * hours / 24).mean())
    mins = int(round((angle / (2 * np.pi) * 24 % 24) * 60 / 15) * 15) % (24 * 60)
    h, m = divmod(mins, 60)
    return f"around {(h % 12) or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"


def _habit_name(median_amount: float, user_median: float, pct_weekend: float,
                count_share: float, top_categories: list, bills_count_pct: float,
                pct_new_category: float, part_of_day: str = "") -> str:
    """A plain-language name built from what is in the group."""
    main_cat, main_share = (top_categories[0]["name"], top_categories[0]["pct"]) if top_categories else ("", 0)

    if median_amount >= 5 * user_median and count_share <= 0.10:
        return "Big one-off purchases"
    # Mostly first-ever payments in a category (common in the first days of data)
    if pct_new_category >= 50:
        return "First-time spending"
    # Bills must be most of the money AND most of the payments
    # (one large rent payment alone should not make a group "bills")
    if main_cat == "Bills & Utilities" and main_share >= 50 and bills_count_pct >= 50:
        return "Bills and utilities"

    if median_amount <= user_median:
        size = "Small"
    elif median_amount >= 3 * user_median:
        size = "Large"
    else:
        size = ""

    if pct_weekend >= 70:
        when = "weekend"
    elif pct_weekend <= 15:
        when = "weekday"
    else:
        when = ""

    # e.g. "Weekday morning spends", "Large weekend evening payments", "Evening spending"
    words = [w for w in (size, when, part_of_day) if w]
    if not words:
        return "Everyday spending"
    if not (when or part_of_day) and size == "Small":
        words.append("everyday")
    noun = "spends" if size == "Small" else "payments" if size == "Large" else "spending"
    name = " ".join(words + [noun])
    return name[0].upper() + name[1:]


def describe_clusters(featured_df: pd.DataFrame) -> dict:
    """
    Describe each habit (cluster) in terms a user understands: what it is
    mostly spent on, where, how much, when and how it is paid.
    """
    total_money = float(featured_df["amount"].sum()) or 1.0
    total_count = len(featured_df) or 1
    user_median = float(featured_df["amount"].median()) or 1.0

    clusters_out = {}
    for cluster_id, g in featured_df.groupby("cluster"):
        money = float(g["amount"].sum())

        cat_money = g.groupby("category_name")["amount"].sum().sort_values(ascending=False)
        top_categories = [
            {"name": str(name), "pct": round(float(amount) / money * 100) if money else 0}
            for name, amount in cat_money.head(3).items()
        ]

        merchants = g.loc[g["counterparty"] != "", "counterparty"].value_counts().head(3)
        top_merchants = [str(m).title() for m in merchants.index]

        median_amount = float(g["amount"].median())
        pct_weekend = float(g["is_weekend"].mean() * 100)
        count_share = len(g) / total_count

        bills_count_pct = float((g["category_name"] == "Bills & Utilities").mean() * 100)

        # Time of day, only from payments whose exact time is known.
        # A part of the day is named only when most payments fall in it.
        timed = g.loc[g["time_known"], "hour"]
        enough_times = len(timed) >= 3 and len(timed) >= 0.5 * len(g)
        part, part_pct = _part_of_day(timed) if enough_times else ("", 0.0)
        part_of_day = part if part_pct >= 50 else ""

        clusters_out[int(cluster_id)] = {
            "habit_name": _habit_name(median_amount, user_median, pct_weekend, count_share,
                                      top_categories, bills_count_pct,
                                      float(g["is_new_category"].mean() * 100),
                                      part_of_day),
            "transaction_count": int(len(g)),
            "avg_amount_kes": round(float(g["amount"].mean()), 2),
            "median_amount_kes": round(median_amount, 2),
            "typical_low_kes": round(float(g["amount"].quantile(0.25)), 2),
            "typical_high_kes": round(float(g["amount"].quantile(0.75)), 2),
            "total_spend_kes": round(money, 2),
            "share_of_spend_pct": round(money / total_money * 100, 1),
            "pct_weekend": round(pct_weekend, 1),
            "busiest_day": DAY_NAMES[int(g["day_of_week"].mode().iloc[0])],
            "part_of_day": part_of_day or None,
            "part_of_day_pct": round(part_pct, 1) if part_of_day else None,
            "typical_time": _typical_time(timed) if enough_times else None,
            "main_source": SOURCE_LABELS.get(str(g["source"].mode().iloc[0]).upper(), "M-Pesa"),
            "top_category": top_categories[0]["name"] if top_categories else "Other",
            "top_categories": top_categories,
            "top_merchants": top_merchants,
        }

    # Make names unique, e.g. two "Weekday spending" groups
    seen = {}
    for c in sorted(clusters_out.values(), key=lambda c: -c["total_spend_kes"]):
        name = c["habit_name"]
        if name in seen:
            c["habit_name"] = f"{name} ({c['top_category']})"
        seen[name] = True

    return clusters_out


# ── Isolation Forest anomaly detection ──────────────────────────────────────

def _is_recurring(row, df: pd.DataFrame) -> bool:
    """True if the same payee received a similar amount about a month before or after."""
    payee = row["counterparty"]
    if not payee:
        return False
    same_payee = df[(df["counterparty"] == payee) & (df["transaction_id"] != row["transaction_id"])]
    if same_payee.empty:
        return False
    gap = (same_payee["date"] - row["date"]).abs().dt.days
    similar = (same_payee["amount"] - row["amount"]).abs() <= RECURRING_AMOUNT_TOLERANCE * row["amount"]
    return bool(((gap >= RECURRING_GAP_DAYS[0]) & (gap <= RECURRING_GAP_DAYS[1]) & similar).any())


def _fmt_time(row) -> str | None:
    """'2:14 PM' when the exact time is known, otherwise None."""
    if not row["time_known"]:
        return None
    t = row["ts"]
    return f"{(t.hour % 12) or 12}:{t.minute:02d} {'AM' if t.hour < 12 else 'PM'}"


def _anomaly_reasons(row) -> list:
    """Plain-language reasons a payment stands out (at most two)."""
    reasons = []
    if row["dup_1h"] == 1:
        reasons.append("The same amount was paid in this category less than an hour before")
    if row["tx_count_1h"] >= 3:
        reasons.append(f"{int(row['tx_count_1h'])} other payments in the hour before it")
    if row["is_night"] == 1:
        reasons.append(f"Paid late at night ({_fmt_time(row)})")
    if row["is_new_category"] == 1:
        reasons.append("Your first payment in this category")
    if row["cat_amount_ratio"] >= 3:
        reasons.append(f"About {row['cat_amount_ratio']:.0f}x what you usually pay for {row['category_name']}")
    elif row["spending_velocity"] >= 3:
        reasons.append(f"About {row['spending_velocity']:.0f}x your average payment this month")
    if not reasons:
        reasons.append("An unusual mix of amount, timing and category for you")
    return reasons[:2]


def run_anomaly_detection(df: pd.DataFrame) -> dict:
    """Flag transactions that the trained Isolation Forest considers unusual."""
    iso_forest = models["isolation_forest_model"]

    # Must match the feature set the training notebook selected (same order)
    anomaly_features = [
        "amount",
        "cat_share",
        "cat_amount_ratio",
        "is_new_category",
        "source_encoded",
        "day_of_week",
        "is_weekend",
        "spending_velocity",
        "hour_sin",
        "hour_cos",
        "is_night",
        "tx_count_1h",
        "tx_count_24h",
        "log_mins_since_prev",
        "dup_1h",
    ]

    featured_df = add_transaction_features(df)
    x = featured_df[anomaly_features].values

    predictions = iso_forest.predict(x)  # -1 = flagged, 1 = not flagged
    scores = iso_forest.decision_function(x)

    featured_df["anomaly_flag"] = predictions
    featured_df["anomaly_score"] = scores

    # Skip transactions the user has confirmed are normal
    dismissed = featured_df["anomaly_dismissed"].fillna(False).astype(bool)

    # Skip the warm-up period and borderline scores
    warmup_end = featured_df["date"].min() + pd.Timedelta(days=ANOMALY_WARMUP_DAYS)
    after_warmup = featured_df["date"] >= warmup_end
    clear_case = featured_df["anomaly_score"] < ANOMALY_SCORE_CUTOFF

    candidates = featured_df[
        (featured_df["anomaly_flag"] == -1) & clear_case & after_warmup & ~dismissed
    ].copy()
    model_flagged = len(candidates)

    # Only recent transactions are worth an alert
    recent_start = featured_df["date"].max() - pd.Timedelta(days=ANOMALY_RECENT_DAYS)
    candidates = candidates[candidates["date"] >= recent_start]

    # Skip recurring payments (same payee, similar amount, about a month apart)
    candidates = candidates[
        ~candidates.apply(lambda row: _is_recurring(row, featured_df), axis=1)
    ] if len(candidates) else candidates

    # Show only the most unusual few
    anomalies = candidates.sort_values("anomaly_score").head(ANOMALY_MAX_SHOWN)
    anomaly_rate = (len(anomalies) / len(featured_df) * 100) if len(featured_df) else 0

    anomaly_list = sorted(
        [
            {
                "transaction_id": int(row["transaction_id"]),
                "amount": round(float(row["amount"]), 2),
                "date": str(row["date"].date()),
                "time": _fmt_time(row),
                "category": str(row["category_name"]),
                "counterparty": str(row["counterparty"]).title() if row["counterparty"] else None,
                "reasons": _anomaly_reasons(row),
                "source": str(row["source"]),
                "anomaly_score": round(float(row["anomaly_score"]), 4),
            }
            for _, row in anomalies.iterrows()
        ],
        key=lambda item: item["anomaly_score"],
    )

    return {
        "total_transactions": int(len(featured_df)),
        "model_flagged_count": int(model_flagged),  # before the display rules
        "recent_days": ANOMALY_RECENT_DAYS,
        "anomaly_count": int(len(anomalies)),
        "anomaly_rate_pct": round(float(anomaly_rate), 2),
        "anomalies": anomaly_list,
    }


# ── Random Forest weekly spending prediction ────────────────────────────────

def run_prediction(df: pd.DataFrame) -> dict:
    """
    Predict weekly spending for the next four weeks.

    IMPORTANT: This function assumes the Random Forest was trained using the
    same eight features and feature order listed below.
    """
    rf_model = models["random_forest_model"]
    scaler = models["scaler_prediction"]

    prediction_features = [
        "total_spend",
        "transaction_count",
        "avg_transaction",
        "max_transaction",
        "4week_avg",
        "4week_max",
        "spend_vs_avg",
        "week_of_month_num",
    ]

    weekly = build_weekly_features(df)

    if len(weekly) < 4:
        return {
            "status": "insufficient_data",
            "message": "At least 4 weeks of transactions are needed for predictions.",
            "predictions": [],
        }

    # Forecast from the end of the last recorded week.
    history = weekly["total_spend"].astype(float).tolist()
    last_week_start = weekly["week"].iloc[-1].start_time
    last_observed = weekly.iloc[-1]

    predictions = []

    for i in range(1, 5):
        previous_four = history[-4:]
        historical_average = float(np.mean(previous_four))
        historical_maximum = float(np.max(previous_four))

        next_week_start = last_week_start + timedelta(weeks=i)

        # For future rows, the target-week transaction count/average/max are
        # not known. Use the most recent observed values as estimates.
        feature_row = {
            "total_spend": history[-1],
            "transaction_count": float(last_observed["transaction_count"]),
            "avg_transaction": float(last_observed["avg_transaction"]),
            "max_transaction": float(last_observed["max_transaction"]),
            "4week_avg": historical_average,
            "4week_max": historical_maximum,
            "spend_vs_avg": (
                history[-1] / historical_average
                if historical_average > 0 else 1.0
            ),
            "week_of_month_num": (next_week_start.day - 1) // 7 + 1,
        }

        x_future = pd.DataFrame(
            [feature_row], columns=prediction_features
        ).values
        x_scaled = scaler.transform(x_future)
        predicted_spend = max(0.0, float(rf_model.predict(x_scaled)[0]))

        predictions.append(
            {
                "week_label": next_week_start.strftime("Week of %d %b %Y"),
                "predicted_spend_kes": round(predicted_spend, 2),
            }
        )

        # Use this prediction as history for the following forecast.
        history.append(predicted_spend)

    return {
        "status": "ok",
        "model_used": "Random Forest Regression",
        "weeks_of_history": int(len(weekly)),
        "average_weekly_spend_kes": round(
            float(weekly["total_spend"].mean()), 2
        ),
        "predictions": predictions,
    }


# ── Insights and recommendations ────────────────────────────────────────────

# ── Recurring payments and subscriptions ─────────────────────────────────────

RECURRING_PATTERNS = [
    # (label, min days between payments, max days, minimum number of payments)
    ("Weekly", 6, 8, 3),
    ("Every 2 weeks", 13, 16, 3),
    ("Monthly", 26, 35, 2),
]
RECURRING_PRICE_TOLERANCE = 0.15   # payments within 15% of the usual amount
PRICE_CHANGE_THRESHOLD = 0.10      # a change of more than 10% is reported


def detect_recurring(df: pd.DataFrame) -> dict:
    """
    Find payments that repeat on a regular schedule to the same payee
    (subscriptions, rent, fibre, airtime bundles...). Rule-based: the same
    payee, a similar amount, and a regular gap between payments.
    """
    end = df["date"].max()
    found = []

    for payee, g in df[df["counterparty"] != ""].groupby("counterparty"):
        g = g.sort_values("date")
        if len(g) < 2:
            continue
        gaps = g["date"].diff().dt.days.dropna()
        median_gap = float(gaps.median())

        pattern = next(
            (p for p in RECURRING_PATTERNS if p[1] <= median_gap <= p[2] and len(g) >= p[3]),
            None,
        )
        if pattern is None:
            continue
        label, low, high, _ = pattern

        # Most gaps must fit the pattern, and most amounts must be similar
        if ((gaps >= low) & (gaps <= high)).mean() < 0.7:
            continue
        usual = float(g["amount"].median())
        similar = ((g["amount"] - usual).abs() <= RECURRING_PRICE_TOLERANCE * usual).mean()
        if similar < 0.7:
            continue

        last = g.iloc[-1]
        previous_amount = float(g.iloc[-2]["amount"])
        last_amount = float(last["amount"])
        next_due = last["date"] + pd.Timedelta(days=round(median_gap))
        per_month = usual * (30.4 / median_gap)

        price_change = None
        if previous_amount > 0 and abs(last_amount - previous_amount) / previous_amount > PRICE_CHANGE_THRESHOLD:
            price_change = {"from": round(previous_amount, 2), "to": round(last_amount, 2)}

        if end > last["date"] + pd.Timedelta(days=round(median_gap * 1.5)):
            status_ = "may_have_stopped"
        elif next_due <= end + pd.Timedelta(days=7):
            status_ = "due_soon"
        else:
            status_ = "active"

        found.append({
            "name": str(payee).title(),
            "category": str(g["category_name"].mode().iloc[0]),
            "frequency": label,
            "usual_amount_kes": round(usual, 2),
            "last_amount_kes": round(last_amount, 2),
            "last_date": str(last["date"].date()),
            "next_expected_date": str(next_due.date()),
            "payments": int(len(g)),
            "monthly_cost_kes": round(per_month, 2),
            "yearly_cost_kes": round(per_month * 12, 2),
            "status": status_,
            "is_new": bool(len(g) == 2 and g.iloc[0]["date"] >= end - pd.Timedelta(days=70)),
            "price_change": price_change,
        })

    found.sort(key=lambda r: -r["monthly_cost_kes"])
    active = [r for r in found if r["status"] != "may_have_stopped"]
    monthly_total = sum(r["monthly_cost_kes"] for r in active)
    return {
        "count": len(found),
        "active_count": len(active),
        "monthly_total_kes": round(monthly_total, 2),
        "yearly_total_kes": round(monthly_total * 12, 2),
        "payments": found,
    }


# ── Insight cards (most important first) ─────────────────────────────────────

def _ksh(v: float) -> str:
    return f"KSh {v:,.0f}"


def build_insight_cards(
    period_df: pd.DataFrame,
    period_days: int,
    clustering: dict,
    anomaly_result: dict,
    prediction_result: dict,
    recurring: dict,
) -> list:
    """
    Each card pairs what we noticed with what the user can do about it.
    'priority' orders them (higher = more important); 'tab' says which
    Analysis tab has the details.
    """
    cards = []

    def card(priority, kind, title, detail, action=None, tab=None):
        cards.append({"priority": priority, "type": kind, "title": title,
                      "detail": detail, "action": action, "tab": tab})

    # Unusual transactions: needs checking
    n = int(anomaly_result.get("anomaly_count", 0))
    days = anomaly_result.get("recent_days", 30)
    if n:
        top = anomaly_result["anomalies"][0]
        card(100, "alert",
             f"{n} unusual transaction{'s' if n > 1 else ''} to check",
             f"The most unusual is {_ksh(top['amount'])} on {top['category']} on {top['date']}"
             f"{' at ' + top['time'] if top.get('time') else ''}. "
             f"{top['reasons'][0]}.",
             "Confirm these were you. Mark any that are normal so they are not flagged again.",
             "anomalies")

    # Subscriptions: new ones and price rises first
    for r in recurring.get("payments", []):
        if r["price_change"] and r["price_change"]["to"] > r["price_change"]["from"]:
            card(88, "subscription",
                 f"{r['name']} now costs more",
                 f"It went from {_ksh(r['price_change']['from'])} to {_ksh(r['price_change']['to'])}.",
                 "Check whether the new price is still worth it.", "recurring")
        elif r["is_new"] and r["status"] != "may_have_stopped":
            card(80, "subscription",
                 f"New regular payment: {r['name']}",
                 f"{_ksh(r['usual_amount_kes'])} {r['frequency'].lower()} since {r['last_date'][:7]}.",
                 "Make sure you meant to sign up for it.", "recurring")
    if recurring.get("active_count"):
        card(70, "subscription",
             f"{_ksh(recurring['monthly_total_kes'])} a month goes to regular payments",
             f"{recurring['active_count']} regular payment{'s' if recurring['active_count'] > 1 else ''} "
             f"add up to {_ksh(recurring['yearly_total_kes'])} a year.",
             "Cancel any subscriptions you no longer use.", "recurring")

    # Forecast
    if prediction_result.get("status") == "ok" and prediction_result.get("predictions"):
        nxt = float(prediction_result["predictions"][0]["predicted_spend_kes"])
        avg = float(prediction_result["average_weekly_spend_kes"])
        change = (nxt - avg) / avg * 100 if avg > 0 else 0
        if change > 10:
            card(90, "forecast", f"Next week may cost more: about {_ksh(nxt)}",
                 f"That is {change:.0f}% above your usual {_ksh(avg)} a week.",
                 "Check for large planned expenses and where you could cut back.", "forecast")
        elif change < -10:
            card(45, "forecast", f"Next week looks lighter: about {_ksh(nxt)}",
                 f"That is {abs(change):.0f}% below your usual {_ksh(avg)} a week.",
                 None, "forecast")
        else:
            card(40, "forecast", f"Next week: about {_ksh(nxt)}",
                 f"In line with your usual {_ksh(avg)} a week.", None, "forecast")
    else:
        card(20, "info", "Forecast not available yet",
             "At least 4 weeks of transactions are needed to predict your spending.",
             "Keep recording transactions; the forecast appears automatically.", "forecast")

    # Categories in the selected period
    total = float(period_df["amount"].sum())
    if total > 0:
        by_cat = (period_df.groupby("category_name")
                  .agg(total=("amount", "sum"), count=("amount", "count"))
                  .sort_values("total", ascending=False))
        top_cat = str(by_cat.index[0])
        top_share = float(by_cat.iloc[0]["total"]) / total * 100
        card(60, "category", f"{top_cat} is your biggest expense",
             f"{_ksh(by_cat.iloc[0]['total'])}, {top_share:.0f}% of your spending in this period.",
             f"Look through your {top_cat} payments for any you could reduce.", "habits")

        frequent = str(by_cat["count"].idxmax())
        if frequent != top_cat:
            card(55, "category", f"Many small {frequent} payments",
                 f"{int(by_cat.loc[frequent, 'count'])} payments in this period, more than any other category.",
                 f"Small payments add up. Try tracking your weekly {frequent} total.", "habits")

        weekend_share = float(period_df.loc[period_df["date"].dt.dayofweek >= 5, "amount"].sum()) / total * 100
        if weekend_share >= 40:
            card(50, "habit", f"{weekend_share:.0f}% of your spending is on weekends",
                 "Weekends are when spending on non-essentials is usually highest.",
                 "Try setting a weekend spending limit.", "habits")

    # Habits
    clusters = clustering.get("clusters", {})
    if clusters:
        frequent_habit = max(clusters.values(), key=lambda c: c["transaction_count"])
        card(35, "habit", f"Most frequent habit: {frequent_habit['habit_name'].lower()}",
             f"{frequent_habit['transaction_count']} payments, usually around "
             f"{_ksh(frequent_habit['median_amount_kes'])}, mostly {frequent_habit['top_category']}.",
             None, "habits")

    if not n:
        card(30, "info", f"No unusual transactions in the last {days} days",
             "Your recent spending looks consistent with your normal habits.", None, "anomalies")

    card(10, "info", "What this covers",
         f"{len(period_df):,} transactions from the last {period_days} days "
         f"({period_df['date'].min().date()} to {period_df['date'].max().date()})."
         if len(period_df) else f"No transactions in the last {period_days} days.",
         None, None)

    cards.sort(key=lambda c: -c["priority"])
    return cards


# ── API route ────────────────────────────────────────────────────────────────

@router.get("/{user_id}")
def analyse_user(
    user_id: int,
    days: int = Query(90, ge=7, le=3650, description="Period to describe, in days"),
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Run the full analysis pipeline for one user.

    The whole history is used to build features and the forecast, but habits,
    category figures and insights describe only the last `days` days, so
    totals do not keep growing as the app is used.
    At least five transactions are required for the overall analysis.
    Forecasting has a separate minimum of four observed weeks.
    """
    require_same_user(user_id, current_user_id)
    user = db.execute(
        text("SELECT user_id FROM users WHERE user_id = :user_id"),
        {"user_id": user_id},
    ).fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {user_id} not found",
        )

    df = fetch_user_transactions(user_id, db)

    if df.empty or len(df) < 5:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"User {user_id} has {len(df)} valid transaction(s). "
                "At least 5 are required to run analysis."
            ),
        )

    period_end = df["date"].max()
    period_start = period_end - pd.Timedelta(days=days - 1)
    period_df = df[df["date"] >= period_start]

    clustering = run_clustering(df, period_start)
    anomaly_result = run_anomaly_detection(df)
    prediction_result = run_prediction(df)
    recurring = detect_recurring(df)

    cards = build_insight_cards(period_df, days, clustering, anomaly_result,
                                prediction_result, recurring)

    result = {
        "user_id": user_id,
        "transaction_count": int(len(period_df)),
        "total_transaction_count": int(len(df)),
        "period": {
            "days": days,
            "start": str(period_start.date()),
            "end": str(period_end.date()),
            "total_spend_kes": round(float(period_df["amount"].sum()), 2),
        },
        "analysis_timestamp": datetime.now().isoformat(),
        "spending_clusters": clustering,
        "anomaly_detection": anomaly_result,
        "spending_prediction": prediction_result,
        "recurring_payments": recurring,
        "insight_cards": cards,
        # Plain lists kept for older app versions
        "insights": [f"{c['title']}. {c['detail']}" for c in cards],
        "recommendations": [c["action"] for c in cards if c["action"]],
    }

    save_analysis_record(user_id, days, result, db)
    return result


def save_analysis_record(user_id: int, days: int, result: dict, db: Session) -> None:
    """
    Keep a record of each analysis run (analysis_results table), so results can
    be compared over time. A failure here never stops the analysis being returned.
    """
    preds = result["spending_prediction"].get("predictions") or []
    try:
        db.execute(
            text(
                """
                INSERT INTO analysis_results (
                    user_id, period_days, transaction_count, total_spend_kes,
                    anomaly_count, next_week_forecast_kes, result
                )
                VALUES (
                    :user_id, :period_days, :transaction_count, :total_spend_kes,
                    :anomaly_count, :next_week_forecast_kes, CAST(:result AS JSONB)
                )
                """
            ),
            {
                "user_id": user_id,
                "period_days": days,
                "transaction_count": result["transaction_count"],
                "total_spend_kes": result["period"]["total_spend_kes"],
                "anomaly_count": result["anomaly_detection"]["anomaly_count"],
                "next_week_forecast_kes": preds[0].get("predicted_spend_kes") if preds else None,
                "result": json.dumps(result, default=str),
            },
        )
        db.commit()
    except Exception:
        db.rollback()