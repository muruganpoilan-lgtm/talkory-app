-- A copy of every host's KYC photos, profile photos and signed agreements, kept inside the database
-- (so one database backup holds everything, and the admin panel can open them).
CREATE TABLE IF NOT EXISTS host_files (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('kyc_id', 'kyc_selfie', 'photo', 'photo_pending', 'agreement')),
  ref        TEXT NOT NULL,            -- the source file name, or 'v2@<time>' for an agreement
  mime       TEXT NOT NULL,
  data       BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, kind, ref)
);
CREATE INDEX IF NOT EXISTS host_files_account_idx ON host_files (account_id, created_at DESC);
