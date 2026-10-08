const router = require('express').Router();
const path = require('path');
const { pool, redis, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');
const { deleteAccount } = require('./account');
router.use(requireAuth(['admin']));

router.get('/kyc', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.created_at, p.bio, p.languages, p.rate_per_min, p.kyc
       FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.kyc=$1 AND ($1 <> 'pending' OR p.kyc_submitted_at IS NOT NULL)
      ORDER BY p.kyc_submitted_at NULLS LAST, a.created_at LIMIT 100`, [req.query.status || 'pending']);
  res.json(rows);
});

router.post('/kyc/:id', async (req, res) => {
  const { status } = req.body;
  if (!['approved', 'rejected'].includes(status)) return res.status(400).json({ error: 'invalid status' });
  const note = String(req.body.note || '').trim().slice(0, 200);
  if (status === 'rejected' && !note) return res.status(400).json({ error: 'Add a reason the partner will see' });
  await pool.query('UPDATE partner_profiles SET kyc=$1, kyc_note=$3 WHERE account_id=$2',
    [status, req.params.id, status === 'rejected' ? note : null]);
  if (status === 'rejected') {
    await pool.query('UPDATE partner_profiles SET is_online=false WHERE account_id=$1', [req.params.id]);
    await redis.srem('partners:online', req.params.id);
  }
  res.json({ ok: true });
});

router.get('/kyc/:id/document/:kind', async (req, res) => {
  const { rows } = await pool.query('SELECT file_name FROM kyc_documents WHERE account_id=$1 AND kind=$2', [req.params.id, req.params.kind]);
  if (!rows[0]) return res.status(404).json({ error: 'document not found' });
  res.sendFile(path.join(KYC_DIR, path.basename(rows[0].file_name)),
    { cacheControl: false, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
});

// For deletion requests that arrive by email/web form. Verify the requester owns the number first.
router.post('/accounts/:id/delete', async (req, res) => {
  try {
    await deleteAccount(req.params.id, { force: true });
    res.json({ ok: true });
  } catch (e) {
    if (e.status) return res.status(e.status).json({ error: e.message });
    throw e;
  }
});

router.get('/reports', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT r.id, r.reason, r.call_id, r.created_at, r.status, rep.display_name AS reporter,
            rd.display_name AS reported, rd.id AS reported_id, rd.role AS reported_role, rd.is_blocked,
            (SELECT COUNT(*) FROM reports x WHERE x.reported_id=r.reported_id) AS total_reports
       FROM reports r JOIN accounts rep ON rep.id=r.reporter_id JOIN accounts rd ON rd.id=r.reported_id
      WHERE r.status=$1 ORDER BY r.created_at DESC LIMIT 100`, [req.query.status || 'open']);
  res.json(rows.map((r) => ({ ...r, total_reports: Number(r.total_reports) })));
});

// Resolve a report; optionally block the reported account (also takes a partner offline)
router.post('/reports/:id/resolve', async (req, res) => {
  const r = await pool.query(
    `UPDATE reports SET status='resolved', resolved_at=now() WHERE id=$1 AND status='open' RETURNING reported_id`,
    [req.params.id]);
  if (!r.rowCount) return res.status(409).json({ error: 'already resolved' });
  if (req.body.block) {
    const id = r.rows[0].reported_id;
    await pool.query('UPDATE accounts SET is_blocked=true WHERE id=$1', [id]);
    await redis.sadd('blocked', id);
    await pool.query('UPDATE partner_profiles SET is_online=false WHERE account_id=$1', [id]);
    await redis.srem('partners:online', id);
  }
  res.json({ ok: true });
});

module.exports = router;
