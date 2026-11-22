-- Hosts a user has marked as favourite (heart button). They get a "your favourite is online" alert.
CREATE TABLE IF NOT EXISTS favourite_hosts (
  user_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  host_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, host_id)
);
CREATE INDEX IF NOT EXISTS idx_favourite_hosts_host ON favourite_hosts(host_id);
