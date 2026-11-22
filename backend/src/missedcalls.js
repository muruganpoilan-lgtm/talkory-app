const { pool } = require('./db');
const push = require('./push');

// ---- Missed call fine
// A host who lets MISS_LIMIT user calls ring out in one day pays FINE_RUPEES out of her earnings.
// Charged once a day, on the miss that reaches the limit. Change these two numbers to adjust it.
const MISS_LIMIT = 2;
const FINE_RUPEES = 10;

// Calls the host started herself never count: a user who does not answer is not her fault.
const MISSED_TODAY = `
  SELECT COUNT(*)::int AS n FROM calls
   WHERE partner_id=$1 AND status='missed' AND initiated_by <> 'partner'
     AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`;

/// Called when a user's call to this host rings out. Fines her once she passes the day's limit.
async function chargeIfNeeded(partnerId) {
  const missed = (await pool.query(MISSED_TODAY, [partnerId])).rows[0].n;
  if (missed < MISS_LIMIT) return null;

  const day = (await pool.query(`SELECT to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD') AS d`)).rows[0].d;
  const idem = `missed_penalty:${partnerId}:${day}`;
  const full = FINE_RUPEES * 100;

  const client = await pool.connect();
  let charged = 0;
  try {
    await client.query('BEGIN');
    const w = await client.query('SELECT balance FROM wallets WHERE account_id=$1 FOR UPDATE', [partnerId]);
    if (!w.rows[0]) { await client.query('ROLLBACK'); return null; }
    // Never take more than she has: a wallet must not go below zero, or payouts break.
    charged = Math.min(full, Number(w.rows[0].balance));
    if (charged <= 0) { await client.query('ROLLBACK'); return null; } // nothing to take yet; a later miss can still charge
    const ins = await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key)
       VALUES ($1,'adjustment',$2,'missed_penalty',$3) ON CONFLICT (idem_key) DO NOTHING`,
      [partnerId, -charged, idem]);
    if (!ins.rowCount) { await client.query('ROLLBACK'); return null; } // already fined today
    await client.query('UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2', [charged, partnerId]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }

  push.notifyHostNote(partnerId, '📵 Missed calls today',
    `You missed ${missed} calls from users today, so Rs ${Math.round(charged / 100)} was taken from your earnings. `
    + 'Go offline when you cannot answer: there is no charge for being offline.').catch(() => {});
  return charged;
}

// ---- Admin: every fine, newest first
const admin = require('express').Router();
admin.use(require('./db').requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT l.id, l.amount, l.created_at, a.display_name, a.phone,
            (SELECT COUNT(*)::int FROM calls c
              WHERE c.partner_id=l.account_id AND c.status='missed' AND c.initiated_by <> 'partner'
                AND c.created_at::date = l.created_at::date) AS missed
       FROM ledger l JOIN accounts a ON a.id=l.account_id
      WHERE l.ref='missed_penalty' ORDER BY l.id DESC LIMIT 200`);
  res.json(rows.map((r) => ({ ...r, amount: Number(r.amount) })));
});

module.exports = { chargeIfNeeded, admin, MISS_LIMIT, FINE_RUPEES };
