const router = require('express').Router();
const { pool, redis, requireAuth } = require('./db');
const push = require('./push');
const contract = require('./contract');
const tier = require('./tier');
const { profanity, tooManyDigits, hasEmail } = require('./wordfilter');
const billing = require('./billing');
const slots = require('./slots');
// the per-minute price this user pays (VIP users see their cheaper price on every host card)
const priceFor = async (userId) => billing.rateFor({ is_vip: await billing.isVip(userId) });

const LANGUAGES = ['Hindi', 'English', 'Tamil', 'Telugu', 'Bengali', 'Marathi', 'Odia', 'Bhojpuri', 'Malayalam', 'Kannada', 'Gujarati', 'Punjabi', 'Urdu', 'Assamese']; // keep in sync with kLanguages in talkory_core/api.dart
const MIN_RATE = 5, MAX_RATE = 200; // rupees per minute
// Keep contact details out of public profiles: phone numbers, handles, links
const LEAKS = /(\+?\d[\d\s-]{6,}\d|@|https?:|www\.)/i;

// Tamil girls' names (first name only, like most hosts on the app) that hosts can tap instead of typing a name.
// No family names, so hosts stay anonymous. Kept on the server so the list can change without an app update.
// Names already used by a host are never offered.
const NICKNAMES = [
  'Aadhira', 'Aaradhana', 'Aarthi', 'Abinaya', 'Abirami', 'Akshaya', 'Amudha', 'Amudhavalli', 'Anbarasi', 'Anbuselvi',
  'Anjugam', 'Anusha', 'Aparnaa', 'Archana', 'Arivumathi', 'Aruvi', 'Aruna', 'Arulmozhi', 'Arulselvi', 'Ashwini',
  'Azhagammai', 'Azhagi', 'Bharathi', 'Bhavani', 'Bhuvana', 'Bhuvaneswari', 'Chandra', 'Chandrika', 'Chellam', 'Chitra',
  'Deepa', 'Deepika', 'Dhanalakshmi', 'Dhanya', 'Dharani', 'Dharshini', 'Divya', 'Durga', 'Elakkiya', 'Elavarasi',
  'Ezhilarasi', 'Ezhilmathi', 'Gayathri', 'Geetha', 'Gomathi', 'Gowri', 'Hamsini', 'Harini', 'Hemalatha', 'Ilakkiya',
  'Ilamathi', 'Ilavarasi', 'Ilavenil', 'Indhu', 'Indhumathi', 'Inbavalli', 'Iniya', 'Isaivani', 'Jananee', 'Janani',
  'Jayalakshmi', 'Jayanthi', 'Jeeva', 'Jothi', 'Kalaivani', 'Kalaiselvi', 'Kalpana', 'Kamala', 'Kanaga', 'Kaniha',
  'Kanimozhi', 'Kanmani', 'Kanchana', 'Karthika', 'Kasthuri', 'Kaveri', 'Kavi', 'Kavibharathi', 'Kavimathi', 'Kavitha',
  'Kavya', 'Kayalvizhi', 'Keerthana', 'Keerthi', 'Kokila', 'Kousalya', 'Krithika', 'Kumudha', 'Lakshana', 'Lakshmi',
  'Latha', 'Leela', 'Lavanya', 'Madhumitha', 'Mahalakshmi', 'Maheswari', 'Malar', 'Malarkodi', 'Malarvizhi', 'Malathi',
  'Mangai', 'Manimegalai', 'Manjula', 'Mathivadhani', 'Mathumitha', 'Meena', 'Meenakshi', 'Meenal', 'Megala', 'Mohana',
  'Mounika', 'Mullai', 'Muthulakshmi', 'Muthuselvi', 'Nalini', 'Nandhini', 'Nagalakshmi', 'Narmadha', 'Nila', 'Nilavazhagi',
  'Nirmala', 'Nithya', 'Nivetha', 'Oviya', 'Padma', 'Padmini', 'Parimala', 'Pavai', 'Pavithra', 'Poongodi',
  'Poonguzhali', 'Poorani', 'Poovizhi', 'Ponmalar', 'Ponni', 'Prabha', 'Preethi', 'Priyadharshini', 'Punitha', 'Radha',
  'Radhika', 'Rajeswari', 'Rajalakshmi', 'Ramya', 'Rasathi', 'Rathi', 'Renuka', 'Revathi', 'Roja', 'Rukmani',
  'Sakthi', 'Sangeetha', 'Santhiya', 'Saranya', 'Sarasu', 'Sasikala', 'Selvi', 'Senthamarai', 'Shenbagam', 'Sindhu',
  'Sivagami', 'Sivaranjani', 'Sneha', 'Sowmya', 'Sridevi', 'Srimathi', 'Subbulakshmi', 'Sudha', 'Sumathi', 'Surya',
  'Swathi', 'Tamilselvi', 'Tamilini', 'Thamarai', 'Thangam', 'Thara', 'Thenmozhi', 'Thilaga', 'Thirumagal', 'Uma',
  'Umamaheswari', 'Usha', 'Vaishnavi', 'Valarmathi', 'Vanathi', 'Vani', 'Vanmathi', 'Varsha', 'Vasanthi', 'Vasuki',
  'Vennila', 'Vidhya', 'Vijaya', 'Vimala', 'Vinitha', 'Yamuna', 'Yazhini', 'Yogeswari', 'Agalya', 'Akila',
  'Ambiga', 'Amirtha', 'Anandhi', 'Anitha', 'Annam', 'Arasi', 'Arthi', 'Bavithra', 'Chellammal', 'Devayani',
  'Ezhil', 'Gnanam', 'Hema', 'Jamuna', 'Janaki', 'Jansi', 'Kalai', 'Kamatchi', 'Kannagi', 'Karpagam',
  'Kayal', 'Kothai', 'Kuyil', 'Madhavi', 'Mallika', 'Mangalam', 'Maragatham', 'Menaka', 'Mythili', 'Nachiyar',
  'Nanthini', 'Nilakshi', 'Pachaiyammal', 'Pavazham', 'Ponmani', 'Pushpa', 'Rani', 'Saroja', 'Seetha', 'Shanthi',
  'Sornam', 'Subha', 'Sugantha', 'Sundari', 'Thenral', 'Valli', 'Vedhavalli', 'Velammal', 'Vijayalakshmi', 'Aathmika',
  'Aazhi', 'Adhirai', 'Agarathi', 'Amuthini', 'Anbumozhi', 'Ilampirai', 'Inisai', 'Isai', 'Kaarthiyayini', 'Kayalini',
  'Kirthika', 'Mahizhini', 'Mathangi', 'Mazhai', 'Mithra', 'Mugilini', 'Naveena', 'Nilaa', 'Oviyaa', 'Pavalakodi',
  'Pirai', 'Poomagal', 'Pozhil', 'Saralmozhi', 'Semmozhi', 'Sinthuja', 'Tharshini', 'Thenu', 'Thiviya', 'Vaigai',
  'Vaishali', 'Velvizhi', 'Yalini', 'Yazhmozhi', 'Aalini', 'Ilaya', 'Iniyaval', 'Mathi', 'Mugil', 'Nilavu',
  'Pooja', 'Sahana', 'Samyuktha', 'Shanvika', 'Srinidhi', 'Thenmathi', 'Vijayashri', 'Malvika', 'Akshara', 'Bhagya',
  'Chinmayi', 'Dhivya', 'Gopika', 'Jaya', 'Kalyani', 'Lalitha', 'Nandhana', 'Pranavi', 'Rakshana', 'Sabitha',
  'Sathya', 'Shalini', 'Sharmila', 'Sheela', 'Shobana', 'Suganya', 'Thulasi', 'Vasantha',
];

