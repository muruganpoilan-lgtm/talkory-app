const crypto = require('crypto');
const { coins, COINS_PER_RUPEE } = require('./coins');
const router = require('express').Router();
const { pool, requireAuth } = require('./db');

const MIN_RUPEES = 100;
const MAX_RUPEES = 10000;

// Coin packs: pay (rupees) -> rupees' worth credited ("coins" below are rupee values; the app shows them
// as coins via coins.js, 3 coins = Rs 1). Bigger packs give bonus value.
const PACKS = [
  { id: 'p100', pay: 100, coins: 100, tag: '' },
  { id: 'p200', pay: 200, coins: 220, tag: '' },
  { id: 'p500', pay: 500, coins: 560, tag: 'Popular' },
  { id: 'p1000', pay: 1000, coins: 1200, tag: 'Best value' },
];

// First recharge: a user's very first paid top-up gets free coins on top.
// Bonus = 100% of the pack price (double coins), up to 200 free coins. Change these two numbers to adjust the offer.
const FIRST_BONUS_PCT = 100;
const FIRST_BONUS_MAX = 200;
const firstBonusFor = (pay) => Math.min(FIRST_BONUS_MAX, Math.floor((pay * FIRST_BONUS_PCT) / 100));
async function isFirstRecharge(accountId) {
  const { rows } = await pool.query(`SELECT 1 FROM topup_orders WHERE account_id=$1 AND status='paid' LIMIT 1`, [accountId]);
  return !rows[0];
}

// Call saver: a cheaper top-up offered only while the user is on a paid call (shown when the 2-minute alert fires).
const SAVER = { id: 'saver', pay: 99, coins: 125, tag: '⚡ Call saver offer: keep talking', offer: true };
// VIP plan: one payment = coins + 30 days of cheaper calls (₹8 a minute instead of ₹10) + a VIP badge hosts can see
const VIP = { id: 'vip30', pay: 199, coins: 200, vip: true, days: 30 };
async function vipUntil(accountId) {
  const { rows } = await pool.query('SELECT vip_until FROM accounts WHERE id=$1 AND vip_until > now()', [accountId]);
  return rows[0]?.vip_until || null;
}
const vipPack = (until) => ({ ...VIP, tag: until
  ? `👑 VIP till ${new Date(until).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', timeZone: 'Asia/Kolkata' })} · renew: +30 days`
  : '👑 VIP 30 days: calls ₹8/min + VIP badge' });
