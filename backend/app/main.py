"""SpendingAnalysis service — serves the trained models over HTTP.

The notebooks train the models; this is what the platform and the Flutter app
call. Models are loaded once at startup from ``backend/model`` and reused.

Two routes do the work:

    POST /forecast   next-period spend for one user — U-CS 37 contract
    POST /anomaly    flag unusual weeks with the Isolation Forest

Both take the user's raw transactions in the request body, so the same
service answers for the Wasaa sandbox data and for SMS-parsed transactions
from the mobile app without caring where they came from.

Run locally:
    uvicorn app.main:app --reload --port 8000
"""

from __future__ import annotations

import math
import os
from pathlib import Path
from typing import Dict, List, Optional

import joblib
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from app.features import FEATURES, MIN_WEEKS, latest_feature_row, weekly_features

MODEL_DIR = Path(os.getenv("MODEL_DIR", Path(__file__).resolve().parents[1] / "model"))

app = FastAPI(title="SpendingAnalysis", version="0.1.0")
_models: Dict[str, object] = {}


@app.on_event("startup")
def load_models() -> None:
    """Load every pickle once. A missing file is a loud failure at boot, not at
    the first request."""
    for name in ("random_forest_model", "isolation_forest_model", "kmeans_model", "scaler_prediction"):
        path = MODEL_DIR / f"{name}.pkl"
        if not path.exists():
            raise RuntimeError(f"model file missing: {path}")
        _models[name] = joblib.load(path)


# ── request / response shapes ────────────────────────────────────────────────


class Transaction(BaseModel):
    model_config = ConfigDict(extra="ignore")
    date: str
    amount: float
    category: Optional[str] = None


class ForecastRequest(BaseModel):
    """The platform sends userId/month/year. Transactions come with it so the
    service does not need its own copy of anyone's data."""

    model_config = ConfigDict(populate_by_name=True)
    user_id: str = Field(alias="userId")
    month: int = Field(ge=1, le=12)
    year: int = Field(ge=2000, le=2100)
    transactions: List[Transaction]


class ForecastResponse(BaseModel):
    """U-CS 37: { estimatedTotal, breakdown{}, confidence, riskFlag }"""

    estimatedTotal: float
    breakdown: Dict[str, float]
    confidence: float
    riskFlag: bool
    basis: Dict[str, float]


class AnomalyRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    user_id: str = Field(alias="userId")
    transactions: List[Transaction]


class AnomalyWeek(BaseModel):
    week: str
    total_spend: float
    score: float
    is_anomaly: bool


class AnomalyResponse(BaseModel):
    weeks_checked: int
    anomalies: List[AnomalyWeek]


# ── routes ───────────────────────────────────────────────────────────────────


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "models_loaded": sorted(_models)}


@app.post("/forecast", response_model=ForecastResponse)
def forecast(req: ForecastRequest) -> ForecastResponse:
    weekly = weekly_features(t.model_dump() for t in req.transactions)
    if len(weekly) < MIN_WEEKS:
        raise HTTPException(
            status_code=422,
            detail=f"need at least {MIN_WEEKS} weeks of transactions to forecast, got {len(weekly)}",
        )

    scaler = _models["scaler_prediction"]
    rf = _models["random_forest_model"]

    # A DataFrame, not .to_numpy(): the scaler was fitted with column names and
    # warns on every call if they are stripped.
    x = scaler.transform(latest_feature_row(weekly))
    next_week = float(rf.predict(x)[0])

    # The model predicts one week. The contract asks for a month; roughly
    # 4.35 weeks in a month. Said explicitly in `basis` so nobody has to guess.
    weeks_in_month = 4.35
    estimated_month = max(next_week, 0.0) * weeks_in_month

    # Spread the total across categories in the proportions this user has
    # actually been spending — that is the most defensible breakdown from
    # transaction data alone.
    cats = {}
    for t in req.transactions:
        if t.amount > 0:
            cats[t.category or "uncategorised"] = cats.get(t.category or "uncategorised", 0.0) + t.amount
    total_seen = sum(cats.values()) or 1.0
    breakdown = {c: round(estimated_month * v / total_seen, 2) for c, v in cats.items()}

    # Agreement across the forest's trees is the honest confidence signal a
    # random forest gives you. Tight spread = high confidence.
    tree_preds = np.array([est.predict(x)[0] for est in rf.estimators_])
    spread = float(tree_preds.std() / (abs(tree_preds.mean()) + 1e-9))
    confidence = round(max(0.0, min(1.0, 1.0 - spread)), 3)

    recent_avg_week = float(weekly["4week_avg"].iloc[-1])
    risk = next_week > 1.25 * recent_avg_week if recent_avg_week > 0 else False

    return ForecastResponse(
        estimatedTotal=round(estimated_month, 2),
        breakdown=breakdown,
        confidence=confidence,
        riskFlag=bool(risk),
        basis={
            "predicted_next_week": round(next_week, 2),
            "weeks_in_month": weeks_in_month,
            "recent_4week_avg": round(recent_avg_week, 2),
            "weeks_of_history": float(len(weekly)),
        },
    )


@app.post("/anomaly", response_model=AnomalyResponse)
def anomaly(req: AnomalyRequest) -> AnomalyResponse:
    weekly = weekly_features(t.model_dump() for t in req.transactions)
    if weekly.empty:
        return AnomalyResponse(weeks_checked=0, anomalies=[])

    iso = _models["isolation_forest_model"]
    x = weekly[FEATURES].to_numpy()
    scores = iso.decision_function(x)          # lower = more anomalous
    flags = iso.predict(x) == -1

    out = [
        AnomalyWeek(week=str(w), total_spend=round(float(s), 2), score=round(float(sc), 4), is_anomaly=bool(f))
        for w, s, sc, f in zip(weekly["week"], weekly["total_spend"], scores, flags)
        if f
    ]
    return AnomalyResponse(weeks_checked=int(len(weekly)), anomalies=out)
