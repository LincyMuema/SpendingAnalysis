-- PESIGHT: FULL DATABASE RESET (deletes EVERYTHING, then rebuilds the empty tables)
--
-- What it does:
--   1. Deletes every table, including ALL user accounts and ALL transactions.
--   2. Recreates the 6 tables, the indexes and the 17 standard categories.
-- It adds no users or transactions. To add the demo account, run
-- sample.sql afterwards.
--
-- How to run: pgAdmin -> the Render database -> a NEW, EMPTY query tab ->
-- paste this whole file -> run with nothing highlighted.

BEGIN;


-- ── 1. Remove existing tables (children before parents) ─────────────────────
DROP TABLE IF EXISTS recommendations  CASCADE;   -- old reserved tables, no longer used
DROP TABLE IF EXISTS predictions      CASCADE;
DROP TABLE IF EXISTS alerts           CASCADE;
DROP TABLE IF EXISTS analysis_results CASCADE;
DROP TABLE IF EXISTS auth_codes       CASCADE;
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
    password_hash VARCHAR(255),                 -- empty for Google-only accounts
    google_id     VARCHAR(255) UNIQUE,          -- set when signed in with Google
    two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE once the emailed code is entered (or Google sign-in)
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
    occurred_at       TIMESTAMP,                             -- time of the payment from the SMS, if known
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

-- ── 3. Sign-in codes and analysis records ───────────────────────────────────

-- One-time codes for password reset and two-step sign-in (only hashes are stored).
CREATE TABLE auth_codes (
    code_id     SERIAL PRIMARY KEY,
    user_id     INT          NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    purpose     VARCHAR(20)  NOT NULL CHECK (purpose IN ('password_reset', 'login_2fa', 'email_verify')),
    code_hash   VARCHAR(255) NOT NULL,
    expires_at  TIMESTAMP    NOT NULL,
    attempts    INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- A record of every analysis run (summary columns plus the full result).
CREATE TABLE analysis_results (
    analysis_id            SERIAL PRIMARY KEY,
    user_id                INT           NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    created_at             TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    period_days            INT           NOT NULL,
    transaction_count      INT           NOT NULL,
    total_spend_kes        NUMERIC(12,2) NOT NULL,
    anomaly_count          INT           NOT NULL,
    next_week_forecast_kes NUMERIC(12,2),             -- empty when there is not enough history
    result                 JSONB         NOT NULL
);

-- ── 4. Indexes ───────────────────────────────────────────────────────────────

-- The same SMS can never be imported twice for a user (manual rows have no reference).
CREATE UNIQUE INDEX uq_transactions_user_reference
    ON transactions (user_id, reference)
    WHERE reference IS NOT NULL;

-- Speeds up loading a user's transactions newest-first.
CREATE INDEX ix_transactions_user_date ON transactions (user_id, date DESC, occurred_at DESC);

CREATE INDEX ix_auth_codes_user_purpose ON auth_codes (user_id, purpose);
CREATE INDEX ix_analysis_results_user_time ON analysis_results (user_id, created_at DESC);

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

-- Check
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;      -- expect 6 tables

SELECT COUNT(*) AS categories FROM categories;           -- expect 17