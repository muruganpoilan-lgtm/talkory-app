-- Talkory's own earnings (its share of every call and chat message) and the withdrawals the admin has taken
CREATE TABLE IF NOT EXISTS admin_withdrawals (
  id          BIGSERIAL PRIMARY KEY,
  admin_id    UUID NOT NULL REFERENCES accounts(id),
  amount      BIGINT NOT NULL CHECK (amount > 0),
  upi_id      TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
