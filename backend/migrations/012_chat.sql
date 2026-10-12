CREATE TABLE IF NOT EXISTS messages (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES accounts(id),
  partner_id   UUID NOT NULL REFERENCES accounts(id),
  sender_id    UUID NOT NULL REFERENCES accounts(id),
  body         TEXT NOT NULL,
  read_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(user_id, partner_id, id);
CREATE INDEX IF NOT EXISTS idx_messages_partner ON messages(partner_id, created_at DESC);
