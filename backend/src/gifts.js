const router = require('express').Router();
const { coins } = require('./coins');
const rateLimit = require('express-rate-limit');
const { pool, requireAuth } = require('./db');
const push = require('./push');

// What the host earns from a gift, as a percentage of its price (calls pay the host 60%). The rest stays with Talkory.
const HOST_PERCENT = Number(process.env.GIFT_HOST_PERCENT || 60);

// The gift shop. Prices here are in rupees (the app shows them as coins: 3 coins = Rs 1, see coins.js). Change the list here; the apps read it from the server.
const GIFTS = [
  { key: 'rose',      emoji: '🌹', name: 'Rose',           coins: 12 },
  { key: 'missyou',   emoji: '💌', name: 'Miss You',       coins: 12 },
  { key: 'hug',       emoji: '🤗', name: 'Hug',            coins: 12 },
  { key: 'chocolate', emoji: '🍫', name: 'Chocolates',     coins: 30 },
  { key: 'flowers',   emoji: '💐', name: 'Flowers',        coins: 30 },
  { key: 'birthday',  emoji: '🎂', name: 'Happy Birthday', coins: 60 },
  { key: 'teddy',     emoji: '🧸', name: 'Teddy Bear',     coins: 60 },
  { key: 'giftbox',   emoji: '🎁', name: 'Surprise Box',   coins: 120 },
  { key: 'crown',     emoji: '👑', name: 'Crown',          coins: 120 },
];

const sendLimit = rateLimit({ windowMs: 60 * 1000, limit: 20, keyGenerator: (req) => req.auth?.id || req.ip, validate: false,
  message: { error: 'You are sending gifts too fast. Please slow down.' } });

router.get('/', requireAuth(['user', 'partner']), (req, res) => {
  res.json(GIFTS.map((g) => ({ ...g, rupees: g.coins, coins: coins(g.coins), hostCoins: coins((g.coins * HOST_PERCENT) / 100) })));
});

// A user sends a gift to a host, from the chat (hostId) or during a call (callId)
router.post('/send', requireAuth(['user']), sendLimit, async (req, res) => {
  const gift = GIFTS.find((g) => g.key === req.body.giftKey);
  if (!gift) return res.status(400).json({ error: 'Choose a gift' });
  const price = gift.coins * 100;
  const share = Math.floor((price * HOST_PERCENT) / 100);

  let hostId = String(req.body.hostId || '');
  let callId = null;
  if (req.body.callId) {
    const c = (await pool.query(
      `SELECT id, partner_id FROM calls WHERE id=$1 AND user_id=$2 AND status IN ('ringing','active')`,
      [req.body.callId, req.auth.id])).rows[0];
    if (!c) return res.status(404).json({ error: 'This call is not active' });
    hostId = c.partner_id;
    callId = c.id;
  }
  if (!/^[0-9a-f-]{36}$/i.test(hostId)) return res.status(400).json({ error: 'Choose a host' });

  const host = (await pool.query(
    `SELECT a.id, a.display_name, a.is_blocked, p.kyc FROM accounts a JOIN partner_profiles p ON p.account_id=a.id
      WHERE a.id=$1 AND a.role='partner' AND a.deleted_at IS NULL`, [hostId])).rows[0];
  if (!host || host.is_blocked || host.kyc !== 'approved') return res.status(404).json({ error: 'Not found' });
  const blocked = await pool.query(
    'SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1)', [req.auth.id, hostId]);
  if (blocked.rowCount) return res.status(403).json({ error: 'You cannot send a gift to this person' });

  const client = await pool.connect();
  let msg, balance;
  try {
    await client.query('BEGIN');
    const debit = await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2 AND balance >= $1 RETURNING balance', [price, req.auth.id]);
    if (!debit.rowCount) { await client.query('ROLLBACK'); return res.status(402).json({ error: 'Not enough coins for this gift. Add coins first.' }); }
    balance = Number(debit.rows[0].balance);
    const g = (await client.query(
      `INSERT INTO gifts_sent (sender_id, host_id, gift_key, price, host_share, call_id) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
      [req.auth.id, hostId, gift.key, price, share, callId])).rows[0];
    msg = (await client.query(
      'INSERT INTO messages (user_id, partner_id, sender_id, body, gift_key) VALUES ($1,$2,$1,$3,$4) RETURNING id, body, created_at, gift_key',
      [req.auth.id, hostId, `${gift.emoji} ${gift.name}`, gift.key])).rows[0];
    await client.query('UPDATE gifts_sent SET message_id=$1 WHERE id=$2', [msg.id, g.id]);
    await client.query(`INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'gift_debit',$2,$3,$4)`,
      [req.auth.id, -price, `gift:${g.id}`, `gift:${g.id}:debit`]);
    await client.query(`INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'gift_earning',$2,$3,$4)`,
      [hostId, share, `gift:${g.id}`, `gift:${g.id}:earn`]);
    await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [share, hostId]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }

  const me = (await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0];
  push.notifyGift(hostId, me.display_name, `${gift.emoji} ${gift.name}`).catch(() => {});
  res.json({ ok: true, balance, gift: { key: gift.key, emoji: gift.emoji, name: gift.name, coins: coins(gift.coins) },
             message: { id: msg.id, body: msg.body, created_at: msg.created_at, gift_key: msg.gift_key, mine: true } });
});

module.exports = { router, GIFTS };