// True when another host already uses this name (not case sensitive)
async function nameTaken(name, exceptId) {
  const { rows } = await pool.query(
    `SELECT 1 FROM accounts WHERE role='partner' AND deleted_at IS NULL AND lower(display_name)=lower($1) AND ($2::uuid IS NULL OR id<>$2::uuid) LIMIT 1`,
    [name, exceptId || null]);
  return rows.length > 0;
}

// Nickname suggestions that nobody uses yet. Public, because new hosts need it while signing up.
router.get('/nickname-suggestions', async (req, res) => {
  const { rows } = await pool.query(`SELECT lower(display_name) AS n FROM accounts WHERE role='partner' AND deleted_at IS NULL`);
  const used = new Set(rows.map((r) => r.n));
  const free = NICKNAMES.filter((n) => !used.has(n.toLowerCase()));
  for (let i = free.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [free[i], free[j]] = [free[j], free[i]]; }
  res.json(free.slice(0, 12));
});

router.get('/me', requireAuth(['partner']), async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.display_name, a.name_locked, a.avatar_url, p.avatar_status, p.avatar_note, p.tagline, p.is_online, p.manual_busy, p.intro_url, p.intro_status, p.intro_note, p.bio, p.languages, p.rate_per_min, p.payout_share, p.kyc
       FROM partner_profiles p JOIN accounts a ON a.id=p.account_id WHERE p.account_id=$1`, [req.auth.id]);
  const r = rows[0];
  res.json({
    displayName: r.display_name, nameLocked: r.name_locked === true, tagline: r.tagline || '', isOnline: r.is_online, status: !r.is_online ? 'offline' : r.manual_busy ? 'busy' : 'online', introUrl: r.intro_url, introStatus: r.intro_status, introNote: r.intro_note, bio: r.bio || '', languages: r.languages, rateRupees: r.rate_per_min / 100,
    payoutShare: Number(r.payout_share), kyc: r.kyc, avatarUrl: r.avatar_url, avatarStatus: r.avatar_status, avatarNote: r.avatar_note, allLanguages: LANGUAGES, minRate: MIN_RATE, maxRate: MAX_RATE,
  });
});

// The host app calls this every 20 s while it is open on screen. Online time only counts while this is fresh.
router.post('/heartbeat', requireAuth(['partner']), async (req, res) => {
  await redis.set(`partner:active:${req.auth.id}`, '1', 'EX', 75);
  res.json({ ok: true });
});

// Users who have the app open right now (for the host's "Users online" tab). Names only: no photo, no phone number.
const ONLINE_WINDOW_MS = 75 * 1000;
router.get('/online-users', requireAuth(['partner']), async (req, res) => {
  const me = (await pool.query(`SELECT 1 FROM partner_profiles WHERE account_id=$1 AND kyc='approved'`, [req.auth.id])).rowCount;
  if (!me) return res.json([]);
  await redis.zremrangebyscore('users:online', 0, Date.now() - 10 * 60 * 1000); // tidy up
  const ids = await redis.zrangebyscore('users:online', Date.now() - ONLINE_WINDOW_MS, '+inf');
  if (!ids.length) return res.json([]);
  // new_user = joined recently and no real call yet: the first host to call them can earn the new-user bonus (firstcall.js)
  const fc = require('./firstcall');
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name AS name,
            EXISTS (SELECT 1 FROM calls c WHERE c.user_id=a.id AND c.status IN ('ringing','active')) AS busy,
            ${fc.NEW_USER_SQL.replace('$1', '$3').replace('$2', '$4')} AS new_user
       FROM accounts a
      WHERE a.id = ANY($1::uuid[]) AND a.role='user' AND NOT a.is_blocked AND a.deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=a.id) OR (b.blocker_id=a.id AND b.blocked_id=$2))
      ORDER BY busy, new_user DESC, a.display_name LIMIT 100`, [ids, req.auth.id, String(fc.NEW_USER_DAYS), fc.MIN_SECONDS]);
  res.json(fc.offer().enabled ? rows : rows.map((r) => ({ ...r, new_user: false })));
});

