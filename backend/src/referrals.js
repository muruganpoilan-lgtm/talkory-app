const router = require('express').Router();
const { coins: toCoins } = require('./coins');
const { pool, requireAuth } = require('./db');
const push = require('./push');

// ---- Refer and earn
// The friend gets FRIEND_COINS the moment they use a code. The person who shared it gets
// REFERRER_COINS only when that friend first puts money in, so fake sign-ups earn nothing.
// Change these two numbers to adjust the offer.
const REFERRER_COINS = 25;
const FRIEND_COINS = 25;
const MAX_REFERRALS = 100; // how many friends one person can be paid for
const JOIN_WINDOW_DAYS = 7; // a code can only be used in the first week after signing up

// No 0/O or 1/I: codes get read out loud and typed by hand.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const randomCode = () => Array.from({ length: 6 }, () => ALPHABET[Math.floor(Math.random() * ALPHABET.length)]).join('');

/// The person's own code, made the first time they ask for it.
async function codeFor(accountId) {
  const have = await pool.query('SELECT referral_code FROM accounts WHERE id=$1', [accountId]);
  if (have.rows[0] && have.rows[0].referral_code) return have.rows[0].referral_code;
  for (let i = 0; i < 10; i++) {
    try {
      const r = await pool.query(
        'UPDATE accounts SET referral_code=$1 WHERE id=$2 AND referral_code IS NULL RETURNING referral_code',
        [randomCode(), accountId]);
      if (r.rows[0]) return r.rows[0].referral_code;
      // someone set it in between: read it back
      const again = await pool.query('SELECT referral_code FROM accounts WHERE id=$1', [accountId]);
      if (again.rows[0] && again.rows[0].referral_code) return again.rows[0].referral_code;
    } catch (e) {
      if (e.code !== '23505') throw e; // 23505 = that code is taken, try another
    }
  }
  throw new Error('could not make a referral code');
}

/// Adds coins to a wallet once and once only, whatever happens to the request.
async function credit(client, accountId, coins, idemKey) {
  const amount = coins * 100; // wallet is in paise; these amounts are rupees (shown to users x3 as coins)
  const ins = await client.query(
    `INSERT INTO ledger (account_id, type, amount, ref, idem_key)
     VALUES ($1,'adjustment',$2,'referral',$3) ON CONFLICT (idem_key) DO NOTHING`,
    [accountId, amount, idemKey]);
  if (ins.rowCount) {
    await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [amount, accountId]);
  }
  return ins.rowCount > 0;
}

