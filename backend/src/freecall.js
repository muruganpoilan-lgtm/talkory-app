const { pool } = require('./db');

const FREE_SECONDS = 120; // length of the free call
const COOLDOWN_HOURS = Number(process.env.FREE_CALL_COOLDOWN_HOURS || 3); // one free call per user in this window

// One free call per user every 3 hours. A free call that was offered counts, even if the user declined or missed it,
// so the "free for 2 minutes" message does not show on every ring.
async function freeStatus(userId) {
  const { rows } = await pool.query(
    `SELECT created_at FROM calls
      WHERE user_id=$1 AND is_free AND created_at > now() - ($2 || ' hours')::interval
        AND status <> 'failed'
      ORDER BY created_at DESC LIMIT 1`, [userId, String(COOLDOWN_HOURS)]);
  if (!rows[0]) return { available: true, seconds: FREE_SECONDS, nextAt: null };
  return { available: false, seconds: FREE_SECONDS, nextAt: new Date(new Date(rows[0].created_at).getTime() + COOLDOWN_HOURS * 3600 * 1000).toISOString() };
}

module.exports = { freeStatus, FREE_SECONDS, COOLDOWN_HOURS };
