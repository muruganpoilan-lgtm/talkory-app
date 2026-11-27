// New-user offer for hosts: the host who makes a new user's first paid call earns a one-time bonus.
//
// Rules (all changeable in .env):
//   - the user joined in the last FIRST_CALL_NEW_USER_DAYS days (default 7)
//   - the HOST made the call (initiated_by = 'partner'), the user answered, and it was a paid call
//     (free calls move no money, so they can't be used to farm the bonus with throwaway accounts)
//   - it is the user's first paid answered call ever, with any host, either direction
//   - the call lasted at least FIRST_CALL_MIN_SECONDS (default 60) of billed time
//   - one bonus per user, ever (idem_key), paid into the host's wallet like the weekly bonus
// Default bonus: Rs 50 = 150 coins at 3 coins = Rs 1.
const { pool } = require('./db');
const push = require('./push');
const { COINS_PER_RUPEE } = require('./coins');

const BONUS_PAISE = Number(process.env.FIRST_CALL_BONUS_PAISE || 5000);
const NEW_USER_DAYS = Number(process.env.FIRST_CALL_NEW_USER_DAYS || 7);
const MIN_SECONDS = Number(process.env.FIRST_CALL_MIN_SECONDS || 60);
const enabled = () => BONUS_PAISE > 0;

// SQL test for "this user still counts as new and has had no paid answered call yet" (used by the Users online list).
// $1 must be the number of days.
const NEW_USER_SQL = `(a.created_at > now() - ($1 || ' days')::interval
   AND NOT EXISTS (SELECT 1 FROM calls c2 WHERE c2.user_id = a.id AND c2.started_at IS NOT NULL AND NOT c2.is_free AND c2.billed_seconds > 0))`;

/** Called when a call finishes. Never throws. */
async function payIfEligible(call) {
  if (!enabled() || !call || !call.started_at || call.initiated_by !== 'partner' || call.is_free) return;
  try {
    // Re-read: the last billing tick may have landed after the call row was closed
    const c = (await pool.query('SELECT * FROM calls WHERE id=$1', [call.id])).rows[0];
    if (!c || c.billed_seconds < MIN_SECONDS) return;
    const ok = (await pool.query(
      `SELECT 1 FROM accounts a
        WHERE a.id = $1 AND a.role = 'user' AND NOT a.is_blocked
          AND a.created_at > $2::timestamptz - ($3 || ' days')::interval
          AND NOT EXISTS (SELECT 1 FROM calls c2
                           WHERE c2.user_id = a.id AND c2.id <> $4 AND c2.started_at IS NOT NULL
                             AND c2.started_at < $2 AND NOT c2.is_free AND c2.billed_seconds > 0)`,
      [c.user_id, c.started_at, String(NEW_USER_DAYS), c.id])).rowCount;
    if (!ok) return;

    const client = await pool.connect();
    let paid = false;
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO ledger (account_id, type, amount, call_id, ref, idem_key)
         VALUES ($1,'adjustment',$2,$3,'first_call_bonus',$4) ON CONFLICT (idem_key) DO NOTHING`,
        [c.partner_id, BONUS_PAISE, c.id, `first_call_bonus:${c.user_id}`]);
      if (ins.rowCount) {
        await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [BONUS_PAISE, c.partner_id]);
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
      push.notifyHostNote(c.partner_id, '🎉 New user bonus!',
        `₹${rupees} (${rupees * COINS_PER_RUPEE} coins) added for the first call with a new user.`).catch(() => {});
    }
  } catch (e) {
    console.error('[firstcall] bonus failed:', e.message);
  }
}

/** What the host app shows on the offer card. */
function offer() {
  const rupees = BONUS_PAISE / 100;
  return { enabled: enabled(), rupees, coins: rupees * COINS_PER_RUPEE, minSeconds: MIN_SECONDS, newUserDays: NEW_USER_DAYS };
}

module.exports = { payIfEligible, offer, NEW_USER_SQL, NEW_USER_DAYS };