/// Called after a paid top-up. Pays the person who referred this user, the first time only.
async function payReferralOnTopup(accountId) {
  const r = await pool.query('SELECT id, referrer_id FROM referrals WHERE friend_id=$1 AND paid_at IS NULL', [accountId]);
  const ref = r.rows[0];
  if (!ref) return;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Lock the row so two payments arriving together can only pay once.
    const lock = await client.query('SELECT id FROM referrals WHERE id=$1 AND paid_at IS NULL FOR UPDATE', [ref.id]);
    if (!lock.rows[0]) { await client.query('ROLLBACK'); return; }
    await credit(client, ref.referrer_id, REFERRER_COINS, `referral:${ref.id}`);
    await client.query('UPDATE referrals SET paid_at=now(), reward_coins=$1 WHERE id=$2', [REFERRER_COINS, ref.id]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  const who = await pool.query('SELECT display_name FROM accounts WHERE id=$1', [accountId]);
  push.notifyHostNote(ref.referrer_id, '🎉 Refer and earn',
    `${(who.rows[0] || {}).display_name || 'Your friend'} added coins, so ${toCoins(REFERRER_COINS)} coins are yours. Thank you!`).catch(() => {});
}

// What the Refer and earn screen shows.
router.get('/me', requireAuth(['user']), async (req, res) => {
  const code = await codeFor(req.auth.id);
  const mine = await pool.query(
    `SELECT r.created_at, r.paid_at, r.reward_coins, a.display_name
       FROM referrals r JOIN accounts a ON a.id=r.friend_id
      WHERE r.referrer_id=$1 ORDER BY r.created_at DESC LIMIT 50`, [req.auth.id]);
  const me = (await pool.query('SELECT created_at FROM accounts WHERE id=$1', [req.auth.id])).rows[0];
  const used = (await pool.query('SELECT 1 FROM referrals WHERE friend_id=$1', [req.auth.id])).rowCount > 0;
  const daysOld = (Date.now() - new Date(me.created_at).getTime()) / 86400000;
  res.json({
    code,
    referrerCoins: toCoins(REFERRER_COINS),
    friendCoins: toCoins(FRIEND_COINS),
    canUseCode: !used && daysOld <= JOIN_WINDOW_DAYS, // only new accounts, and only once
    joined: mine.rowCount,
    earned: toCoins(mine.rows.reduce((n, r) => n + (r.reward_coins || 0), 0)),
    friends: mine.rows.map((r) => ({
      name: r.display_name, at: r.created_at, paid: !!r.paid_at, coins: toCoins(r.reward_coins || 0),
    })),
  });
});

// A new user types a friend's code. The welcome coins land straight away.
router.post('/claim', requireAuth(['user']), async (req, res) => {
  const code = String(req.body.code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (code.length !== 6) return res.status(400).json({ error: 'That code does not look right. It is 6 letters and numbers.' });

  const me = (await pool.query('SELECT created_at, referral_code FROM accounts WHERE id=$1', [req.auth.id])).rows[0];
  if (code === me.referral_code) return res.status(400).json({ error: 'That is your own code!' });
  if ((Date.now() - new Date(me.created_at).getTime()) / 86400000 > JOIN_WINDOW_DAYS) {
    return res.status(400).json({ error: `A code can only be used in your first ${JOIN_WINDOW_DAYS} days on Talkory.` });
  }
  if ((await pool.query('SELECT 1 FROM referrals WHERE friend_id=$1', [req.auth.id])).rowCount) {
    return res.status(400).json({ error: 'You have already used a code.' });
  }

  const owner = (await pool.query(
    `SELECT id, display_name FROM accounts WHERE referral_code=$1 AND role='user' AND NOT is_blocked AND deleted_at IS NULL`,
    [code])).rows[0];
  if (!owner) return res.status(404).json({ error: 'No one has that code. Check the letters and try again.' });
  if (owner.id === req.auth.id) return res.status(400).json({ error: 'That is your own code!' });
  const n = (await pool.query('SELECT COUNT(*)::int AS n FROM referrals WHERE referrer_id=$1', [owner.id])).rows[0].n;
  if (n >= MAX_REFERRALS) return res.status(400).json({ error: 'That code has been used too many times.' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const ins = await client.query(
      `INSERT INTO referrals (referrer_id, friend_id, code, friend_coins) VALUES ($1,$2,$3,$4)
       ON CONFLICT (friend_id) DO NOTHING RETURNING id`, [owner.id, req.auth.id, code, FRIEND_COINS]);
    if (!ins.rows[0]) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'You have already used a code.' }); }
    await credit(client, req.auth.id, FRIEND_COINS, `referral_welcome:${ins.rows[0].id}`);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  push.notifyHostNote(owner.id, '👋 A friend joined',
    `Someone used your code. Once they add coins, ${toCoins(REFERRER_COINS)} coins are yours.`).catch(() => {});
  res.json({ ok: true, coins: toCoins(FRIEND_COINS), from: owner.display_name });
});

// ---- Admin: who referred whom, and what it has cost
const admin = require('express').Router();
admin.use(requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT r.created_at, r.paid_at, r.reward_coins, r.friend_coins, r.code,
            a.display_name AS referrer, a.phone AS referrer_phone,
            f.display_name AS friend, f.phone AS friend_phone
       FROM referrals r JOIN accounts a ON a.id=r.referrer_id JOIN accounts f ON f.id=r.friend_id
      ORDER BY r.created_at DESC LIMIT 200`);
  res.json(rows);
});

module.exports = { router, admin, payReferralOnTopup, REFERRER_COINS, FRIEND_COINS };
