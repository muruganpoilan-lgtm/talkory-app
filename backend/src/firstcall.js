// New-user offer for hosts: the host who makes a new user's first call earns a one-time bonus
// once that user spends money.
//
// Rules (all changeable in .env):
//   1. The user's FIRST answered call (lasting at least FIRST_CALL_MIN_SECONDS, default 60) must have been
//      MADE BY A HOST, within FIRST_CALL_NEW_USER_DAYS (default 7) of him joining. Her free 2-minute
//      giveaway call counts: it is used automatically whenever she has one, so it is usually this call.
//   2. She is paid when that user converts: his first coin top-up, or a paid call (with any host),
//      at or after her call and within FIRST_CALL_PAY_WITHIN_DAYS (default 7) of it.
//      If her call was itself a paid call, that already counts, so she is paid when it ends.
//   3. One bonus per user, ever (idem_key). Fake accounts can't farm it: a real purchase is needed.
// Checked when any call ends and after every top-up. Default bonus: Rs 50 = 150 coins at 3 coins = Rs 1.
const { pool } = require('./db');
const push = require('./push');
const { COINS_PER_RUPEE } = require('./coins');

const BONUS_PAISE = Number(process.env.FIRST_CALL_BONUS_PAISE || 5000);
const NEW_USER_DAYS = Number(process.env.FIRST_CALL_NEW_USER_DAYS || 7);
const MIN_SECONDS = Number(process.env.FIRST_CALL_MIN_SECONDS || 60);
const PAY_WITHIN_DAYS = Number(process.env.FIRST_CALL_PAY_WITHIN_DAYS || 7);
const enabled = () => BONUS_PAISE > 0;

// For the host's Users online list: joined recently and no real call yet, so the first host to call can win the bonus.
// $1 = days, $2 = minimum seconds.
const NEW_USER_SQL = `(a.created_at > now() - ($1 || ' days')::interval
   AND NOT EXISTS (SELECT 1 FROM calls c2 WHERE c2.user_id = a.id AND c2.started_at IS NOT NULL AND c2.billed_seconds >= $2::int))`;

/** Check one user and pay the host if everything is met. Safe to call any number of times. Never throws. */
async function checkUser(userId) {
  if (!enabled() || !userId) return;
  try {
    // His first real call (any direction): who made it, when, and was it a host?
    const first = (await pool.query(
      `SELECT c.id, c.partner_id, c.initiated_by, c.started_at, a.created_at AS joined
         FROM calls c JOIN accounts a ON a.id = c.user_id
        WHERE c.user_id = $1 AND c.started_at IS NOT NULL AND c.billed_seconds >= $2
          AND a.role = 'user' AND NOT a.is_blocked
        ORDER BY c.started_at LIMIT 1`, [userId, MIN_SECONDS])).rows[0];
    if (!first || first.initiated_by !== 'partner') return;
    if (new Date(first.started_at) - new Date(first.joined) > NEW_USER_DAYS * 86400 * 1000) return;

    // Did he spend money at or after her call, within the window? A top-up, or a paid call that ran.
    const converted = (await pool.query(
      `SELECT 1 WHERE EXISTS (
         SELECT 1 FROM ledger l WHERE l.account_id = $1 AND l.type = 'topup'
            AND l.created_at >= $2 AND l.created_at <= $2::timestamptz + ($3 || ' days')::interval)
        OR EXISTS (
         SELECT 1 FROM calls c WHERE c.user_id = $1 AND NOT c.is_free AND c.billed_seconds > 0
            AND c.started_at >= $2 AND c.started_at <= $2::timestamptz + ($3 || ' days')::interval)`,
      [userId, first.started_at, String(PAY_WITHIN_DAYS)])).rowCount;
    if (!converted) return;

    const client = await pool.connect();
    let paid = false;
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO ledger (account_id, type, amount, call_id, ref, idem_key)
         VALUES ($1,'adjustment',$2,$3,'first_call_bonus',$4) ON CONFLICT (idem_key) DO NOTHING`,
        [first.partner_id, BONUS_PAISE, first.id, `first_call_bonus:${userId}`]);
      if (ins.rowCount) {
        await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [BONUS_PAISE, first.partner_id]);
        paid = true;
      }
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
    if (paid) {
      const rupees = BONUS_PAISE / 100;
      push.notifyHostNote(first.partner_id, '🎉 New user bonus!',
        `A new user you called first just bought coins. ₹${rupees} (${rupees * COINS_PER_RUPEE} coins) added to your earnings.`).catch(() => {});
    }
  } catch (e) {
    console.error('[firstcall] bonus check failed:', e.message);
  }
}

/** A call finished. Runs a few seconds later so the last billing tick has landed. */
function afterCall(call) {
  if (!enabled() || !call || !call.started_at) return;
  setTimeout(() => checkUser(call.user_id), 5000);
}

/** A top-up was credited. */
function afterTopup(userId) {
  if (enabled()) checkUser(userId);
}

/** What the host app shows on the offer card. */
function offer() {
  const rupees = BONUS_PAISE / 100;
  return {
    enabled: enabled(), rupees, coins: rupees * COINS_PER_RUPEE,
    minSeconds: MIN_SECONDS, newUserDays: NEW_USER_DAYS, payWithinDays: PAY_WITHIN_DAYS, freeCallCounts: true,
  };
}

module.exports = { checkUser, afterCall, afterTopup, offer, NEW_USER_SQL, NEW_USER_DAYS, MIN_SECONDS };
