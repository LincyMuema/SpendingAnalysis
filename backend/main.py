"""
SpendingAnalysis — FastAPI backend entry point.

Loads trained ML models at startup and registers all route modules.
Run locally:
    uvicorn main:app --reload --port 8000

API documentation available at:
    http://localhost:8000/docs
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import joblib
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# ── Application setup ─────────────────────────────────────────
app = FastAPI(
    title="SpendingAnalysis API",
    description="Personal Spending Analysis and Optimization System",
    version="1.0.0"
)

# ── CORS — allows Flutter app to communicate with this backend ─
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Model loading ─────────────────────────────────────────────

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
models = {}

@app.on_event("startup")
async def load_models():
    """Load all trained .pkl model files when the server starts."""
    model_files = [
        "kmeans_model",
        "isolation_forest_model",
        "random_forest_model",
        "scaler_prediction",
    ]

    for name in model_files:
        path = MODELS_DIR / f"{name}.pkl"
        if not path.exists():
            raise RuntimeError(
                f"Model file not found: {path}\n"
                f"Make sure all .pkl files are in {MODELS_DIR}"
            )
        models[name] = joblib.load(path)
        print(f"Loaded: {name}.pkl")

    print(f"\nAll {len(model_files)} models loaded successfully.")
    print("Server is ready to accept requests.\n")
    from database import test_connection
    test_connection()

# ── Health check ──────────────────────────────────────────────
@app.get("/")
def root():
    """Root endpoint — confirms the API is running."""
    return {
        "message": "SpendingAnalysis API is running",
        "version": "1.0.0",
        "docs": "http://localhost:8000/docs"
    }

@app.get("/health")
def health():
    """Health check — confirms which models are loaded."""
    return {
        "status": "ok",
        "models_loaded": sorted(models.keys()),
        "model_count": len(models)
    }

# ── Route registration ────────────────────────────────────────

from routes.authentication import router as auth_router
from routes.transactions import router as transactions_router
from routes.analysis import router as analysis_router

app.include_router(
    auth_router,
    prefix="/authentication",
    tags=["Authentication"]
)
app.include_router(
    transactions_router,
    prefix="/transactions",
    tags=["Transactions"]
)
app.include_router(
    analysis_router,
    prefix="/analysis",
    tags=["Analysis"]
)