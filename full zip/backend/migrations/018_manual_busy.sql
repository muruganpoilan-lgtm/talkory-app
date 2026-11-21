-- A host can set themselves to Busy (listed, but not receiving calls), besides Online and Offline.
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS manual_busy BOOLEAN NOT NULL DEFAULT false;
