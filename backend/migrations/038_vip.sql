-- VIP plan: a monthly pass with cheaper calls (see wallet.js and billing.js)
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS vip_until TIMESTAMPTZ;
ALTER TABLE calls ADD COLUMN IF NOT EXISTS is_vip BOOLEAN NOT NULL DEFAULT FALSE;
