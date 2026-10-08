const { pool } = require('./db');

const TICK_SECONDS = 15;

// Bills one tick. Returns false if the user can't pay (call must end).
async function billTick(call, tickNo) {
  const amount = Math.ceil((call.rate_per_min * TICK_SECONDS) / 60);
  const { rows } = await pool.query('SELECT payout_share FROM partner_profiles WHERE account_id=$1', [call.partner_id]);
  const share = Math.floor(amount * Number(rows[0].payout_share));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Idempotent: a retried tick hits the unique idem_key and is skipped
    const ins = await client.query(
      `INSERT INTO ledger (account_id, type, amount, call_id, idem_key)
       VALUES ($1,'call_debit',$2,$3,$4) ON CONFLICT (idem_key) DO NOTHING RETURNING id`,
      [call.user_id, -amount, call.id, `call:${call.id}:debit:${tickNo}`]);
    if (!ins.rowCount) { await client.query('ROLLBACK'); return true; }

    const debit = await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2 AND balance >= $1',
      [amount, call.user_id]);
    if (!debit.rowCount) { await client.query('ROLLBACK'); return false; }

    await client.query(
      `INSERT INTO ledger (account_id, type, amount, call_id, idem_key) VALUES ($1,'call_earning',$2,$3,$4)`,
      [call.partner_id, share, call.id, `call:${call.id}:earn:${tickNo}`]);
    await client.query(
      'UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2',
      [share, call.partner_id]);
    await client.query('UPDATE calls SET billed_seconds = billed_seconds + $1 WHERE id=$2', [TICK_SECONDS, call.id]);
    await client.query('COMMIT');
    return true;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

module.exports = { billTick, TICK_SECONDS };
