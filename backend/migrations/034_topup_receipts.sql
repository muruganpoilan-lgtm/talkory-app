-- Every paid coin purchase gets a PDF invoice/receipt for the user (and the same copy for the admin).
CREATE SEQUENCE IF NOT EXISTS receipt_seq;
CREATE TABLE IF NOT EXISTS topup_invoices (
  order_id   UUID PRIMARY KEY REFERENCES topup_orders(id),
  invoice_no TEXT NOT NULL UNIQUE,
  pdf        BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
