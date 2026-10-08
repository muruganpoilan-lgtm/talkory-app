-- Talkory backend schema (PostgreSQL)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE account_role AS ENUM ('user', 'partner', 'admin');
CREATE TYPE call_status AS ENUM ('ringing', 'active', 'ended', 'missed', 'rejected', 'failed');
CREATE TYPE ledger_type AS ENUM ('topup', 'call_debit', 'call_earning', 'platform_fee', 'payout', 'refund', 'adjustment');
CREATE TYPE payout_status AS ENUM ('requested', 'processing', 'paid', 'rejected');
CREATE TYPE kyc_status AS ENUM ('pending', 'approved', 'rejected');

-- Accounts (both apps share one auth table)
CREATE TABLE accounts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role          account_role NOT NULL,
  phone         TEXT UNIQUE NOT NULL,          -- never exposed to the other side
  display_name  TEXT NOT NULL,
  avatar_url    TEXT,
  is_adult      BOOLEAN NOT NULL DEFAULT FALSE, -- 18+ confirmation
  is_blocked    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partner (host/expert) profile
CREATE TABLE partner_profiles (
  account_id      UUID PRIMARY KEY REFERENCES accounts(id),
  bio             TEXT,
  languages       TEXT[] NOT NULL DEFAULT '{}',
  rate_per_min    INTEGER NOT NULL,             -- user price, in minor units (e.g. paise)
  payout_share    NUMERIC(4,3) NOT NULL DEFAULT 0.600, -- partner's cut
  is_online       BOOLEAN NOT NULL DEFAULT FALSE,
  kyc             kyc_status NOT NULL DEFAULT 'pending',
  rating_avg      NUMERIC(3,2) NOT NULL DEFAULT 0,
  rating_count    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_partner_langs ON partner_profiles USING GIN (languages);

-- Wallets (one per account; balance is derived from the ledger, cached here)
CREATE TABLE wallets (
  account_id  UUID PRIMARY KEY REFERENCES accounts(id),
  balance     BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Calls
CREATE TABLE calls (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES accounts(id),
  partner_id    UUID NOT NULL REFERENCES accounts(id),
  status        call_status NOT NULL DEFAULT 'ringing',
  channel_name  TEXT NOT NULL,                  -- voice SDK channel
  rate_per_min  INTEGER NOT NULL,               -- snapshot at call start
  started_at    TIMESTAMPTZ,
  ended_at      TIMESTAMPTZ,
  billed_seconds INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_calls_user ON calls(user_id, created_at DESC);
CREATE INDEX idx_calls_partner ON calls(partner_id, created_at DESC);

-- Append-only ledger: never UPDATE or DELETE rows here
CREATE TABLE ledger (
  id          BIGSERIAL PRIMARY KEY,
  account_id  UUID NOT NULL REFERENCES accounts(id),
  type        ledger_type NOT NULL,
  amount      BIGINT NOT NULL,                  -- positive = credit, negative = debit
  call_id     UUID REFERENCES calls(id),
  ref         TEXT,                             -- payment gateway id, payout id, etc.
  idem_key    TEXT UNIQUE,                      -- prevents double-billing on retries
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_account ON ledger(account_id, created_at DESC);

-- Payouts to partners
CREATE TABLE payouts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id  UUID NOT NULL REFERENCES accounts(id),
  amount      BIGINT NOT NULL CHECK (amount > 0),
  status      payout_status NOT NULL DEFAULT 'requested',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at     TIMESTAMPTZ
);

-- Ratings
CREATE TABLE ratings (
  call_id     UUID PRIMARY KEY REFERENCES calls(id),
  user_id     UUID NOT NULL REFERENCES accounts(id),
  partner_id  UUID NOT NULL REFERENCES accounts(id),
  stars       SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Safety: reports and blocks
CREATE TABLE reports (
  id           BIGSERIAL PRIMARY KEY,
  reporter_id  UUID NOT NULL REFERENCES accounts(id),
  reported_id  UUID NOT NULL REFERENCES accounts(id),
  call_id      UUID REFERENCES calls(id),
  reason       TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE blocks (
  blocker_id  UUID NOT NULL REFERENCES accounts(id),
  blocked_id  UUID NOT NULL REFERENCES accounts(id),
  PRIMARY KEY (blocker_id, blocked_id)
);

-- Device tokens for push (FCM/APNs)
CREATE TABLE devices (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  UUID NOT NULL REFERENCES accounts(id),
  platform    TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  push_token  TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, push_token)
);

-- Razorpay wallet top-ups (amount in paise)
CREATE TABLE topup_orders (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id           UUID NOT NULL REFERENCES accounts(id),
  razorpay_order_id    TEXT UNIQUE NOT NULL,
  razorpay_payment_id  TEXT,
  amount               BIGINT NOT NULL CHECK (amount > 0),
  status               TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at              TIMESTAMPTZ
);
CREATE INDEX idx_topup_account ON topup_orders(account_id, created_at DESC);

-- Payout details (see migrations/002_payouts.sql)
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS upi_id TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS upi_id TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS reference TEXT;
CREATE INDEX IF NOT EXISTS idx_payouts_partner ON payouts(partner_id, requested_at DESC);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'open';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

-- KYC documents (see migrations/004_kyc.sql)
CREATE TABLE IF NOT EXISTS kyc_documents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  UUID NOT NULL REFERENCES accounts(id),
  kind        TEXT NOT NULL CHECK (kind IN ('id_front', 'selfie')),
  file_name   TEXT NOT NULL,
  mime        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, kind)
);
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS kyc_submitted_at TIMESTAMPTZ;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS kyc_note TEXT;

-- Terms acceptance (see migrations/005_terms.sql)
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS terms_version TEXT;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMPTZ;

-- Account deletion (see migrations/006_account_deletion.sql)
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- iOS VoIP push token (see migrations/007_voip_token.sql)
ALTER TABLE devices ADD COLUMN IF NOT EXISTS voip_token TEXT;

-- Profile photos (see migrations/008_avatars.sql)
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_pending TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_status TEXT CHECK (avatar_status IN ('pending', 'approved', 'rejected'));
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_note TEXT;
