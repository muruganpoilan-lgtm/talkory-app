const router = require('express').Router();
const path = require('path');
const { pool, redis, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');
const { requireOwner } = require('./owner'); // earnings and withdrawals: owner only
const { deleteAccount } = require('./account');
const { blockAccount, unblockAccount } = require('./moderation');
router.use(requireAuth(['admin']));

router.get('/kyc', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.created_at, p.bio, p.languages, p.rate_per_min, p.kyc,
            (SELECT MAX(ai_score)::float FROM kyc_documents d WHERE d.account_id=a.id) AS ai
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

// Change a person's display name (for example when a name is not suitable)
router.post('/accounts/:id/rename', async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (name.length < 2 || name.length > 30) return res.status(400).json({ error: 'Name must be 2 to 30 characters' });
  const me = await pool.query('SELECT role FROM accounts WHERE id=$1', [req.params.id]);
  if (!me.rows[0]) return res.status(404).json({ error: 'not found' });
  if (me.rows[0].role === 'partner') {
    const dup = await pool.query(`SELECT 1 FROM accounts WHERE role='partner' AND deleted_at IS NULL AND lower(display_name)=lower($1) AND id<>$2 LIMIT 1`, [name, req.params.id]);
    if (dup.rowCount) return res.status(400).json({ error: 'Another host already has that name' });
  }
  await pool.query('UPDATE accounts SET display_name=$1 WHERE id=$2', [name, req.params.id]);
  res.json({ ok: true });
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

router.get('/locations', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT id, display_name, role, location_lat AS lat, location_lng AS lng, location_at
       FROM accounts WHERE location_at IS NOT NULL AND deleted_at IS NULL ORDER BY location_at DESC LIMIT 200`);
  res.json(rows);
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
    `UPDATE reports SET status='resolved', resolved_at=now() WHERE id=$1 AND status='open' RETURNING reported_id, reason`,
    [req.params.id]);
  if (!r.rowCount) return res.status(409).json({ error: 'already resolved' });
  if (req.body.block) {
    const note = String(req.body.reason || '').trim().slice(0, 300);
    await blockAccount(r.rows[0].reported_id, {
      reason: `Report: ${r.rows[0].reason}${note ? ` | admin: ${note}` : ''}`,
      note: note || 'Breaking the Talkory rules, after a report from another member.',
      byAdmin: req.auth.id,
    });
  }
  res.json({ ok: true });
});

// A host's name is fixed at sign-up. This lets one host change hers once more, for a genuine mistake.
router.post('/accounts/:id/unlock-name', async (req, res) => {
  const r = await pool.query(
    `UPDATE accounts SET name_locked=false WHERE id=$1 AND role='partner' AND deleted_at IS NULL RETURNING display_name`,
    [req.params.id]);
  if (!r.rowCount) return res.status(404).json({ error: 'No such host' });
  res.json({ ok: true });
});

// ---- Blocked accounts: why each one was blocked, and putting them back
router.get('/blocked', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.phone, a.role, a.blocked_reason, a.blocked_note, a.blocked_at,
            b.display_name AS by_admin,
            (SELECT COUNT(*) FROM reports x WHERE x.reported_id=a.id) AS total_reports
       FROM accounts a LEFT JOIN accounts b ON b.id=a.blocked_by
      WHERE a.is_blocked AND a.deleted_at IS NULL AND a.role IN ('user','partner')
      ORDER BY a.blocked_at DESC NULLS LAST LIMIT 200`);
  res.json(rows.map((r) => ({ ...r, total_reports: Number(r.total_reports) })));
});

// Block by hand, with a reason. The reason is also what the person is told, so it is written for them to read.
router.post('/accounts/:id/block', async (req, res) => {
  const reason = String(req.body.reason || '').trim().slice(0, 300);
  if (reason.length < 3) return res.status(400).json({ error: 'Type why this account is being blocked' });
  const a = await blockAccount(req.params.id, { reason, note: reason, byAdmin: req.auth.id });
  if (!a) return res.status(404).json({ error: 'No such user or host' });
  res.json({ ok: true });
});

router.post('/accounts/:id/unblock', async (req, res) => {
  const a = await unblockAccount(req.params.id, req.auth.id);
  if (!a) return res.status(404).json({ error: 'This account is not blocked, or it was deleted' });
  res.json({ ok: true });
});

// Every block and unblock, newest first
router.get('/block-history', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT e.id, e.action, e.reason, e.created_at, a.display_name, a.role, b.display_name AS by_admin
       FROM block_events e JOIN accounts a ON a.id=e.account_id LEFT JOIN accounts b ON b.id=e.by_admin
      ORDER BY e.id DESC LIMIT 200`);
  res.json(rows);
});

// Users and hosts who have blocked each other, with the reason the blocker picked
router.get('/people-blocks', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT br.display_name AS blocker, br.role AS blocker_role, br.id AS blocker_id,
            bd.display_name AS blocked, bd.role AS blocked_role, bd.id AS blocked_id,
            b.reason, b.created_at
       FROM blocks b JOIN accounts br ON br.id=b.blocker_id JOIN accounts bd ON bd.id=b.blocked_id
      ORDER BY b.created_at DESC LIMIT 200`);
  res.json(rows);
});

