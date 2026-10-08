const crypto = require('crypto');
const { redis } = require('./db');

// DEV: codes are generated here and printed to the server log.
// PROD: Twilio Verify generates, sends (SMS) and checks the code, including expiry and its own abuse limits.
const DEV = process.env.OTP_DEV_MODE === 'true';
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex');

async function twilio(path, params) {
  const base = `https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SID}`;
  const basic = Buffer.from(`${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
  const r = await fetch(base + path, {
    method: 'POST',
    headers: { Authorization: `Basic ${basic}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  return { ok: r.ok, status: r.status, data: await r.json().catch(() => ({})) };
}

async function sendOtp(phone) {
  if (DEV) {
    const code = (process.env.NODE_ENV !== 'production' && process.env.OTP_TEST_CODE) || String(crypto.randomInt(100000, 999999));
    await redis.set(`otp:${phone}`, hash(code), 'EX', 300);
    console.log(`[DEV] OTP for ${phone}: ${code}`);
    return;
  }
  const r = await twilio('/Verifications', { To: phone, Channel: 'sms' });
  if (!r.ok) {
    console.error('[sms] Twilio send failed:', r.status, r.data.code, r.data.message);
    throw new Error('sms_failed');
  }
}

async function checkOtp(phone, code) {
  if (DEV) {
    const stored = await redis.get(`otp:${phone}`);
    if (!stored || stored !== hash(String(code))) return false;
    await redis.del(`otp:${phone}`);
    return true;
  }
  const r = await twilio('/VerificationCheck', { To: phone, Code: String(code) });
  return r.ok && r.data.status === 'approved'; // expired / unknown / wrong code all come back as not approved
}

module.exports = { sendOtp, checkOtp };
