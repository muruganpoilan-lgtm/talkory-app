-- Why an account was blocked, who did it and when. The admin panel shows this and can undo it.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS blocked_reason TEXT;        -- full detail, admins only
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS blocked_note   TEXT;        -- short line the blocked person is shown
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS blocked_at     TIMESTAMPTZ;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS blocked_by     UUID REFERENCES accounts(id);

-- Person-to-person blocks: keep the reason the blocker picked, and when they did it
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS reason     TEXT;
ALTER TABLE blocks ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Every block and unblock, so there is always a record of who did what
CREATE TABLE IF NOT EXISTS block_events (
  id          BIGSERIAL PRIMARY KEY,
  account_id  UUID NOT NULL REFERENCES accounts(id),
  action      TEXT NOT NULL CHECK (action IN ('block', 'unblock')),
  reason      TEXT,
  by_admin    UUID REFERENCES accounts(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_block_events_at ON block_events(created_at DESC);

-- Accounts blocked before this change have no reason saved: say so instead of showing an empty cell
UPDATE accounts SET blocked_reason = 'Blocked before Talkory started recording reasons', blocked_at = created_at
 WHERE is_blocked AND blocked_reason IS NULL AND deleted_at IS NULL AND role IN ('user', 'partner');
