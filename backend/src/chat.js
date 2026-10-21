const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const { pool, requireAuth } = require('./db');
const push = require('./push');

const MESSAGE_COST = Number(process.env.CHAT_COST_PAISE || 60); // paise = 0.6 coins, charged to the user for each message they send. Hosts reply free.
const HOST_EARN = Number(process.env.CHAT_HOST_EARN_PAISE || 50); // paise the host receives for each message; the rest (10 paise) stays with Talkory
const MAX_LEN = 500;
// "Best Friend" badge: shown once a user and a host have had more than this many answered calls together
const BEST_FRIEND_AFTER = Number(process.env.BEST_FRIEND_AFTER_CALLS || 5);
// Same rule as profiles: no phone numbers, handles or links, so hosts and users can't move off-platform
const LEAKS = /(\+?\d[\d\s-]{6,}\d|@|https?:|www\.)/i;

const sendLimit = rateLimit({ windowMs: 60 * 1000, limit: 30, keyGenerator: (req) => req.auth?.id || req.ip, validate: false,
  message: { error: 'You are sending too fast. Please slow down.' } });

// Who is on each side of a thread, from the caller's point of view
const sides = (req, otherId) => (req.auth.role === 'user'
  ? { userId: req.auth.id, partnerId: otherId } : { userId: otherId, partnerId: req.auth.id });

async function isBlocked(a, b) {
  return (await pool.query(
    'SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1)', [a, b])).rowCount > 0;
}

// Inbox: one row per conversation, newest first
router.get('/threads', requireAuth(['user', 'partner']), async (req, res) => {
  const mine = req.auth.role === 'user' ? 'user_id' : 'partner_id';
  const other = req.auth.role === 'user' ? 'partner_id' : 'user_id';
  const { rows } = await pool.query(
    `SELECT t.other_id AS id, a.display_name AS name, a.avatar_url, t.last_body, t.last_at, t.unread,
           (SELECT COUNT(*) FROM calls c WHERE c.${mine} = $1 AND c.${other} = t.other_id AND c.started_at IS NOT NULL) > $2 AS best_friend
       FROM (
         SELECT ${other} AS other_id,
                (ARRAY_AGG(body ORDER BY id DESC))[1] AS last_body,
                MAX(created_at) AS last_at,
                COUNT(*) FILTER (WHERE sender_id <> $1 AND read_at IS NULL)::int AS unread
           FROM messages WHERE ${mine} = $1 GROUP BY ${other}
       ) t JOIN accounts a ON a.id = t.other_id
      WHERE NOT a.is_blocked
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=t.other_id) OR (b.blocker_id=t.other_id AND b.blocked_id=$1))
      ORDER BY t.last_at DESC LIMIT 100`, [req.auth.id, BEST_FRIEND_AFTER]);
  // a user's photo is private to them; hosts only ever see an initial
  res.json(rows.map((r) => ({ ...r, avatar_url: req.auth.role === 'user' ? r.avatar_url : null })));
});

router.get('/unread', requireAuth(['user', 'partner']), async (req, res) => {
  const mine = req.auth.role === 'user' ? 'user_id' : 'partner_id';
  const r = await pool.query(`SELECT COUNT(*)::int AS n FROM messages WHERE ${mine}=$1 AND sender_id<>$1 AND read_at IS NULL`, [req.auth.id]);
  res.json({ unread: r.rows[0].n });
});

// Is this person a "Best Friend"? (more than BEST_FRIEND_AFTER answered calls between this user and host)
router.get('/:otherId/info', requireAuth(['user', 'partner']), async (req, res) => {
  if (!/^[0-9a-f-]{36}$/i.test(req.params.otherId)) return res.status(404).json({ error: 'not found' });
  const { userId, partnerId } = sides(req, req.params.otherId);
  const n = (await pool.query('SELECT COUNT(*)::int AS n FROM calls WHERE user_id=$1 AND partner_id=$2 AND started_at IS NOT NULL', [userId, partnerId])).rows[0].n;
  res.json({ bestFriend: n > BEST_FRIEND_AFTER, calls: n });
});

// Messages in a thread. ?after=<id> returns only newer ones (polling). Opening a thread marks theirs as read.
router.get('/:otherId/messages', requireAuth(['user', 'partner']), async (req, res) => {
  const { userId, partnerId } = sides(req, req.params.otherId);
  const after = parseInt(req.query.after, 10) || 0;
  await pool.query(
    'UPDATE messages SET read_at=now() WHERE user_id=$1 AND partner_id=$2 AND sender_id<>$3 AND read_at IS NULL', [userId, partnerId, req.auth.id]);
  const { rows } = await pool.query(
    `SELECT id, body, created_at, (sender_id = $3) AS mine FROM messages
      WHERE user_id=$1 AND partner_id=$2 AND id > $4 ORDER BY id DESC LIMIT 100`, [userId, partnerId, req.auth.id, after]);
  res.json(rows.reverse());
});

