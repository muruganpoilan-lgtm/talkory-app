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
