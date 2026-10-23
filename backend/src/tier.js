const { pool } = require('./db');

// Weekly "Paradise" level for hosts, from the hours they spent talking on answered calls.
// The week runs Monday 00:00 to Sunday 24:00 India time and starts again every Monday.
// Free calls count too. Hours are the billed talk time (counted in 15-second steps).
const TZ = 'Asia/Kolkata';
const TIERS = [ // highest first
  { key: 'green',  name: 'Green Paradise',  minHours: 15 },
  { key: 'golden', name: 'Golden Paradise', minHours: 10 },
  { key: 'ruby',   name: 'Ruby Paradise',   minHours: 7 },
  { key: 'blue',   name: 'Blue Paradise',   minHours: 5 },
  { key: 'purple', name: 'Purple Paradise', minHours: 0 },
];
const tierOf = (seconds) => TIERS.find((t) => seconds >= t.minHours * 3600) || TIERS[TIERS.length - 1];

// SQL for the start of this week as a real timestamp (Monday 00:00 India time)
const WEEK_START = `(date_trunc('week', now() AT TIME ZONE '${TZ}') AT TIME ZONE '${TZ}')`;

// {partnerId: seconds} for this week (offset 0) or last week (offset 1)
async function secondsFor(ids, weeksBack = 0) {
  if (!ids.length) return {};
  const { rows } = await pool.query(
    `SELECT partner_id, COALESCE(SUM(billed_seconds), 0)::int AS s FROM calls
      WHERE partner_id = ANY($1::uuid[]) AND started_at IS NOT NULL
        AND started_at >= ${WEEK_START} - ($2::int * interval '7 days')
        AND started_at <  ${WEEK_START} - (($2::int - 1) * interval '7 days')
      GROUP BY partner_id`, [ids, weeksBack]);
  const out = {};
  for (const r of rows) out[r.partner_id] = r.s;
  return out;
}

const pub = (t) => ({ key: t.key, name: t.name, minHours: t.minHours });

// For the host's own screen
async function weekly(partnerId) {
  const [now, last] = await Promise.all([secondsFor([partnerId], 0), secondsFor([partnerId], 1)]);
  const seconds = now[partnerId] || 0;
  const lastSeconds = last[partnerId] || 0;
  const cur = tierOf(seconds);
  const idx = TIERS.indexOf(cur);
  const next = idx > 0 ? TIERS[idx - 1] : null;
  const wk = (await pool.query(`SELECT to_char(${WEEK_START} AT TIME ZONE '${TZ}' + interval '7 days', 'YYYY-MM-DD') AS ends`)).rows[0].ends;
  return {
    seconds,
    tier: pub(cur),
    next: next ? { ...pub(next), secondsToGo: Math.max(0, next.minHours * 3600 - seconds) } : null,
    lastWeek: { seconds: lastSeconds, tier: pub(tierOf(lastSeconds)) },
    weekEndsOn: wk, // the new week starts on this date (Monday)
  };
}

module.exports = { TIERS, tierOf, secondsFor, weekly };
