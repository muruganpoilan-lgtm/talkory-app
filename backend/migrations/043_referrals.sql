-- Refer and earn: every user has a code to share. The friend who uses it gets welcome coins at once,
-- and the person who shared it is paid when that friend first puts money in (see referrals.js).
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS referral_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_referral_code ON accounts(referral_code) WHERE referral_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS referrals (
  id            BIGSERIAL PRIMARY KEY,
  referrer_id   UUID NOT NULL REFERENCES accounts(id),
  friend_id     UUID NOT NULL UNIQUE REFERENCES accounts(id), -- a person can be referred only once, ever
  code          TEXT NOT NULL,
  friend_coins  INT NOT NULL DEFAULT 0,  -- welcome coins already given to the friend
  reward_coins  INT,                     -- coins paid to the referrer, once the friend recharges
  paid_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_referrals_created ON referrals(created_at DESC);
