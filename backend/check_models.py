import warnings, joblib

warnings.simplefilter("always")          # show every warning, including version warnings

expected = {
    "kmeans_model": 12,             # 10 behaviour features + hour_sin, hour_cos
    "scaler_clustering": 12,
    "isolation_forest_model": 15,   # 8 behaviour features + 7 time features
    "random_forest_model": 8,
    "scaler_prediction": 8,
}

with warnings.catch_warnings(record=True) as caught:
    for name, n in expected.items():
        m = joblib.load(f"models/{name}.pkl")
        ok = "OK " if m.n_features_in_ == n else "MISMATCH"
        print(f"{ok}  {name:<24} {type(m).__name__:<22} expects {m.n_features_in_} (should be {n})")

    rf = joblib.load("models/random_forest_model.pkl")
    print(f"\nRandom Forest: {rf.n_estimators} trees, min leaf {rf.min_samples_leaf}")
    km = joblib.load("models/kmeans_model.pkl")
    print(f"K-Means: {km.n_clusters} clusters (should be 5)")

version_warnings = [w for w in caught if "Version" in type(w.message).__name__]
print(f"\nVersion warnings: {len(version_warnings)}")
for w in version_warnings:
    print("  ", w.message)