const { pool } = require('./db');

const FREE_SECONDS = 120; // the user's own free call
const HOST_FREE_SECONDS = Number(process.env.HOST_FREE_SECONDS || 180); // the minutes a host can give away
const COOLDOWN_HOURS = Number(process.env.FREE_CALL_COOLDOWN_HOURS || 3); // one free call per user in this window
const HOST_COOLDOWN_HOURS = Number(process.env.HOST_FREE_CALL_COOLDOWN_HOURS || 3); // one giveaway per host in this window

/// How long this free call lasts. A host's giveaway is longer than the user's own free call.
const freeSecondsFor = (call) => (call && call.is_host_free ? HOST_FREE_SECONDS : FREE_SECONDS);

/// A free call that was offered counts even if it was declined or missed, so the "free minutes"
/// message does not show on every ring.
async function lastFreeAt(column, id, hours, hostGift) {
  const { rows } = await pool.query(
    `SELECT created_at FROM calls
      WHERE ${column}=$1 AND is_free AND is_host_free = $3 AND created_at > now() - ($2 || ' hours')::interval
        AND status <> 'failed'
      ORDER BY created_at DESC LIMIT 1`, [id, String(hours), hostGift]);
  return rows[0] ? rows[0].created_at : null;
}

const after = (at, hours) => new Date(new Date(at).getTime() + hours * 3600 * 1000).toISOString();

// One free call per user every 3 hours. The host is paid for these by the platform.
async function freeStatus(userId) {
  const at = await lastFreeAt('user_id', userId, COOLDOWN_HOURS, false);
  return at
    ? { available: false, seconds: FREE_SECONDS, nextAt: after(at, COOLDOWN_HOURS) }
    : { available: true, seconds: FREE_SECONDS, nextAt: null };
}

// One giveaway per host every 3 hours, for calls she makes. She earns nothing for these minutes.
async function hostFreeStatus(partnerId) {
  const at = await lastFreeAt('partner_id', partnerId, HOST_COOLDOWN_HOURS, true);
  return at
    ? { available: false, seconds: HOST_FREE_SECONDS, nextAt: after(at, HOST_COOLDOWN_HOURS) }
    : { available: true, seconds: HOST_FREE_SECONDS, nextAt: null };
}

module.exports = { freeStatus, hostFreeStatus, freeSecondsFor, FREE_SECONDS, HOST_FREE_SECONDS, COOLDOWN_HOURS, HOST_COOLDOWN_HOURS };
