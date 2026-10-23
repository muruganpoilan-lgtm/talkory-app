const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');

// The Owner is the admin whose accounts.is_owner is true (the first admin). Other admins do everyday work
// (KYC, photos, support, reports); only the owner touches money and the list of admins.
const requireAdmin = requireAuth(['admin']);
async function isOwner(id) {
  const r = await pool.query('SELECT 1 FROM accounts WHERE id=$1 AND role=\'admin\' AND is_owner AND NOT is_blocked', [id]);
  return r.rowCount > 0;
}
function requireOwner(req, res, next) {
  requireAdmin(req, res, async () => {
    try {
      if (!(await isOwner(req.auth.id))) return res.status(403).json({ error: 'Only the owner can do this' });
      next();
    } catch (e) {
      res.status(503).json({ error: 'try again' });
    }
  });
}

// ---- GET /admin/me: lets the apps hide the owner-only tabs
const me = require('express').Router();
me.get('/', requireAdmin, async (req, res) => res.json({ isOwner: await isOwner(req.auth.id) }));

// ---- /admin/admins: owner only
router.use(requireOwner);

router.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT id, display_name, phone, is_owner, is_blocked, created_at FROM accounts
      WHERE role='admin' AND deleted_at IS NULL ORDER BY is_owner DESC, created_at LIMIT 100`);
  res.json(rows);
});

router.post('/', async (req, res) => {
  const phone = String(req.body.phone || '').trim().replace(/[\s-]/g, '');
  const name = String(req.body.name || '').trim().slice(0, 60) || 'Admin';
  if (!/^\+\d{8,15}$/.test(phone)) return res.status(400).json({ error: 'Phone must look like +919876543210' });
  const old = (await pool.query('SELECT id, role, is_blocked FROM accounts WHERE phone=$1', [phone])).rows[0];
  if (old && old.role === 'admin' && old.is_blocked) { // an admin who was removed earlier: give access back
    await pool.query('UPDATE accounts SET is_blocked=false, display_name=$2 WHERE id=$1', [old.id, name]);
    await redis.srem('blocked', old.id);
    return res.json({ ok: true, restored: true });
  }
  if (old) return res.status(409).json({ error: old.role === 'admin' ? 'This number is already an admin' : 'This number is already used by a user or host. Use a different number.' });
  await pool.query(`INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin',$1,$2,true)`, [phone, name]);
  res.json({ ok: true });
});

// Remove access: the admin can no longer log in. The owner cannot be removed, and nobody can remove themselves.
router.post('/:id/remove', async (req, res) => {
  const id = req.params.id;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return res.status(404).json({ error: 'not found' });
  if (id === req.auth.id) return res.status(400).json({ error: 'You cannot remove yourself' });
  const r = await pool.query(`UPDATE accounts SET is_blocked=true WHERE id=$1 AND role='admin' AND NOT is_owner RETURNING id`, [id]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not an admin, or this is the owner' });
  await redis.sadd('blocked', id); // a login still in use stops working at once
  res.json({ ok: true });
});

module.exports = { requireOwner, isOwner, router, me };
