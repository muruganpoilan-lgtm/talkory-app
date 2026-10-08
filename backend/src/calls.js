const crypto = require('crypto');
const router = require('express').Router();
const { RtcTokenBuilder, RtcRole } = require('agora-token');
const { pool, redis, requireAuth } = require('./db');
const { billTick, TICK_SECONDS } = require('./billing');
const push = require('./push');
const { finishCall } = require('./callctl');
const { ringTimeout, scheduleTick } = require('./queue');

const CALL_MAX_SECONDS = 4 * 3600; // token + privilege lifetime, also the partner busy-lock lifetime
const agoraToken = (channel, uid) =>
  RtcTokenBuilder.buildTokenWithUid(
    process.env.AGORA_APP_ID, process.env.AGORA_APP_CERT, channel, uid, RtcRole.PUBLISHER,
    CALL_MAX_SECONDS, CALL_MAX_SECONDS); // both are durations in seconds

// User starts a call
router.post('/', requireAuth(['user']), async (req, res) => {
  const { partnerId } = req.body;
  const { rows } = await pool.query(
    `SELECT p.rate_per_min, p.is_online FROM partner_profiles p
      JOIN accounts a ON a.id=p.account_id
      WHERE p.account_id=$1 AND p.kyc='approved' AND NOT a.is_blocked`, [partnerId]);
  const p = rows[0];
  if (!p || !p.is_online) return res.status(409).json({ error: 'partner offline' });

  const blocked = await pool.query(
    'SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1)',
    [req.auth.id, partnerId]);
  if (blocked.rowCount) return res.status(403).json({ error: 'this host is unavailable' });

  const minCost = Math.ceil((p.rate_per_min * Number(process.env.MIN_CALL_SECONDS || 60)) / 60);
  const w = await pool.query('SELECT balance FROM wallets WHERE account_id=$1', [req.auth.id]);
  if (Number(w.rows[0].balance) < minCost) return res.status(402).json({ error: 'insufficient balance', required: minCost });

  // Atomic busy lock: only one call per partner
  if (!(await redis.set(`partner:busy:${partnerId}`, req.auth.id, 'EX', CALL_MAX_SECONDS, 'NX')))
    return res.status(409).json({ error: 'partner busy' });

  const channel = `call_${crypto.randomBytes(8).toString('hex')}`;
  const call = (await pool.query(
    `INSERT INTO calls (user_id, partner_id, channel_name, rate_per_min) VALUES ($1,$2,$3,$4) RETURNING *`,
    [req.auth.id, partnerId, channel, p.rate_per_min])).rows[0];

  const caller = await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id]);
  push.notifyIncomingCall(partnerId, call.id, caller.rows[0].display_name).catch(() => {});
  await ringTimeout(call.id);

  res.json({ callId: call.id, appId: process.env.AGORA_APP_ID, channel, token: agoraToken(channel, 1), uid: 1 });
});

