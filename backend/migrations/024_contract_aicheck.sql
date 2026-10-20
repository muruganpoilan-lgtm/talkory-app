-- Host agreement, signed after KYC is approved
CREATE TABLE IF NOT EXISTS partner_contracts (
  partner_id  UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  version     INT  NOT NULL,
  full_name   TEXT NOT NULL,
  ip          TEXT,
  signed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- AI-generated image check (score 0..1, higher = more likely AI). *_file remembers which file was checked.
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_ai NUMERIC;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_ai_file TEXT;
ALTER TABLE kyc_documents ADD COLUMN IF NOT EXISTS ai_score NUMERIC;
ALTER TABLE kyc_documents ADD COLUMN IF NOT EXISTS ai_file TEXT;
