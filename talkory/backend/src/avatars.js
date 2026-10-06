const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const { pool, requireAuth } = require('./db');

// pending/ is private (admins only). A photo moves to public/ only after approval, and only public/ is served.
const AVATAR_DIR = path.resolve(process.env.AVATAR_DIR || (process.env.NODE_ENV === 'production' ? '/data/avatars' : path.join(__dirname, '../data/avatars')));
const PENDING = path.join(AVATAR_DIR, 'pending');
const PUBLIC = path.join(AVATAR_DIR, 'public');
const MAX_BYTES = 1.5 * 1024 * 1024;

// Re-write the file without metadata: phone photos carry GPS location, device model and timestamps, which would
// undermine hosts' anonymity. JPEG: drop APP1-15 (EXIF/XMP/GPS) and comments. PNG: keep only the image chunks.
function stripJpeg(b) {
  const out = [b.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xda) { out.push(b.subarray(i)); return Buffer.concat(out); } // start of scan: rest is pixel data
    const end = i + 2 + b.readUInt16BE(i + 2);
    if (end > b.length) return null;
    if (!((marker >= 0xe1 && marker <= 0xef) || marker === 0xfe)) out.push(b.subarray(i, end));
    i = end;
  }
  return null;
}
function stripPng(b) {
  const keep = new Set(['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND', 'gAMA', 'sRGB']);
  const out = [b.subarray(0, 8)];
  let i = 8;
  while (i + 12 <= b.length) {
    const end = i + 12 + b.readUInt32BE(i);
    const type = b.toString('ascii', i + 4, i + 8);
    if (end > b.length) return null;
    if (keep.has(type)) out.push(b.subarray(i, end));
    i = end;
    if (type === 'IEND') return Buffer.concat(out);
  }
  return null;
}
function sanitize(b) {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) { const x = stripJpeg(b); return x && { buf: x, ext: 'jpg' }; }
  if (b.length > 8 && b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) { const x = stripPng(b); return x && { buf: x, ext: 'png' }; }
  return null;
}
const rm = (dir, file) => (file ? fs.unlink(path.join(dir, path.basename(file))).catch(() => {}) : Promise.resolve());

// ---- partner (mounted at /partner/avatar)
const router = express.Router();

router.post('/', requireAuth(['partner']), async (req, res) => {
  const b64 = req.body.imageBase64;
  if (typeof b64 !== 'string' || b64.length > MAX_BYTES * 1.4) return res.status(400).json({ error: 'That photo is too large' });
  const clean = sanitize(Buffer.from(b64, 'base64'));
  if (!clean || clean.buf.length > MAX_BYTES) return res.status(400).json({ error: 'Please upload a JPG or PNG photo' });

  await fs.mkdir(PENDING, { recursive: true });
  const file = `${crypto.randomUUID()}.${clean.ext}`;
  await fs.writeFile(path.join(PENDING, file), clean.buf, { mode: 0o600 });
  const prev = (await pool.query('SELECT avatar_pending FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  await pool.query(`UPDATE partner_profiles SET avatar_pending=$1, avatar_status='pending', avatar_note=NULL WHERE account_id=$2`, [file, req.auth.id]);
  await rm(PENDING, prev?.avatar_pending);
  res.json({ ok: true });
});

router.post('/remove', requireAuth(['partner']), async (req, res) => {
  const row = (await pool.query(
    'SELECT a.avatar_url, p.avatar_pending FROM accounts a JOIN partner_profiles p ON p.account_id=a.id WHERE a.id=$1', [req.auth.id])).rows[0];
  await pool.query('UPDATE accounts SET avatar_url=NULL WHERE id=$1', [req.auth.id]);
  await pool.query('UPDATE partner_profiles SET avatar_pending=NULL, avatar_status=NULL, avatar_note=NULL WHERE account_id=$1', [req.auth.id]);
  await rm(PUBLIC, row.avatar_url);
  await rm(PENDING, row.avatar_pending);
  res.json({ ok: true });
});

// ---- admin review (mounted at /admin/avatars)
const admin = express.Router();
admin.use(requireAuth(['admin']));

admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.avatar_status='pending' ORDER BY a.created_at LIMIT 100`);
  res.json(rows);
});

admin.get('/:id/image', async (req, res) => {
  const row = (await pool.query(`SELECT avatar_pending FROM partner_profiles WHERE account_id=$1 AND avatar_status='pending'`, [req.params.id])).rows[0];
  if (!row) return res.status(404).json({ error: 'no pending photo' });
  res.sendFile(path.join(PENDING, path.basename(row.avatar_pending)),
    { cacheControl: false, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
});

admin.post('/:id', async (req, res) => {
  const { status } = req.body;
  const note = String(req.body.note || '').trim().slice(0, 200);
  if (!['approved', 'rejected'].includes(status)) return res.status(400).json({ error: 'invalid status' });
  if (status === 'rejected' && !note) return res.status(400).json({ error: 'Add a reason the host will see' });

  const row = (await pool.query(
    `SELECT p.avatar_pending, a.avatar_url FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.account_id=$1 AND p.avatar_status='pending'`, [req.params.id])).rows[0];
  if (!row) return res.status(409).json({ error: 'nothing to review' });

  if (status === 'approved') {
    await fs.mkdir(PUBLIC, { recursive: true });
    await fs.rename(path.join(PENDING, path.basename(row.avatar_pending)), path.join(PUBLIC, path.basename(row.avatar_pending)));
    await pool.query('UPDATE accounts SET avatar_url=$1 WHERE id=$2', [`/avatars/${row.avatar_pending}`, req.params.id]);
    await pool.query(`UPDATE partner_profiles SET avatar_pending=NULL, avatar_status='approved', avatar_note=NULL WHERE account_id=$1`, [req.params.id]);
    await rm(PUBLIC, row.avatar_url); // the photo it replaces
  } else {
    await rm(PENDING, row.avatar_pending);
    await pool.query(`UPDATE partner_profiles SET avatar_pending=NULL, avatar_status='rejected', avatar_note=$2 WHERE account_id=$1`, [req.params.id, note]);
  }
  res.json({ ok: true });
});

module.exports = { router, admin, AVATAR_DIR, PUBLIC, PENDING };
