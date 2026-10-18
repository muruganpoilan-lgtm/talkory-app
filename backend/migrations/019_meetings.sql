-- Group video meetings that an admin arranges for users and/or hosts. Free for everyone; only admins can create them.
CREATE TABLE IF NOT EXISTS meetings (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     UUID NOT NULL REFERENCES accounts(id),
  title        TEXT NOT NULL,
  channel_name TEXT NOT NULL,
  audience     TEXT NOT NULL CHECK (audience IN ('everyone','users','partners','selected')),
  status       TEXT NOT NULL DEFAULT 'live' CHECK (status IN ('scheduled','live','ended')),
  scheduled_at TIMESTAMPTZ,
  started_at   TIMESTAMPTZ,
  ended_at     TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS meeting_invitees (
  meeting_id UUID NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id),
  PRIMARY KEY (meeting_id, account_id)
);
CREATE INDEX IF NOT EXISTS meetings_status_idx ON meetings (status, created_at DESC);
