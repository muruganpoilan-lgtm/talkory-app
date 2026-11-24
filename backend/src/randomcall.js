// Random Call: picks whichever host is free right now, so a user who does not want to
// browse the list can tap once and start talking. If nobody picks up, the app asks again
// with the hosts it has already tried, and we hand back the next one.
const { pool, redis } = require('./db');
const slots = require('./slots');

// How many hosts to pull per attempt. We only ring one, but several may turn out to be
// busy between the query and the lock, so we need spares to walk through.
const CANDIDATES = 12;
// The app sends every host it has already rung. Cap it so one session cannot grow forever.
const MAX_EXCLUDE = 60;

/// Hosts this user could be connected to right now, in random order.
/// Leaves out: offline, busy-by-choice, not KYC-approved, blocked either way, deleted,
/// already tried in this session, and anyone held for a user who booked a slot.
async function candidates(userId, exclude) {
  const skip = (Array.isArray(exclude) ? exclude : []).filter((x) => typeof x === 'string').slice(0, MAX_EXCLUDE);
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.avatar_url, p.tagline, p.languages, p.rating_avg
       FROM partner_profiles p JOIN accounts a ON a.id = p.account_id
      WHERE p.is_online AND NOT p.manual_busy AND p.kyc='approved'
        AND NOT a.is_blocked AND a.deleted_at IS NULL
        AND a.id <> ALL($2::uuid[])
        AND NOT EXISTS (SELECT 1 FROM blocks b
                         WHERE (b.blocker_id=a.id AND b.blocked_id=$1)
                            OR (b.blocker_id=$1 AND b.blocked_id=a.id))
      ORDER BY random() LIMIT $3`,
    [userId, skip, CANDIDATES]);
  return rows;
}

/// Walks the candidates and returns the first one whose busy lock we win, with the lock held.
/// Returns null when nobody is free. `lockSeconds` must match the lifetime used for normal calls.
async function claimHost(userId, exclude, lockSeconds) {
  for (const host of await candidates(userId, exclude)) {
    if (await redis.exists(`partner:busy:${host.id}`)) continue; // already on a call
    if (!(await slots.canCall(host.id, userId))) continue; // kept for a user who booked a slot
    if (await redis.set(`partner:busy:${host.id}`, userId, 'EX', lockSeconds, 'NX')) return host;
    // Lost the race to another caller in the last few milliseconds: try the next one.
  }
  return null;
}

module.exports = { claimHost, MAX_EXCLUDE };
