-- Automatic UPI payouts through RazorpayX
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS rzp_payout_id TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS payout_note TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS reference TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS rzp_contact_id TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS rzp_fund_id TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS rzp_fund_upi TEXT;
CREATE INDEX IF NOT EXISTS payouts_rzp_idx ON payouts (rzp_payout_id);
