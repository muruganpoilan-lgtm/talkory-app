const router = require('express').Router();
const { pool, requireAuth } = require('./db');

// Daily check-in: users collect free coins once a day (India time). Coming back on consecutive days builds a streak:
// day 1..7 pay the amounts below, then the week starts again. Missing a day starts again from day 1.
// Change the numbers here to adjust the reward (whole coins).
const REWARDS = [1, 1, 2, 2, 3, 3, 8];

const today = async (client) => (await client.query(`SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date AS d`)).rows[0].d;

// The last check-in and whether it was yesterday (streak still alive) or today (already collected)
async function state(client, accountId) {
  const d = await today(client);
  const last = (await client.query(
    `SELECT day, streak, (day = $2::date) AS is_today, (day = $2::date - 1) AS is_yesterday
       FROM checkins WHERE account_id=$1 ORDER BY day DESC LIMIT 1`, [accountId, d])).rows[0];
  const claimedToday = !!last?.is_today;
  const streak = last && (last.is_today || last.is_yesterday) ? last.streak : 0; // days in a row so far
  const nextDay = (streak % REWARDS.length) + 1; // reward day to collect next: today's if not collected yet, else tomorrow's
  return { d, claimedToday, streak, nextDay };
}

router.use(requireAuth(['user']));

router.get('/', async (req, res) => {
  const s = await state(pool, req.auth.id);
  res.json({ claimedToday: s.claimedToday, streak: s.streak, day: s.nextDay, coins: REWARDS[s.nextDay - 1], rewards: REWARDS });
});

router.post('/', async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT 1 FROM wallets WHERE account_id=$1 FOR UPDATE', [req.auth.id]); // one claim at a time per user
    const s = await state(client, req.auth.id);
    if (s.claimedToday) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Already collected today. Come back tomorrow!' }); }
    const streak = s.streak + 1;
    const coins = REWARDS[s.nextDay - 1];
    await client.query('INSERT INTO checkins (account_id, day, streak, coins) VALUES ($1,$2,$3,$4)', [req.auth.id, s.d, streak, coins]);
    await client.query(
      `INSERT INTO ledger (account_id, type, amount, ref, idem_key) VALUES ($1,'adjustment',$2,'checkin',$3)`,
      [req.auth.id, coins * 100, `checkin:${req.auth.id}:${s.d.toISOString().slice(0, 10)}`]);
    await client.query('UPDATE wallets SET balance = balance + $1, updated_at = now() WHERE account_id=$2', [coins * 100, req.auth.id]);
    await client.query('COMMIT');
    res.json({ coins, streak, day: s.nextDay, rewards: REWARDS });
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    if (e.code === '23505') return res.status(409).json({ error: 'Already collected today. Come back tomorrow!' });
    throw e;
  } finally {
    client.release();
  }
});

module.exports = router;
