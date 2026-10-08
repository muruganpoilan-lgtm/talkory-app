const router = require('express').Router();
const { pool, requireAuth } = require('./db');

const MIN_PAYOUT_RUPEES = 500;
const UPI_RE = /^[\w.\-]{2,}@[a-zA-Z]{2,}$/;
const IST_DAY = "(created_at AT TIME ZONE 'Asia/Kolkata')::date = (now() AT TIME ZONE 'Asia/Kolkata')::date";

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const num = (v) => Number(v ?? 0);

// ---------------- partner ----------------

// Everything the earnings screen needs, in one call (all money in paise)
router.get('/earnings', requireAuth(['partner']), async (req, res) => {
  const id = req.auth.id;
  const [wallet, sums, payoutSums, profile, calls, payouts] = await Promise.all([
    pool.query('SELECT balance FROM wallets WHERE account_id=$1', [id]),
    pool.query(
      `SELECT COALESCE(SUM(amount),0) AS total,
              COALESCE(SUM(amount) FILTER (WHERE ${IST_DAY}),0) AS today
         FROM ledger WHERE account_id=$1 AND type='call_earning'`, [id]),
    pool.query(
      `SELECT COALESCE(SUM(amount) FILTER (WHERE status='paid'),0) AS withdrawn,
              COALESCE(SUM(amount) FILTER (WHERE status IN ('requested','processing')),0) AS pending
         FROM payouts WHERE partner_id=$1`, [id]),
    pool.query('SELECT upi_id, kyc FROM partner_profiles WHERE account_id=$1', [id]),
    pool.query(
      `SELECT c.id, c.started_at, c.billed_seconds, COALESCE(SUM(l.amount),0) AS earned
         FROM calls c
         LEFT JOIN ledger l ON l.call_id=c.id AND l.type='call_earning' AND l.account_id=$1
        WHERE c.partner_id=$1 AND c.started_at IS NOT NULL
        GROUP BY c.id ORDER BY c.started_at DESC LIMIT 30`, [id]),
    pool.query(
      `SELECT id, amount, status, upi_id, requested_at, paid_at FROM payouts
        WHERE partner_id=$1 ORDER BY requested_at DESC LIMIT 20`, [id]),
  ]);

  res.json({
    balance: num(wallet.rows[0]?.balance),
    totalEarned: num(sums.rows[0].total),
    today: num(sums.rows[0].today),
    withdrawn: num(payoutSums.rows[0].withdrawn),
    pending: num(payoutSums.rows[0].pending),
    upiId: profile.rows[0]?.upi_id ?? null,
    kyc: profile.rows[0]?.kyc,
    minPayoutRupees: MIN_PAYOUT_RUPEES,
    recentCalls: calls.rows.map((r) => ({
      id: r.id, startedAt: r.started_at, seconds: r.billed_seconds, earned: num(r.earned),
    })),
    payouts: payouts.rows.map((r) => ({
      id: r.id, amount: num(r.amount), status: r.status, upiId: r.upi_id,
      requestedAt: r.requested_at, paidAt: r.paid_at,
    })),
  });
});

router.put('/payout-method', requireAuth(['partner']), async (req, res) => {
  const upi = String(req.body.upiId || '').trim().toLowerCase();
  if (!UPI_RE.test(upi)) return res.status(400).json({ error: 'Enter a valid UPI ID, e.g. name@bank' });
  await pool.query('UPDATE partner_profiles SET upi_id=$1 WHERE account_id=$2', [upi, req.auth.id]);
  res.json({ upiId: upi });
});

// Withdrawal request: money leaves the wallet immediately (held), admin then pays it out
router.post('/payouts', requireAuth(['partner']), async (req, res) => {
  const rupees = Number(req.body.amountRupees);
  if (!Number.isInteger(rupees) || rupees < MIN_PAYOUT_RUPEES)
    return res.status(400).json({ error: `Minimum withdrawal is ₹${MIN_PAYOUT_RUPEES}` });
  const amount = rupees * 100;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const p = (await client.query(
      'SELECT kyc, upi_id FROM partner_profiles WHERE account_id=$1 FOR UPDATE', [req.auth.id])).rows[0];
    if (!p || p.kyc !== 'approved') throw new HttpError(403, 'KYC approval is required to withdraw');
    if (!p.upi_id) throw new HttpError(400, 'Add your UPI ID first');

    const open = await client.query(
      `SELECT 1 FROM payouts WHERE partner_id=$1 AND status IN ('requested','processing')`, [req.auth.id]);
    if (open.rowCount) throw new HttpError(409, 'You already have a withdrawal in progress');

    const debit = await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2 AND balance >= $1',
      [amount, req.auth.id]);
    if (!debit.rowCount) throw new HttpError(402, 'Insufficient balance');

    const payout = (await client.query(
      'INSERT INTO payouts (partner_id, amount, upi_id) VALUES ($1,$2,$3) RETURNING id',
      [req.auth.id, amount, p.upi_id])).rows[0];
    await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'payout',$2,$3,$4)`,
      [req.auth.id, -amount, payout.id, `payout:${payout.id}`]);
    await client.query('COMMIT');
    res.json({ payoutId: payout.id });
  } catch (e) {
    await client.query('ROLLBACK');
    if (e instanceof HttpError) return res.status(e.status).json({ error: e.message });
    throw e;
  } finally {
    client.release();
  }
});

// ---------------- admin (minimal; a full panel comes later) ----------------

router.get('/admin/payouts', requireAuth(['admin']), async (req, res) => {
  const status = req.query.status || 'requested';
  const { rows } = await pool.query(
    `SELECT p.id, p.amount, p.status, p.upi_id, p.requested_at, a.display_name, pp.kyc
       FROM payouts p JOIN accounts a ON a.id=p.partner_id JOIN partner_profiles pp ON pp.account_id=p.partner_id
      WHERE p.status=$1 ORDER BY p.requested_at ASC LIMIT 100`, [status]);
  res.json(rows.map((r) => ({ ...r, amount: num(r.amount) })));
});

// Call this AFTER you have actually sent the money (UPI / bank transfer / RazorpayX)
router.post('/admin/payouts/:id/paid', requireAuth(['admin']), async (req, res) => {
  const r = await pool.query(
    `UPDATE payouts SET status='paid', paid_at=now(), reference=$2
      WHERE id=$1 AND status IN ('requested','processing')`, [req.params.id, req.body.reference || null]);
  if (!r.rowCount) return res.status(409).json({ error: 'payout not pending' });
  res.json({ ok: true });
});

// Reject: returns the held money to the partner's wallet
router.post('/admin/payouts/:id/reject', requireAuth(['admin']), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const p = (await client.query(
      `UPDATE payouts SET status='rejected' WHERE id=$1 AND status IN ('requested','processing')
       RETURNING partner_id, amount`, [req.params.id])).rows[0];
    if (!p) throw new HttpError(409, 'payout not pending');
    const ins = await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'refund',$2,$3,$4)
       ON CONFLICT (idem_key) DO NOTHING`,
      [p.partner_id, p.amount, req.params.id, `payout-refund:${req.params.id}`]);
    if (ins.rowCount)
      await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2',
        [p.amount, p.partner_id]);
    await client.query('COMMIT');
    res.json({ ok: true });
  } catch (e) {
    await client.query('ROLLBACK');
    if (e instanceof HttpError) return res.status(e.status).json({ error: e.message });
    throw e;
  } finally {
    client.release();
  }
});

module.exports = router;
