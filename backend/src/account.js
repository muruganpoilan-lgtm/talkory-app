const fs = require('fs/promises');
const path = require('path');
const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');
const { PUBLIC: AVATAR_PUBLIC, PENDING: AVATAR_PENDING } = require('./avatars');

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
      'SELECT a.avatar_url, p.avatar_pending FROM accounts a LEFT JOIN partner_profiles p ON p.account_id=a.id WHERE a.id=$1', [id])).rows[0];
    avatarFiles = [[AVATAR_PUBLIC, av.avatar_url], [AVATAR_PENDING, av.avatar_pending]];
    await client.query(
      `UPDATE accounts SET phone='deleted:'||id::text, display_name='Deleted user', avatar_url=NULL,
              is_blocked=true, deleted_at=now() WHERE id=$1`, [id]);
    await client.query(
      `UPDATE partner_profiles SET bio=NULL, languages='{}', is_online=false, upi_id=NULL, kyc_note=NULL, avatar_pending=NULL, avatar_status=NULL, avatar_note=NULL WHERE account_id=$1`, [id]);
    files = (await client.query('DELETE FROM kyc_documents WHERE account_id=$1 RETURNING file_name', [id])).rows.map((r) => r.file_name);
    await client.query('DELETE FROM devices WHERE account_id=$1', [id]);
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
