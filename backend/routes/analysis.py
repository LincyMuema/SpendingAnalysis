"""
Analysis routes.

GET /analysis/{user_id} — run the full ML pipeline for a user and return
spending patterns, anomalies, and predictions.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from database import get_db
from main import models
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from collections import defaultdict

router = APIRouter()

# ── Label encoder mappings (must match preprocessing notebook) ─────────────
CATEGORY_CLASSES = [
    'Bills & Utilities', 'Business', 'Crypto', 'Education',
    'Entertainment', 'Food & Dining', 'Gambling', 'Government',
    'Healthcare', 'Insurance', 'Investments', 'Other',
    'Personal Care', 'Shopping', 'Transfer', 'Transport', 'Travel'
]  # indices 0–16

SOURCE_MAP = {'CARD': 0, 'CASH': 1, 'MPESA': 2, 'WALLET': 3}


def encode_category(name: str) -> int:
    name = name.strip()
    if name in CATEGORY_CLASSES:
        return CATEGORY_CLASSES.index(name)
    return CATEGORY_CLASSES.index('Other')  # fallback


def encode_source(source: str) -> int:
    return SOURCE_MAP.get(str(source).upper().strip(), 2)  # default MPESA


# ── DB fetch ───────────────────────────────────────────────────────────────

def fetch_user_transactions(user_id: int, db: Session) -> pd.DataFrame:
    rows = db.execute(
        text("""
            SELECT
                t.transaction_id,
                t.amount,
                t.date,
                t.transaction_type,
                t.source,
                c.name AS category_name
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.category_id
            WHERE t.user_id = :user_id
            ORDER BY t.date ASC
        """),
        {"user_id": user_id}
    ).fetchall()

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows, columns=[
        "transaction_id", "amount", "date",
        "transaction_type", "source", "category_name"
    ])
    df["date"] = pd.to_datetime(df["date"])
    df["amount"] = df["amount"].astype(float)
    df["category_name"] = df["category_name"].fillna("Other")
    df = df.sort_values("date").reset_index(drop=True)
    return df


# ── Feature engineering helpers ────────────────────────────────────────────

def add_transaction_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add the 8 clustering features and 5 anomaly features to the dataframe."""
    df = df.copy()

    # Encoded columns
    df["category_encoded"] = df["category_name"].apply(encode_category)
    df["source_encoded"]   = df["source"].apply(encode_source)

    # Time features
    df["day_of_week"]   = df["date"].dt.dayofweek          # 0=Mon … 6=Sun
    df["week_of_month"] = (df["date"].dt.day - 1) // 7 + 1 # 1–5
    df["is_weekend"]    = (df["day_of_week"] >= 5).astype(int)

    # Rolling spend features (require sorted date)
    df = df.sort_values("date").reset_index(drop=True)
    df["7day_spend"] = (
        df.set_index("date")["amount"]
        .rolling("7D", closed="left")
        .sum()
        .values
    )
    df["30day_avg"] = (
        df.set_index("date")["amount"]
        .rolling("30D", closed="left")
        .mean()
        .values
    )

    # Spending velocity = amount / 30day_avg (how many times above average)
    df["spending_velocity"] = df["amount"] / df["30day_avg"].replace(0, np.nan)
    df["spending_velocity"] = df["spending_velocity"].fillna(1.0)

    # Fill NaN rolling values (first few rows have no history)
    df["7day_spend"] = df["7day_spend"].fillna(0.0)
    df["30day_avg"]  = df["30day_avg"].fillna(df["amount"])

    return df