// The new-user offer, for the card on the host's Home page
router.get('/first-call-offer', requireAuth(['partner']), (req, res) => res.json(require('./firstcall').offer()));

// Today's online time against the daily minimum (shown in the partner app)
router.get('/online-today', requireAuth(['partner']), async (req, res) => {
  res.json(await require('./onlinetime').today(req.auth.id));
});

// This week's hours on calls and the host's Paradise level (shown in the partner app)
// Weekly leaderboard: top hosts by talk time this week, plus this host's own place
router.get('/leaderboard', requireAuth(['partner']), async (req, res) => {
  res.json(await require('./hostgrowth').leaderboard(req.auth.id));
});

router.get('/weekly-tier', requireAuth(['partner']), async (req, res) => {
  res.json(await tier.weekly(req.auth.id));
});

router.put('/me', requireAuth(['partner']), async (req, res) => {
  // A host picks her name at sign-up and keeps it. Older apps still send one: it is ignored, not refused,
  // so the rest of her profile still saves.
  const locked = (await pool.query('SELECT name_locked, display_name FROM accounts WHERE id=$1', [req.auth.id])).rows[0];
  const name = locked.name_locked ? String(locked.display_name || '').trim() : String(req.body.displayName || '').trim();
  const bio = String(req.body.bio || '').trim();
  const tagline = String(req.body.tagline || '').trim();
  const langs = Array.isArray(req.body.languages) ? [...new Set(req.body.languages)] : [];
  const rate = Number(req.body.rateRupees);
  const bad = (m) => res.status(400).json({ error: m });

  if (name.length < 2 || name.length > 30) return bad('Name must be 2 to 30 characters');
  if (bio.length > 300) return bad('Bio can be up to 300 characters');
  if (tagline.length > 40) return bad('Tagline can be up to 40 characters');
  if (LEAKS.test(name) || LEAKS.test(bio) || LEAKS.test(tagline)) return bad('Please remove phone numbers, links and social handles');
  if (profanity(name) || profanity(bio) || profanity(tagline)) return bad('Please remove abusive words from your name, bio or tagline');
  if ([name, bio, tagline].some((x) => tooManyDigits(x) || hasEmail(x))) return bad('Phone numbers and emails are not allowed. Use up to 2 digits only.');
  if (!locked.name_locked && await nameTaken(name, req.auth.id)) return bad('That name is already taken. Please pick another one.');
  if (!langs.length || langs.length > 5 || langs.some((l) => !LANGUAGES.includes(l))) return bad('Choose 1 to 5 languages');
  // the call price is fixed for everyone (see billing.js), so the rate sent by the app is ignored

  if (!locked.name_locked) await pool.query('UPDATE accounts SET display_name=$1, name_locked=true WHERE id=$2', [name, req.auth.id]);
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
  if (status === 'online') { await redis.sadd('partners:online', req.auth.id); slots.offerNext(req.auth.id).catch(() => {}); } // back online: next booked user's turn
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
  const busy = await Promise.all(rows.map(async (r) => (await redis.exists(`partner:busy:${r.id}`)) || (await slots.heldForOther(r.id, req.auth.id))));
  const price = await priceFor(req.auth.id);
  res.json(rows.map((r, i) => ({ ...r, rate_per_min: price, busy: !!busy[i] || r.manual_busy, verified: true })));
});

