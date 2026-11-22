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

// ---- abusive / filthy words. Latin spellings (English and Indian languages typed in English letters) and native scripts.
// Short or common-looking words only match as a whole word, so normal words that contain them are not blocked.
const PROFANITY_LATIN = [
  // English
  'fuck', 'fucker', 'fucking', 'fucked', 'fuk', 'fck', 'fcuk', 'motherfucker', 'mf', 'wtf', 'shit', 'bullshit', 'bitch', 'bitches', 'bastard',
  'asshole', 'arsehole', 'dick', 'dickhead', 'cock', 'cunt', 'pussy', 'whore', 'slut', 'prick', 'wanker', 'twat', 'son of a bitch',
  'blowjob', 'handjob', 'dildo', 'cum', 'jerk off', 'boobs', 'tits', 'horny', 'porn', 'nigger', 'nigga', 'faggot', 'fag', 'retard',
  // Hindi / Urdu
  'madarchod', 'maderchod', 'madarchood', 'behenchod', 'bhenchod', 'benchod', 'bhenchodd', 'mc', 'bc', 'bsdk', 'chutiya', 'chutiye', 'chutia',
  'chut', 'choot', 'lund', 'lauda', 'lawda', 'lavda', 'loda', 'gandu', 'gaandu', 'gaand', 'gand', 'randi', 'raand', 'harami', 'haramkhor',
  'bhosdike', 'bhosadike', 'bhosdi', 'bhosda', 'bhosdiwale', 'jhaat', 'jhatu', 'chodu', 'chod', 'kutiya', 'kamina', 'kamine', 'tatti', 'suar ki aulad',
  // Tamil
  'thevidiya', 'thevdiya', 'thevidiyal', 'thevidiya paiya', 'thevdiya paiya', 'thayoli', 'thaayoli', 'otha', 'ottha', 'ommala', 'oombu', 'oombhu',
  'umbu', 'punda', 'pundai', 'koothi', 'kudhi', 'sootha', 'soothu', 'mayiru', 'mairu', 'okkala', 'pottai', 'kena koothi', 'loosu punda',
  // Malayalam
  'myre', 'myru', 'myran', 'mairan', 'poorimon', 'poori mone', 'pooru', 'kunna', 'kunne', 'thendi', 'pulayadi', 'pulayadi mone',
  'naayinte mone', 'kandaroli', 'umbi',
  // Kannada
  'soole', 'sulemaga', 'soolemaga', 'sule maga', 'bolimaga', 'boli maga', 'bolimagne', 'tunne', 'tullu', 'ninamman', 'ninn amman',
  // Telugu
  'dengu', 'dengey', 'dengutha', 'lanja', 'lanjakoduku', 'lanja koduku', 'lanjakodaka', 'lanja kodaka', 'modda', 'puku', 'pooku', 'kojja',
  // Bengali / Marathi
  'khanki', 'khankir chele', 'bokachoda', 'chudir bhai', 'zavadya', 'aai zavadya', 'bhadkhau', 'lavdya', 'randichya',
];
const PROFANITY_NATIVE = [
  // Hindi
  'मादरचोद', 'मादरचोड', 'बहनचोद', 'भेनचोद', 'बहनचोद', 'चूतिया', 'चुतिया', 'चूत', 'लंड', 'लौड़ा', 'लौडा', 'लोड़ा', 'गांडू', 'गांड', 'गाँड', 'रंडी', 'हरामी',
  'हरामखोर', 'भोसड़ी', 'भोसडी', 'भोसड़ीके', 'भोसडीके', 'कुतिया', 'झाट', 'चोद', 'कमीना',
  // Tamil
  'தேவடியா', 'தேவிடியா', 'தேவுடியா', 'தாயோளி', 'ஓத்தா', 'ஓம்மால', 'ஊம்பு', 'புண்டை', 'புண்ட', 'சுன்னி', 'கூதி', 'மயிரு', 'சூத்து', 'பூல்', 'ஒக்கால',
  // Malayalam
  'മൈര്', 'മൈരേ', 'മൈരൻ', 'പൂറി', 'പൂറിമോൻ', 'പൂറ്', 'കുണ്ണ', 'തായോളി', 'തെണ്ടി', 'പുലയാടി', 'നായിന്റെ മോൻ', 'കണ്ടാരോളി',
  // Kannada
  'ಸೂಳೆ', 'ಸೂಳೆಮಗ', 'ಬೋಳಿಮಗ', 'ಬೋಳಿಮಗನೆ', 'ತುಣ್ಣೆ', 'ತುಲ್ಲು', 'ಸೂಳೆಮಗನೆ',
  // Telugu
  'దెంగు', 'దెంగెయ్', 'లంజ', 'లంజకొడుకు', 'మొడ్డ', 'పూకు', 'కొజ్జా',
  // Bengali / Marathi
  'খানকি', 'চোদ', 'মাগী', 'বোকাচোদা', 'झवाड्या', 'भडखाऊ',
];
const extraProfanity = String(process.env.BANNED_ABUSE || '').split(',').map((s) => s.trim()).filter(Boolean);
const isLatin = (w) => /^[\x00-\x7f]+$/.test(w);
const profLatin = [...new Set([...PROFANITY_LATIN, ...extraProfanity.filter(isLatin)])].map((w) => normalise(w)).filter(Boolean);
const profNative = [...new Set([...PROFANITY_NATIVE, ...extraProfanity.filter((w) => !isLatin(w))])].map((w) => w.normalize('NFC').toLowerCase());
const INVISIBLE = /[­​-‏⁠﻿]/g; // zero-width characters people insert to slip past filters
const shorten = (t) => t.replace(/([a-z])\1{2,}/g, '$1'); // "fuuuuck" -> "fuck"

// Returns the abusive word found, or null.
function profanity(text) {
  const raw = String(text || '').normalize('NFC').toLowerCase().replace(INVISIBLE, '');
  const tokens = raw.split(/[\s.,!?;:'"()\[\]{}<>\/\\|*_~`+=\-]+/).filter(Boolean);
  for (const w of profNative) {
    if (w.includes(' ') ? raw.includes(w) : tokens.some((tk) => tk === w || (w.length >= 5 && tk.startsWith(w)))) return w;
  }
  const t = ` ${normalise(raw)} `, ts = ` ${shorten(t.trim())} `, sq = squash(t);
  for (const w of profLatin) {
    if (t.includes(` ${w} `) || ts.includes(` ${w} `)) return w;
    if (w.length >= 5 && !w.includes(' ') && sq.includes(w) && !t.includes(w)) return w; // spaced out: "f u c k e r"
  }
  return null;
}

// Returns the matched word, or null when the message is fine.
function check(text) {
  const c = contactCheck(text);
  if (c) return c;
  const p = profanity(text);
  if (p) return p;
  const t = ` ${normalise(text)} `;
  const sq = squash(t);
  for (const w of words) {
    if (t.includes(` ${w} `)) return w; // whole word / phrase
    // spaced-out spelling like "c o c a i n e": only for words of 5+ letters, to avoid false hits
    if (w.length >= 5 && !w.includes(' ') && sq.includes(w) && !t.includes(w)) return w;
  }
  return null;
}

module.exports = { check, normalise, contactCheck, profanity };
