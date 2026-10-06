const crypto = require('crypto');
const router = require('express').Router();
const { pool, requireAuth } = require('./db');

const MIN_RUPEES = 100;
const MAX_RUPEES = 10000;

const hmac = (secret, data) => crypto.createHmac('sha256', secret).update(data).digest('hex');
const safeEqual = (a, b) => {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

async function razorpayPost(path, body) {
  const auth = Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const r = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await r.json();
  if (!r.ok) throw new Error(data?.error?.description || 'razorpay error');
  return data;
}

// Credits the wallet exactly once per order. Called by BOTH /verify and the webhook,
// whichever arrives first wins; the other is a no-op.
async function creditTopup(orderId, paymentId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      'SELECT * FROM topup_orders WHERE razorpay_order_id=$1 FOR UPDATE', [orderId]);
    const order = rows[0];
    if (!order) { await client.query('ROLLBACK'); return null; }
    if (order.status === 'paid') { await client.query('COMMIT'); return order; }

    const ins = await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key)
       VALUES ($1,'topup',$2,$3,$4) ON CONFLICT (idem_key) DO NOTHING`,
      [order.account_id, order.amount, paymentId, `topup:${paymentId}`]);
    if (ins.rowCount) {
      await client.query(
        'UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2',
        [order.amount, order.account_id]);
    }
    await client.query(
      `UPDATE topup_orders SET status='paid', razorpay_payment_id=$1, paid_at=now() WHERE id=$2`,
      [paymentId, order.id]);
    await client.query('COMMIT');
    return order;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function balanceOf(accountId) {
  const { rows } = await pool.query('SELECT balance FROM wallets WHERE account_id=$1', [accountId]);
  return Number(rows[0]?.balance ?? 0);
}

// Current balance (paise)
router.get('/', requireAuth(['user', 'partner']), async (req, res) => {
  res.json({ balance: await balanceOf(req.auth.id) });
});

const PAGE = 30;
router.get('/history', requireAuth(['user']), async (req, res) => {
  const page = Math.max(0, parseInt(req.query.page, 10) || 0);
  const { rows } = await pool.query(
    `SELECT 'call' AS kind, c.id::text AS id, SUM(l.amount)::bigint AS amount, MAX(l.created_at) AS at,
            a.display_name AS counterpart, c.billed_seconds AS seconds
       FROM ledger l JOIN calls c ON c.id = l.call_id JOIN accounts a ON a.id = c.partner_id
      WHERE l.account_id = $1 AND l.type = 'call_debit'
      GROUP BY c.id, a.display_name, c.billed_seconds
     UNION ALL
     SELECT l.type::text, l.id::text, l.amount, l.created_at, NULL::text, NULL::int
       FROM ledger l WHERE l.account_id = $1 AND l.type IN ('topup', 'refund', 'adjustment')
     ORDER BY at DESC LIMIT ${PAGE} OFFSET $2`, [req.auth.id, page * PAGE]);
  res.json(rows.map((r) => ({ ...r, amount: Number(r.amount) })));
});

// Step 1: create a Razorpay order for the app to open checkout with
router.post('/topup', requireAuth(['user']), async (req, res) => {
  const rupees = Number(req.body.amountRupees);
  if (!Number.isInteger(rupees) || rupees < MIN_RUPEES || rupees > MAX_RUPEES)
    return res.status(400).json({ error: `Amount must be between ₹${MIN_RUPEES} and ₹${MAX_RUPEES}` });

  const amount = rupees * 100; // paise: always computed server-side
  try {
    const order = await razorpayPost('/orders', {
      amount, currency: 'INR',
      receipt: `tk_${Date.now()}`,
      notes: { account_id: req.auth.id },
    });
    await pool.query(
      'INSERT INTO topup_orders (account_id, razorpay_order_id, amount) VALUES ($1,$2,$3)',
      [req.auth.id, order.id, amount]);
    res.json({ orderId: order.id, keyId: process.env.RAZORPAY_KEY_ID, amount, currency: 'INR' });
  } catch (e) {
    console.error('create order failed', e.message);
    res.status(502).json({ error: 'Could not start payment. Try again.' });
  }
});

// Step 2: app sends the checkout result; we verify the signature, then credit
router.post('/topup/verify', requireAuth(['user']), async (req, res) => {
  const { orderId, paymentId, signature } = req.body;
  if (!orderId || !paymentId || !signature) return res.status(400).json({ error: 'missing fields' });

  const { rows } = await pool.query(
    'SELECT 1 FROM topup_orders WHERE razorpay_order_id=$1 AND account_id=$2', [orderId, req.auth.id]);
  if (!rows[0]) return res.status(404).json({ error: 'order not found' });

  const expected = hmac(process.env.RAZORPAY_KEY_SECRET, `${orderId}|${paymentId}`);
  if (!safeEqual(expected, signature)) return res.status(400).json({ error: 'payment verification failed' });

  await creditTopup(orderId, paymentId);
  res.json({ balance: await balanceOf(req.auth.id) });
});

// Webhook safety net (covers the app being killed right after paying).
// Mounted with express.raw() in server.js because the signature needs the exact raw body.
async function webhook(req, res) {
  const sig = req.headers['x-razorpay-signature'];
  const expected = hmac(process.env.RAZORPAY_WEBHOOK_SECRET, req.body);
  if (!sig || !safeEqual(expected, sig)) return res.status(400).end();

  try {
    const event = JSON.parse(req.body.toString());
    if (event.event === 'payment.captured') {
      const p = event.payload.payment.entity;
      await creditTopup(p.order_id, p.id);
    } else if (event.event === 'order.paid') {
      const o = event.payload.order.entity;
      const p = event.payload.payment.entity;
      await creditTopup(o.id, p.id);
    }
    res.json({ ok: true });
  } catch (e) {
    console.error('webhook failed', e);
    res.status(500).end(); // Razorpay will retry
  }
}

module.exports = { router, webhook };
