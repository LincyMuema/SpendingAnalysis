"""Service tests. Run from backend/:  python -m pytest -q

They use the real pickled models in backend/model, so they also prove the
pickles load and accept the feature layout the service builds.
"""

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from app.main import app


def synthetic_transactions(weeks: int, per_week: int = 6, base: float = 1500.0):
    """A steady spender: `weeks` weeks of `per_week` purchases around `base`."""
    start = date(2025, 1, 6)  # a Monday
    rows = []
    for w in range(weeks):
        for i in range(per_week):
            d = start + timedelta(days=7 * w + (i % 7))
            rows.append({"date": d.isoformat(), "amount": base + 100 * (i % 3), "category": ["Food", "Transport", "Rent"][i % 3]})
    return rows


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def test_health_lists_all_four_models(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["models_loaded"] == [
        "isolation_forest_model", "kmeans_model", "random_forest_model", "scaler_prediction",
    ]


def test_forecast_returns_the_platform_contract(client):
    r = client.post("/forecast", json={
        "userId": "u-1", "month": 6, "year": 2026,
        "transactions": synthetic_transactions(weeks=12),
    })
    assert r.status_code == 200, r.text
    body = r.json()
    for key in ("estimatedTotal", "breakdown", "confidence", "riskFlag"):
        assert key in body
    assert body["estimatedTotal"] > 0
    assert 0.0 <= body["confidence"] <= 1.0
    assert isinstance(body["riskFlag"], bool)
    # breakdown is proportional to what the user actually spends on
    assert set(body["breakdown"]) == {"Food", "Transport", "Rent"}
    assert abs(sum(body["breakdown"].values()) - body["estimatedTotal"]) < 1.0


def test_forecast_refuses_too_little_history(client):
    r = client.post("/forecast", json={
        "userId": "u-1", "month": 6, "year": 2026,
        "transactions": synthetic_transactions(weeks=2),
    })
    assert r.status_code == 422
    assert "at least 4 weeks" in r.json()["detail"]


def test_anomaly_flags_a_spike_week(client):
    rows = synthetic_transactions(weeks=16)
    # One wild week: a single purchase ten times the usual
    rows.append({"date": "2025-03-10", "amount": 15000.0, "category": "Other"})
    r = client.post("/anomaly", json={"userId": "u-1", "transactions": rows})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["weeks_checked"] >= 16
    assert any(a["week"].startswith("2025-03-10") for a in body["anomalies"]), body
