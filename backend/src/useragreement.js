const router = require('express').Router();
const { pool, requireAuth } = require('./db');

// The user agreement. Raise VERSION whenever the text changes: users are then asked to sign again.
const VERSION = 1;
const CO = process.env.COMPANY_NAME || 'Talkory Tech';
const TEXT = `TALKORY USER AGREEMENT

This agreement is between ${CO} ("Talkory") and you, the user.

1. Who can use Talkory
You must be 18 years or older. You must give true information and keep your account to yourself.

2. What Talkory is
Talkory lets you talk to hosts by voice and chat, anonymously, and pay for the time you use with coins.

3. Coins and charges
1 coin = ₹1. Voice calls are charged per minute and chat per message, at the rates shown in the app. Calls and chats are billed while they happen. Coins you buy are used for calls and chats. Except where the law requires it, coins already bought or used are not refundable. If a payment fails or is charged twice, contact support and we will fix it.

4. Stay anonymous and safe
Hosts and users stay anonymous to each other. Do not share or ask for phone numbers, social media handles, links or any contact details. Do not try to find out who a host is.

5. Behave respectfully
No abuse, threats, hate, sexual or illegal talk, no harassment, and no asking hosts for money or gifts outside Talkory. Do not record calls or chats, or share them.

6. Reporting and blocking
You can report or block a host any time from the call or chat screen. Talkory reviews reports and may suspend accounts.

7. Suspension
Talkory may suspend or close your account if you break this agreement. Unused coins may be held while we look into a report or fraud.

8. Privacy
We use your phone number, calls and payments data to run Talkory, keep it safe and follow the law. We do not share your number with hosts. See the Privacy Policy in the app for details.

9. Law
This agreement is governed by the laws of India. Disputes will be handled by the courts of the city where ${CO} is registered.

By writing your signature and tapping Sign, you confirm that you have read and agree to this agreement.`;

router.get('/', requireAuth(['user']), async (req, res) => {
  const row = (await pool.query('SELECT version, full_name, signed_at FROM user_agreements WHERE account_id=$1', [req.auth.id])).rows[0];
  res.json({ version: VERSION, text: TEXT, signed: !!row && row.version >= VERSION, signedName: row?.full_name || null, signedAt: row?.signed_at || null });
});

router.post('/', requireAuth(['user']), async (req, res) => {
  const name = String(req.body.fullName || '').trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 80 || !/^[\p{L} .'-]+$/u.test(name)) return res.status(400).json({ error: 'Type your name' });
  if (req.body.agree !== true) return res.status(400).json({ error: 'Tick the box to agree' });
  const b64 = String(req.body.signaturePng || '');
  if (!b64 || b64.length > 280000) return res.status(400).json({ error: 'Please sign again' });
  const png = Buffer.from(b64, 'base64');
  if (png.length < 200 || png.length > 200000 || !png.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])))
    return res.status(400).json({ error: 'Please sign again' });
  await pool.query(
    `INSERT INTO user_agreements (account_id, version, full_name, signature, ip) VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (account_id) DO UPDATE SET version=EXCLUDED.version, full_name=EXCLUDED.full_name, signature=EXCLUDED.signature, ip=EXCLUDED.ip, signed_at=now()`,
    [req.auth.id, VERSION, name, png, String(req.ip || '').slice(0, 64)]);
  res.json({ ok: true });
});

async function isSigned(accountId) {
  const row = (await pool.query('SELECT version FROM user_agreements WHERE account_id=$1', [accountId])).rows[0];
  return !!row && row.version >= VERSION;
}

// Admin: who has signed, and the drawn signature
const admin = require('express').Router();
admin.use(requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, a.phone, g.full_name, g.version, g.signed_at
       FROM user_agreements g JOIN accounts a ON a.id=g.account_id ORDER BY g.signed_at DESC LIMIT 200`);
  res.json(rows);
});
admin.get('/:id/signature', async (req, res) => {
  const row = (await pool.query('SELECT signature FROM user_agreements WHERE account_id=$1', [req.params.id])).rows[0];
  if (!row) return res.status(404).json({ error: 'not found' });
  res.set({ 'Content-Type': 'image/png', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }).send(row.signature);
});

module.exports = { router, admin, isSigned, VERSION };
