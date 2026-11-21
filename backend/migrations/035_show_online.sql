-- A user can choose not to appear in the hosts' "Users online" list.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS show_online BOOLEAN NOT NULL DEFAULT true;
