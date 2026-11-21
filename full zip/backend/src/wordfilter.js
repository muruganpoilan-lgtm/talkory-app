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

// ---- contact details: phone numbers (digits, other-script digits, spelled-out numbers) and "message me on ..." apps
const DIGIT_BASES = [0x660, 0x6f0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6, 0xd66, 0xff10];
const NUMBER_WORDS = {
  zero: 0, shunya: 0, sifar: 0, oh: 0,
  one: 1, ek: 1, onnu: 1, ondru: 1,
  two: 2, do: 2, rendu: 2, irandu: 2,
  three: 3, teen: 3, moonu: 3, moondru: 3,
  four: 4, char: 4, chaar: 4, naalu: 4, naangu: 4,
  five: 5, paanch: 5, panch: 5, anju: 5, ainthu: 5,
  six: 6, chhe: 6, che: 6, aaru: 6, aaru2: 6,
  seven: 7, saat: 7, saath: 7, yezhu: 7, ezhu: 7,
  eight: 8, aath: 8, aat: 8, ettu: 8, ettu2: 8,
  nine: 9, nau: 9, nav: 9, onbadhu: 9, ombathu: 9,
};
const CONTACT_PHRASES = ['whatsapp', 'whats app', 'watsapp', 'telegram', 'snapchat', 'instagram', 'insta id', 'facebook id', 'phone number', 'mobile number',
  'contact number', 'my number', 'your number', 'call me on', 'dm me', 'signal app'];

function toDigits(text) {
  let t = String(text || '').toLowerCase();
  // digits written in other scripts (Hindi, Tamil, Arabic ...) and full-width digits
  t = Array.from(t).map((ch) => {
    const cp = ch.codePointAt(0);
    for (const b of DIGIT_BASES) if (cp >= b && cp <= b + 9) return String(cp - b);
    return ch;
  }).join('');
  // spelled-out numbers: "nine eight seven ..." -> 987
  return t.replace(/[a-z]+/g, (w) => (w in NUMBER_WORDS ? String(NUMBER_WORDS[w]) : w));
}

function contactCheck(text) {
  const t = toDigits(text);
  // 8+ digits in a row, allowing spaces, dots, dashes, commas and similar between them
  const m = t.match(/(?:\d[^a-z0-9]{0,3}){8,}/);
  if (m && (m[0].match(/\d/g) || []).length >= 8) return 'phone number';
  const n = ` ${normalise(text).replace(/\d/g, '')} `;
  for (const ph of CONTACT_PHRASES) if (n.includes(` ${ph} `)) return ph;
  return null;
}

// Returns the matched word, or null when the message is fine.
function check(text) {
  const c = contactCheck(text);
  if (c) return c;
  const t = ` ${normalise(text)} `;
  const sq = squash(t);
  for (const w of words) {
    if (t.includes(` ${w} `)) return w; // whole word / phrase
    // spaced-out spelling like "c o c a i n e": only for words of 5+ letters, to avoid false hits
    if (w.length >= 5 && !w.includes(' ') && sq.includes(w) && !t.includes(w)) return w;
  }
  return null;
}

module.exports = { check, normalise, contactCheck };
