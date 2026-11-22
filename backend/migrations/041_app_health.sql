-- Call-quality reports sent by the apps at the end of each call, and app crash reports (see reports.js)
CREATE TABLE IF NOT EXISTS call_reports (
  id          BIGSERIAL PRIMARY KEY,
  call_id     UUID,
  account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  role        TEXT,
  connect_ms  INT,          -- from opening the call screen to hearing the other person (null: never connected)
  duration_s  INT,
  end_reason  TEXT,         -- hung_up, other_left, network, balance, declined, no_answer, free_ended, ended, mic_denied, error
  net_quality REAL,         -- Agora 1 (excellent) .. 6 (down), average during the call
  device      TEXT,
  os          TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_call_reports_at ON call_reports(created_at DESC);
CREATE TABLE IF NOT EXISTS app_crashes (
  id          BIGSERIAL PRIMARY KEY,
  account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  role        TEXT,
  error       TEXT,
  stack       TEXT,
  device      TEXT,
  os          TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_app_crashes_at ON app_crashes(created_at DESC);
