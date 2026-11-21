-- Host-started calls: 'user' (default) or 'partner'
ALTER TABLE calls ADD COLUMN IF NOT EXISTS initiated_by TEXT NOT NULL DEFAULT 'user';