// Undo one person-to-person block, so the two can reach each other again
router.post('/people-blocks/remove', async (req, res) => {
  const { blockerId, blockedId } = req.body || {};
  const uuid = (v) => /^[0-9a-f-]{36}$/i.test(String(v || ''));
  if (!uuid(blockerId) || !uuid(blockedId)) return res.status(400).json({ error: 'invalid' });
  const r = await pool.query('DELETE FROM blocks WHERE blocker_id=$1 AND blocked_id=$2', [blockerId, blockedId]);
  if (!r.rowCount) return res.status(404).json({ error: 'That block is already gone' });
  res.json({ ok: true });
});

// ---- Talkory's own earnings: what is left of every call and chat payment after the host is paid (caller pays 10, host 6 -> 4).
// Free-call earnings (host paid, caller pays nothing) count against it. Admin takes it out to a UPI ID with "Withdraw".
const UPI_RE = /^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,32}$/;
async function earningsNumbers(q) {
  // calls = what Talkory keeps from paid calls; free = what Talkory paid hosts for free calls (the caller paid nothing), so it is <= 0
  const r = (await q.query(
    `SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.type IN ('call_debit','call_earning') AND NOT COALESCE(c.is_free, false)), 0)::bigint AS calls,
            COALESCE(-SUM(l.amount) FILTER (WHERE l.type = 'call_earning' AND COALESCE(c.is_free, false)), 0)::bigint AS free,
            COALESCE(-SUM(l.amount) FILTER (WHERE l.type IN ('chat_debit','chat_earning','gift_debit','gift_earning')), 0)::bigint AS chats,
            COALESCE(-SUM(l.amount) FILTER (WHERE l.created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'), 0)::bigint AS today,
            COALESCE(-SUM(l.amount) FILTER (WHERE l.created_at >= date_trunc('month', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'), 0)::bigint AS month
       FROM ledger l LEFT JOIN calls c ON c.id = l.call_id
      WHERE l.type IN ('call_debit','call_earning','chat_debit','chat_earning','gift_debit','gift_earning')`)).rows[0];
  const w = (await q.query('SELECT COALESCE(SUM(amount),0)::bigint AS n FROM admin_withdrawals')).rows[0].n;
  return { calls: Number(r.calls), free: Number(r.free), chats: Number(r.chats), today: Number(r.today), month: Number(r.month), withdrawn: Number(w) };
}
const availableOf = (n) => Math.max(0, n.calls + n.free + n.chats - n.withdrawn); // never shown below zero

// Phone numbers, users and hosts kept apart. Owner only: it is the whole contact list.
router.get('/phones', requireOwner, async (req, res) => {
  const role = req.query.role === 'partner' ? 'partner' : 'user';
  const { rows } = await pool.query(
    `SELECT id, display_name, phone, created_at, is_blocked
       FROM accounts WHERE role=$1 AND deleted_at IS NULL
      ORDER BY created_at DESC LIMIT 5000`, [role]);
  res.json(rows);
});

// One summary row first, then the withdrawals already taken.
router.get('/earnings', requireOwner, async (req, res) => {
  const n = await earningsNumbers(pool);
  const last = (await pool.query('SELECT upi_id, upi_app FROM admin_withdrawals ORDER BY id DESC LIMIT 1')).rows[0];
  const past = (await pool.query('SELECT id, amount, upi_id, upi_app, created_at FROM admin_withdrawals ORDER BY id DESC LIMIT 50')).rows;
  res.json([
    { kind: 'summary', id: 'summary', ...n, available: availableOf(n), upi_id: last ? last.upi_id : '', upi_app: last ? last.upi_app : null },
    ...past.map((p) => ({ kind: 'withdrawal', ...p, amount: Number(p.amount) })),
  ]);
});

router.post('/earnings/withdraw', requireOwner, async (req, res) => {
  const upi = String(req.body.upiId || '').trim();
  const upiApp = ['gpay', 'phonepe'].includes(req.body.upiApp) ? req.body.upiApp : null;
  if (!UPI_RE.test(upi)) return res.status(400).json({ error: 'Enter a valid UPI ID, like name@bank' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(7001)'); // two taps at once cannot take the same money twice
    const n = await earningsNumbers(client);
    const available = availableOf(n);
    if (available < 100) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Less than ₹1 available to withdraw' }); }
    await client.query('INSERT INTO admin_withdrawals (admin_id, amount, upi_id, upi_app) VALUES ($1,$2,$3,$4)', [req.auth.id, available, upi, upiApp]);
    await client.query('COMMIT');
    res.json({ ok: true, amount: available });
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
});

module.exports = router;
