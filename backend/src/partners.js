const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');
const push = require('./push');
const contract = require('./contract');

const LANGUAGES = ['Hindi', 'English', 'Tamil', 'Telugu', 'Bengali', 'Marathi', 'Odia', 'Bhojpuri', 'Malayalam', 'Kannada', 'Gujarati', 'Punjabi', 'Urdu', 'Assamese']; // keep in sync with kLanguages in talkory_core/api.dart
const MIN_RATE = 5, MAX_RATE = 200; // rupees per minute
// Keep contact details out of public profiles: phone numbers, handles, links
const LEAKS = /(\+?\d[\d\s-]{6,}\d|@|https?:|www\.)/i;

router.get('/me', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.display_name, a.avatar_url, p.avatar_status, p.avatar_note, p.tagline, p.is_online, p.manual_busy, p.intro_url, p.intro_status, p.intro_note, p.bio, p.languages, p.rate_per_min, p.payout_share, p.kyc
       FROM partner_profiles p JOIN accounts a ON a.id=p.account_id WHERE p.account_id=$1`, [req.auth.id]);
  const r = rows[0];
  res.json({
    displayName: r.display_name, tagline: r.tagline || '', isOnline: r.is_online, status: !r.is_online ? 'offline' : r.manual_busy ? 'busy' : 'online', introUrl: r.intro_url, introStatus: r.intro_status, introNote: r.intro_note, bio: r.bio || '', languages: r.languages, rateRupees: r.rate_per_min / 100,
    payoutShare: Number(r.payout_share), kyc: r.kyc, avatarUrl: r.avatar_url, avatarStatus: r.avatar_status, avatarNote: r.avatar_note, allLanguages: LANGUAGES, minRate: MIN_RATE, maxRate: MAX_RATE,
  });
});

// Today's online time against the daily minimum (shown in the partner app)
router.get('/online-today', requireAuth(['partner']), async (req, res) => {
  res.json(await require('./onlinetime').today(req.auth.id));
});

router.put('/me', requireAuth(['partner']), async (req, res) => {
  const name = String(req.body.displayName || '').trim();
  const bio = String(req.body.bio || '').trim();
  const tagline = String(req.body.tagline || '').trim();
  const langs = Array.isArray(req.body.languages) ? [...new Set(req.body.languages)] : [];
  const rate = Number(req.body.rateRupees);
  const bad = (m) => res.status(400).json({ error: m });

  if (name.length < 2 || name.length > 30) return bad('Name must be 2 to 30 characters');
  if (bio.length > 300) return bad('Bio can be up to 300 characters');
  if (tagline.length > 40) return bad('Tagline can be up to 40 characters');
  if (LEAKS.test(name) || LEAKS.test(bio) || LEAKS.test(tagline)) return bad('Please remove phone numbers, links and social handles');
  if (!langs.length || langs.length > 5 || langs.some((l) => !LANGUAGES.includes(l))) return bad('Choose 1 to 5 languages');
  // the call price is fixed for everyone (see billing.js), so the rate sent by the app is ignored

  await pool.query('UPDATE accounts SET display_name=$1 WHERE id=$2', [name, req.auth.id]);
  await pool.query('UPDATE partner_profiles SET bio=$1, languages=$2, tagline=$3 WHERE account_id=$4',
    [bio || null, langs, tagline || null, req.auth.id]);
  res.json({ ok: true });
});

// Partner toggles availability (partner app)
router.post('/online', requireAuth(['partner']), async (req, res) => {
  // status: 'online' | 'busy' (listed but not taking calls) | 'offline'. Older app versions send { online: bool }.
  const status = ['online', 'busy', 'offline'].includes(req.body.status) ? req.body.status : (req.body.online ? 'online' : 'offline');
  const on = status !== 'offline';
  const { rows } = await pool.query('SELECT kyc, languages FROM partner_profiles WHERE account_id=$1', [req.auth.id]);
  if (on && rows[0]?.kyc !== 'approved') return res.status(403).json({ error: 'Verification pending. Open Verification (KYC) to submit your documents.' });
  if (on && !(await contract.isSigned(req.auth.id))) return res.status(403).json({ error: 'Please sign the partner agreement first (Home screen).', code: 'contract_required' });
  if (on && !rows[0].languages.length) return res.status(400).json({ error: 'Complete your profile (languages) before going online' });

  await pool.query('UPDATE partner_profiles SET is_online=$1, manual_busy=$2 WHERE account_id=$3', [on, status === 'busy', req.auth.id]);
  if (status === 'online') await redis.sadd('partners:online', req.auth.id);
  else await redis.srem('partners:online', req.auth.id);
  res.json({ online: on, status });
  if (status === 'online') {
    // Tell users this host is online, at most once every 30 minutes per host (so toggling does not spam anyone)
    try { // best friends get their own alert (own 30-minute limit per host)
      if (await redis.set(`bfnotif:${req.auth.id}`, '1', 'EX', 1800, 'NX')) {
        const name = (await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0]?.display_name;
        push.notifyBestFriendsOnline(req.auth.id, name).catch((e) => console.error('[push] best-friend-online:', e.message));
      }
    } catch (e) { console.error('[push] best-friend-online:', e.message); }
    try {
      if (await redis.set(`hostnotif:${req.auth.id}`, '1', 'EX', 1800, 'NX')) {
        const name = (await pool.query('SELECT display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0]?.display_name;
        push.notifyHostOnline(req.auth.id, name).catch((e) => console.error('[push] host-online:', e.message));
      }
    } catch (e) { console.error('[push] host-online:', e.message); }
  }
});

// "Best friends" who are online right now: hosts this user has called before (answered or missed). Newest first.
router.get('/best-friends', requireAuth(['user']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.avatar_url, p.tagline, p.intro_url, p.bio, p.languages, p.rate_per_min, p.rating_avg, p.rating_count, p.manual_busy
       FROM (SELECT partner_id, MAX(created_at) AS last_called FROM calls
              WHERE user_id=$1 AND status IN ('ended','missed') GROUP BY partner_id) f
       JOIN partner_profiles p ON p.account_id = f.partner_id
       JOIN accounts a ON a.id = f.partner_id
      WHERE p.is_online AND p.kyc='approved' AND NOT a.is_blocked
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=a.id AND b.blocked_id=$1) OR (b.blocker_id=$1 AND b.blocked_id=a.id))
      ORDER BY f.last_called DESC LIMIT 5`, [req.auth.id]);
  const busy = await Promise.all(rows.map((r) => redis.exists(`partner:busy:${r.id}`)));
  res.json(rows.map((r, i) => ({ ...r, busy: !!busy[i] || r.manual_busy, verified: true })));
});

