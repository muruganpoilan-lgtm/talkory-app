const { pool, redis } = require('./db');
const push = require('./push');

// "Book next slot" for a busy host. Users wait in a short line (Redis list per host).
// When the host becomes free, the first user in line gets an alert and the host is kept for them for HOLD_SECONDS:
// other users see the host as busy until then. If they don't call in time, the next user gets the turn.
const MAX_LINE = Number(process.env.SLOT_MAX_LINE || 5);
const HOLD_SECONDS = Number(process.env.SLOT_HOLD_SECONDS || 120);
const lineKey = (hostId) => `slotq:${hostId}`;
const heldKey = (hostId) => `slot:held:${hostId}`;
const HOSTS = 'slot:hosts'; // hosts that have a line, checked by the once-a-minute sweep

async function position(hostId, userId) {
  const list = await redis.lrange(lineKey(hostId), 0, -1);
  const i = list.indexOf(String(userId));
  return i < 0 ? null : i + 1;
}

async function join(hostId, userId) {
  const now = await position(hostId, userId);
  if (now) return now;
  if ((await redis.llen(lineKey(hostId))) >= MAX_LINE) throw Object.assign(new Error(`The line for this host is full (${MAX_LINE} people). Please try later.`), { status: 409 });
  await redis.rpush(lineKey(hostId), String(userId));
  await redis.expire(lineKey(hostId), 6 * 3600); // a line left behind clears itself
  await redis.sadd(HOSTS, String(hostId));
  return position(hostId, userId);
}

async function leave(hostId, userId) {
  await redis.lrem(lineKey(hostId), 0, String(userId));
  if ((await redis.get(heldKey(hostId))) === String(userId)) await redis.del(heldKey(hostId));
}

const isHeld = async (hostId) => !!(await redis.exists(heldKey(hostId)));
// Kept for someone other than this user? (the user whose turn it is sees the host as free)
const heldForOther = async (hostId, userId) => { const h = await redis.get(heldKey(hostId)); return !!h && h !== String(userId); };

// Called when a user starts a call. Returns false when the host is being kept for someone else.
async function canCall(hostId, userId) {
  const held = await redis.get(heldKey(hostId));
  if (held && held !== String(userId)) return false;
  if (held) await redis.del(heldKey(hostId));
  await redis.lrem(lineKey(hostId), 0, String(userId)); // they are calling now: out of the line
  return true;
}

// Gives the turn to the next user in line, if the host is free and nobody holds a turn already.
async function offerNext(hostId) {
  if (await isHeld(hostId)) return;
  if (await redis.exists(`partner:busy:${hostId}`)) return; // still on a call
  const h = (await pool.query(
    `SELECT a.display_name, p.is_online, p.manual_busy FROM partner_profiles p JOIN accounts a ON a.id=p.account_id WHERE p.account_id=$1`, [hostId])).rows[0];
  if (!h || !h.is_online || h.manual_busy) return; // offline or busy by choice: the line waits
  const userId = await redis.lpop(lineKey(hostId));
  if (!userId) { await redis.srem(HOSTS, String(hostId)); return; }
  if (!(await redis.set(heldKey(hostId), userId, 'EX', HOLD_SECONDS, 'NX'))) { await redis.lpush(lineKey(hostId), userId); return; }
  push.notifySlotReady(userId, hostId, h.display_name, HOLD_SECONDS).catch((e) => console.error('[push] slot-ready:', e.message));
}

// Once a minute: hand out turns that expired or were missed
async function sweep() {
  for (const hostId of await redis.smembers(HOSTS)) await offerNext(hostId).catch((e) => console.error('[slots] sweep:', e.message));
}

module.exports = { join, leave, position, canCall, isHeld, heldForOther, offerNext, sweep, HOLD_SECONDS };
