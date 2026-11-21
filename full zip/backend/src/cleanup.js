const router = require('express').Router();
const { pool, requireAuth } = require('./db');
const { deleteAccount } = require('./account');

// A host who has not opened the app for INACTIVE_DELETE_DAYS (default 30) is treated as gone (uninstalled):
// their personal records are deleted automatically, the same as "Delete my account", and so are their saved agreement copy and files.
// Calls, payments and payout records stay (accounting), without the name and phone number.
// Not touched: hosts who still have money in the wallet or a payout waiting (they are listed in the admin panel instead),
// blocked accounts (kept for investigations) and anyone on a call right now.
const DAYS = Number(process.env.INACTIVE_DELETE_DAYS || 30);
const WARN_DAYS = 7; // the admin list starts this many days before deletion

const CANDIDATES = `
  SELECT a.id, a.display_name, a.phone, a.last_active_at, COALESCE(w.balance, 0)::bigint AS balance,
         GREATEST(0, EXTRACT(DAY FROM now() - a.last_active_at))::int AS days_away
    FROM accounts a LEFT JOIN wallets w ON w.account_id = a.id
   WHERE a.role = 'partner' AND a.deleted_at IS NULL AND NOT a.is_blocked
     AND a.last_active_at < now() - ($1::int * interval '1 day')
     AND NOT EXISTS (SELECT 1 FROM payouts p WHERE p.partner_id = a.id AND p.status IN ('requested', 'processing'))
     AND NOT EXISTS (SELECT 1 FROM calls c WHERE c.partner_id = a.id AND c.status IN ('ringing', 'active'))`;

// Daily job
async function run() {
  const { rows } = await pool.query(`${CANDIDATES} ORDER BY a.last_active_at LIMIT 50`, [DAYS]);
  let deleted = 0, waiting = 0;
  for (const r of rows) {
    if (Number(r.balance) > 0) { waiting++; continue; } // money first: the host can still log in and withdraw
    try {
      await deleteAccount(r.id);
      await pool.query('DELETE FROM host_files WHERE account_id=$1', [r.id]); // also the saved agreement copy
      await pool.query('DELETE FROM partner_contracts WHERE partner_id=$1', [r.id]);
      deleted++;
      console.log(`[cleanup] deleted inactive host ${r.id} (away ${r.days_away} days)`);
    } catch (e) {
      console.error(`[cleanup] could not delete ${r.id}:`, e.message);
    }
  }
  if (rows.length) console.log(`[cleanup] inactive hosts: ${deleted} deleted, ${waiting} waiting for their balance to be withdrawn`);
}

// Admin: hosts who are away and about to be (or waiting to be) deleted
const admin = router;
admin.use(requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(`${CANDIDATES} ORDER BY a.last_active_at LIMIT 200`, [Math.max(1, DAYS - WARN_DAYS)]);
  res.json(rows.map((r) => ({
    id: r.id, display_name: r.display_name, phone: r.phone, last_active_at: r.last_active_at, days_away: r.days_away,
    balance: Number(r.balance),
    state: Number(r.balance) > 0 ? 'waiting' : r.days_away >= DAYS ? 'due' : 'soon',
    deletes_in_days: Math.max(0, DAYS - r.days_away),
  })));
});

module.exports = { run, admin, DAYS };
