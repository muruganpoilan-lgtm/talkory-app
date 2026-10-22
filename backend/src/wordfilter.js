// Chat safety filter: blocks messages about illegal things, sexual solicitation and threats.
// A starter list. Add more words on the server with BANNED_WORDS="word one,word two" (comma separated), no code change needed.
const BUILTIN = [
  // drugs
  'ganja', 'charas', 'cocaine', 'heroin', 'mdma', 'lsd', 'brown sugar', 'smack', 'opium', 'afeem', 'drugs for sale', 'sell drugs', 'buy drugs',
  // weapons, violence, terror
  'buy gun', 'sell gun', 'illegal gun', 'katta', 'bomb', 'explosive', 'kill you', 'will kill', 'acid attack', 'terrorist', 'suicide bomb',
  // sexual solicitation and abuse
  'rape', 'child porn', 'cp video', 'underage', 'escort', 'call girl', 'sex for money', 'sex chat', 'nude pic', 'nude video', 'send nudes', 'sexting', 'one night stand', 'hookup',
  // fraud, hacking, trafficking
  'carding', 'stolen card', 'credit card dump', 'hack account', 'hacking service', 'fake passport', 'fake aadhaar', 'fake id', 'human trafficking', 'sell kidney', 'black money', 'hawala',
  // taking people off the app, money scams
  'send money', 'gift card', 'western union', 'investment scheme',
];
const extra = String(process.env.BANNED_WORDS || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
const LEET = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', $: 's', '!': 'i' };

// lower-case, undo common tricks (r@pe, k1ll, c o c a i n e), keep single spaces
function normalise(text) {
  let t = String(text || '').toLowerCase().replace(/[0134 57$!]/g, (c) => (c === ' ' ? ' ' : LEET[c]));
  t = t.replace(/[^a-z\s]/g, '').replace(/\s+/g, ' ').trim();
  return t;
}
const squash = (t) => t.replace(/ /g, '');

const words = [...new Set([...BUILTIN, ...extra])].map((w) => normalise(w)).filter(Boolean);

// Returns the matched word, or null when the message is fine.
function check(text) {
  const t = ` ${normalise(text)} `;
  const sq = squash(t);
  for (const w of words) {
    if (t.includes(` ${w} `)) return w; // whole word / phrase
    // spaced-out spelling like "c o c a i n e": only for words of 5+ letters, to avoid false hits
    if (w.length >= 5 && !w.includes(' ') && sq.includes(w) && !t.includes(w)) return w;
  }
  return null;
}

module.exports = { check, normalise };
