const router = require('express').Router();
const { pool, requireAuth } = require('./db');

// The host agreement. Raise VERSION whenever the text changes: hosts are then asked to sign again.
const VERSION = 3;
const CO = process.env.COMPANY_NAME || 'Talkory Tech';
const TEXT = `TALKORY PARTNER (HOST) AGREEMENT

This agreement is between ${CO} ("Talkory") and you, the host ("Partner").

1. Independent partner
You work as an independent partner, not as an employee of Talkory. You choose when to go online.

2. Honest information
Your name, documents, selfie and profile photo must be genuine and your own. Photos that are AI-generated, edited to look like someone else, or taken from another person are not allowed, and may lead to rejection or removal.

3. Conduct on calls and chats
You will be polite and respectful. You will not share your phone number, social media handles, links or any contact details, and you will not ask users for theirs. You will not record calls or chats. No abusive, sexual, illegal or harmful conversation. No asking users for money or gifts outside Talkory.

4. Earnings
You earn the amount shown in the app for each minute you talk and for each chat message you receive. Talkory keeps the rest as its service fee. Earnings are paid to your UPI ID.

5. Withdrawals
Withdrawals are paid on the 10th, 20th and 30th of each month (the last day of February instead of the 30th), and only when your balance is at least the minimum shown in the app (₹500). GST at 18% is deducted from every withdrawal, and you get an invoice after each payment. Talkory may hold or cancel a withdrawal where it suspects fraud or breach of this agreement.

6. Daily online time
You agree to stay Online for at least 4 hours every day, in one stretch or split across the day. The count starts again every day at midnight (India time). For each 30 minutes short, ₹1 is deducted from your earnings, as shown in the app.

7. Privacy
Users and hosts stay anonymous to each other. You will not try to find out who a user is. Talkory keeps your KYC documents private and uses them only for verification and legal compliance.

8. Suspension and ending
Talkory may suspend or remove your account if you break this agreement or the rules in the app. You may stop at any time by going offline and withdrawing your balance when eligible.

9. Law
This agreement is governed by the laws of India. Disputes will be handled by the courts of the city where ${CO} is registered.

By typing your full name, drawing your signature and tapping Sign, you confirm that you have read and agree to this agreement.`;

router.get('/', requireAuth(['partner']), async (req, res) => {
  const row = (await pool.query('SELECT version, full_name, signed_at FROM partner_contracts WHERE partner_id=$1', [req.auth.id])).rows[0];
  res.json({ version: VERSION, text: TEXT, signed: !!row && row.version >= VERSION, signedName: row?.full_name || null, signedAt: row?.signed_at || null });
});

router.post('/sign', requireAuth(['partner']), async (req, res) => {
  const name = String(req.body.fullName || '').trim().replace(/\s+/g, ' ');
  if (name.length < 3 || name.length > 80 || !/^[\p{L} .'-]+$/u.test(name)) return res.status(400).json({ error: 'Type your full name as on your ID' });
  if (req.body.agree !== true) return res.status(400).json({ error: 'Tick the box to agree' });
  const b64 = String(req.body.signaturePng || '');
  if (!b64 || b64.length > 280000) return res.status(400).json({ error: 'Please draw your signature' });
  const png = Buffer.from(b64, 'base64');
  if (png.length < 200 || png.length > 200000 || !png.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])))
    return res.status(400).json({ error: 'Please sign again' });
  const p = (await pool.query('SELECT kyc FROM partner_profiles WHERE account_id=$1', [req.auth.id])).rows[0];
  if (p?.kyc !== 'approved') return res.status(409).json({ error: 'You can sign after your verification (KYC) is approved' });
  await pool.query(
    `INSERT INTO partner_contracts (partner_id, version, full_name, ip) VALUES ($1,$2,$3,$4)
     ON CONFLICT (partner_id) DO UPDATE SET version=EXCLUDED.version, full_name=EXCLUDED.full_name, ip=EXCLUDED.ip, signed_at=now()`,
    [req.auth.id, VERSION, name, String(req.ip || '').slice(0, 64)]);
  await require('./hostfiles').saveAgreement(req.auth.id, VERSION, name, String(req.ip || '').slice(0, 64), TEXT).catch((e) => console.error('[hostfiles] agreement copy failed:', e.message)); // permanent copy in the database
  await require('./hostfiles').saveSignature(req.auth.id, VERSION, png).catch((e) => console.error('[hostfiles] signature copy failed:', e.message));
  res.json({ ok: true });
});

async function isSigned(partnerId) {
  const row = (await pool.query('SELECT version FROM partner_contracts WHERE partner_id=$1', [partnerId])).rows[0];
  return !!row && row.version >= VERSION;
}

// Admin: who has signed (shown in the admin panel)
const admin = require('express').Router();
admin.use(requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT a.id, a.display_name, c.full_name, c.version, c.signed_at, c.ip,
            (SELECT h.id FROM host_files h WHERE h.account_id=a.id AND h.kind='agreement' ORDER BY h.created_at DESC LIMIT 1) AS agreement_id
       FROM partner_contracts c JOIN accounts a ON a.id=c.partner_id ORDER BY c.signed_at DESC LIMIT 200`);
  res.json(rows);
});

module.exports = { router, admin, isSigned, VERSION, TEXT };
