const { pool } = require('./db');

const FREE_SECONDS = 120; // length of the free call
const COOLDOWN_HOURS = 3; // one free call per user in this window

// Free call is available unless this user already has one in the last 3 hours that connected (or is still ringing).
async function freeStatus(userId) {
  const { rows } = await pool.query(
    `SELECT created_at FROM calls
      WHERE user_id=$1 AND is_free AND created_at > now() - ($2 || ' hours')::interval
        AND (started_at IS NOT NULL OR status='ringing')
      ORDER BY created_at DESC LIMIT 1`, [userId, String(COOLDOWN_HOURS)]);
  if (!rows[0]) return { available: true, seconds: FREE_SECONDS, nextAt: null };
  return { available: false, seconds: FREE_SECONDS, nextAt: new Date(new Date(rows[0].created_at).getTime() + COOLDOWN_HOURS * 3600 * 1000).toISOString() };
}

module.exports = { freeStatus, FREE_SECONDS, COOLDOWN_HOURS };