// Browse partners (user app). Never returns phone numbers. By default only online hosts; ?all=1 also lists busy and offline hosts
// with a status field ('online' | 'busy' | 'offline'), online first.
router.get('/', requireAuth(['user']), async (req, res) => {
  const lang = req.query.language;
  const all = req.query.all === '1';
  const q = String(req.query.q || '').trim().slice(0, 40).replace(/[%_\\]/g, '\\$&'); // search by name; escape LIKE wildcards
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.avatar_url, p.tagline, p.intro_url, p.bio, p.languages, p.rate_per_min, p.rating_avg, p.rating_count, p.is_online, p.manual_busy,
            EXISTS (SELECT 1 FROM favourite_hosts f WHERE f.user_id=$2 AND f.host_id=a.id) AS favourite
       FROM partner_profiles p JOIN accounts a ON a.id = p.account_id
      WHERE ($4::boolean OR p.is_online) AND p.kyc='approved' AND NOT a.is_blocked AND a.deleted_at IS NULL
        AND ($1::text IS NULL OR $1 = ANY(p.languages))
        AND ($3::text IS NULL OR a.display_name ILIKE '%' || $3 || '%')
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=a.id AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=a.id))
      ORDER BY p.is_online DESC, p.rating_avg DESC LIMIT 100`,
    [lang || null, req.auth.id, q || null, all]);

  const inCall = await Promise.all(rows.map(async (r) => (await redis.exists(`partner:busy:${r.id}`)) || (await slots.heldForOther(r.id, req.auth.id)))); // on a call, or kept for a booked user
  const booked = await Promise.all(rows.map((r) => slots.position(r.id, req.auth.id)));
  const rank = { online: 0, busy: 1, offline: 2 };
  const price = await priceFor(req.auth.id);
  const out = rows.map((r, i) => {
    const status = !r.is_online ? 'offline' : (inCall[i] || r.manual_busy) ? 'busy' : 'online';
    const { is_online, manual_busy, ...rest } = r;
    return { ...rest, rate_per_min: price, status, busy: status === 'busy', booked: booked[i], verified: true }; // only KYC-approved hosts are listed
  });
  // online first, then busy, then offline; favourites first inside each group; rating order kept otherwise (stable sort)
  out.sort((x, y) => rank[x.status] - rank[y.status] || (y.favourite === true) - (x.favourite === true));
  res.json(out);
});

// Book next slot with a busy host: { on: true } joins the line, { on: false } leaves it. Answers your place in line.
router.post('/:id/book', requireAuth(['user']), async (req, res) => {
  if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  if (req.body.on === false) { await slots.leave(req.params.id, req.auth.id); return res.json({ position: null }); }
  const h = (await pool.query(`SELECT p.is_online FROM partner_profiles p JOIN accounts a ON a.id=p.account_id
    WHERE p.account_id=$1 AND p.kyc='approved' AND NOT a.is_blocked AND a.deleted_at IS NULL`, [req.params.id])).rows[0];
  if (!h) return res.status(404).json({ error: 'not found' });
  if (!h.is_online) return res.status(409).json({ error: 'This host is offline. Tap the heart to get an alert when they come online.' });
  try {
    const position = await slots.join(req.params.id, req.auth.id);
    await slots.offerNext(req.params.id); // in case the host is already free
    res.json({ position });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

// Heart button: mark or unmark a host as a favourite. { on: true | false }
router.post('/:id/favourite', requireAuth(['user']), async (req, res) => {
  if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  if (req.body.on === false) {
    await pool.query('DELETE FROM favourite_hosts WHERE user_id=$1 AND host_id=$2', [req.auth.id, req.params.id]);
    return res.json({ favourite: false });
  }
  const host = await pool.query(`SELECT 1 FROM accounts WHERE id=$1 AND role='partner' AND deleted_at IS NULL`, [req.params.id]);
  if (!host.rowCount) return res.status(404).json({ error: 'not found' });
  const n = (await pool.query('SELECT COUNT(*)::int AS n FROM favourite_hosts WHERE user_id=$1', [req.auth.id])).rows[0].n;
  if (n >= 50) return res.status(400).json({ error: 'You can have up to 50 favourites' });
  await pool.query('INSERT INTO favourite_hosts (user_id, host_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [req.auth.id, req.params.id]);
  res.json({ favourite: true });
});

module.exports = router;
module.exports.nameTaken = nameTaken;
