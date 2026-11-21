const crypto = require('crypto');
const express = require('express');
const { RtcTokenBuilder, RtcRole } = require('agora-token');
const { pool, requireAuth } = require('./db');
const push = require('./push');

// Group video meetings that an admin arranges (Meet now, or scheduled and started later). Free for everyone.
// Users and hosts can only join a live meeting they are invited to; they cannot create or end one.
const MAX_SECONDS = 4 * 3600;
const MAX_PEOPLE = Number(process.env.MEETING_MAX_PEOPLE || 16);
const UUID = /^[0-9a-f-]{36}$/i;
const AUDIENCES = ['everyone', 'users', 'partners', 'selected'];
const token = (channel, uid) =>
  RtcTokenBuilder.buildTokenWithUid(process.env.AGORA_APP_ID, process.env.AGORA_APP_CERT, channel, uid, RtcRole.PUBLISHER, MAX_SECONDS, MAX_SECONDS);
const session = (m, uid) => ({ callId: m.id, appId: process.env.AGORA_APP_ID, channel: m.channel_name, token: token(m.channel_name, uid), uid, title: m.title });
const randomUid = () => 1000 + crypto.randomInt(0, 2000000000);

// A meeting nobody ended is closed after the longest token life
const expire = () => pool.query(`UPDATE meetings SET status='ended', ended_at=now() WHERE status='live' AND started_at < now() - interval '4 hours'`);

// Everyone invited to this meeting (who has not blocked/deleted accounts)
const inviteesSql = `
  SELECT a.id FROM accounts a
   WHERE a.role IN ('user','partner') AND a.deleted_at IS NULL AND NOT a.is_blocked
     AND ( $1 = 'everyone' OR ($1 = 'users' AND a.role = 'user') OR ($1 = 'partners' AND a.role = 'partner')
        OR ($1 = 'selected' AND EXISTS (SELECT 1 FROM meeting_invitees i WHERE i.meeting_id = $2 AND i.account_id = a.id)) )`;

async function tellInvitees(m, scheduled) {
  const { rows } = await pool.query(inviteesSql, [m.audience, m.id]);
  const when = scheduled && m.scheduled_at
    ? new Date(m.scheduled_at).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' }) : '';
  await push.notifyMeeting(rows.map((r) => r.id), scheduled
    ? { title: 'Meeting scheduled', body: `${m.title}${when ? ' · ' + when : ''}` }
    : { title: 'Meeting started', body: `${m.title}. Open Talkory to join.` });
}

// ---------- Admin (web panel and admin app), mounted at /admin/meetings ----------
const admin = express.Router();
admin.use(requireAuth(['admin']));

admin.get('/', async (req, res) => {
  await expire();
  const { rows } = await pool.query(
    `SELECT id, title, audience, status, scheduled_at, started_at, ended_at, created_at FROM meetings
      ORDER BY (status='live') DESC, (status='scheduled') DESC, created_at DESC LIMIT 50`);
  res.json(rows);
});

admin.post('/', async (req, res) => {
  const title = String(req.body.title || '').trim().slice(0, 80);
  const audience = String(req.body.audience || '');
  if (!title) return res.status(400).json({ error: 'give the meeting a title' });
  if (!AUDIENCES.includes(audience)) return res.status(400).json({ error: 'choose who to invite' });
  let ids = [];
  if (audience === 'selected') {
    ids = (Array.isArray(req.body.accountIds) ? req.body.accountIds : []).map(String).filter((x) => UUID.test(x)).slice(0, 500);
    if (!ids.length) return res.status(400).json({ error: 'choose at least one person' });
  }
  let at = null;
  if (req.body.scheduledAt) {
    at = new Date(req.body.scheduledAt);
    if (Number.isNaN(at.getTime())) return res.status(400).json({ error: 'that date and time is not valid' });
    if (at.getTime() < Date.now() - 60000) return res.status(400).json({ error: 'pick a time in the future' });
  }
  const channel = `meet_${crypto.randomBytes(8).toString('hex')}`;
  const m = (await pool.query(
    `INSERT INTO meetings (admin_id, title, channel_name, audience, status, scheduled_at, started_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [req.auth.id, title, channel, audience, at ? 'scheduled' : 'live', at, at ? null : new Date()])).rows[0];
  for (const id of ids) await pool.query('INSERT INTO meeting_invitees (meeting_id, account_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [m.id, id]);
  tellInvitees(m, !!at).catch((e) => console.error('[push] meeting:', e.message));
  res.json(at ? { id: m.id, status: m.status } : { id: m.id, status: m.status, ...session(m, 1) });
});

admin.get('/accounts', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT id, display_name, role, phone FROM accounts
      WHERE role IN ('user','partner') AND deleted_at IS NULL AND NOT is_blocked ORDER BY display_name LIMIT 500`);
  res.json(rows);
});

// Start a scheduled meeting, or rejoin one that is already live
admin.post('/:id/join', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await expire();
  const m = (await pool.query('SELECT * FROM meetings WHERE id=$1', [req.params.id])).rows[0];
  if (!m || m.status === 'ended') return res.status(409).json({ error: 'this meeting has ended' });
  if (m.status === 'scheduled') {
    const u = (await pool.query(`UPDATE meetings SET status='live', started_at=now() WHERE id=$1 AND status='scheduled' RETURNING *`, [m.id])).rows[0];
    if (u) tellInvitees(u, false).catch((e) => console.error('[push] meeting:', e.message));
    return res.json(session(u || m, 1));
  }
  res.json(session(m, 1));
});

admin.get('/:id', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const m = (await pool.query('SELECT status FROM meetings WHERE id=$1', [req.params.id])).rows[0];
  if (!m) return res.status(404).json({ error: 'not found' });
  res.json({ status: m.status });
});

admin.post('/:id/end', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await pool.query(`UPDATE meetings SET status='ended', ended_at=now() WHERE id=$1 AND status IN ('scheduled','live')`, [req.params.id]);
  res.json({ ok: true });
});

// ---------- Apps, mounted at /meetings: see live meetings I am invited to, and join ----------
const app = express.Router();
app.use(requireAuth(['user', 'partner']));

const visibleSql = `
  m.audience = 'everyone' OR (m.audience = 'users' AND $2 = 'user') OR (m.audience = 'partners' AND $2 = 'partner')
  OR (m.audience = 'selected' AND EXISTS (SELECT 1 FROM meeting_invitees i WHERE i.meeting_id = m.id AND i.account_id = $1))`;

app.get('/live', async (req, res) => {
  await expire();
  const { rows } = await pool.query(
    `SELECT m.id, m.title FROM meetings m WHERE m.status='live' AND (${visibleSql}) ORDER BY m.started_at DESC LIMIT 5`,
    [req.auth.id, req.auth.role]);
  res.json(rows);
});

app.post('/:id/join', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  await expire();
  const m = (await pool.query(
    `SELECT m.* FROM meetings m WHERE m.id=$3 AND m.status='live' AND (${visibleSql})`, [req.auth.id, req.auth.role, req.params.id])).rows[0];
  if (!m) return res.status(409).json({ error: 'this meeting is not available' });
  res.json({ ...session(m, randomUid()), maxPeople: MAX_PEOPLE });
});

app.get('/:id/status', async (req, res) => {
  if (!UUID.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const m = (await pool.query('SELECT status FROM meetings WHERE id=$1', [req.params.id])).rows[0];
  if (!m) return res.status(404).json({ error: 'not found' });
  res.json({ status: m.status });
});

module.exports = { admin, app };
