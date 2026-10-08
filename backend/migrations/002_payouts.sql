-- Partner payout details + payout bookkeeping (safe to run more than once)
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS upi_id TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS upi_id TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS reference TEXT;
CREATE INDEX IF NOT EXISTS idx_payouts_partner ON payouts(partner_id, requested_at DESC);
