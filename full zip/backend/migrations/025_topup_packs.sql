-- Coin packs: the user can pay less than the coins they get (bonus coins). amount = coins credited, pay_amount = rupees charged (paise).
ALTER TABLE topup_orders ADD COLUMN IF NOT EXISTS pay_amount BIGINT;
ALTER TABLE topup_orders ADD COLUMN IF NOT EXISTS pack_id TEXT;
