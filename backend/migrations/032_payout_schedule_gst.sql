-- Payouts are paid on the 10th, 20th and 30th (28th/29th in February) with 18% GST taken out, and every paid payout gets an invoice.
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS gst_paise BIGINT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS net_paise BIGINT;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS pay_on DATE;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS invoice_no TEXT;
CREATE SEQUENCE IF NOT EXISTS invoice_seq;
CREATE TABLE IF NOT EXISTS payout_invoices (
  payout_id  UUID PRIMARY KEY REFERENCES payouts(id),
  invoice_no TEXT NOT NULL UNIQUE,
  pdf        BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payouts_pay_on_idx ON payouts (pay_on) WHERE status = 'requested';
