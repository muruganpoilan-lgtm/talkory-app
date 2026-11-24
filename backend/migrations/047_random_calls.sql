-- Random Call: the user taps one button and we ring whichever host is free.
-- Marked so reports can tell these apart from calls where the user picked the host,
-- and so a host who misses one is not fined for a call they were never chosen for.
ALTER TABLE calls ADD COLUMN IF NOT EXISTS is_random BOOLEAN NOT NULL DEFAULT false;

-- Finding the next free host runs on every tap, so keep the lookup cheap.
CREATE INDEX IF NOT EXISTS idx_partner_profiles_available
  ON partner_profiles (account_id) WHERE is_online AND kyc = 'approved';
