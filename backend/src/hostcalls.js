const crypto = require('crypto');
const router = require('express').Router();
const { RtcTokenBuilder, RtcRole } = require('agora-token');
const { pool, redis, requireAuth } = require('./db');
const { billTick, rateFor, isVip } = require('./billing');
const { finishCall } = require('./callctl');
const { ringTimeout, scheduleTick } = require('./queue');
const { freeStatus, hostFreeStatus, freeSecondsFor } = require('./freecall');

// A host calls a user they already chat with. Billing only begins when the user taps Accept.
// Free minutes come in two kinds: the user's own short daily one, then the host's own longer giveaway
// (once per host every 3 hours). No money moves on either: the user pays nothing and the host earns nothing.
const CALL_MAX_SECONDS = 4 * 3600;
const agoraToken = (channel, uid) =>
  RtcTokenBuilder.buildTokenWithUid(
    process.env.AGORA_APP_ID, process.env.AGORA_APP_CERT, channel, uid, RtcRole.PUBLISHER,
    CALL_MAX_SECONDS, CALL_MAX_SECONDS);

// What this call would cost: the user's own free 2 minutes if they have them, otherwise the host's
// own 3-minute giveaway if she has one left (she earns nothing for those).
router.get('/free-status', requireAuth(['partner']), async (req, res) => {
  const userId = String(req.query.userId || '');
  if (!/^[0-9a-f-]{36}$/i.test(userId)) return res.status(404).json({ error: 'not found' });
  const thread = await pool.query('SELECT 1 FROM messages WHERE user_id=$1 AND partner_id=$2 LIMIT 1', [userId, req.auth.id]);
  if (!thread.rowCount) return res.status(404).json({ error: 'not found' });
  const user = await freeStatus(userId);
  const mine = await hostFreeStatus(req.auth.id);
  res.json({
    ...user, // kept as it was, so an older app still shows the right thing
    gift: { ...mine, used: !user.available && mine.available }, // "used" = this call would spend her giveaway
  });
});

// Host starts a call
router.post('/', requireAuth(['partner']), async (req, res) => {
  const userId = String(req.body.userId || '');
  if (!/^[0-9a-f-]{36}$/i.test(userId)) return res.status(404).json({ error: 'user not found' });
  const me = (await pool.query(
    `SELECT p.rate_per_min FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.account_id=$1 AND p.kyc='approved' AND NOT a.is_blocked`, [req.auth.id])).rows[0];
  if (!me) return res.status(403).json({ error: 'your account is not approved for calls yet' });

  const user = (await pool.query(`SELECT id FROM accounts WHERE id=$1 AND role='user' AND NOT is_blocked`, [userId])).rows[0];
  if (!user) return res.status(404).json({ error: 'user not found' });

  // The host may call a user who wrote to them before, or a user who is online right now (the "Users online" list)
  const thread = await pool.query('SELECT 1 FROM messages WHERE user_id=$1 AND partner_id=$2 LIMIT 1', [userId, req.auth.id]);
  if (!thread.rowCount) {
    const seen = await redis.zscore('users:online', userId);
    if (!seen || Date.now() - Number(seen) > 75 * 1000) return res.status(403).json({ error: 'this user is not online right now' });
  }

  const blocked = await pool.query(
    'SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1)', [req.auth.id, userId]);
  if (blocked.rowCount) return res.status(403).json({ error: 'this user is unavailable' });

  const inCall = await pool.query(`SELECT 1 FROM calls WHERE user_id=$1 AND status IN ('ringing','active') LIMIT 1`, [userId]);
  if (inCall.rowCount) return res.status(409).json({ error: 'user is busy right now' });

  const vip = await isVip(userId);
  const minCost = Math.ceil((rateFor({ is_vip: vip }) * Number(process.env.MIN_CALL_SECONDS || 60)) / 60);
  // The user's own free call comes first where it is switched on (FREE_SECONDS); it is off by default,
  // so in practice the host's own giveaway is what makes a call free. Neither earns her anything.
  const userFree = (await freeStatus(userId)).available;
  const hostFree = userFree ? false : (await hostFreeStatus(req.auth.id)).available;
  const free = userFree || hostFree;
  const w = await pool.query('SELECT balance FROM wallets WHERE account_id=$1', [userId]);
  if (!free && (!w.rows[0] || Number(w.rows[0].balance) < minCost)) return res.status(402).json({ error: 'user does not have enough coins for a call' });

  // not more than one ring every 30s to the same user
  if (!(await redis.set(`hostcall:cool:${req.auth.id}:${userId}`, 1, 'EX', 30, 'NX')))
    return res.status(429).json({ error: 'please wait a little before calling again' });

  if (!(await redis.set(`partner:busy:${req.auth.id}`, userId, 'EX', CALL_MAX_SECONDS, 'NX')))
    return res.status(409).json({ error: 'you are already on a call' });

  const channel = `call_${crypto.randomBytes(8).toString('hex')}`;
  const call = (await pool.query(
    `INSERT INTO calls (user_id, partner_id, channel_name, rate_per_min, initiated_by, is_free, is_host_free, is_vip)
     VALUES ($1,$2,$3,$4,'partner',$5,$6,$7) RETURNING *`,
    [userId, req.auth.id, channel, rateFor({ is_vip: vip }), free, hostFree, vip])).rows[0];
  await ringTimeout(call.id);

  res.json({ callId: call.id, appId: process.env.AGORA_APP_ID, channel, token: agoraToken(channel, 2), uid: 2 });
});

// User polls for a host ringing them
router.get('/incoming', requireAuth(['user']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT c.id, c.is_free, c.is_host_free, a.display_name AS partner_name FROM calls c JOIN accounts a ON a.id = c.partner_id
      WHERE c.user_id=$1 AND c.status='ringing' AND c.initiated_by='partner' AND c.created_at > now() - interval '25 seconds'
      ORDER BY c.created_at DESC LIMIT 1`, [req.auth.id]);
  const c = rows[0];
  res.json(c ? { ...c, free_seconds: c.is_free ? freeSecondsFor(c) : 0 } : null);
});

// User accepts -> billing starts
router.post('/:id/accept', requireAuth(['user']), async (req, res) => {
  const { rows } = await pool.query(
    `UPDATE calls SET status='active', started_at=now()
      WHERE id=$1 AND user_id=$2 AND initiated_by='partner' AND status='ringing' RETURNING *`, [req.params.id, req.auth.id]);
  const call = rows[0];
  if (!call) return res.status(409).json({ error: 'call not available' });

  if (!(await billTick(call, 1))) {
    await finishCall(call.id, 'failed');
    return res.status(402).json({ error: 'not enough coins' });
  }
  await redis.set(`call:hb:${call.id}`, 1, 'EX', 40);
  await scheduleTick(call.id, 2);

  res.json({ callId: call.id, appId: process.env.AGORA_APP_ID, channel: call.channel_name, token: agoraToken(call.channel_name, 1), uid: 1 });
});

router.post('/:id/reject', requireAuth(['user']), async (req, res) => {
  const { rows } = await pool.query('SELECT 1 FROM calls WHERE id=$1 AND user_id=$2 AND initiated_by=$3', [req.params.id, req.auth.id, 'partner']);
  if (!rows[0]) return res.status(404).json({ error: 'not found' });
  await finishCall(req.params.id, 'rejected', ['ringing']);
  res.json({ ok: true });
});

module.exports = router;
