const crypto = require('crypto');
const { pool } = require('./db');
const paydays = require('./paydays');
const invoice = require('./invoice');

// Automatic UPI payouts through RazorpayX. Switched on only when AUTO_PAYOUTS=1 and RAZORPAYX_ACCOUNT_NUMBER is set;
// otherwise withdrawals stay manual (admin pays from a UPI app and taps "Mark paid").
//
// Flow: a host requests a withdrawal (money is held) -> send() creates the RazorpayX contact + UPI fund account (once per
// UPI ID) and the payout -> RazorpayX calls /webhooks/razorpayx -> "paid" (with the bank reference) or "rejected" + refund.
const ENABLED = process.env.AUTO_PAYOUTS === '1' && !!process.env.RAZORPAYX_ACCOUNT_NUMBER
  && !!process.env.RAZORPAY_KEY_ID && !!process.env.RAZORPAY_KEY_SECRET;

class RzpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function rzp(path, body, idempotencyKey) {
  const auth = Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const r = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json', ...(idempotencyKey ? { 'X-Payout-Idempotency': idempotencyKey } : {}) },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new RzpError(r.status, data?.error?.description || `RazorpayX error ${r.status}`);
  return data;
}

// Return the held money to the host's wallet and mark the payout rejected. Safe to call twice.
async function refund(payoutId, note, allowFromPaid = false) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const statuses = allowFromPaid ? "('requested','processing','paid')" : "('requested','processing')";
    const p = (await client.query(
      `UPDATE payouts SET status='rejected', payout_note=$2 WHERE id=$1 AND status IN ${statuses} RETURNING partner_id, amount`, [payoutId, note || null])).rows[0];
    if (!p) { await client.query('ROLLBACK'); return false; }
    const ins = await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'refund',$2,$3,$4) ON CONFLICT (idem_key) DO NOTHING`,
      [p.partner_id, p.amount, payoutId, `payout-refund:${payoutId}`]);
    if (ins.rowCount) await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [p.amount, p.partner_id]);
    await client.query('COMMIT');
    return true;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function markPaid(payoutId, utr) {
  const r = await pool.query(
    `UPDATE payouts SET status='paid', paid_at=now(), reference=COALESCE($2, reference) WHERE id=$1 AND status IN ('requested','processing')`, [payoutId, utr || null]);
  if (r.rowCount) await invoice.create(payoutId).catch((e) => console.error('[invoice] failed:', e.message)); // host and admin copies
  return r.rowCount > 0;
}

// Pay one requested withdrawal. Safe to call again: RazorpayX treats the same payout id as the same payout.
async function send(payoutId) {
  if (!ENABLED) return;
  const p = (await pool.query(
    `UPDATE payouts SET status='processing' WHERE id=$1 AND status='requested' AND rzp_payout_id IS NULL RETURNING partner_id, amount, net_paise, upi_id`, [payoutId])).rows[0];
  if (!p) return; // already being handled, paid or rejected
  try {
    const prof = (await pool.query(
      `SELECT a.display_name, a.phone, pp.rzp_contact_id, pp.rzp_fund_id, pp.rzp_fund_upi
         FROM partner_profiles pp JOIN accounts a ON a.id = pp.account_id WHERE pp.account_id=$1`, [p.partner_id])).rows[0];
    let contactId = prof.rzp_contact_id;
    if (!contactId) {
      const name = String(prof.display_name || 'Talkory host').replace(/[^\w .'-]/g, '').trim().slice(0, 50) || 'Talkory host';
      contactId = (await rzp('/contacts', { name, type: 'vendor', reference_id: p.partner_id })).id;
      await pool.query('UPDATE partner_profiles SET rzp_contact_id=$1 WHERE account_id=$2', [contactId, p.partner_id]);
    }
    let fundId = prof.rzp_fund_id;
    if (!fundId || prof.rzp_fund_upi !== p.upi_id) { // new UPI ID: make a new fund account
      fundId = (await rzp('/fund_accounts', { contact_id: contactId, account_type: 'vpa', vpa: { address: p.upi_id } })).id;
      await pool.query('UPDATE partner_profiles SET rzp_fund_id=$1, rzp_fund_upi=$2 WHERE account_id=$3', [fundId, p.upi_id, p.partner_id]);
    }
    const out = await rzp('/payouts', {
      account_number: process.env.RAZORPAYX_ACCOUNT_NUMBER,
      fund_account_id: fundId,
      amount: Number(p.net_paise ?? p.amount), // the host gets the amount after GST
      currency: 'INR',
      mode: 'UPI',
      purpose: 'payout',
      queue_if_low_balance: true, // if the RazorpayX balance is short, it waits and goes out once you add money
      reference_id: payoutId,
      narration: 'Talkory payout',
    }, payoutId);
    await pool.query('UPDATE payouts SET rzp_payout_id=$1 WHERE id=$2', [out.id, payoutId]);
    if (out.status === 'processed') await markPaid(payoutId, out.utr);
    else if (['rejected', 'failed', 'cancelled', 'reversed'].includes(out.status)) await refund(payoutId, out.status_details?.description || out.status);
    // queued / pending / processing: the webhook finishes it
  } catch (e) {
    if (e instanceof RzpError && e.status >= 400 && e.status < 500) {
      // RazorpayX refused it (for example a wrong UPI ID): give the money back so the host can fix the UPI ID and try again
      console.error('[payout] refused:', payoutId, e.message);
      await refund(payoutId, e.message.slice(0, 200));
    } else {
      // network trouble or RazorpayX down: put it back in the queue; the minute sweep tries again (safe: same payout id)
      console.error('[payout] will retry:', payoutId, e.message);
      await pool.query(`UPDATE payouts SET status='requested', payout_note=$2 WHERE id=$1 AND status='processing' AND rzp_payout_id IS NULL`, [payoutId, 'retrying']);
    }
  }
}

// Every minute: send the requests whose pay day has come (the 10th, 20th and 30th, from 6 pm India time). Older manual
// requests have no pay day and are never auto-paid by surprise.
async function retryPending() {
  if (!ENABLED) return;
  const t = paydays.ist();
  const { rows } = await pool.query(
    `SELECT id FROM payouts WHERE status='requested' AND rzp_payout_id IS NULL AND pay_on IS NOT NULL
        AND (pay_on < $1::date OR (pay_on = $1::date AND $2::int >= 18)) ORDER BY requested_at LIMIT 20`, [paydays.todayIso(), t.h]);
  for (const r of rows) await send(r.id);
}

// RazorpayX webhook (raw body; signed with RAZORPAYX_WEBHOOK_SECRET). Events: payout.processed, payout.failed, payout.rejected, payout.reversed, payout.cancelled
async function webhook(req, res) {
  const secret = process.env.RAZORPAYX_WEBHOOK_SECRET;
  const sig = req.headers['x-razorpay-signature'];
  if (!secret || !sig) return res.status(400).end();
  const expected = crypto.createHmac('sha256', secret).update(req.body).digest('hex');
  const a = Buffer.from(String(sig)), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return res.status(400).end();
  try {
    const event = JSON.parse(req.body.toString());
    const e = event?.payload?.payout?.entity;
    if (!e) return res.json({ ok: true });
    const ours = (await pool.query(
      `SELECT id FROM payouts WHERE rzp_payout_id=$1 OR id::text=$2 LIMIT 1`, [e.id, String(e.reference_id || '')])).rows[0];
    if (ours) {
      if (event.event === 'payout.processed') await markPaid(ours.id, e.utr);
      else if (['payout.failed', 'payout.rejected', 'payout.cancelled'].includes(event.event)) await refund(ours.id, e.status_details?.description || event.event);
      else if (event.event === 'payout.reversed') await refund(ours.id, 'reversed by the bank', true);
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('[payout] webhook failed', err);
    res.status(500).end(); // RazorpayX retries
  }
}

module.exports = { ENABLED, send, retryPending, webhook, refund, markPaid };
