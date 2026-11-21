// End-to-end API check: signup, KYC, call, billing, auto cut-off, rating, report/block, payouts, deletion.
// Takes about 100 seconds (it waits for real 15s billing ticks). LOCAL/DEV DATABASE ONLY.
//
// Setup (see README "Testing"): backend running with OTP_DEV_MODE=true, OTP_TEST_CODE=123456, NODE_ENV not "production",
// and dummy AGORA_APP_ID / AGORA_APP_CERT (any 32 hex characters). Then:  npm run smoke
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const BASE = process.env.BASE || 'http://localhost:3000';
const CODE = process.env.OTP_TEST_CODE || '123456';
if (!/localhost|127\.0\.0\.1|@db[:/]/.test(process.env.DATABASE_URL || '')) {
  console.error('Refusing to run: DATABASE_URL must point at a local/dev database.');
  process.exit(1);
}
const AVATAR_DIR = process.env.AVATAR_DIR || path.join(__dirname, '..', 'data', 'avatars');
const db = new Pool({ connectionString: process.env.DATABASE_URL });
let failures = 0;
const ok = (cond, msg) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${msg}`); if (!cond) failures++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(method, path, token, body) {
  const r = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function login(role, name) {
  const phone = '+9199' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  await api('POST', '/auth/request-otp', null, { phone });
  const r = await api('POST', '/auth/verify-otp', null, { phone, code: CODE, role, displayName: name, isAdult: true, acceptedTerms: true });
  if (r.status !== 200) throw new Error(`login ${role} failed: ${r.status} ${JSON.stringify(r.data)}`);
  return { phone, token: r.data.token, id: r.data.account.id };
}
const balance = async (id) => Number((await db.query('SELECT balance FROM wallets WHERE account_id=$1', [id])).rows[0].balance);
const fund = (id, paise) => db.query('UPDATE wallets SET balance=$1 WHERE account_id=$2', [paise, id]);

async function main() {
  ok((await api('GET', '/health')).status === 200, 'server is up');
  const host = await login('partner', 'TestHost');
  const user = await login('user', 'TestCaller');
  const poor = await login('user', 'ShortOnCredits');

  console.log('\n-- host setup');
  let r = await api('PUT', '/partners/me', host.token, { displayName: 'TestHost', bio: 'call me on 9876543210', languages: ['English'], rateRupees: 60 });
  ok(r.status === 400, 'phone numbers in a bio are rejected');
  r = await api('PUT', '/partners/me', host.token, { displayName: 'TestHost', bio: 'hello there', languages: ['English'], rateRupees: 60 });
  ok(r.status === 200, 'host saves profile (₹60/min)');
  ok((await api('POST', '/partners/online', host.token, { online: true })).status === 403, 'unverified host cannot go online');
  await db.query(`UPDATE partner_profiles SET kyc='approved' WHERE account_id=$1`, [host.id]);
  ok((await api('POST', '/partners/online', host.token, { online: true })).status === 200, 'verified host goes online');
  r = await api('GET', '/partners?language=English', user.token);
  ok(Array.isArray(r.data) && r.data.some((p) => p.id === host.id), 'host shows in the user list');
  ok(!JSON.stringify(r.data).includes(host.phone), 'host phone number is not exposed');

  console.log('\n-- call and billing');
  ok((await api('POST', '/calls', user.token, { partnerId: host.id })).status === 402, 'caller with no credits is refused');
  await fund(user.id, 100000);
  r = await api('POST', '/calls', user.token, { partnerId: host.id });
  ok(r.status === 200 && !!r.data.token && !!r.data.appId, 'call starts and returns a voice token');
  const callId = r.data.callId;
  ok((await api('GET', '/calls/incoming', host.token)).data?.id === callId, 'host sees the ringing call');
  ok((await api('POST', '/calls', user.token, { partnerId: host.id })).status === 409, 'a second call to a busy host is refused');
  ok((await api('POST', `/calls/${callId}/accept`, host.token)).status === 200, 'host accepts');
  ok((await balance(user.id)) === 98500, 'first 15s charged up front (₹15)');
  ok((await balance(host.id)) === 900, 'host credited 60% of it');
  r = await api('GET', `/calls/${callId}/status`, user.token);
  ok(r.data.status === 'active' && r.data.secondsLeft > 0, 'status shows active and talk time left');
  console.log('      waiting 17s for the next billing tick...');
  await sleep(17000);
  await api('GET', `/calls/${callId}/status`, user.token);
  ok((await balance(user.id)) === 97000, 'second 15s step billed by the queue');
  ok((await api('POST', `/calls/${callId}/end`, user.token)).status === 200, 'call ends');

  console.log('\n-- rating, report, block');
  ok((await api('POST', `/calls/${callId}/rate`, user.token, { stars: 5, comment: 'great' })).status === 200, 'rating saved');
  const prof = (await db.query('SELECT rating_avg, rating_count FROM partner_profiles WHERE account_id=$1', [host.id])).rows[0];
  ok(Number(prof.rating_avg) === 5 && prof.rating_count === 1, 'host rating updated');
  r = await api('GET', '/wallet/history', user.token);
  ok(r.data.some((e) => e.kind === 'call' && e.amount === -3000), 'wallet activity shows one line for the call');
  ok((await api('POST', `/calls/${callId}/report`, user.token, { reason: 'Abusive or offensive language' })).status === 200, 'report accepted');
  await api('POST', `/calls/${callId}/block`, user.token);
  ok((await api('POST', '/calls', user.token, { partnerId: host.id })).status === 403, 'a blocked host cannot be called');

  console.log('\n-- automatic cut-off when credits run out (about 70s)');
  await fund(poor.id, 6000); // exactly the 60s minimum: four 15s steps, then the fifth fails
  r = await api('POST', '/calls', poor.token, { partnerId: host.id });
  ok(r.status === 200, 'second caller starts a call');
  await api('POST', `/calls/${r.data.callId}/accept`, host.token);
  let status = 'active';
  for (let i = 0; i < 16 && status === 'active'; i++) {
    await sleep(5000);
    status = (await api('GET', `/calls/${r.data.callId}/status`, poor.token)).data.status; // polling doubles as the heartbeat
  }
  ok(status === 'ended', 'call was ended automatically when credits ran out');
  ok((await balance(poor.id)) === 0, 'all four affordable steps were billed, nothing more');

  console.log('\n-- earnings and payouts');
  r = await api('GET', '/partner/earnings', host.token);
  ok(r.data.totalEarned === 5400, 'earnings total matches (6 steps x ₹9)');
  ok((await api('POST', '/partner/payouts', host.token, { amountRupees: 500 })).status === 400, 'withdrawal needs a UPI ID first');
  ok((await api('PUT', '/partner/payout-method', host.token, { upiId: 'testhost@upi' })).status === 200, 'UPI ID saved');
  ok((await api('POST', '/partner/payouts', host.token, { amountRupees: 500 })).status === 402, 'withdrawal above the balance is refused');
  await fund(host.id, 100000);
  r = await api('POST', '/partner/payouts', host.token, { amountRupees: 500 });
  ok(r.status === 200, 'withdrawal requested');
  ok((await balance(host.id)) === 50000, 'the money is held immediately');
  ok((await api('POST', '/partner/payouts', host.token, { amountRupees: 500 })).status === 409, 'only one withdrawal at a time');
  const adminPhone = '+9198' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  await db.query(`INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin',$1,'Admin',true)`, [adminPhone]);
  await api('POST', '/auth/request-otp', null, { phone: adminPhone });
  const adminLogin = await api('POST', '/auth/verify-otp', null, { phone: adminPhone, code: CODE, role: 'admin' });
  ok(adminLogin.status === 200, 'admin can log in');
  ok((await api('POST', `/partner/admin/payouts/${r.data.payoutId}/paid`, adminLogin.data.token, { reference: 'TEST-123' })).status === 200, 'admin marks the payout paid');

  console.log('\n-- profile photo');
  const jpeg = Buffer.concat([ // tiny fake JPEG carrying an EXIF segment with "GPS" data
    Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
    Buffer.from([0xff, 0xe1, 0x00, 0x10]), Buffer.from('Exif\0\0GPSDATA!'),
    Buffer.from([0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, 0x12, 0x34, 0xff, 0xd9]),
  ]);
  ok((await api('POST', '/partner/avatar', host.token, { imageBase64: jpeg.toString('base64') })).status === 200, 'host uploads a photo');
  ok((await api('GET', '/partners/me', host.token)).data.avatarStatus === 'pending', 'photo waits for review');
  ok((await api('GET', '/admin/avatars', adminLogin.data.token)).data.some((a) => a.id === host.id), 'admin sees the pending photo');
  ok((await api('POST', `/admin/avatars/${host.id}`, adminLogin.data.token, { status: 'approved' })).status === 200, 'admin approves it');
  const url = (await db.query('SELECT avatar_url FROM accounts WHERE id=$1', [host.id])).rows[0].avatar_url;
  ok(!!url, 'approved photo gets a public url');
  const stored = fs.readFileSync(path.join(AVATAR_DIR, 'public', path.basename(url)));
  ok(!stored.includes('Exif') && !stored.includes('GPSDATA'), 'camera/location metadata was stripped');

  console.log('\n-- account deletion');
  ok((await api('POST', '/account/delete', host.token, { confirm: 'DELETE' })).status === 409, 'host with ₹500+ must withdraw before deleting');
  await fund(host.id, 1000);
  ok((await api('POST', '/account/delete', host.token, { confirm: 'DELETE' })).status === 200, 'host account deleted');
  ok((await api('POST', '/account/delete', user.token, { confirm: 'DELETE' })).status === 200, 'user account deleted');
  ok((await api('GET', '/wallet', user.token)).status === 403, 'a deleted account token stops working');
  const gone = (await db.query('SELECT phone, display_name FROM accounts WHERE id=$1', [user.id])).rows[0];
  ok(gone.display_name === 'Deleted user' && !gone.phone.startsWith('+'), 'personal data was removed');
}

main()
  .catch((e) => { console.error('\nTest crashed:', e.message); failures++; })
  .finally(async () => {
    console.log(failures ? `\n${failures} check(s) FAILED` : '\nAll checks passed');
    await db.end();
    process.exit(failures ? 1 : 0);
  });