router.post('/:otherId', requireAuth(['user', 'partner']), sendLimit, async (req, res) => {
  const body = String(req.body.body || '').trim();
  if (!body) return res.status(400).json({ error: 'Type a message' });
  if (body.length > MAX_LEN) return res.status(400).json({ error: `Messages can be up to ${MAX_LEN} characters` });
  if (LEAKS.test(body)) return res.status(400).json({ error: 'Phone numbers, links and handles are not allowed in chat' });

  if (req.auth.role === 'user' && !(await require('./useragreement').isSigned(req.auth.id))) return res.status(403).json({ error: 'Please sign the user agreement first.', code: 'agreement_required' });
  const { userId, partnerId } = sides(req, req.params.otherId);
  const target = (await pool.query(
    `SELECT a.id, a.role, a.is_blocked, a.display_name, p.kyc FROM accounts a LEFT JOIN partner_profiles p ON p.account_id=a.id WHERE a.id=$1`,
    [req.params.otherId])).rows[0];
  const wantedRole = req.auth.role === 'user' ? 'partner' : 'user';
  if (!target || target.role !== wantedRole || target.is_blocked) return res.status(404).json({ error: 'Not found' });
  if (await isBlocked(req.auth.id, target.id)) return res.status(403).json({ error: 'You cannot message this person' });

  if (req.auth.role === 'partner') {
    // hosts can reply to users who wrote to them, but not start conversations
    const started = await pool.query('SELECT 1 FROM messages WHERE user_id=$1 AND partner_id=$2 AND sender_id=$1 LIMIT 1', [userId, partnerId]);
    if (!started.rowCount) return res.status(403).json({ error: 'You can reply once this user messages you' });
  } else if (target.kyc !== 'approved') {
    return res.status(404).json({ error: 'Not found' });
  }

  const client = await pool.connect();
  let msg;
  try {
    await client.query('BEGIN');
    msg = (await client.query(
      'INSERT INTO messages (user_id, partner_id, sender_id, body) VALUES ($1,$2,$3,$4) RETURNING id, body, created_at',
      [userId, partnerId, req.auth.id, body])).rows[0];
    if (req.auth.role === 'user') {
      const debit = await client.query('UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2 AND balance >= $1', [MESSAGE_COST, req.auth.id]);
      if (!debit.rowCount) { await client.query('ROLLBACK'); return res.status(402).json({ error: 'Not enough coins. Add coins to keep chatting.' }); }
      const share = Math.min(HOST_EARN, MESSAGE_COST);
      await client.query(`INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'chat_debit',$2,$3,$4)`,
        [req.auth.id, -MESSAGE_COST, `msg:${msg.id}`, `chat:${msg.id}:debit`]);
      await client.query(`INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'chat_earning',$2,$3,$4)`,
        [partnerId, share, `msg:${msg.id}`, `chat:${msg.id}:earn`]);
      await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [share, partnerId]);
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }

  const senderName = req.auth.role === 'user' ? (await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0].display_name : target.display_name;
  push.notifyMessage(target.id, req.auth.role === 'user' ? senderName : (await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0].display_name).catch(() => {});
  const balance = req.auth.role === 'user' ? Number((await pool.query('SELECT balance FROM wallets WHERE account_id=$1', [req.auth.id])).rows[0].balance) : null;
  res.json({ id: msg.id, body: msg.body, created_at: msg.created_at, mine: true, balance });
});

// Report a conversation (messages stay available to admins) and optionally block
router.post('/:otherId/report', requireAuth(['user', 'partner']), async (req, res) => {
  const reason = String(req.body.reason || '').trim().slice(0, 500);
  if (!reason) return res.status(400).json({ error: 'Tell us what happened' });
  await pool.query('INSERT INTO reports (reporter_id, reported_id, reason) VALUES ($1,$2,$3)', [req.auth.id, req.params.otherId, `[chat] ${reason}`]);
  res.json({ ok: true });
});

router.post('/:otherId/block', requireAuth(['user', 'partner']), async (req, res) => {
  if (req.params.otherId === req.auth.id) return res.status(400).json({ error: 'invalid' });
  await pool.query('INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [req.auth.id, req.params.otherId]);
  res.json({ ok: true });
});

module.exports = { router, MESSAGE_COST };
