-- Approximate location (rounded to about 1 km) shared by the app while it is open, with the person's permission.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS location_lat NUMERIC(6,2);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS location_lng NUMERIC(6,2);
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS location_at  TIMESTAMPTZ;