async function inPaidCall(accountId) {
  const { rows } = await pool.query(`SELECT 1 FROM calls WHERE user_id=$1 AND status='active' AND NOT COALESCE(is_free,false) LIMIT 1`, [accountId]);
  return !!rows[0];
}

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
    if (Number(order.first_bonus) > 0) {
      // two orders opened before the first payment: only the first one paid keeps the bonus
      const before = await client.query(`SELECT 1 FROM topup_orders WHERE account_id=$1 AND status='paid' AND id<>$2 LIMIT 1`, [order.account_id, order.id]);
      if (before.rowCount) {
        order.amount = Number(order.amount) - Number(order.first_bonus) * 100;
        await client.query('UPDATE topup_orders SET amount=$1, first_bonus=0 WHERE id=$2', [order.amount, order.id]);
      }
    }

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
    if (order.pack_id === VIP.id) // VIP pass: 30 more days, counted from today or from the end of the current pass
      await client.query(`UPDATE accounts SET vip_until = GREATEST(COALESCE(vip_until, now()), now()) + make_interval(days => $1) WHERE id=$2`, [VIP.days, order.account_id]);
    await client.query('COMMIT');
    require('./invoice').createReceipt(order.id).catch((e) => console.error('[invoice] receipt failed:', e.message)); // invoice for the user
    // Refer and earn: whoever brought this user in is paid on their first top-up (does nothing after that)
    require('./referrals').payReferralOnTopup(order.account_id).catch((e) => console.error('[referral] payout failed:', e.message));
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
            a.display_name AS counterpart, c.billed_seconds AS seconds, NULL::text AS order_id
       FROM ledger l JOIN calls c ON c.id = l.call_id JOIN accounts a ON a.id = c.partner_id
      WHERE l.account_id = $1 AND l.type = 'call_debit'
      GROUP BY c.id, a.display_name, c.billed_seconds
     UNION ALL
     SELECT 'chat' AS kind, 'chat-' || MAX(l.id)::text, SUM(l.amount)::bigint, MAX(l.created_at), a.display_name, COUNT(*)::int, NULL::text
       FROM ledger l JOIN messages m ON l.ref = 'msg:' || m.id::text JOIN accounts a ON a.id = m.partner_id
      WHERE l.account_id = $1 AND l.type = 'chat_debit'
      GROUP BY m.partner_id, a.display_name, date_trunc('day', l.created_at)
     UNION ALL
     SELECT 'gift' AS kind, 'gift-' || l.id::text, l.amount, l.created_at, a.display_name, NULL::int, NULL::text
       FROM ledger l JOIN gifts_sent g ON l.ref = 'gift:' || g.id::text JOIN accounts a ON a.id = g.host_id
      WHERE l.account_id = $1 AND l.type = 'gift_debit'
     UNION ALL
     SELECT CASE WHEN l.ref = 'checkin' THEN 'checkin' WHEN l.ref = 'referral' THEN 'referral' ELSE l.type::text END, l.id::text, l.amount, l.created_at, NULL::text, NULL::int,
            (SELECT o.id::text FROM topup_orders o JOIN topup_invoices i ON i.order_id=o.id WHERE l.type='topup' AND o.razorpay_payment_id = l.ref)
       FROM ledger l WHERE l.account_id = $1 AND l.type IN ('topup', 'refund', 'adjustment')
     ORDER BY at DESC LIMIT ${PAGE} OFFSET $2`, [req.auth.id, page * PAGE]);
  res.json(rows.map((r) => ({ ...r, amount: Number(r.amount) })));
});

// Step 1: create a Razorpay order for the app to open checkout with
// Coin packs. On a user's first recharge every pack shows its free bonus coins (coins already include them).
router.get('/packs', requireAuth(['user']), async (req, res) => {
  const vp = vipPack(await vipUntil(req.auth.id));
  const list = (await inPaidCall(req.auth.id)) ? [SAVER, ...PACKS, vp] : [...PACKS, vp]; // on a call: the call saver comes first
  // Sent to the app in coins (3 per rupee); `value` is what the pack is worth in rupees.
  const shown = (p, bonus = 0) => ({ ...p, value: p.coins + bonus, coins: coins(p.coins + bonus), coinsPerRupee: COINS_PER_RUPEE,
    ...(bonus ? { firstBonus: coins(bonus) } : {}) });
  if (!(await isFirstRecharge(req.auth.id))) return res.json(list.map((p) => shown(p)));
  res.json(list.map((p) => {
    if (p.vip) return shown(p); // the VIP pass gets no first-recharge bonus
    const bonus = firstBonusFor(p.pay);
    return { ...shown(p, bonus), tag: `${p.offer ? '⚡ Call saver' : '🎁 First recharge offer'}: +${coins(bonus)} free coins` };
  }));
});

router.post('/topup', requireAuth(['user']), async (req, res) => {
  let pay, coins, packId = null;
  let pack = req.body.packId ? PACKS.find((p) => p.id === req.body.packId) : null;
  if (req.body.packId === SAVER.id) {
    if (!(await inPaidCall(req.auth.id))) return res.status(400).json({ error: 'The call saver offer is only available during a call' });
    pack = SAVER;
  }
  const isVipPack = req.body.packId === VIP.id;
  if (isVipPack) pack = VIP;
  if (req.body.packId && !pack) return res.status(400).json({ error: 'Choose a pack' });
  let firstBonus = 0;
  if (pack) {
    pay = pack.pay; coins = pack.coins; packId = pack.id;
    if (!isVipPack && await isFirstRecharge(req.auth.id)) { firstBonus = firstBonusFor(pay); coins += firstBonus; }
  }
  else { // older app versions send a plain amount: 1 coin per rupee
    const rupees = Number(req.body.amountRupees);
    if (!Number.isInteger(rupees) || rupees < MIN_RUPEES || rupees > MAX_RUPEES)
      return res.status(400).json({ error: `Amount must be between ₹${MIN_RUPEES} and ₹${MAX_RUPEES}` });
    pay = coins = rupees;
  }

  const amount = coins * 100; // paise credited to the wallet: always computed server-side
  const payAmount = pay * 100; // paise charged
  try {
    const order = await razorpayPost('/orders', {
      amount: payAmount, currency: 'INR',
      receipt: `tk_${Date.now()}`,
      notes: { account_id: req.auth.id, pack: packId || '' },
    });
    await pool.query(
      'INSERT INTO topup_orders (account_id, razorpay_order_id, amount, pay_amount, pack_id, first_bonus) VALUES ($1,$2,$3,$4,$5,$6)',
      [req.auth.id, order.id, amount, payAmount, packId, firstBonus]);
    res.json({ orderId: order.id, keyId: process.env.RAZORPAY_KEY_ID, amount: payAmount, currency: 'INR' });
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
