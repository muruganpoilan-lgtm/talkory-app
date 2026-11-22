-- First-recharge bonus: free coins added to a user's very first paid top-up (see wallet.js)
ALTER TABLE topup_orders ADD COLUMN IF NOT EXISTS first_bonus BIGINT NOT NULL DEFAULT 0;
