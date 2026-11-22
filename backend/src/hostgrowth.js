const { pool, redis } = require('./db');
const push = require('./push');
const tier = require('./tier');

const TZ = 'Asia/Kolkata';
const WEEK_START = `(date_trunc('week', now() AT TIME ZONE '${TZ}') AT TIME ZONE '${TZ}')`;

// ---------- Weekly leaderboard: hosts ranked by talk time on answered calls this week (Monday to Sunday, India time)
async function leaderboard(partnerId, top = 10) {
  const { rows } = await pool.query(
    `WITH w AS (
       SELECT c.partner_id, SUM(c.billed_seconds)::int AS s FROM calls c
        WHERE c.started_at IS NOT NULL AND c.started_at >= ${WEEK_START}
        GROUP BY c.partner_id HAVING SUM(c.billed_seconds) > 0),
     r AS (SELECT partner_id, s, RANK() OVER (ORDER BY s DESC) AS rank FROM w)
     SELECT r.partner_id, r.s, r.rank::int, a.display_name, a.avatar_url
       FROM r JOIN accounts a ON a.id = r.partner_id
      WHERE (r.rank <= $2 OR r.partner_id = $1) AND a.deleted_at IS NULL
      ORDER BY r.rank`, [partnerId, top]);
  const row = (r) => ({ rank: r.rank, name: r.display_name, avatarUrl: r.avatar_url, seconds: r.s, tier: tier.tierOf(r.s).key, me: r.partner_id === partnerId });
  const mine = rows.find((r) => r.partner_id === partnerId);
  return {
    top: rows.filter((r) => r.rank <= top).map(row),
    me: mine ? row(mine) : { rank: null, seconds: 0, me: true },
    bonuses: WEEKLY_BONUS_RUPEES, // what the top places win on Monday
  };
}

// ---------- Weekly bonus for the top hosts, paid into their wallet every Monday just after midnight.
// Rupees for 1st, 2nd, 3rd ... place. Empty list = no bonus. A host needs at least MIN_BONUS_HOURS of talk time that week to win.
const WEEKLY_BONUS_RUPEES = [300, 200, 100];
const MIN_BONUS_HOURS = 10;

async function payWeeklyBonus() {
  if (!WEEKLY_BONUS_RUPEES.length) return;
  const { rows } = await pool.query(
    `SELECT c.partner_id, SUM(c.billed_seconds)::int AS s,
            to_char((${WEEK_START} - interval '7 days') AT TIME ZONE '${TZ}', 'YYYY-MM-DD') AS week
       FROM calls c JOIN accounts a ON a.id=c.partner_id
      WHERE c.started_at >= ${WEEK_START} - interval '7 days' AND c.started_at < ${WEEK_START} AND NOT a.is_blocked AND a.deleted_at IS NULL
      GROUP BY c.partner_id HAVING SUM(c.billed_seconds) >= $1
      ORDER BY s DESC LIMIT $2`, [MIN_BONUS_HOURS * 3600, WEEKLY_BONUS_RUPEES.length]);
  for (let i = 0; i < rows.length; i++) {
    const paise = WEEKLY_BONUS_RUPEES[i] * 100;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'adjustment',$2,'weekly_bonus',$3)
         ON CONFLICT (idem_key) DO NOTHING`, [rows[i].partner_id, paise, `weekly_bonus:${rows[i].week}:${rows[i].partner_id}`]);
      if (ins.rowCount) await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [paise, rows[i].partner_id]);
      await client.query('COMMIT');
      if (ins.rowCount) push.notifyHostNote(rows[i].partner_id, `🏆 You were #${i + 1} last week!`, `₹${WEEKLY_BONUS_RUPEES[i]} bonus added to your earnings.`).catch(() => {});
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      console.error('[bonus] failed:', e.message);
    } finally {
      client.release();
    }
  }
}

// ---------- Peak-hour reminder: many users online and few hosts -> remind offline hosts to go online.
// Checked once an hour (from the once-a-minute sweep), between 10 AM and 11 PM India time, at most twice a day per host.
const PEAK_MIN_USERS = 5;
const PEAK_RATIO = 3; // users per online host
const MAX_REMINDERS_PER_DAY = 2;

async function peakReminder() {
  if (!(await redis.set('peak:checked', '1', 'EX', 3600, 'NX'))) return;
  const hour = Number(new Date().toLocaleString('en-US', { timeZone: TZ, hour: 'numeric', hour12: false }));
  if (hour < 10 || hour >= 23) return;
  const users = await redis.zcount('users:online', Date.now() - 75 * 1000, '+inf');
  const hosts = await redis.scard('partners:online');
  if (users < PEAK_MIN_USERS || users < PEAK_RATIO * Math.max(1, hosts)) return;
  const day = new Date().toLocaleDateString('en-CA', { timeZone: TZ });
  const { rows } = await pool.query(
    `SELECT p.account_id FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.kyc='approved' AND NOT p.is_online AND NOT a.is_blocked AND a.deleted_at IS NULL LIMIT 2000`);
  const ids = [];
  for (const r of rows) {
    const k = `peak:rem:${r.account_id}:${day}`;
    const n = await redis.incr(k);
    await redis.expire(k, 26 * 3600);
    if (n <= MAX_REMINDERS_PER_DAY) ids.push(r.account_id);
  }
  if (ids.length) await push.notifyHostsPeak(ids, users);
}

module.exports = { leaderboard, payWeeklyBonus, peakReminder, WEEKLY_BONUS_RUPEES };
