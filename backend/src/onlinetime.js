const { pool, redis } = require('./db');

// Daily online-time rule for hosts (days run on India time):
//  - A host must be shown as "Online" for at least ONLINE_MIN_HOURS (default 3) each day.
//  - For every full ONLINE_PENALTY_BLOCK_MIN (default 30) minutes short, ONLINE_PENALTY_RUPEES (default 1) is taken from the host's wallet.
//  - The wallet never goes below 0.
//  - Only hosts who have been online at least once since this rule started are checked (nobody is charged before their first online day).
//  - Time on "Busy" and time spent on a call do not count (set ONLINE_COUNT_CALL_TIME=1 to count call time).
const MIN_SECONDS = Number(process.env.ONLINE_MIN_HOURS || 3) * 3600;
const BLOCK_SECONDS = Number(process.env.ONLINE_PENALTY_BLOCK_MIN || 30) * 60;
const PENALTY_PAISE = Math.round(Number(process.env.ONLINE_PENALTY_RUPEES || 1) * 100);
const COUNT_CALLS = process.env.ONLINE_COUNT_CALL_TIME === '1';
const ENABLED = process.env.ONLINE_PENALTY_ENABLED !== '0';
const TZ = 'Asia/Kolkata';
const STEP = 60; // seconds added each time track() runs (it runs once a minute)

// Once a minute: add a minute to every host who is Online right now
async function track() {
  if (!ENABLED) return;
  if (!(await redis.set('online:track', '1', 'EX', 50, 'NX'))) return; // another API container already did this minute
  const { rows } = await pool.query(
    `SELECT p.account_id AS id FROM partner_profiles p JOIN accounts a ON a.id = p.account_id
      WHERE p.is_online AND NOT p.manual_busy AND p.kyc = 'approved' AND NOT a.is_blocked AND a.deleted_at IS NULL`);
  let ids = rows.map((r) => r.id);
  if (!COUNT_CALLS && ids.length) {
    const busy = await Promise.all(ids.map((id) => redis.exists(`partner:busy:${id}`)));
    ids = ids.filter((_, i) => !busy[i]);
  }
  if (!ids.length) return;
  await pool.query(
    `INSERT INTO partner_online_daily (partner_id, day, seconds)
     SELECT x, (now() AT TIME ZONE '${TZ}')::date, $2::int FROM unnest($1::uuid[]) AS x
     ON CONFLICT (partner_id, day) DO UPDATE SET seconds = partner_online_daily.seconds + $2::int`, [ids, STEP]);
}

// Settle one finished day for every host who has been active on or before it. Safe to run twice.
async function settleDay(day) {
  const { rows } = await pool.query(
    `SELECT f.partner_id, COALESCE(d.seconds, 0) AS seconds
       FROM (SELECT partner_id, MIN(day) AS first_day FROM partner_online_daily GROUP BY partner_id) f
       JOIN accounts a ON a.id = f.partner_id AND NOT a.is_blocked AND a.deleted_at IS NULL
       JOIN partner_profiles p ON p.account_id = f.partner_id AND p.kyc = 'approved'
       LEFT JOIN partner_online_daily d ON d.partner_id = f.partner_id AND d.day = $1::date
      WHERE f.first_day <= $1::date
        AND NOT EXISTS (SELECT 1 FROM online_penalties o WHERE o.partner_id = f.partner_id AND o.day = $1::date)`, [day]);
  for (const r of rows) {
    const short = Math.max(0, MIN_SECONDS - Number(r.seconds));
    const penalty = Math.floor(short / BLOCK_SECONDS) * PENALTY_PAISE;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const bal = Number((await client.query('SELECT balance FROM wallets WHERE account_id=$1 FOR UPDATE', [r.partner_id])).rows[0]?.balance ?? 0);
      const charged = Math.min(penalty, bal);
      const ins = await client.query(
        `INSERT INTO online_penalties (partner_id, day, short_seconds, penalty_paise, charged_paise) VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT DO NOTHING RETURNING 1`, [r.partner_id, day, short, penalty, charged]);
      if (ins.rowCount && charged > 0) {
        await client.query(
          `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'adjustment',$2,$3,$4) ON CONFLICT (idem_key) DO NOTHING`,
          [r.partner_id, -charged, `online_penalty:${day}`, `online_penalty:${r.partner_id}:${day}`]);
        await client.query('UPDATE wallets SET balance = balance - $1, updated_at = now() WHERE account_id=$2', [charged, r.partner_id]);
      }
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      console.error('[online] settle failed:', r.partner_id, day, e.message);
    } finally {
      client.release();
    }
  }
}

// Runs just after midnight India time: settles yesterday (and the two days before it, in case the server was down)
async function settleRecent() {
  if (!ENABLED) return;
  for (let back = 3; back >= 1; back--) {
    const { rows } = await pool.query(`SELECT ((now() AT TIME ZONE '${TZ}')::date - $1::int)::text AS d`, [back]);
    await settleDay(rows[0].d);
  }
}

// For the host's own app: how much of today's minimum is done
async function today(partnerId) {
  const { rows } = await pool.query(
    `SELECT COALESCE((SELECT seconds FROM partner_online_daily WHERE partner_id=$1 AND day=(now() AT TIME ZONE '${TZ}')::date), 0) AS seconds`, [partnerId]);
  return {
    enabled: ENABLED,
    seconds: Number(rows[0].seconds),
    requiredSeconds: MIN_SECONDS,
    penaltyPaise: PENALTY_PAISE,
    blockMinutes: BLOCK_SECONDS / 60,
  };
}

module.exports = { track, settleRecent, settleDay, today };
