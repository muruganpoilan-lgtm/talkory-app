const express = require('express');
const { pool, redis, requireAuth } = require('./db');

// App health: the apps report how each call went (time to connect, why it ended, network quality, phone model)
// and any crash. The admin panel shows the summary (Call quality and App crashes tabs).
const router = express.Router();
router.use(requireAuth(['user', 'partner']));

const REASONS = ['hung_up', 'other_left', 'network', 'balance', 'declined', 'no_answer', 'free_ended', 'ended', 'mic_denied', 'error'];
const str = (v, n) => (v == null ? null : String(v).slice(0, n));
const int = (v, max) => (Number.isFinite(Number(v)) ? Math.max(0, Math.min(max, Math.round(Number(v)))) : null);

// at most 60 reports an hour per account, so a broken phone can't flood the database
async function allowed(id) {
  const k = `reports:rate:${id}`;
  const n = await redis.incr(k);
  if (n === 1) await redis.expire(k, 3600);
  return n <= 60;
}

router.post('/call', async (req, res) => {
  if (!(await allowed(req.auth.id))) return res.json({ ok: true });
  const b = req.body || {};
  const callId = /^[0-9a-f-]{36}$/i.test(String(b.callId || '')) ? b.callId : null;
  const q = Number(b.netQuality);
  await pool.query(
    `INSERT INTO call_reports (call_id, account_id, role, connect_ms, duration_s, end_reason, net_quality, device, os)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [callId, req.auth.id, req.auth.role, int(b.connectMs, 600000), int(b.durationS, 86400),
      REASONS.includes(b.endReason) ? b.endReason : 'ended', q >= 0 && q <= 6 ? q : null, str(b.device, 80), str(b.os, 60)]);
  res.json({ ok: true });
});

router.post('/crash', async (req, res) => {
  if (!(await allowed(req.auth.id))) return res.json({ ok: true });
  const b = req.body || {};
  await pool.query('INSERT INTO app_crashes (account_id, role, error, stack, device, os) VALUES ($1,$2,$3,$4,$5,$6)',
    [req.auth.id, req.auth.role, str(b.error, 500), str(b.stack, 4000), str(b.device, 80), str(b.os, 60)]);
  res.json({ ok: true });
});

// ---- admin panel
const admin = express.Router();
admin.use(requireAuth(['admin']));

// One summary row for the last 7 days, then one row per phone model (worst first)
admin.get('/quality', async (req, res) => {
  const total = (await pool.query(
    `SELECT COUNT(*)::int AS calls,
            ROUND(AVG(connect_ms) FILTER (WHERE connect_ms IS NOT NULL AND role='partner') / 1000.0, 1) AS host_connect_s,
            ROUND(AVG(connect_ms) FILTER (WHERE connect_ms IS NOT NULL AND role='user') / 1000.0, 1) AS user_connect_s,
            ROUND(100.0 * COUNT(*) FILTER (WHERE end_reason='network') / NULLIF(COUNT(*) FILTER (WHERE connect_ms IS NOT NULL), 0), 1) AS drop_pct,
            ROUND(AVG(net_quality)::numeric, 1) AS quality
       FROM call_reports WHERE created_at > now() - interval '7 days'`)).rows[0];
  const phones = (await pool.query(
    `SELECT COALESCE(device, 'Unknown') AS device, COUNT(*)::int AS calls,
            ROUND(AVG(connect_ms) FILTER (WHERE connect_ms IS NOT NULL) / 1000.0, 1) AS connect_s,
            ROUND(100.0 * COUNT(*) FILTER (WHERE end_reason='network') / NULLIF(COUNT(*) FILTER (WHERE connect_ms IS NOT NULL), 0), 1) AS drop_pct,
            ROUND(AVG(net_quality)::numeric, 1) AS quality
       FROM call_reports WHERE created_at > now() - interval '7 days'
      GROUP BY 1 ORDER BY drop_pct DESC NULLS LAST, connect_s DESC NULLS LAST LIMIT 50`)).rows;
  res.json([{ kind: 'summary', ...total }, ...phones.map((p) => ({ kind: 'phone', ...p }))]);
});

admin.get('/crashes', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT c.id, c.role, c.error, c.stack, c.device, c.os, c.created_at, a.display_name
       FROM app_crashes c LEFT JOIN accounts a ON a.id=c.account_id ORDER BY c.created_at DESC LIMIT 100`);
  res.json(rows);
});

module.exports = { router, admin };
