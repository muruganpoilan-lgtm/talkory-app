const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');

const LANGUAGES = ['Hindi', 'English', 'Tamil', 'Telugu', 'Bengali', 'Marathi'];
const MIN_RATE = 5, MAX_RATE = 200; // rupees per minute
// Keep contact details out of public profiles: phone numbers, handles, links
const LEAKS = /(\+?\d[\d\s-]{6,}\d|@|https?:|www\.)/i;

router.get('/me', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.display_name, a.avatar_url, p.avatar_status, p.avatar_note, p.bio, p.languages, p.rate_per_min, p.payout_share, p.kyc
       FROM partner_profiles p JOIN accounts a ON a.id=p.account_id WHERE p.account_id=$1`, [req.auth.id]);
  const r = rows[0];
  res.json({
    displayName: r.display_name, bio: r.bio || '', languages: r.languages, rateRupees: r.rate_per_min / 100,
    payoutShare: Number(r.payout_share), kyc: r.kyc, avatarUrl: r.avatar_url, avatarStatus: r.avatar_status, avatarNote: r.avatar_note, allLanguages: LANGUAGES, minRate: MIN_RATE, maxRate: MAX_RATE,
  });
});

router.put('/me', requireAuth(['partner']), async (req, res) => {
  const name = String(req.body.displayName || '').trim();
  const bio = String(req.body.bio || '').trim();
  const langs = Array.isArray(req.body.languages) ? [...new Set(req.body.languages)] : [];
  const rate = Number(req.body.rateRupees);
  const bad = (m) => res.status(400).json({ error: m });

  if (name.length < 2 || name.length > 30) return bad('Name must be 2 to 30 characters');
  if (bio.length > 300) return bad('Bio can be up to 300 characters');
  if (LEAKS.test(name) || LEAKS.test(bio)) return bad('Please remove phone numbers, links and social handles');
  if (!langs.length || langs.length > 5 || langs.some((l) => !LANGUAGES.includes(l))) return bad('Choose 1 to 5 languages');
  if (!Number.isInteger(rate) || rate < MIN_RATE || rate > MAX_RATE) return bad(`Rate must be ₹${MIN_RATE} to ₹${MAX_RATE} per minute`);

  await pool.query('UPDATE accounts SET display_name=$1 WHERE id=$2', [name, req.auth.id]);
  await pool.query('UPDATE partner_profiles SET bio=$1, languages=$2, rate_per_min=$3 WHERE account_id=$4',
    [bio || null, langs, rate * 100, req.auth.id]); // calls in progress keep the rate they started with
  res.json({ ok: true });
});

// Partner toggles availability (partner app)
router.post('/online', requireAuth(['partner']), async (req, res) => {
  const online = !!req.body.online;
  const { rows } = await pool.query('SELECT kyc, languages FROM partner_profiles WHERE account_id=$1', [req.auth.id]);
  if (online && rows[0]?.kyc !== 'approved') return res.status(403).json({ error: 'Verification pending. Open Verification (KYC) to submit your documents.' });
  if (online && !rows[0].languages.length) return res.status(400).json({ error: 'Complete your profile (languages) before going online' });

  await pool.query('UPDATE partner_profiles SET is_online=$1 WHERE account_id=$2', [online, req.auth.id]);
  if (online) await redis.sadd('partners:online', req.auth.id);
  else await redis.srem('partners:online', req.auth.id);
  res.json({ online });
});

// Browse online partners (user app). Never returns phone numbers.
router.get('/', requireAuth(['user']), async (req, res) => {
  const lang = req.query.language;
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.avatar_url, p.bio, p.languages, p.rate_per_min, p.rating_avg, p.rating_count
       FROM partner_profiles p JOIN accounts a ON a.id = p.account_id
      WHERE p.is_online AND p.kyc='approved' AND NOT a.is_blocked
        AND ($1::text IS NULL OR $1 = ANY(p.languages))
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=a.id AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=a.id))
      ORDER BY p.rating_avg DESC LIMIT 50`,
    [lang || null, req.auth.id]);

  const busy = await Promise.all(rows.map((r) => redis.exists(`partner:busy:${r.id}`)));
  res.json(rows.map((r, i) => ({ ...r, busy: !!busy[i] })));
});

module.exports = router;
