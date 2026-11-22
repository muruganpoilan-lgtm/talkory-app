-- Counting a host's missed calls for the day (see missedcalls.js) runs on every ring-out
CREATE INDEX IF NOT EXISTS idx_calls_partner_missed ON calls(partner_id, created_at DESC) WHERE status = 'missed';
