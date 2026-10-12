const fs = require('fs/promises');
const path = require('path');
const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');
const { PUBLIC: AVATAR_PUBLIC, PENDING: AVATAR_PENDING } = require('./avatars');
const { PUBLIC: INTRO_PUBLIC, PENDING: INTRO_PENDING } = require('./intros');

// Recognition levels by total minutes talked (no perks attached; change the numbers freely)
const LEVELS = [['New', 0], ['Silver', 60], ['Gold', 300], ['Platinum', 1000]];
const GSTIN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const MIN_PAYOUT = 50000; // paise; keep in sync with MIN_PAYOUT_RUPEES in payouts.js
const fail = (status, message) => Object.assign(new Error(message), { status });

// "Deletion" removes everything personal but keeps the account row, calls and ledger so the books still add up.
// The phone number is freed, so the same number can sign up again as a brand-new account.
async function deleteAccount(id, { force = false } = {}) {
  const client = await pool.connect();
  let files = [];
  let avatarFiles = [];
  try {
    await client.query('BEGIN');
    const acc = (await client.query('SELECT role, deleted_at FROM accounts WHERE id=$1 FOR UPDATE', [id])).rows[0];
    if (!acc || acc.deleted_at) throw fail(404, 'Account not found');
    if (acc.role === 'admin') throw fail(403, 'Admin accounts cannot be deleted here');

    const live = await client.query(
      `SELECT 1 FROM calls WHERE (user_id=$1 OR partner_id=$1) AND status IN ('ringing','active')`, [id]);
    if (live.rowCount) throw fail(409, 'Finish your current call first');

    const bal = Number((await client.query('SELECT balance FROM wallets WHERE account_id=$1 FOR UPDATE', [id])).rows[0]?.balance ?? 0);
    if (acc.role === 'partner' && !force) {
      const open = await client.query(`SELECT 1 FROM payouts WHERE partner_id=$1 AND status IN ('requested','processing')`, [id]);
      if (open.rowCount) throw fail(409, 'You have a withdrawal in progress. Try again once it is paid.');
      if (bal >= MIN_PAYOUT) throw fail(409, 'Withdraw your balance first, then delete your account.');
    }
    if (bal > 0) { // forfeited balance leaves the ledger too, so ledger and wallet still match
      await client.query(
        `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'adjustment',$2,'account_deleted',$3)
         ON CONFLICT (idem_key) DO NOTHING`, [id, -bal, `delete:${id}`]);
      await client.query('UPDATE wallets SET balance=0, updated_at=now() WHERE account_id=$1', [id]);
    }

    const av = (await client.query(
      'SELECT a.avatar_url, p.avatar_pending, p.intro_url, p.intro_pending FROM accounts a LEFT JOIN partner_profiles p ON p.account_id=a.id WHERE a.id=$1', [id])).rows[0];
    avatarFiles = [[AVATAR_PUBLIC, av.avatar_url], [AVATAR_PENDING, av.avatar_pending], [INTRO_PUBLIC, av.intro_url], [INTRO_PENDING, av.intro_pending]];
    await client.query(
      `UPDATE accounts SET phone='deleted:'||id::text, display_name='Deleted user', avatar_url=NULL,
              is_blocked=true, deleted_at=now(), gst_number=NULL WHERE id=$1`, [id]);
    await client.query(
      `UPDATE partner_profiles SET bio=NULL, languages='{}', is_online=false, upi_id=NULL, kyc_note=NULL, avatar_pending=NULL, avatar_status=NULL, avatar_note=NULL, intro_pending=NULL, intro_status=NULL, intro_note=NULL, intro_url=NULL, tagline=NULL WHERE account_id=$1`, [id]);
    files = (await client.query('DELETE FROM kyc_documents WHERE account_id=$1 RETURNING file_name', [id])).rows.map((r) => r.file_name);
    await client.query('DELETE FROM devices WHERE account_id=$1', [id]);
    await client.query('DELETE FROM messages WHERE user_id=$1 OR partner_id=$1', [id]);
    await client.query('UPDATE ratings SET comment=NULL WHERE user_id=$1', [id]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  await Promise.all(files.map((f) => fs.unlink(path.join(KYC_DIR, path.basename(f))).catch(() => {})));
  await Promise.all(avatarFiles.filter(([, f]) => f).map(([dir, f]) => fs.unlink(path.join(dir, path.basename(f))).catch(() => {})));
  await redis.srem('partners:online', id);
  await redis.sadd('blocked', id); // any login token still in circulation stops working immediately
}

// The signed-in person's own details (their own phone number is shown only to them)
router.get('/me', requireAuth(['user', 'partner']), async (req, res) => {
  const { rows } = await pool.query('SELECT role, display_name, phone, avatar_url, gst_number FROM accounts WHERE id=$1', [req.auth.id]);
  const a = rows[0];
  const col = a.role === 'user' ? 'user_id' : 'partner_id';
  const t = await pool.query(`SELECT COALESCE(SUM(billed_seconds), 0) AS s FROM calls WHERE ${col}=$1 AND status='ended'`, [req.auth.id]);
  const minutes = Math.floor(Number(t.rows[0].s) / 60);
  let idx = 0;
  LEVELS.forEach(([, from], i) => { if (minutes >= from) idx = i; });
  const next = LEVELS[idx + 1];
  res.json({
    role: a.role, displayName: a.display_name, phone: a.phone, avatarUrl: a.avatar_url, gstNumber: a.gst_number || '',
    supportEmail: process.env.SUPPORT_EMAIL || '',
    minutes, level: LEVELS[idx][0], nextLevel: next ? next[0] : null, nextAt: next ? next[1] : null, levelFrom: LEVELS[idx][1],
  });
});

// GST number for invoices (callers only). Empty clears it.
router.put('/gst', requireAuth(['user']), async (req, res) => {
  const g = String(req.body.gstin || '').trim().toUpperCase();
  if (g && !GSTIN.test(g)) return res.status(400).json({ error: 'That does not look like a valid 15-character GST number' });
  await pool.query('UPDATE accounts SET gst_number=$1 WHERE id=$2', [g || null, req.auth.id]);
  res.json({ gstNumber: g });
});

router.post('/delete', requireAuth(['user', 'partner']), async (req, res) => {
  if (req.body.confirm !== 'DELETE') return res.status(400).json({ error: 'Type DELETE to confirm' });
  try {
    await deleteAccount(req.auth.id);
    res.json({ ok: true });
  } catch (e) {
    if (e.status) return res.status(e.status).json({ error: e.message });
    throw e;
  }
});

module.exports = { router, deleteAccount };