// Browse partners (user app). Never returns phone numbers. By default only online hosts; ?all=1 also lists busy and offline hosts
// with a status field ('online' | 'busy' | 'offline'), online first.
router.get('/', requireAuth(['user']), async (req, res) => {
  const lang = req.query.language;
  const all = req.query.all === '1';
  const q = String(req.query.q || '').trim().slice(0, 40).replace(/[%_\\]/g, '\\$&'); // search by name; escape LIKE wildcards
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.avatar_url, p.tagline, p.intro_url, p.bio, p.languages, p.rate_per_min, p.rating_avg, p.rating_count, p.is_online, p.manual_busy
       FROM partner_profiles p JOIN accounts a ON a.id = p.account_id
      WHERE ($4::boolean OR p.is_online) AND p.kyc='approved' AND NOT a.is_blocked AND a.deleted_at IS NULL
        AND ($1::text IS NULL OR $1 = ANY(p.languages))
        AND ($3::text IS NULL OR a.display_name ILIKE '%' || $3 || '%')
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=a.id AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=a.id))
      ORDER BY p.is_online DESC, p.rating_avg DESC LIMIT 100`,
    [lang || null, req.auth.id, q || null, all]);

  const inCall = await Promise.all(rows.map((r) => redis.exists(`partner:busy:${r.id}`)));
  const rank = { online: 0, busy: 1, offline: 2 };
  const out = rows.map((r, i) => {
    const status = !r.is_online ? 'offline' : (inCall[i] || r.manual_busy) ? 'busy' : 'online';
    const { is_online, manual_busy, ...rest } = r;
    return { ...rest, status, busy: status === 'busy', verified: true }; // only KYC-approved hosts are listed
  });
  out.sort((x, y) => rank[x.status] - rank[y.status]); // stable: rating order kept inside each group
  res.json(out);
});

module.exports = router;
