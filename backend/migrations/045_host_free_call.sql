-- A host can give a user 3 free minutes, once every 3 hours. She earns nothing for them,
-- so this is a win-back tool she spends her own time on, not a way to collect earnings.
ALTER TABLE calls ADD COLUMN IF NOT EXISTS is_host_free BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_calls_host_free ON calls(partner_id, created_at DESC) WHERE is_host_free;
