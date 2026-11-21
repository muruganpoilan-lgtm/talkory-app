const fs = require('fs/promises');
const path = require('path');
const { pool, requireAuth } = require('./db');
const { KYC_DIR } = require('./kyc');

// Detects AI-generated profile photos, selfies and ID photos with the Sightengine "genai" model (https://sightengine.com).
// Turned on when SIGHTENGINE_USER and SIGHTENGINE_SECRET are set; otherwise nothing is checked.
//   score >= AI_BLOCK_SCORE (default 0.90): the upload is rejected and the host must upload a real photo
//   score >= AI_FLAG_SCORE  (default 0.50): admin sees a warning with the score and decides
const ENABLED = !!(process.env.SIGHTENGINE_USER && process.env.SIGHTENGINE_SECRET);
const BLOCK = Number(process.env.AI_BLOCK_SCORE || 0.9);
const FLAG = Number(process.env.AI_FLAG_SCORE || 0.5);
const AVATAR_PENDING = path.join(path.resolve(process.env.AVATAR_DIR || (process.env.NODE_ENV === 'production' ? '/data/avatars' : path.join(__dirname, '../data/avatars'))), 'pending');
const REAL_PHOTO_NOTE = 'Please upload a real photo of yourself. AI-generated or heavily edited images are not allowed.';

// Returns 0..1 (chance the image is AI-generated), or null if the check could not be done
async function score(buf, name) {
  const form = new FormData();
  form.append('media', new Blob([buf]), name);
  form.append('models', 'genai');
  form.append('api_user', process.env.SIGHTENGINE_USER);
  form.append('api_secret', process.env.SIGHTENGINE_SECRET);
  const r = await fetch('https://api.sightengine.com/1.0/check.json', { method: 'POST', body: form });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d.status !== 'success' || typeof d.type?.ai_generated !== 'number') {
    console.error('[aicheck] check failed:', r.status, d?.error?.message || d.status);
    return null;
  }
  return d.type.ai_generated;
}

// Runs every minute from the queue sweep: checks new profile photos (waiting for review) and new KYC photos.
async function scan() {
  if (!ENABLED) return;
  const avatars = (await pool.query(
    `SELECT account_id, avatar_pending FROM partner_profiles
      WHERE avatar_status='pending' AND avatar_pending IS NOT NULL AND avatar_ai_file IS DISTINCT FROM avatar_pending LIMIT 5`)).rows;
  for (const a of avatars) {
    let buf;
    try { buf = await fs.readFile(path.join(AVATAR_PENDING, path.basename(a.avatar_pending))); } catch { continue; }
    const s = await score(buf, a.avatar_pending);
    if (s === null) continue;
    if (s >= BLOCK) {
      await pool.query(`UPDATE partner_profiles SET avatar_ai=$2, avatar_ai_file=$3, avatar_pending=NULL, avatar_status='rejected', avatar_note=$4
                         WHERE account_id=$1 AND avatar_pending=$3`, [a.account_id, s, a.avatar_pending, REAL_PHOTO_NOTE]);
      await fs.unlink(path.join(AVATAR_PENDING, path.basename(a.avatar_pending))).catch(() => {});
    } else {
      await pool.query('UPDATE partner_profiles SET avatar_ai=$2, avatar_ai_file=$3 WHERE account_id=$1 AND avatar_pending=$3', [a.account_id, s, a.avatar_pending]);
    }
  }

  const docs = (await pool.query(
    `SELECT d.account_id, d.kind, d.file_name FROM kyc_documents d JOIN partner_profiles p ON p.account_id=d.account_id
      WHERE p.kyc <> 'approved' AND d.ai_file IS DISTINCT FROM d.file_name LIMIT 5`)).rows;
  for (const d of docs) {
    let buf;
    try { buf = await fs.readFile(path.join(KYC_DIR, path.basename(d.file_name))); } catch { continue; }
    const s = await score(buf, d.file_name);
    if (s === null) continue;
    if (s >= BLOCK) { // make the host retake it
      await pool.query('DELETE FROM kyc_documents WHERE account_id=$1 AND kind=$2 AND file_name=$3', [d.account_id, d.kind, d.file_name]);
      await pool.query(`UPDATE partner_profiles SET kyc='rejected', kyc_note=$2 WHERE account_id=$1 AND kyc <> 'approved'`,
        [d.account_id, d.kind === 'selfie' ? 'Your selfie looks AI-generated. Please take a fresh photo of yourself.' : 'Your ID photo looks AI-generated or edited. Please upload the original ID.']);
      await fs.unlink(path.join(KYC_DIR, path.basename(d.file_name))).catch(() => {});
    } else {
      await pool.query('UPDATE kyc_documents SET ai_score=$3, ai_file=$4 WHERE account_id=$1 AND kind=$2 AND file_name=$4', [d.account_id, d.kind, s, d.file_name]);
    }
  }
}

// Admin photo review list, now with the AI score. (Same list as before; mounted ahead of the old one.)
const adminAvatars = require('express').Router();
adminAvatars.get('/', requireAuth(['admin']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, p.avatar_ai::float AS ai FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
      WHERE p.avatar_status='pending' ORDER BY a.created_at LIMIT 100`);
  res.json(rows);
});

module.exports = { ENABLED, FLAG, BLOCK, scan, adminAvatars };
