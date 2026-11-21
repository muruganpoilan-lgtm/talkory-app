const { pool, redis } = require('./db');

const TICK_SECONDS = 15;
const FREE_SECONDS = 120; // keep equal to freecall.js

// Fixed pricing for every call: the caller pays CALL_RATE_PAISE per minute, the host earns CALL_HOST_PAISE per minute,
// Talkory keeps the difference (1000 / 600 / 400 paise = Rs 10 / Rs 6 / Rs 4, so 10 minutes = 100 coins). Charged exactly per minute, even though billing runs every 15 seconds.
const CALL_RATE = Number(process.env.CALL_RATE_PAISE || 1000);
const CALL_HOST = Number(process.env.CALL_HOST_PAISE || 600);
const upTo = (perMin, tickNo) => Math.ceil((perMin * TICK_SECONDS * tickNo) / 60); // total owed after this many ticks

// A busy host: from their 4th answered call of the day (India time, calls from anyone), the host earns a flat Rs 3 per minute
// instead of their normal cut (never more than the caller pays for that call). The caller still pays the normal rate.
// Both numbers can be changed in .env.
const REPEAT_AFTER = Number(process.env.REPEAT_CALLER_AFTER || 3);
const REPEAT_RUPEES_PER_MIN = Number(process.env.REPEAT_CALLER_RUPEES_PER_MIN || 3);
async function isRepeatCall(call) {
  const key = `call:repeat:${call.id}`;
  const cached = await redis.get(key);
  if (cached !== null) return cached === '1';
  const { rows } = await pool.query(
    `SELECT COUNT(*)::int AS n FROM calls
      WHERE partner_id=$1 AND started_at IS NOT NULL AND started_at <= $2
        AND (started_at AT TIME ZONE 'Asia/Kolkata')::date = ($2::timestamptz AT TIME ZONE 'Asia/Kolkata')::date`,
    [call.partner_id, call.started_at]);
  const repeat = rows[0].n > REPEAT_AFTER;
  await redis.set(key, repeat ? '1' : '0', 'EX', 5 * 3600);
  return repeat;
}

// Bills one tick. Returns false if the user can't pay (call must end).
async function billTick(call, tickNo) {
  const amount = upTo(CALL_RATE, tickNo) - upTo(CALL_RATE, tickNo - 1);
  const share = Math.min(amount, upTo(CALL_HOST, tickNo) - upTo(CALL_HOST, tickNo - 1));

  if (call.is_free && tickNo * TICK_SECONDS > FREE_SECONDS) return false; // free minutes are used up: end the call

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (call.is_free) { // user pays nothing, the host is still paid
      const earn = await client.query(
        `INSERT INTO ledger (account_id, type, amount, call_id, idem_key) VALUES ($1,'call_earning',$2,$3,$4)
         ON CONFLICT (idem_key) DO NOTHING RETURNING id`,
        [call.partner_id, share, call.id, `call:${call.id}:earn:${tickNo}`]);
      if (!earn.rowCount) { await client.query('ROLLBACK'); return true; }
      await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [share, call.partner_id]);
      await client.query('UPDATE calls SET billed_seconds = billed_seconds + $1 WHERE id=$2', [TICK_SECONDS, call.id]);
      await client.query('COMMIT');
      return true;
    }
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
