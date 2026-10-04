# SpendingAnalysis

A personal spending analysis and optimization system designed for Kenyan mobile money users. The system automatically captures M-Pesa and bank card transactions from SMS notifications, analyses spending behaviour using machine learning, detects unusual transactions, and predicts future expenditure. Delivered through an Android mobile application.



## What the System Does

- Automatically reads and parses M-Pesa and bank card SMS notifications
- Groups transactions into personalised spending clusters using K-Means Clustering
- Detects unusual spending behaviour using Isolation Forest
- Predicts future weekly expenditure using Random Forest Regression
- Delivers insights through a Flutter Android application

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter (Android) |
| Backend | Python + FastAPI |
| Database | PostgreSQL |
| ML Models | scikit-learn |
| Model Training | Google Colab |

## ML Model Results

| Model | Metric | Result |
|---|---|---|
| K-Means Clustering | Silhouette Score | 0.3003 (K=4) |
| Isolation Forest | Anomaly Rate | 5.0% (112 anomalies detected) |
| Random Forest | RMSE | KES 14,029 |
