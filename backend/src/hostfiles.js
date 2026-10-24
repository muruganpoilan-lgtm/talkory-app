const fs = require('fs/promises');
const path = require('path');
const router = require('express').Router();
const { pool, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');

// Keeps a copy of each host's KYC photos, profile photos and signed agreement inside the database (table host_files).
// The apps keep working from the disk files as before; this is the permanent record the admin panel opens.
const AVATAR_DIR = path.resolve(process.env.AVATAR_DIR || (process.env.NODE_ENV === 'production' ? '/data/avatars' : path.join(__dirname, '../data/avatars')));
const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp' };
const mimeOf = (f) => MIME[path.extname(f).toLowerCase()] || 'application/octet-stream';
const BATCH = 20; // files copied per minute: a backlog catches up quickly without slowing the server

async function save(accountId, kind, ref, mime, data) {
  await pool.query(
    `INSERT INTO host_files (account_id, kind, ref, mime, data) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (account_id, kind, ref) DO NOTHING`,
    [accountId, kind, ref, mime, data]);
}

async function copyFile(dir, name, accountId, kind, mime) {
  const file = path.basename(String(name || ''));
  if (!file) return;
  let buf;
  try { buf = await fs.readFile(path.join(dir, file)); } catch { return; } // file already gone: nothing to copy
  await save(accountId, kind, file, mime || mimeOf(file), buf);
}

// Hosts who signed before agreement copies were saved: build the copy from their signing record.
async function backfillAgreements() {
  const contract = require('./contract');
  const { rows } = await pool.query(
    `SELECT c.partner_id, c.version, c.full_name, c.ip, c.signed_at FROM partner_contracts c
      WHERE NOT EXISTS (SELECT 1 FROM host_files h WHERE h.account_id=c.partner_id AND h.kind='agreement')`);
  for (const r of rows) {
    const at = new Date(r.signed_at).toISOString();
    const text = Number(r.version) === contract.VERSION ? contract.TEXT : `(The exact wording of version ${r.version} was not stored. The signing record above is kept as proof.)`;
    const body = `TALKORY HOST AGREEMENT (version ${r.version})\nSigned by: ${r.full_name}\nSigned at: ${at}\nIP address: ${r.ip || ''}\n\n${text}\n`;
    await save(r.partner_id, 'agreement', `v${r.version}@${at}`, 'text/plain; charset=utf-8', Buffer.from(body, 'utf8'));
  }
}

// Once a minute, from the queue sweep: copy whatever is not in the database yet
async function sync() {
  await backfillAgreements().catch((e) => console.error('[hostfiles] agreement backfill failed:', e.message));
  const kyc = await pool.query(
    `SELECT d.account_id, d.kind, d.file_name, d.mime FROM kyc_documents d
      WHERE NOT EXISTS (SELECT 1 FROM host_files h WHERE h.account_id=d.account_id AND h.ref=d.file_name AND h.kind IN ('kyc_id','kyc_selfie'))
      LIMIT $1`, [BATCH]);
  for (const r of kyc.rows) await copyFile(KYC_DIR, r.file_name, r.account_id, r.kind === 'selfie' ? 'kyc_selfie' : 'kyc_id', r.mime);

  const pending = await pool.query(
    `SELECT p.account_id, p.avatar_pending AS f FROM partner_profiles p
      WHERE p.avatar_pending IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM host_files h WHERE h.account_id=p.account_id AND h.kind='photo_pending' AND h.ref=p.avatar_pending)
      LIMIT $1`, [BATCH]);
  for (const r of pending.rows) await copyFile(path.join(AVATAR_DIR, 'pending'), r.f, r.account_id, 'photo_pending');

  const live = await pool.query(
    `SELECT a.id AS account_id, a.avatar_url AS f FROM accounts a JOIN partner_profiles p ON p.account_id=a.id
      WHERE a.avatar_url IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM host_files h WHERE h.account_id=a.id AND h.kind='photo' AND h.ref=regexp_replace(a.avatar_url, '^.*/', ''))
      LIMIT $1`, [BATCH]);
  for (const r of live.rows) await copyFile(path.join(AVATAR_DIR, 'public'), r.f, r.account_id, 'photo');
}

// The signed agreement: who signed, when, from where, and the exact words they agreed to
async function saveAgreement(partnerId, version, fullName, ip, text) {
  const at = new Date().toISOString();
  const body = `TALKORY HOST AGREEMENT (version ${version})\nSigned by: ${fullName}\nSigned at: ${at}\nIP address: ${ip || ''}\n\n${text}\n`;
  await save(partnerId, 'agreement', `v${version}@${at}`, 'text/plain; charset=utf-8', Buffer.from(body, 'utf8'));
}

// ---- admin panel: one record per host with every saved file
const admin = router;
admin.use(requireAuth(['admin']));

admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.phone, p.kyc,
            COALESCE(json_agg(json_build_object('id', h.id, 'kind', h.kind, 'at', h.created_at) ORDER BY h.created_at)
                     FILTER (WHERE h.id IS NOT NULL), '[]') AS files,
            MAX(h.created_at) AS last_at
       FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
       LEFT JOIN host_files h ON h.account_id=a.id
      WHERE a.deleted_at IS NULL
      GROUP BY a.id, p.kyc
     HAVING COUNT(h.id) > 0
      ORDER BY MAX(h.created_at) DESC LIMIT 200`);
  res.json(rows);
});

admin.get('/file/:id', async (req, res) => {
  if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const f = (await pool.query('SELECT mime, data FROM host_files WHERE id=$1', [req.params.id])).rows[0];
  if (!f) return res.status(404).json({ error: 'not found' });
  res.set({ 'Content-Type': f.mime, 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' });
  res.send(f.data);
});

module.exports = { sync, saveAgreement, admin };
