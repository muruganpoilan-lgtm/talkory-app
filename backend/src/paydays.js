// Pay days: the 10th, the 20th and the 30th of every month (the last day of February instead of the 30th).
const TZ = 'Asia/Kolkata';
const GST_PERCENT = Number(process.env.PAYOUT_GST_PERCENT ?? 18);

const pad = (n) => String(n).padStart(2, '0');
const lastDay = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate(); // m is 1..12
const thirtieth = (y, m) => Math.min(30, lastDay(y, m)); // February: 28 (29 in a leap year)
const isoOf = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;

// India date and hour right now (or for the given instant)
function ist(now = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23' })
    .formatToParts(now).map((x) => [x.type, x.value]));
  return { y: Number(p.year), m: Number(p.month), d: Number(p.day), h: Number(p.hour) };
}

// Pay days of one month as ISO dates
function monthDays(y, m) { return [isoOf(y, m, 10), isoOf(y, m, 20), isoOf(y, m, thirtieth(y, m))]; }

// The pay day a request made now belongs to. Requests made on a pay day before 6 pm India time are paid that same evening.
function nextPayOn(now = new Date()) {
  const t = ist(now);
  const today = isoOf(t.y, t.m, t.d);
  let y = t.y, m = t.m;
  for (let i = 0; i < 3; i++) {
    for (const day of monthDays(y, m)) {
      if (day > today || (day === today && t.h < 18)) return day;
    }
    m += 1;
    if (m > 12) { m = 1; y += 1; }
  }
}

const todayIso = (now = new Date()) => { const t = ist(now); return isoOf(t.y, t.m, t.d); };

// 18% (default) of the amount is taken out as GST; the host receives the rest. All in paise.
function split(grossPaise) {
  const gst = Math.round(Number(grossPaise) * GST_PERCENT / 100);
  return { gross: Number(grossPaise), gst, net: Number(grossPaise) - gst };
}

module.exports = { ist, nextPayOn, todayIso, split, monthDays, GST_PERCENT };
