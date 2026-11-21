const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const { pool, requireAuth } = require('./db');
const { AVATAR_DIR } = require('./avatars');

// Same pattern as profile photos: pending/ is private (admins only); approved intros move to public/ and are served at /intros/<file>
const PENDING = path.join(AVATAR_DIR, 'intro-pending');
const PUBLIC = path.join(AVATAR_DIR, 'intro-public');
const MAX_BYTES = 800 * 1024; // 20 s of AAC is about 160 KB
const isM4a = (b) => b.length > 12 && b.toString('ascii', 4, 8) === 'ftyp'; // MP4/M4A container
const rm = (dir, file) => (file ? fs.unlink(path.join(dir, path.basename(file))).catch(() => {}) : Promise.resolve());

// ---- partner (mounted at /partner/intro)
const router = express.Router();

router.post('/', requireAuth(['partner']), async (req, res) => {
  const b64 = req.body.audioBase64;
  if (typeof b64 !== 'string' || b64.length > MAX_BYTES * 1.4) return res.status(400).json({ error: 'That recording is too long' });
  const buf = Buffer.from(b64, 'base64');
  if (buf.length > MAX_BYTES || !isM4a(buf)) return res.status(400).json({ error: 'Please record the intro again' });

  await fs.mkdir(PENDING, { recursive: true });
  const file = `${crypto.randomUUID()}.m4a`;
  await fs.writeFile(path.join(PENDING, file), buf, { mode: 0o600 });
  const prev = (await pool.query('SELECT intro_pending FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  await pool.query(`UPDATE partner_profiles SET intro_pending=$1, intro_status='pending', intro_note=NULL WHERE account_id=$2`, [file, req.auth.id]);
  await rm(PENDING, prev?.intro_pending);
  res.json({ ok: true });
});

router.post('/remove', requireAuth(['partner']), async (req, res) => {
  const row = (await pool.query('SELECT intro_url, intro_pending FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  await pool.query('UPDATE partner_profiles SET intro_url=NULL, intro_pending=NULL, intro_status=NULL, intro_note=NULL WHERE account_id=$1', [req.auth.id]);
  await rm(PUBLIC, row.intro_url);
  await rm(PENDING, row.intro_pending);
  res.json({ ok: true });
});

// ---- admin review (mounted at /admin/intros)
const admin = express.Router();
admin.use(requireAuth(['admin']));

admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.intro_status='pending' ORDER BY a.created_at LIMIT 100`);
  res.json(rows);
});

admin.get('/:id/audio', async (req, res) => {
  const row = (await pool.query(`SELECT intro_pending FROM partner_profiles WHERE account_id=$1 AND intro_status='pending'`, [req.params.id])).rows[0];
  if (!row) return res.status(404).json({ error: 'no pending intro' });
  res.sendFile(path.join(PENDING, path.basename(row.intro_pending)),
    { cacheControl: false, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
});

admin.post('/:id', async (req, res) => {
  const { status } = req.body;
  const note = String(req.body.note || '').trim().slice(0, 200);
  if (!['approved', 'rejected'].includes(status)) return res.status(400).json({ error: 'invalid status' });
  if (status === 'rejected' && !note) return res.status(400).json({ error: 'Add a reason the host will see' });

  const row = (await pool.query(
    `SELECT intro_pending, intro_url FROM partner_profiles WHERE account_id=$1 AND intro_status='pending'`, [req.params.id])).rows[0];
  if (!row) return res.status(409).json({ error: 'nothing to review' });

  if (status === 'approved') {
    await fs.mkdir(PUBLIC, { recursive: true });
    await fs.rename(path.join(PENDING, path.basename(row.intro_pending)), path.join(PUBLIC, path.basename(row.intro_pending)));
    await pool.query(
      `UPDATE partner_profiles SET intro_url=$2, intro_pending=NULL, intro_status='approved', intro_note=NULL WHERE account_id=$1`,
      [req.params.id, `/intros/${row.intro_pending}`]);
    await rm(PUBLIC, row.intro_url); // the intro it replaces
  } else {
    await rm(PENDING, row.intro_pending);
    await pool.query(`UPDATE partner_profiles SET intro_pending=NULL, intro_status='rejected', intro_note=$2 WHERE account_id=$1`, [req.params.id, note]);
  }
  res.json({ ok: true });
});

module.exports = { router, admin, PUBLIC, PENDING };
