"""
Analysis routes.

GET /analysis/{user_id}
Runs spending pattern analysis, anomaly detection, predictions,
and generates user-friendly insights and recommendations.
"""

from datetime import datetime, timedelta

import numpy as np
import pandas as pd
from fastapi import APIRouter, Depends, HTTPException, status
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
                t.transaction_type,
                t.source,
                c.name AS category_name,
                COALESCE(t.anomaly_dismissed, FALSE) AS anomaly_dismissed
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.category_id
            WHERE t.user_id = :user_id
            ORDER BY t.date ASC, t.transaction_id ASC
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
            "transaction_type",
            "source",
            "category_name",
            "anomaly_dismissed",
        ],
    )

    df["date"] = pd.to_datetime(df["date"], errors="coerce")
    df["amount"] = pd.to_numeric(df["amount"], errors="coerce")
    df["category_name"] = df["category_name"].fillna("Other")
    df["source"] = df["source"].fillna("MPESA")
    df["transaction_type"] = df["transaction_type"].fillna("expense")

    df = df.dropna(subset=["date", "amount"])
    df = df[df["amount"] > 0].copy()
    # Same-day transactions are kept in the order they were recorded, so the
    # results do not change when rows are updated (e.g. an anomaly is dismissed).
    df = df.sort_values(["date", "transaction_id"], kind="mergesort").reset_index(drop=True)

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
    df = df.sort_values("date", kind="mergesort").reset_index(drop=True)
    date_indexed_amounts = df.set_index("date")["amount"]

    df["7day_spend"] = (
        date_indexed_amounts.rolling("7D", closed="left").sum().to_numpy()
    )
    df["30day_avg"] = (
        date_indexed_amounts.rolling("30D", closed="left").mean().to_numpy()
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

def run_clustering(df: pd.DataFrame) -> dict:
    """Assign transactions to the trained K-Means spending clusters."""
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
    ]

    featured_df = add_transaction_features(df)
    x = featured_df[clustering_features].values
    x_scaled = scaler.transform(x)
    featured_df["cluster"] = kmeans.predict(x_scaled)

    cluster_summary = (
        featured_df.groupby("cluster")
        .agg(
            transaction_count=("amount", "count"),
            avg_amount=("amount", "mean"),
            total_spend=("amount", "sum"),
            pct_weekend=("is_weekend", "mean"),
        )
        .round(2)
        .reset_index()
    )

    top_categories = (
        featured_df.groupby(["cluster", "category_name"])["amount"]
        .sum()
        .reset_index()
        .sort_values("amount", ascending=False)
        .groupby("cluster")
        .first()["category_name"]
        .to_dict()
    )

    clusters_out = {}
    for _, row in cluster_summary.iterrows():
        cluster_id = int(row["cluster"])
        clusters_out[cluster_id] = {
            "transaction_count": int(row["transaction_count"]),
            "avg_amount_kes": round(float(row["avg_amount"]), 2),
            "total_spend_kes": round(float(row["total_spend"]), 2),
            "pct_weekend": round(float(row["pct_weekend"]) * 100, 1),
            "top_category": top_categories.get(cluster_id, "Unknown"),
        }

    return {
        "cluster_count": int(kmeans.n_clusters),
        "clusters": clusters_out,
    }


# ── Isolation Forest anomaly detection ──────────────────────────────────────

