-- User agreement signed by hand on the touch screen: the drawn signature is kept as a small PNG
CREATE TABLE IF NOT EXISTS user_agreements (
  account_id  UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  version     INT   NOT NULL,
  full_name   TEXT  NOT NULL,
  signature   BYTEA NOT NULL,
  ip          TEXT,
  signed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
