const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const router = require('express').Router();
const { pool, requireAuth } = require('./db');

const KYC_DIR = path.resolve(process.env.KYC_DIR || (process.env.NODE_ENV === 'production' ? '/data/kyc' : path.join(__dirname, '../data/kyc'))); // private volume, never served statically
const KINDS = ['id_front', 'selfie'];
const MAX_BYTES = 3 * 1024 * 1024;

// Trust the file's real bytes, not what the client says it is
function sniff(b) {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg' };
  if (b.length > 4 && b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return { mime: 'image/png', ext: 'png' };
  return null;
}

router.get('/status', requireAuth(['partner']), async (req, res) => {
  const p = (await pool.query('SELECT kyc, kyc_submitted_at, kyc_note FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  const docs = (await pool.query('SELECT kind FROM kyc_documents WHERE account_id=$1', [req.auth.id])).rows.map((r) => r.kind);
  res.json({ status: p.kyc, submitted: !!p.kyc_submitted_at, note: p.kyc_note, docs });
});

router.post('/documents', requireAuth(['partner']), async (req, res) => {
  const { kind, imageBase64 } = req.body;
  if (!KINDS.includes(kind) || typeof imageBase64 !== 'string' || imageBase64.length > MAX_BYTES * 1.4)
    return res.status(400).json({ error: 'Invalid upload (max 3 MB)' });
  const p = (await pool.query('SELECT kyc FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  if (p.kyc === 'approved') return res.status(409).json({ error: 'You are already verified' });

  const buf = Buffer.from(imageBase64, 'base64');
  const type = buf.length <= MAX_BYTES && sniff(buf);
  if (!type) return res.status(400).json({ error: 'Please upload a JPG or PNG photo under 3 MB' });

  await fs.mkdir(KYC_DIR, { recursive: true });
  const file = `${crypto.randomUUID()}.${type.ext}`;
  await fs.writeFile(path.join(KYC_DIR, file), buf, { mode: 0o600 });

  const prev = (await pool.query('SELECT file_name FROM kyc_documents WHERE account_id=$1 AND kind=$2', [req.auth.id, kind])).rows[0];
  await pool.query(
    `INSERT INTO kyc_documents (account_id, kind, file_name, mime) VALUES ($1,$2,$3,$4)
     ON CONFLICT (account_id, kind) DO UPDATE SET file_name=EXCLUDED.file_name, mime=EXCLUDED.mime, created_at=now()`,
    [req.auth.id, kind, file, type.mime]);
  if (prev) fs.unlink(path.join(KYC_DIR, path.basename(prev.file_name))).catch(() => {});
  res.json({ ok: true });
});

router.post('/submit', requireAuth(['partner']), async (req, res) => {
  const n = (await pool.query('SELECT COUNT(*) FROM kyc_documents WHERE account_id=$1', [req.auth.id])).rows[0].count;
  if (Number(n) < KINDS.length) return res.status(400).json({ error: 'Upload both photos first' });
  await pool.query(
    `UPDATE partner_profiles SET kyc_submitted_at=now(), kyc_note=NULL, kyc='pending'
      WHERE account_id=$1 AND kyc <> 'approved'`, [req.auth.id]);
  res.json({ ok: true });
});

module.exports = { router, KYC_DIR };
