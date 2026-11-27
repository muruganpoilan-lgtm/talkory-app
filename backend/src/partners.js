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

// Indian girls' names, first name and second name (like Priya Kumari), that hosts can tap instead of typing a name.
// Second names are common name endings (Devi, Selvi, Kumari...), never family surnames, so hosts stay anonymous.
// Kept on the server so the list can change without an app update. Names already used by a host are never offered.
const NICKNAMES = [
  'Priya Kumari', 'Rani Selvi', 'Anbu Selvi', 'Thamarai Selvi', 'Kayal Vizhi', 'Ponmalar Selvi', 'Nila Rani', 'Malar Kodi',
  'Muthu Selvi', 'Kalai Rani', 'Rani Devi', 'Sujatha Rani', 'Harini Priya', 'Rahini Malar', 'Yazhini Lakshmi', 'Thenmozhi Mathi',
  'Kayal Selvi', 'Mullai Devi', 'Ilakkiya Kumari', 'Selvi Rani', 'Poonguzhali Priya', 'Aruvi Malar', 'Vennila Lakshmi', 'Kanmani Mathi',
  'Nila Devi', 'Ezhil Kumari', 'Pavai Rani', 'Oviya Priya', 'Iniya Malar', 'Nandhini Lakshmi', 'Malar Mathi', 'Poovizhi Selvi',
  'Tamilselvi Devi', 'Meenal Kumari', 'Janani Rani', 'Keerthi Priya', 'Abirami Malar', 'Bhuvana Lakshmi', 'Deepa Mathi', 'Dhanya Selvi',
  'Gayathri Devi', 'Indhu Kumari', 'Jothi Rani', 'Kalai Priya', 'Lakshmi Malar', 'Maheswari Lakshmi', 'Nithya Mathi', 'Pavithra Selvi',
  'Revathi Devi', 'Sandhya Kumari', 'Thara Rani', 'Uma Priya', 'Vidhya Malar', 'Yamini Lakshmi', 'Anitha Mathi', 'Kavitha Selvi',
  'Sangeetha Devi', 'Vasanthi Kumari', 'Shanthi Rani', 'Sumathi Priya', 'Geetha Malar', 'Mala Lakshmi', 'Valli Mathi', 'Kamala Selvi',
  'Saroja Devi', 'Padma Kumari', 'Latha Rani', 'Radha Priya', 'Rukmini Malar', 'Sarasu Lakshmi', 'Chitra Mathi', 'Banu Selvi',
  'Amudha Devi', 'Sudha Kumari', 'Malathi Rani', 'Vijaya Priya', 'Kalyani Malar', 'Vimala Lakshmi', 'Jeya Mathi', 'Jeyanthi Selvi',
  'Suganya Devi', 'Sowmya Kumari', 'Ramya Rani', 'Divya Priya', 'Swathi Malar', 'Sindhu Lakshmi', 'Kanchana Mathi', 'Prema Selvi',
  'Pushpa Devi', 'Hema Kumari', 'Mythili Rani', 'Sharmila Priya', 'Sathya Malar', 'Rajeswari Lakshmi', 'Muthulakshmi Mathi', 'Parvathi Selvi',
  'Meenakshi Devi', 'Kamakshi Kumari', 'Visalakshi Rani', 'Annapoorani Priya', 'Selvarani Malar', 'Jayanthi Lakshmi', 'Bharathi Mathi', 'Kalaivani Selvi',
  'Thilaga Devi', 'Pooja Kumari', 'Brindha Kumari', 'Arthi Rani', 'Aarthi Priya', 'Sasikala Malar', 'Shalini Lakshmi', 'Nirmala Mathi',
  'Shobana Selvi', 'Usha Devi', 'Kowsalya Kumari', 'Lalitha Rani', 'Vanitha Priya', 'Vanathi Malar', 'Nalini Lakshmi', 'Vasuki Mathi',
  'Kokila Selvi', 'Kuyil Devi', 'Mayil Kumari', 'Thendral Rani', 'Mathi Priya', 'Ilavarasi Malar', 'Anbarasi Lakshmi', 'Kayalvizhi Mathi',
  'Kalaiselvi Devi', 'Mangai Devi', 'Ponni Kumari', 'Seetha Rani', 'Sarala Priya', 'Sasirekha Malar', 'Akila Lakshmi', 'Akshaya Mathi',
  'Archana Selvi', 'Bhavani Devi', 'Dharani Kumari', 'Gowri Rani', 'Hemalatha Priya', 'Jayashree Malar', 'Kiruthika Lakshmi', 'Lavanya Mathi',
  'Logeshwari Selvi', 'Madhumitha Devi', 'Monika Kumari', 'Nivetha Rani', 'Priyanka Malar', 'Ranjani Malar', 'Ranjitha Lakshmi', 'Saranya Mathi',
  'Sathyapriya Selvi', 'Sowndarya Devi', 'Subhashini Kumari', 'Sujitha Rani', 'Swetha Priya', 'Thanuja Malar', 'Vaishnavi Lakshmi', 'Varsha Mathi',
  'Vinodhini Selvi', 'Yogeshwari Devi', 'Roja Kumari', 'Malli Rani', 'Senthamarai Priya', 'Kaveri Malar', 'Vaigai Lakshmi', 'Tamarai Mathi',
  'Mangalam Selvi', 'Ponmani Devi', 'Thangam Kumari', 'Muthu Rani', 'Kanaga Priya', 'Sornam Malar', 'Vairam Lakshmi', 'Maragatham Mathi',
  'Pavazham Selvi', 'Nilavu Devi', 'Tharani Kumari', 'Vanmathi Rani', 'Kanimozhi Priya', 'Elakkiya Malar', 'Inbavalli Lakshmi', 'Azhagi Mathi',
  'Sundari Selvi', 'Anjali Devi', 'Mohana Kumari', 'Vasantha Rani', 'Nagalakshmi Priya', 'Seethalakshmi Malar', 'Kavya Lakshmi', 'Sneha Devi',
  'Shruthi Mathi', 'Keerthana Selvi', 'Haritha Devi', 'Sahana Kumari', 'Nandhitha Rani', 'Pranitha Priya', 'Shwetha Devi', 'Varshini Malar',
  'Dharshini Lakshmi', 'Sanjana Mathi', 'Mahalakshmi Selvi', 'Gomathi Devi', 'Kasthuri Kumari', 'Rajalakshmi Rani', 'Shenbagam Priya', 'Valarmathi Malar',
  'Ilamathi Lakshmi', 'Poongodi Mathi', 'Pongodi Selvi', 'Arasi Devi', 'Nachiyar Kumari', 'Andal Rani', 'Aandal Priya', 'Kothai Malar',
  'Vasugi Lakshmi', 'Yamuna Mathi', 'Ganga Selvi', 'Kalpana Devi', 'Gnanam Kumari', 'Ammu Devi', 'Anju Lakshmi', 'Athira Priya',
  'Aparna Kumari', 'Ashwathy Devi', 'Chinnu Lakshmi', 'Devika Priya', 'Gopika Kumari', 'Lakshmipriya Devi', 'Meenu Lakshmi', 'Neethu Priya',
  'Reshma Kumari', 'Sreelakshmi Devi', 'Sreeja Lakshmi', 'Sruthi Priya', 'Anagha Kumari', 'Nimisha Devi', 'Parvathy Lakshmi', 'Unnimaya Priya',
  'Malavika Kumari', 'Revathy Devi', 'Anupama Lakshmi', 'Keerthy Priya', 'Nayana Kumari', 'Bhavana Lakshmi', 'Deepika Kumari', 'Spandana Priya',
  'Rashmi Rani', 'Shilpa Devi', 'Pallavi Lakshmi', 'Chaitra Kumari', 'Vidya Rani', 'Kavana Priya', 'Kruthika Rani', 'Akshatha Devi',
  'Varalakshmi Kumari', 'Vani Kumari', 'Navya Priya', 'Shravya Priya', 'Tejaswini Rani', 'Harika Devi', 'Mounika Lakshmi', 'Sravani Kumari',
  'Sirisha Priya', 'Lahari Rani', 'Bindu Devi', 'Madhavi Lakshmi', 'Sailaja Kumari', 'Padmaja Priya', 'Annapurna Rani', 'Sowjanya Devi',
  'Swapna Lakshmi', 'Vaani Kumari', 'Anushka Kumari', 'Ananya Devi', 'Aishwarya Rani', 'Kajal Priya', 'Neha Kumari', 'Riya Devi',
  'Sapna Rani', 'Kiran Priya', 'Komal Kumari', 'Mansi Devi', 'Nikita Rani', 'Payal Priya', 'Pinky Kumari', 'Preeti Devi',
  'Rekha Rani', 'Reena Priya', 'Ritu Kumari', 'Ruchi Devi', 'Seema Rani', 'Sonia Priya', 'Suman Kumari', 'Sunita Devi',
  'Shweta Rani', 'Tanvi Priya', 'Vandana Kumari', 'Jyoti Devi', 'Kusum Rani', 'Meena Priya', 'Neelam Kumari', 'Poonam Devi',
  'Rachna Rani', 'Rajni Priya', 'Renu Kumari', 'Sarita Devi', 'Savita Rani', 'Shobha Priya', 'Sushma Kumari', 'Asha Devi',
  'Nisha Rani', 'Isha Priya', 'Diya Kumari', 'Tara Devi', 'Meera Rani', 'Gauri Priya', 'Roshni Kumari', 'Sitara Devi',
  'Disha Rani', 'Heena Priya', 'Jhanvi Kumari', 'Geeta Devi', 'Lata Rani', 'Rupa Priya', 'Zoya Kumari', 'Aisha Devi',
  'Shreya Rani', 'Ishita Priya', 'Bhavya Kumari', 'Avni Devi', 'Saanvi Rani', 'Trisha Priya', 'Veda Kumari', 'Mahi Devi',
  'Naina Rani', 'Kiara Priya', 'Rhea Kumari', 'Anika Devi', 'Aadhya Rani', 'Advika Priya', 'Avantika Kumari', 'Charvi Devi',
  'Hansika Rani', 'Prisha Priya', 'Ahana Kumari', 'Myra Devi', 'Aarohi Rani', 'Anaya Priya', 'Siya Kumari',
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