// Partner polls for a ringing call (interim until push/WebSocket is added)
router.get('/incoming', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT c.id, a.display_name AS user_name FROM calls c JOIN accounts a ON a.id = c.user_id
      WHERE c.partner_id=$1 AND c.status='ringing' ORDER BY c.created_at DESC LIMIT 1`, [req.auth.id]);
  res.json(rows[0] || null);
});

// Partner accepts -> billing starts
router.post('/:id/accept', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query(
    `UPDATE calls SET status='active', started_at=now()
      WHERE id=$1 AND partner_id=$2 AND status='ringing' RETURNING *`, [req.params.id, req.auth.id]);
  const call = rows[0];
  if (!call) return res.status(409).json({ error: 'call not available' });

  if (!(await billTick(call, 1))) { // first 15s are charged up front
    await finishCall(call.id, 'failed');
    return res.status(402).json({ error: 'caller balance too low' });
  }
  await redis.set(`call:hb:${call.id}`, 1, 'EX', 40);
  await scheduleTick(call.id, 2); // the queue bills every following 15s

  res.json({ callId: call.id, appId: process.env.AGORA_APP_ID, channel: call.channel_name, token: agoraToken(call.channel_name, 2), uid: 2 });
});

router.post('/:id/reject', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query('SELECT 1 FROM calls WHERE id=$1 AND partner_id=$2', [req.params.id, req.auth.id]);
  if (!rows[0]) return res.status(404).json({ error: 'not found' });
  await finishCall(req.params.id, 'rejected', ['ringing']);
  res.json({ ok: true });
});

// Either side ends the call
router.post('/:id/end', requireAuth(['user', 'partner']), async (req, res) => {
  const { rows } = await pool.query(
    'SELECT 1 FROM calls WHERE id=$1 AND (user_id=$2 OR partner_id=$2)', [req.params.id, req.auth.id]);
  if (!rows[0]) return res.status(404).json({ error: 'not found' });
  const call = await finishCall(req.params.id, 'ended');
  res.json({ ok: true, billedSeconds: call?.billed_seconds ?? 0 });
});

// Polled by the call screens: is the call still live, and how long can the user keep talking?
// secondsLeft is counted in whole billing ticks, so it matches when the server will actually cut the call.
router.get('/:id/status', requireAuth(['user', 'partner']), async (req, res) => {
  const c = await callFor(req, res); if (!c) return;
  let secondsLeft = null;
  if (c.status === 'active') await redis.set(`call:hb:${c.id}`, 1, 'EX', 40);
  if (c.status === 'active' && req.auth.id === c.user_id) {
    const w = await pool.query('SELECT balance FROM wallets WHERE account_id=$1', [c.user_id]);
    const tickCost = Math.ceil((c.rate_per_min * TICK_SECONDS) / 60);
    secondsLeft = Math.floor(Number(w.rows[0].balance) / tickCost) * TICK_SECONDS;
  }
  res.json({ status: c.status, secondsLeft });
});

// ---- post-call: rating, report, block (either side may report/block; only the user rates)
const otherParty = (c, me) => (c.user_id === me ? c.partner_id : c.user_id);
async function callFor(req, res) {
  const { rows } = await pool.query(
    'SELECT * FROM calls WHERE id=$1 AND (user_id=$2 OR partner_id=$2)', [req.params.id, req.auth.id]);
  if (!rows[0]) res.status(404).json({ error: 'not found' });
  return rows[0];
}

router.post('/:id/rate', requireAuth(['user']), async (req, res) => {
  const stars = Number(req.body.stars);
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) return res.status(400).json({ error: 'stars must be 1-5' });
  const c = await callFor(req, res); if (!c) return;
  if (!c.started_at) return res.status(409).json({ error: 'call did not connect' });
  const comment = String(req.body.comment || '').trim().slice(0, 500) || null;
  const ins = await pool.query(
    'INSERT INTO ratings (call_id, user_id, partner_id, stars, comment) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (call_id) DO NOTHING',
    [c.id, c.user_id, c.partner_id, stars, comment]);
  if (ins.rowCount)
    await pool.query(
      'UPDATE partner_profiles SET rating_avg=(rating_avg*rating_count+$1)/(rating_count+1), rating_count=rating_count+1 WHERE account_id=$2',
      [stars, c.partner_id]);
  res.json({ ok: true });
});

router.post('/:id/report', requireAuth(['user', 'partner']), async (req, res) => {
  const reason = String(req.body.reason || '').trim().slice(0, 500);
  if (reason.length < 3) return res.status(400).json({ error: 'please choose a reason' });
  const c = await callFor(req, res); if (!c) return;
  const dup = await pool.query('SELECT 1 FROM reports WHERE call_id=$1 AND reporter_id=$2', [c.id, req.auth.id]);
  if (!dup.rowCount)
    await pool.query('INSERT INTO reports (reporter_id, reported_id, call_id, reason) VALUES ($1,$2,$3,$4)',
      [req.auth.id, otherParty(c, req.auth.id), c.id, reason]);
  res.json({ ok: true });
});

router.post('/:id/block', requireAuth(['user', 'partner']), async (req, res) => {
  const c = await callFor(req, res); if (!c) return;
  await pool.query('INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
    [req.auth.id, otherParty(c, req.auth.id)]);
  res.json({ ok: true });
});

module.exports = router;
