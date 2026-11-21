const crypto = require('crypto');
const router = require('express').Router();
const { pool, redis, signToken } = require('./db');
const sms = require('./sms');

// Bump this (or set TERMS_VERSION) whenever the Terms/Privacy text changes: everyone must accept again at next login
const TERMS_VERSION = process.env.TERMS_VERSION || '2026-10-03';
const E164 = /^\+\d{8,15}$/;
const hashToken = (t) => crypto.createHash('sha256').update(String(t)).digest('hex');

// 1) Request OTP (rate-limited: 1 per 30s, 5 attempts)
router.post('/request-otp', async (req, res) => {
  const { phone } = req.body;
  if (!E164.test(phone || '')) return res.status(400).json({ error: 'Enter your number with country code, e.g. +919876543210' });
  if (!(await redis.set(`otp:cool:${phone}`, 1, 'EX', 30, 'NX')))
    return res.status(429).json({ error: 'wait before retrying' });

  try {
    await sms.sendOtp(phone);
  } catch {
    await redis.del(`otp:cool:${phone}`); // let them retry straight away
    return res.status(502).json({ error: 'Could not send the OTP. Please try again.' });
  }
  await redis.del(`otp:tries:${phone}`);
  res.json({ ok: true });
});

// 2) Verify OTP and log in / sign up
router.post('/verify-otp', async (req, res) => {
  const { phone, code, role = 'user', displayName, isAdult, acceptedTerms } = req.body;
  if (!['user', 'partner', 'admin'].includes(role)) return res.status(400).json({ error: 'invalid role' });

  if (!E164.test(phone || '')) return res.status(400).json({ error: 'invalid phone' });
  const tries = await redis.incr(`otp:tries:${phone}`);
  await redis.expire(`otp:tries:${phone}`, 600);
  if (tries > 5) return res.status(429).json({ error: 'too many attempts' });

  if (!(await sms.checkOtp(phone, code))) return res.status(401).json({ error: 'invalid code' });

  let { rows } = await pool.query('SELECT * FROM accounts WHERE phone=$1', [phone]);
  let acc = rows[0];

  if (!acc) {
    if (role === 'admin') return res.status(403).json({ error: 'admin accounts are created manually' });
    if (!isAdult) return res.status(400).json({ error: 'must confirm 18+' });
    if (!acceptedTerms) return res.status(400).json({ error: 'Please accept the Terms and Privacy Policy' });
    if (!displayName) return res.status(400).json({ error: 'displayName required' });
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      acc = (await client.query(
        'INSERT INTO accounts (role, phone, display_name, is_adult, terms_version, terms_accepted_at) VALUES ($1,$2,$3,TRUE,$4,now()) RETURNING *',
        [role, phone, displayName, TERMS_VERSION])).rows[0];
      await client.query('INSERT INTO wallets (account_id) VALUES ($1)', [acc.id]);
      if (role === 'partner')
        await client.query('INSERT INTO partner_profiles (account_id, rate_per_min) VALUES ($1, 1000)', [acc.id]);
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } else if (acc.role !== role) {
    return res.status(403).json({ error: `this number is registered as ${acc.role}` });
  }
  if (acc.is_blocked) return res.status(403).json({ error: 'account blocked' });
  if (acc.role !== 'admin' && acc.terms_version !== TERMS_VERSION) { // returning user, text changed (or pre-dates this feature)
    if (!acceptedTerms) return res.status(400).json({ error: 'Please accept the updated Terms and Privacy Policy' });
    await pool.query('UPDATE accounts SET terms_version=$1, terms_accepted_at=now() WHERE id=$2', [TERMS_VERSION, acc.id]);
  }

  // Remember this phone: next time it can log in without an OTP (not for admins)
  let deviceToken = null;
  if (acc.role !== 'admin') {
    deviceToken = crypto.randomBytes(32).toString('hex');
    await pool.query('INSERT INTO trusted_devices (account_id, token_hash) VALUES ($1,$2)', [acc.id, hashToken(deviceToken)]);
    await pool.query(
      `DELETE FROM trusted_devices WHERE account_id=$1 AND id NOT IN
         (SELECT id FROM trusted_devices WHERE account_id=$1 ORDER BY last_used_at DESC LIMIT 5)`, [acc.id]); // keep the 5 newest phones
  }
  res.json({ token: signToken(acc), deviceToken, account: { id: acc.id, role: acc.role, displayName: acc.display_name } });
});

// 3) Log in on a remembered phone: no OTP. Anything unusual answers "otp_required" and the app falls back to the OTP.
router.post('/device-login', async (req, res) => {
  const { phone, deviceToken, role = 'user' } = req.body;
  const needOtp = () => res.status(401).json({ error: 'otp_required' });
  if (!E164.test(phone || '') || typeof deviceToken !== 'string' || deviceToken.length !== 64 || !['user', 'partner'].includes(role)) return needOtp();
  const tries = await redis.incr(`dev:tries:${phone}`);
  await redis.expire(`dev:tries:${phone}`, 600);
  if (tries > 10) return res.status(429).json({ error: 'too many attempts' });

  const acc = (await pool.query(
    `SELECT a.* FROM accounts a JOIN trusted_devices d ON d.account_id=a.id
      WHERE a.phone=$1 AND d.token_hash=$2 AND a.deleted_at IS NULL`, [phone, hashToken(deviceToken)])).rows[0];
  if (!acc || acc.role !== role) return needOtp();
  if (acc.is_blocked) return res.status(403).json({ error: 'account blocked' });
  if (acc.terms_version !== TERMS_VERSION) return needOtp(); // terms changed: they must accept again, which happens with the OTP
  await pool.query('UPDATE trusted_devices SET last_used_at=now() WHERE token_hash=$1', [hashToken(deviceToken)]);
  res.json({ token: signToken(acc), account: { id: acc.id, role: acc.role, displayName: acc.display_name } });
});

module.exports = router;
