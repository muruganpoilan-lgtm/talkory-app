-- Which UPI app a host (or the admin) wants to receive money in: gpay or phonepe
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS upi_app TEXT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS upi_app TEXT;
ALTER TABLE admin_withdrawals ADD COLUMN IF NOT EXISTS upi_app TEXT;
