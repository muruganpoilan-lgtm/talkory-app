-- Daily online time per host (India time) and the penalty applied for being online less than the daily minimum.
CREATE TABLE IF NOT EXISTS partner_online_daily (
  partner_id UUID NOT NULL REFERENCES accounts(id),
  day        DATE NOT NULL,
  seconds    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (partner_id, day)
);
CREATE TABLE IF NOT EXISTS online_penalties (
  partner_id    UUID NOT NULL REFERENCES accounts(id),
  day           DATE NOT NULL,
  short_seconds INTEGER NOT NULL,
  penalty_paise INTEGER NOT NULL,   -- what the rule asked for
  charged_paise INTEGER NOT NULL,   -- what was actually taken (never more than the wallet held)
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (partner_id, day)
);
