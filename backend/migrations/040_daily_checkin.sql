-- Daily check-in reward: one row per user per India day (see checkin.js)
CREATE TABLE IF NOT EXISTS checkins (
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day        DATE NOT NULL,
  streak     INT  NOT NULL,
  coins      INT  NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, day)
);
