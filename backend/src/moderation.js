const { pool, redis } = require('./db');

// One place for blocking and unblocking an account, so every block records why, who did it and when,
// and every unblock undoes all of it. Used by the admin panel and by the chat auto-filter.

async function blockAccount(id, { reason, note = null, byAdmin = null }) {
  if (!/^[0-9a-f-]{36}$/i.test(String(id || ''))) return null;
  const r = await pool.query(
    `UPDATE accounts SET is_blocked=true, blocked_reason=$2, blocked_note=$3, blocked_at=now(), blocked_by=$4
      WHERE id=$1 AND role IN ('user','partner') AND deleted_at IS NULL
      RETURNING id, display_name, role`, [id, reason, note, byAdmin]);
  if (!r.rows[0]) return null;
  await redis.sadd('blocked', id); // any login token still in circulation stops working immediately
  await pool.query('UPDATE partner_profiles SET is_online=false, manual_busy=false WHERE account_id=$1', [id]);
  await redis.srem('partners:online', id);
  await pool.query('INSERT INTO block_events (account_id, action, reason, by_admin) VALUES ($1,$2,$3,$4)',
    [id, 'block', reason, byAdmin]);
  return r.rows[0];
}

async function unblockAccount(id, byAdmin = null) {
  if (!/^[0-9a-f-]{36}$/i.test(String(id || ''))) return null;
  // Deleted accounts stay blocked: unblocking one would bring back an account its owner asked us to remove.
  const r = await pool.query(
    `UPDATE accounts SET is_blocked=false, blocked_reason=NULL, blocked_note=NULL, blocked_at=NULL, blocked_by=NULL
      WHERE id=$1 AND is_blocked AND deleted_at IS NULL AND role IN ('user','partner')
      RETURNING id, display_name, role`, [id]);
  if (!r.rows[0]) return null;
  await redis.srem('blocked', id);
  await redis.del(`chatstrike:${id}`); // a clean slate: old strikes must not block them again on the next message
  await pool.query('INSERT INTO block_events (account_id, action, by_admin) VALUES ($1,$2,$3)', [id, 'unblock', byAdmin]);
  return r.rows[0];
}

/// What the blocked person is told when they try to log in. Only the short note is shown:
/// the full reason can quote the words they used, which is for admins to read, not to repeat back.
function blockedMessage(acc) {
  const note = String((acc && acc.blocked_note) || '').trim();
  return note
    ? `Your account has been blocked. Reason: ${note} Contact support if you think this is a mistake.`
    : 'Your account has been blocked. Contact support if you think this is a mistake.';
}

module.exports = { blockAccount, unblockAccount, blockedMessage };
