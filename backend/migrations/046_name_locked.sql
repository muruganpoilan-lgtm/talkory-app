-- A host picks her name once, when she signs up, and cannot change it afterwards.
-- An admin can unlock one account when someone made a genuine mistake at sign-up.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS name_locked BOOLEAN NOT NULL DEFAULT false;

-- Every host already picked a name at sign-up, so they all start locked.
UPDATE accounts SET name_locked = true WHERE role = 'partner' AND COALESCE(display_name, '') <> '';
