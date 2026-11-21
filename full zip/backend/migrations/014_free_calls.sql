-- Free trial call: one free 2-minute call per user every 3 hours (the platform pays the host's share)
ALTER TABLE calls ADD COLUMN IF NOT EXISTS is_free BOOLEAN NOT NULL DEFAULT FALSE;
