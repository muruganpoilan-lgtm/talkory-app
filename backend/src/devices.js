const router = require('express').Router();
const { pool, requireAuth } = require('./db');

// App registers its push tokens after login / on token refresh. voipToken is iOS only.
router.post('/', requireAuth(['user', 'partner']), async (req, res) => {
  const { platform, pushToken, voipToken } = req.body;
  if (!['android', 'ios'].includes(platform) || !pushToken || String(pushToken).length > 4096)
    return res.status(400).json({ error: 'invalid device' });

  // A token belongs to one account at a time (shared phone, logout then login as someone else)
  await pool.query('DELETE FROM devices WHERE push_token=$1 AND account_id<>$2', [pushToken, req.auth.id]);
  await pool.query(
    `INSERT INTO devices (account_id, platform, push_token, voip_token) VALUES ($1,$2,$3,$4)
     ON CONFLICT (account_id, push_token) DO UPDATE SET platform=EXCLUDED.platform, voip_token=EXCLUDED.voip_token, updated_at=now()`,
    [req.auth.id, platform, pushToken, platform === 'ios' && voipToken ? String(voipToken).slice(0, 200) : null]);
  res.json({ ok: true });
});

// Called on logout so a signed-out phone stops ringing
router.post('/unregister', requireAuth(['user', 'partner']), async (req, res) => {
  await pool.query('DELETE FROM devices WHERE account_id=$1 AND push_token=$2', [req.auth.id, req.body.pushToken || '']);
  res.json({ ok: true });
});

module.exports = router;
