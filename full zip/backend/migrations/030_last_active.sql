-- When a host (or anyone) last used the app. Hosts who stay away for 30 days are cleaned up automatically (see cleanup.js).
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;
UPDATE accounts SET last_active_at = now() WHERE last_active_at IS NULL; -- the 30 days start counting from this update
ALTER TABLE accounts ALTER COLUMN last_active_at SET DEFAULT now();
