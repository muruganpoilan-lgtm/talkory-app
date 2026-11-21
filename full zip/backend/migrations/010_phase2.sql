ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS intro_pending TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS intro_status TEXT CHECK (intro_status IN ('pending', 'approved', 'rejected'));
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS intro_note TEXT;
ALTER TABLE partner_profiles ADD COLUMN IF NOT EXISTS intro_url TEXT;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS gst_number TEXT;
