ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_pending TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_status TEXT CHECK (avatar_status IN ('pending', 'approved', 'rejected'));
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS avatar_note TEXT;