def build_weekly_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Aggregate transactions into weekly rows with the 8 prediction features.
    Returns a dataframe where each row = one week.
    """
    df = df.copy()
    df["week"] = df["date"].dt.to_period("W")

    weekly = df.groupby("week").agg(
        total_spend       = ("amount", "sum"),
        transaction_count = ("amount", "count"),
        avg_transaction   = ("amount", "mean"),
        max_transaction   = ("amount", "max"),
    ).reset_index()

    weekly = weekly.sort_values("week").reset_index(drop=True)

    # Rolling 4-week features
    weekly["4week_avg"] = (
        weekly["total_spend"].rolling(4, min_periods=1).mean().shift(1).fillna(0)
    )
    weekly["4week_max"] = (
        weekly["total_spend"].rolling(4, min_periods=1).max().shift(1).fillna(0)
    )
    weekly["spend_vs_avg"] = weekly["total_spend"] / weekly["4week_avg"].replace(0, np.nan)
    weekly["spend_vs_avg"] = weekly["spend_vs_avg"].fillna(1.0)
    weekly["week_of_month_num"] = weekly["week"].apply(
        lambda p: (p.start_time.day - 1) // 7 + 1
    )

    return weekly


# ── ML functions ───────────────────────────────────────────────────────────

def run_clustering(df: pd.DataFrame) -> dict:
    """
    K-Means clustering on per-transaction 8-feature matrix.
    Features: amount, category_encoded, day_of_week, week_of_month,
              is_weekend, 7day_spend, 30day_avg, spending_velocity
    """
    kmeans = models["kmeans_model"]
    scaler = models["scaler_clustering"]

    CLUSTERING_FEATURES = [
        'amount', 'category_encoded', 'day_of_week',
        'week_of_month', 'is_weekend', '7day_spend',
        '30day_avg', 'spending_velocity'
    ]

    df = add_transaction_features(df)
    X = df[CLUSTERING_FEATURES].values
    X_scaled = scaler.transform(X)
    labels = kmeans.predict(X_scaled)
    df["cluster"] = labels

    # Summarise each cluster
    cluster_summary = (
        df.groupby("cluster")
        .agg(
            transaction_count = ("amount", "count"),
            avg_amount        = ("amount", "mean"),
            total_spend       = ("amount", "sum"),
            pct_weekend       = ("is_weekend", "mean"),
        )
        .round(2)
        .reset_index()
    )

    # Top category per cluster
    top_categories = (
        df.groupby(["cluster", "category_name"])["amount"]
        .sum()
        .reset_index()
        .sort_values("amount", ascending=False)
        .groupby("cluster")
        .first()["category_name"]
        .to_dict()
    )

    clusters_out = {}
    for _, row in cluster_summary.iterrows():
        c = int(row["cluster"])
        clusters_out[c] = {
            "transaction_count": int(row["transaction_count"]),
            "avg_amount_kes":    round(float(row["avg_amount"]), 2),
            "total_spend_kes":   round(float(row["total_spend"]), 2),
            "pct_weekend":       round(float(row["pct_weekend"]) * 100, 1),
            "top_category":      top_categories.get(c, "Unknown"),
        }

    return {
        "cluster_count": int(kmeans.n_clusters),
        "clusters": clusters_out
    }


def run_anomaly_detection(df: pd.DataFrame) -> dict:
    """
    Isolation Forest on 5 features:
    amount, category_encoded, source_encoded, day_of_week, is_weekend
    """
    iso_forest = models["isolation_forest_model"]

    ANOMALY_FEATURES = [
        'amount', 'category_encoded', 'source_encoded',
        'day_of_week', 'is_weekend'
    ]

    df = add_transaction_features(df)
    X = df[ANOMALY_FEATURES].values

    predictions = iso_forest.predict(X)       # -1 = anomaly, 1 = normal
    scores      = iso_forest.decision_function(X)

    df = df.copy()
    df["anomaly_flag"]  = predictions
    df["anomaly_score"] = scores

    anomalies = df[df["anomaly_flag"] == -1].copy()
    anomaly_rate = round(len(anomalies) / len(df) * 100, 2)

    anomaly_list = sorted(
        [
            {
                "transaction_id": int(row["transaction_id"]),
                "amount":         round(float(row["amount"]), 2),
                "date":           str(row["date"].date()),
                "category":       row["category_name"],
                "source":         row["source"],
                "anomaly_score":  round(float(row["anomaly_score"]), 4),
            }
            for _, row in anomalies.iterrows()
        ],
        key=lambda x: x["anomaly_score"]   # most anomalous first (lowest score)
    )

    return {
        "total_transactions": len(df),
        "anomaly_count":      len(anomalies),
        "anomaly_rate_pct":   anomaly_rate,
        "anomalies":          anomaly_list,
    }


def run_prediction(df: pd.DataFrame) -> dict:
    """
    Random Forest prediction for next 4 weeks.
    Features: total_spend, transaction_count, avg_transaction, max_transaction,
              4week_avg, 4week_max, spend_vs_avg, week_of_month_num
    """
    rf_model = models["random_forest_model"]
    scaler   = models["scaler_prediction"]

    PREDICTION_FEATURES = [
        'total_spend', 'transaction_count', 'avg_transaction',
        'max_transaction', '4week_avg', '4week_max',
        'spend_vs_avg', 'week_of_month_num'
    ]

    weekly = build_weekly_features(df)

    if len(weekly) < 4:
        return {
            "status":   "insufficient_data",
            "message":  "At least 4 weeks of transactions are needed for predictions.",
            "predictions": []
        }

    # Use the last row as the "current week" to build the next 4 predictions
    last_row = weekly.iloc[-1]

    # Build 4 future feature rows by sliding the window forward
    future_rows = []
    history = weekly["total_spend"].tolist()

    for i in range(4):
        last4 = history[-4:]
        row = {
            "total_spend":       last_row["total_spend"] if i == 0 else history[-1],
            "transaction_count": last_row["transaction_count"],
            "avg_transaction":   last_row["avg_transaction"],
            "max_transaction":   last_row["max_transaction"],
            "4week_avg":         np.mean(last4),
            "4week_max":         np.max(last4),
            "spend_vs_avg":      (history[-1] / np.mean(last4)) if np.mean(last4) > 0 else 1.0,
            "week_of_month_num": ((last_row["week"].start_time + timedelta(weeks=i+1)).day - 1) // 7 + 1,
        }
        future_rows.append(row)

    X_future = pd.DataFrame(future_rows)[PREDICTION_FEATURES].values
    X_scaled  = scaler.transform(X_future)
    rf_preds  = rf_model.predict(X_scaled)

    # Append predictions to history so each week's rolling avg uses prior prediction
    for pred in rf_preds:
        history.append(pred)

    predictions = [
        {
            "week_label":           (datetime.now() + timedelta(weeks=i + 1)).strftime("Week of %d %b %Y"),
            "predicted_spend_kes":  round(max(0.0, float(rf_preds[i])), 2),
        }
        for i in range(4)
    ]

    return {
        "status":                    "ok",
        "model_used":                "Random Forest Regression",
        "weeks_of_history":          len(weekly),
        "average_weekly_spend_kes":  round(float(weekly["total_spend"].mean()), 2),
        "predictions":               predictions,
    }


# ── Route ──────────────────────────────────────────────────────────────────

@router.get("/{user_id}")
def analyse_user(user_id: int, db: Session = Depends(get_db)):
    """
    Run the full ML pipeline for a user.
    Returns spending clusters, anomalies, and predictions.
    Requires at least 5 transactions.
    """
    user = db.execute(
        text("SELECT user_id FROM users WHERE user_id = :user_id"),
        {"user_id": user_id}
    ).fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User {user_id} not found"
        )

    df = fetch_user_transactions(user_id, db)

    if df.empty or len(df) < 5:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"User {user_id} has {len(df)} transaction(s). "
                f"At least 5 are required to run analysis."
            )
        )

    return {
        "user_id":             user_id,
        "transaction_count":   len(df),
        "analysis_timestamp":  datetime.now().isoformat(),
        "spending_clusters":   run_clustering(df),
        "anomaly_detection":   run_anomaly_detection(df),
        "spending_prediction": run_prediction(df),
    }