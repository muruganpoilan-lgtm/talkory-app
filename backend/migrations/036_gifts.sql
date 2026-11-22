-- Gifts: a user spends coins on a gift for a host, the host earns a share.
ALTER TYPE ledger_type ADD VALUE IF NOT EXISTS 'gift_debit';
ALTER TYPE ledger_type ADD VALUE IF NOT EXISTS 'gift_earning';

CREATE TABLE IF NOT EXISTS gifts_sent (
  id         BIGSERIAL PRIMARY KEY,
  sender_id  UUID NOT NULL REFERENCES accounts(id),
  host_id    UUID NOT NULL REFERENCES accounts(id),
  gift_key   TEXT NOT NULL,
  price      BIGINT NOT NULL,          -- paise the user paid
  host_share BIGINT NOT NULL,          -- paise the host earned
  call_id    UUID,
  message_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gifts_host ON gifts_sent(host_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gifts_sender ON gifts_sent(sender_id, created_at DESC);

-- A chat message that is a gift carries the gift's key, so the apps can draw it as a gift card
ALTER TABLE messages ADD COLUMN IF NOT EXISTS gift_key TEXT;