def run_anomaly_detection(df: pd.DataFrame) -> dict:
    """Flag transactions that the trained Isolation Forest considers unusual."""
    iso_forest = models["isolation_forest_model"]

    # Must match the feature set the training notebook selected (same order).
    # If the notebook printed "Using: CURRENT", replace this list with:
    #   ["amount", "category_encoded", "source_encoded", "day_of_week",
    #    "is_weekend", "spending_velocity"]
    anomaly_features = [
        "amount",
        "cat_share",
        "cat_amount_ratio",
        "is_new_category",
        "source_encoded",
        "day_of_week",
        "is_weekend",
        "spending_velocity",
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

    anomalies = featured_df[
        (featured_df["anomaly_flag"] == -1) & clear_case & after_warmup & ~dismissed
    ].copy()
    anomaly_rate = (len(anomalies) / len(featured_df) * 100) if len(featured_df) else 0

    anomaly_list = sorted(
        [
            {
                "transaction_id": int(row["transaction_id"]),
                "amount": round(float(row["amount"]), 2),
                "date": str(row["date"].date()),
                "category": str(row["category_name"]),
                "source": str(row["source"]),
                "anomaly_score": round(float(row["anomaly_score"]), 4),
            }
            for _, row in anomalies.iterrows()
        ],
        key=lambda item: item["anomaly_score"],
    )

    return {
        "total_transactions": int(len(featured_df)),
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

def generate_insights_and_recommendations(
    df: pd.DataFrame,
    clustering: dict,
    anomaly_result: dict,
    prediction_result: dict,
) -> dict:
    insights = []
    recommendations = []

    if df.empty:
        return {
            "insights": ["No transaction data found."],
            "recommendations": ["Add or import transactions to start seeing spending insights."],
        }

    # ── Category breakdown ─────────────────────────────────────────────────
    category_summary = (
        df.groupby("category_name")
        .agg(total_spent=("amount", "sum"), transaction_count=("amount", "count"))
        .sort_values("total_spent", ascending=False)
    )

    total_spending = float(df["amount"].sum())

    if not category_summary.empty and total_spending > 0:
        top_category = str(category_summary.index[0])
        top_amount = float(category_summary.iloc[0]["total_spent"])
        top_pct = top_amount / total_spending * 100

        insights.append(
            f"You spend the most on {top_category} — "
            f"KSh {top_amount:,.0f}, which is {top_pct:.0f}% of your total recorded spending."
        )
        recommendations.append(
            f"{top_category} takes up the largest share of your budget. "
            f"Look through those transactions to see if there are any you could reduce."
        )

        frequent_category = str(category_summary["transaction_count"].idxmax())
        frequent_count = int(category_summary.loc[frequent_category, "transaction_count"])

        if frequent_category != top_category:
            insights.append(
                f"You make the most individual purchases in {frequent_category} "
                f"({frequent_count} transactions), even though it is not your biggest spend."
            )
            recommendations.append(
                f"Small {frequent_category} purchases add up quickly. "
                f"Try tracking your weekly {frequent_category} total to stay aware of it."
            )

    # ── Date range and weekend behaviour ──────────────────────────────────
    insights.append(
        f"This analysis covers {len(df):,} transactions "
        f"from {df['date'].min().date()} to {df['date'].max().date()}."
    )

    weekend_pct = float(df["date"].dt.dayofweek.ge(5).mean() * 100)
    if weekend_pct >= 40:
        insights.append(
            f"{weekend_pct:.0f}% of your spending happens on weekends. "
            f"Weekends tend to be when discretionary spending is highest."
        )
        recommendations.append(
            "Try setting a weekend spending limit. "
            "It is often easier to cut back on non-essential purchases on weekends than on weekdays."
        )
    else:
        insights.append(
            f"Most of your spending ({100 - weekend_pct:.0f}%) happens on weekdays, "
            f"which is typical for bills, transport, and work-related costs."
        )

    # ── Spending patterns (clusters) ───────────────────────────────────────
    clusters = clustering.get("clusters", {})
    cluster_count = clustering.get("cluster_count", 0)

    if clusters:
        largest = max(clusters.values(), key=lambda c: c["transaction_count"])
        top_cat = largest["top_category"]
        avg = largest["avg_amount_kes"]
        pct_wknd = largest["pct_weekend"]

        insights.append(
            f"Your most common spending pattern is centred around {top_cat}, "
            f"with an average transaction of KSh {avg:,.0f}."
        )

        if cluster_count > 1:
            recommendations.append(
                f"Your spending falls into {cluster_count} distinct patterns. "
                f"The largest is dominated by {top_cat}. "
                f"Reviewing each pattern can help you spot where your money actually goes."
            )

        if pct_wknd > 50:
            recommendations.append(
                f"More than half of your {top_cat} spending happens on weekends. "
                f"Consider whether a weekend budget for this category would help."
            )

    # ── Anomalies ──────────────────────────────────────────────────────────
    anomaly_count = int(anomaly_result.get("anomaly_count", 0))
    anomalies = anomaly_result.get("anomalies", [])

    if anomaly_count == 0:
        insights.append(
            "All your transactions look consistent with your normal spending habits. "
            "No unusual activity was detected."
        )
    else:
        insights.append(
            f"We found {anomaly_count} transaction{'s' if anomaly_count > 1 else ''} "
            f"that look unusual compared to your own recent spending and typical patterns. "
            f"They could be legitimate but are worth a quick check."
        )
        if anomalies:
            top = anomalies[0]
            recommendations.append(
                f"Your most unusual transaction is KSh {top['amount']:,.0f} "
                f"spent on {top['category']} on {top['date']}. "
                f"Check the Anomalies tab to confirm this was you."
            )

    # ── Forecast ──────────────────────────────────────────────────────────
    if prediction_result.get("status") == "ok":
        preds = prediction_result.get("predictions", [])
        pred_amounts = [float(p["predicted_spend_kes"]) for p in preds]
        historical_avg = float(prediction_result["average_weekly_spend_kes"])

        if pred_amounts:
            pred_avg = float(np.mean(pred_amounts))
            next_week = preds[0]

            insights.append(
                f"Based on your spending history, you are likely to spend around "
                f"KSh {next_week['predicted_spend_kes']:,.0f} next week."
            )

            if historical_avg > 0:
                change_pct = (pred_avg - historical_avg) / historical_avg * 100
                if change_pct > 10:
                    insights.append(
                        f"This is {change_pct:.0f}% higher than your usual weekly average "
                        f"of KSh {historical_avg:,.0f}."
                    )
                    recommendations.append(
                        "Your predicted spending for the coming weeks is higher than usual. "
                        "Check whether any large planned expenses are driving this, "
                        "and consider where you can cut back."
                    )
                elif change_pct < -10:
                    insights.append(
                        f"This is {abs(change_pct):.0f}% lower than your usual weekly average "
                        f"of KSh {historical_avg:,.0f}. You seem to be on track to spend less."
                    )
                else:
                    insights.append(
                        f"This is in line with your usual weekly average of KSh {historical_avg:,.0f}."
                    )
    else:
        insights.append(
            "We do not have enough weekly history yet to make a spending forecast. "
            "Keep recording transactions and a forecast will appear automatically."
        )
        recommendations.append(
            "Record at least 4 weeks of transactions to unlock weekly spending predictions."
        )

    return {"insights": insights, "recommendations": recommendations}

# ── API route ────────────────────────────────────────────────────────────────

@router.get("/{user_id}")
def analyse_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Run the full analysis pipeline for one user.
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

    # IMPORTANT:
    # This example assumes all rows fetched here represent spending outflows.
    # If your database also stores income/incoming transfers, filter those out
    # according to your actual transaction_type values before running analysis.

    clustering = run_clustering(df)
    anomaly_result = run_anomaly_detection(df)
    prediction_result = run_prediction(df)

    insight_results = generate_insights_and_recommendations(
        df=df,
        clustering=clustering,
        anomaly_result=anomaly_result,
        prediction_result=prediction_result,
    )

    return {
        "user_id": user_id,
        "transaction_count": int(len(df)),
        "analysis_timestamp": datetime.now().isoformat(),
        "spending_clusters": clustering,
        "anomaly_detection": anomaly_result,
        "spending_prediction": prediction_result,
        "insights": insight_results["insights"],
        "recommendations": insight_results["recommendations"],
    }