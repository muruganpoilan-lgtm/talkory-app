const crypto = require('crypto');
const { redis } = require('./db');

// DEV: codes are generated here and printed to the server log.
// MSG91: codes are generated here and sent as SMS by MSG91.
// PROD: Twilio Verify generates, sends (SMS) and checks the code, including expiry and its own abuse limits.
// MSG91 (India): we generate the code, MSG91 delivers the SMS with your DLT-approved OTP template (the ##OTP## variable).
// Used when MSG91_AUTH_KEY and MSG91_TEMPLATE_ID are set; otherwise Twilio Verify is used.
const DEV = process.env.OTP_DEV_MODE === 'true';
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex');
const msg91 = () => !!(process.env.MSG91_AUTH_KEY && process.env.MSG91_TEMPLATE_ID);
const local = () => DEV || msg91(); // codes checked here (Redis) instead of by Twilio

async function msg91Send(phone, code) {
  const q = new URLSearchParams({
    template_id: process.env.MSG91_TEMPLATE_ID,
    mobile: phone.replace(/^\+/, ''), // MSG91 wants the country code without the +
    otp: code,
    otp_expiry: '5',
  });
  const r = await fetch(`https://control.msg91.com/api/v5/otp?${q}`, {
    method: 'POST',
    headers: { authkey: process.env.MSG91_AUTH_KEY, 'Content-Type': 'application/json' },
    body: '{}',
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || data.type !== 'success') {
    console.error('[sms] MSG91 send failed:', r.status, data.type, data.message);
    throw new Error('sms_failed');
  }
}

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
  if (local()) {
    const code = (DEV && process.env.NODE_ENV !== 'production' && process.env.OTP_TEST_CODE) || String(crypto.randomInt(100000, 999999));
    await redis.set(`otp:${phone}`, hash(code), 'EX', 300);
    if (DEV) {
      console.log(`[DEV] OTP for ${phone}: ${code}`);
      return;
    }
    try {
      await msg91Send(phone, code);
    } catch (e) {
      await redis.del(`otp:${phone}`);
      throw e;
    }
    return;
  }
  const r = await twilio('/Verifications', { To: phone, Channel: 'sms' });
  if (!r.ok) {
    console.error('[sms] Twilio send failed:', r.status, r.data.code, r.data.message);
    throw new Error('sms_failed');
  }
}

async function checkOtp(phone, code) {
  if (local()) {
    const stored = await redis.get(`otp:${phone}`);
    if (!stored || stored !== hash(String(code))) return false;
    await redis.del(`otp:${phone}`);
    return true;
  }
  const r = await twilio('/VerificationCheck', { To: phone, Code: String(code) });
  return r.ok && r.data.status === 'approved'; // expired / unknown / wrong code all come back as not approved
}

module.exports = { sendOtp, checkOtp };
