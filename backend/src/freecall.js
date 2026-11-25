const { pool } = require('./db');

const FREE_SECONDS = Number(process.env.FREE_SECONDS || 0); // the user's own free call: 0 switches it off
const HOST_FREE_SECONDS = Number(process.env.HOST_FREE_SECONDS || 120); // the seconds a host can give away (120 = 2 minutes)
const COOLDOWN_HOURS = Number(process.env.FREE_CALL_COOLDOWN_HOURS || 24); // one free call per user in this window
const HOST_COOLDOWN_HOURS = Number(process.env.HOST_FREE_CALL_COOLDOWN_HOURS || 3); // one giveaway per host in this window

/// How long this free call lasts. A host's giveaway is longer than the user's own free call.
const freeSecondsFor = (call) => (call && call.is_host_free ? HOST_FREE_SECONDS : FREE_SECONDS);

/// Only a free call that was actually answered uses up the free minutes. A ring that was missed,
/// declined or cut before it connected gives them back, so the host can try again straight away.
async function lastFreeAt(column, id, hours, hostGift) {
  const { rows } = await pool.query(
    `SELECT created_at FROM calls
      WHERE ${column}=$1 AND is_free AND is_host_free = $3 AND created_at > now() - ($2 || ' hours')::interval
        AND started_at IS NOT NULL
      ORDER BY created_at DESC LIMIT 1`, [id, String(hours), hostGift]);
  return rows[0] ? rows[0].created_at : null;
}

const after = (at, hours) => new Date(new Date(at).getTime() + hours * 3600 * 1000).toISOString();

// The user's own free call, when FREE_SECONDS switches it on. Nobody is charged and nobody earns for it.
async function freeStatus(userId) {
  if (FREE_SECONDS <= 0) return { available: false, seconds: 0, nextAt: null, off: true };
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
