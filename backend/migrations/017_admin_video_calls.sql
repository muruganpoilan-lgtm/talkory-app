-- Video calls started by an admin from the web panel to a user or host. Free for everyone; the apps cannot start these.
CREATE TABLE IF NOT EXISTS admin_calls (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id    UUID NOT NULL REFERENCES accounts(id),
  target_id   UUID NOT NULL REFERENCES accounts(id),
  channel_name TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing','active','ended','rejected','missed')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  answered_at TIMESTAMPTZ,
  ended_at    TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS admin_calls_target_idx ON admin_calls (target_id, created_at DESC);
