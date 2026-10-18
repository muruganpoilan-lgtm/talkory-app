const crypto = require('crypto');
const express = require('express');
const { RtcTokenBuilder, RtcRole } = require('agora-token');
const { pool, requireAuth } = require('./db');
const push = require('./push');

// Video calls that an admin starts from the web panel to any user or host. No rates, no wallet: they are free.
// Users and hosts can only answer or decline them; they cannot start one.
const RING_SECONDS = 45;
const MAX_SECONDS = 2 * 3600;
const UUID = /^[0-9a-f-]{36}$/i;
const token = (channel, uid) =>
  RtcTokenBuilder.buildTokenWithUid(process.env.AGORA_APP_ID, process.env.AGORA_APP_CERT, channel, uid, RtcRole.PUBLISHER, MAX_SECONDS, MAX_SECONDS);
const session = (c, uid) => ({ callId: c.id, appId: process.env.AGORA_APP_ID, channel: c.channel_name, token: token(c.channel_name, uid), uid });

// A ring nobody answered in time becomes "missed" the next time anyone looks at it
const expire = () => pool.query(
  `UPDATE admin_calls SET status='missed', ended_at=now() WHERE status='ringing' AND created_at < now() - ($1 || ' seconds')::interval`, [String(RING_SECONDS)]);

// ---------- Admin web panel (mounted at /admin/video-calls) ----------
const admin = express.Router();
admin.use(requireAuth(['admin']));

admin.get('/accounts', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT id, display_name, role, phone FROM accounts
      WHERE role IN ('user','partner') AND deleted_at IS NULL AND NOT is_blocked ORDER BY display_name LIMIT 500`);
  res.json(rows);
});

admin.post('/', async (req, res) => {
  const targetId = String(req.body.accountId || '');
  if (!UUID.test(targetId)) return res.status(404).json({ error: 'account not found' });
  const t = (await pool.query(`SELECT id FROM accounts WHERE id=$1 AND role IN ('user','partner') AND deleted_at IS NULL AND NOT is_blocked`, [targetId])).rows[0];
  if (!t) return res.status(404).json({ error: 'account not found' });
  await expire();
  const busy = await pool.query(`SELECT 1 FROM admin_calls WHERE target_id=$1 AND status IN ('ringing','active')`, [targetId]);
  if (busy.rowCount) return res.status(409).json({ error: 'this person is already being called' });
  const channel = `admin_${crypto.randomBytes(8).toString('hex')}`;
  const c = (await pool.query(`INSERT INTO admin_calls (admin_id, target_id, channel_name) VALUES ($1,$2,$3) RETURNING *`, [req.auth.id, targetId, channel])).rows[0];
  push.notifyAdminVideoCall(targetId).catch((e) => console.error('[push] admin-video:', e.message));
  res.json(session(c, 1));
});

admin.get('/:id', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await expire();
  const c = (await pool.query('SELECT status FROM admin_calls WHERE id=$1', [req.params.id])).rows[0];
  if (!c) return res.status(404).json({ error: 'not found' });
  res.json({ status: c.status });
});

admin.post('/:id/end', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await pool.query(`UPDATE admin_calls SET status = CASE WHEN status='ringing' THEN 'missed' ELSE 'ended' END, ended_at=now() WHERE id=$1 AND status IN ('ringing','active')`, [req.params.id]);
  res.json({ ok: true });
});

// ---------- Apps (mounted at /admin-calls): answer, decline or end only ----------
const app = express.Router();
app.use(requireAuth(['user', 'partner']));

app.get('/incoming', async (req, res) => {
  await expire();
  const { rows } = await pool.query(
    `SELECT id FROM admin_calls WHERE target_id=$1 AND status='ringing' ORDER BY created_at DESC LIMIT 1`, [req.auth.id]);
  res.json(rows[0] ? { id: rows[0].id, name: 'Talkory team' } : null);
});

app.post('/:id/accept', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await expire();
  const c = (await pool.query(
    `UPDATE admin_calls SET status='active', answered_at=now() WHERE id=$1 AND target_id=$2 AND status='ringing' RETURNING *`, [req.params.id, req.auth.id])).rows[0];
  if (!c) return res.status(409).json({ error: 'call not available' });
  res.json(session(c, 2));
});

app.post('/:id/reject', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await pool.query(`UPDATE admin_calls SET status='rejected', ended_at=now() WHERE id=$1 AND target_id=$2 AND status='ringing'`, [req.params.id, req.auth.id]);
  res.json({ ok: true });
});

app.get('/:id/status', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await expire();
  const c = (await pool.query('SELECT status FROM admin_calls WHERE id=$1 AND target_id=$2', [req.params.id, req.auth.id])).rows[0];
  if (!c) return res.status(404).json({ error: 'not found' });
  res.json({ status: c.status });
});

app.post('/:id/end', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await pool.query(`UPDATE admin_calls SET status='ended', ended_at=now() WHERE id=$1 AND target_id=$2 AND status='active'`, [req.params.id, req.auth.id]);
  res.json({ ok: true });
});

module.exports = { admin, app };
