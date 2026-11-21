-- One admin is the Owner: only the owner sees earnings, withdrawals, payouts and the list of admins.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS is_owner BOOLEAN NOT NULL DEFAULT false;
-- If nobody is owner yet, the first admin ever created becomes the owner.
UPDATE accounts SET is_owner = true
 WHERE id = (SELECT id FROM accounts WHERE role = 'admin' AND NOT is_blocked ORDER BY created_at LIMIT 1)
   AND NOT EXISTS (SELECT 1 FROM accounts WHERE is_owner);
