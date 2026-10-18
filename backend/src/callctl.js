const { pool, redis } = require('./db');
const push = require('./push');

// Idempotent: only moves a call out of one of `from`, so late or duplicate jobs can never end the wrong call.
async function finishCall(callId, status, from = ['ringing', 'active']) {
  const { rows } = await pool.query(
    `UPDATE calls SET status=$1, ended_at=now() WHERE id=$2 AND status = ANY($3::call_status[]) RETURNING *`,
    [status, callId, from]);
  if (rows[0]) {
    await redis.del(`partner:busy:${rows[0].partner_id}`);
    // A call nobody picked up means the host is not really there (app closed, phone off, no signal):
    // take them offline so users stop seeing a green dot. They switch back on when they return.
    if (status === 'missed' && rows[0].initiated_by !== 'partner') {
      await pool.query('UPDATE partner_profiles SET is_online=false, manual_busy=false WHERE account_id=$1', [rows[0].partner_id]);
      await redis.srem('partners:online', rows[0].partner_id);
    }
    // Never answered: stop the partner's phone from ringing
    if (!rows[0].started_at && rows[0].initiated_by !== 'partner') push.notifyCallCancelled(rows[0].partner_id, callId).catch(() => {});
  }
  return rows[0];
}

module.exports = { finishCall };
