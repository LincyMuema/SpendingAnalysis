
BEGIN;

-- ── 1. Remove existing tables (children before parents) ─────────────────────
DROP TABLE IF EXISTS recommendations  CASCADE;
DROP TABLE IF EXISTS predictions      CASCADE;
DROP TABLE IF EXISTS alerts           CASCADE;
DROP TABLE IF EXISTS analysis_results CASCADE;
DROP TABLE IF EXISTS merchant_rules   CASCADE;
DROP TABLE IF EXISTS transactions     CASCADE;
DROP TABLE IF EXISTS categories       CASCADE;
DROP TABLE IF EXISTS users            CASCADE;

-- ── 2. Core tables ───────────────────────────────────────────────────────────

-- Registered users. Passwords are stored as hashes, never in plain text.
CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The 17 standard spending categories (seeded below) have user_id NULL and are
-- shared by everyone. Categories a user creates have their user_id and are
-- only visible to that user. Names are unique per user (see the index below).
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL,
    icon        VARCHAR(10),
    user_id     INT REFERENCES users(user_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX uq_categories_owner_name
    ON categories (COALESCE(user_id, 0), LOWER(name));

-- One row per spending transaction (from SMS or entered manually).
CREATE TABLE transactions (
    transaction_id    SERIAL PRIMARY KEY,
    user_id           INT          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    amount            FLOAT        NOT NULL CHECK (amount > 0),
    date              DATE         NOT NULL,
    transaction_type  VARCHAR(20),
    source            VARCHAR(20)  CHECK (source IN ('MPESA', 'CARD', 'CASH', 'WALLET')),
    counterparty      VARCHAR(100),                          -- merchant or person paid
    category_id       INT          NOT NULL REFERENCES categories(category_id),
    is_manual         BOOLEAN      NOT NULL DEFAULT FALSE,   -- TRUE = entered by the user
    reference         VARCHAR(30),                           -- M-Pesa/Airtel code or BANK- fingerprint
    anomaly_dismissed BOOLEAN      NOT NULL DEFAULT FALSE,   -- user marked "Not unusual"
    created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Category a user chose for a merchant/person; applied to future SMS imports.
CREATE TABLE merchant_rules (
    user_id      INT          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    counterparty VARCHAR(100) NOT NULL,                      -- stored in UPPER CASE
    category_id  INT          NOT NULL REFERENCES categories(category_id),
    PRIMARY KEY (user_id, counterparty)
);

-- ── 3. Tables reserved for storing analysis output (not yet used) ─────────────

CREATE TABLE analysis_results (
    result_id   SERIAL PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    cluster_id  INT,
    analysed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE alerts (
    alert_id       SERIAL PRIMARY KEY,
    user_id        INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    transaction_id INT REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    message        TEXT,
    severity       VARCHAR(20),
    status         VARCHAR(20) NOT NULL DEFAULT 'unread',
    created_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE predictions (
    prediction_id    SERIAL PRIMARY KEY,
    user_id          INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    predicted_amount FLOAT,
    period           VARCHAR(20),
    overspend_risk   VARCHAR(20),
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE recommendations (
    recommendation_id SERIAL PRIMARY KEY,
    user_id           INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    message           TEXT,
    category          VARCHAR(50),
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ── 4. Indexes ───────────────────────────────────────────────────────────────

-- The same SMS can never be imported twice for a user (manual rows have no reference).
CREATE UNIQUE INDEX uq_transactions_user_reference
    ON transactions (user_id, reference)
    WHERE reference IS NOT NULL;

-- Speeds up loading a user's transactions newest-first.
CREATE INDEX ix_transactions_user_date ON transactions (user_id, date DESC);

-- ── 5. Seed the 17 standard categories (order fixes their category_id) ──────
INSERT INTO categories (name, icon) VALUES
    ('Bills & Utilities', '💡'),     -- 1
    ('Business',          '💼'),     -- 2
    ('Crypto',            '₿'),     -- 3
    ('Education',         '📚'),     -- 4
    ('Entertainment',     '🎬'),     -- 5
    ('Food & Dining',     '🍽️'),    -- 6
    ('Gambling',          '🎰'),     -- 7
    ('Government',        '🏛️'),    -- 8
    ('Healthcare',        '💊'),     -- 9
    ('Insurance',         '🛡️'),    -- 10
    ('Investments',       '📈'),     -- 11
    ('Other',             '📦'),     -- 12
    ('Personal Care',     '🪥'),     -- 13
    ('Shopping',          '🛍️'),    -- 14
    ('Transfer',          '💸'),     -- 15
    ('Transport',         '🚌'),     -- 16
    ('Travel',            '✈️');    -- 17

COMMIT;

-- ── 6. Check ─────────────────────────────────────────────────────────────────
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;      -- expect 8 tables

SELECT category_id, name FROM categories ORDER BY category_id;   -- expect 17 rows