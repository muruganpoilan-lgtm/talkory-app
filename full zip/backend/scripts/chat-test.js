// Chat + level + GST + photo API check. LOCAL/DEV DATABASE ONLY. Run with the backend up (see smoke-test.js header).
require('dotenv').config();
const { Pool } = require('pg');
const BASE = process.env.BASE || 'http://localhost:3000';
const CODE = process.env.OTP_TEST_CODE || '123456';
if (!/localhost|127\.0\.0\.1|@db[:/]/.test(process.env.DATABASE_URL || '')) { console.error('Refusing: DATABASE_URL must be local.'); process.exit(1); }
const db = new Pool({ connectionString: process.env.DATABASE_URL });
let failures = 0;
const ok = (c, m) => { console.log(`${c ? 'PASS' : 'FAIL'}  ${m}`); if (!c) failures++; };
async function api(method, path, token, body) {
  const r = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json', ...(token && { Authorization: `Bearer ${token}` }) }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}
async function login(role, name) {
  const phone = '+9198' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  await api('POST', '/auth/request-otp', null, { phone });
  const r = await api('POST', '/auth/verify-otp', null, { phone, code: CODE, role, displayName: name, isAdult: true, acceptedTerms: true });
  if (r.status !== 200) throw new Error(`login failed ${r.status} ${JSON.stringify(r.data)}`);
  return { token: r.data.token, id: r.data.account.id };
}
const bal = async (id) => Number((await db.query('SELECT balance FROM wallets WHERE account_id=$1', [id])).rows[0].balance);

(async () => {
  const host = await login('partner', 'ChatHost'), user = await login('user', 'ChatUser');
  await api('PUT', '/partners/me', host.token, { displayName: 'ChatHost', languages: ['English'], rateRupees: 60 });
  await db.query(`UPDATE partner_profiles SET kyc='approved' WHERE account_id=$1`, [host.id]);
  await db.query('UPDATE wallets SET balance=100 WHERE account_id=$1', [user.id]);

  let r = await api('POST', `/chat/${user.id}`, host.token, { body: 'hi first' });
  ok(r.status === 403, 'host cannot start a conversation');
  r = await api('POST', `/chat/${host.id}`, user.token, { body: 'call me on 9876543210' });
  ok(r.status === 400, 'phone number blocked');
  r = await api('POST', `/chat/${host.id}`, user.token, { body: 'find me @someone' });
  ok(r.status === 400, 'handle blocked');
  ok(await bal(user.id) === 100, 'blocked messages are not charged');

  r = await api('POST', `/chat/${host.id}`, user.token, { body: 'Hello!' });
  ok(r.status === 200 && r.data.balance === 70, 'message costs 0.3 coins (30 paise)');
  ok(await bal(host.id) === 18, 'host earns payout share of the message (60%)');
  r = await api('POST', `/chat/${user.id}`, host.token, { body: 'Hi, how are you?' });
  ok(r.status === 200, 'host can reply once user wrote');
  ok(await bal(user.id) === 70, 'host replies are free for the user');

  r = await api('GET', '/chat/threads', host.token);
  ok(r.data.length === 1 && r.data[0].unread === 1 && r.data[0].name === 'ChatUser', 'host inbox shows 1 unread from ChatUser');
  r = await api('GET', `/chat/${user.id}/messages`, host.token);
  ok(r.data.length === 2 && r.data[1].mine === true, 'thread has both messages');
  r = await api('GET', '/chat/threads', host.token);
  ok(r.data[0].unread === 0, 'opening the thread marks read');
  r = await api('GET', '/chat/unread', user.token);
  ok(r.data.unread === 1, 'user has 1 unread reply');
  r = await api('GET', `/chat/${host.id}/messages?after=${(await api('GET', `/chat/${host.id}/messages`, user.token)).data[0].id}`, user.token);
  ok(r.data.length === 1, 'polling with ?after returns only newer');

  await db.query('UPDATE wallets SET balance=10 WHERE account_id=$1', [user.id]);
  r = await api('POST', `/chat/${host.id}`, user.token, { body: 'again' });
  ok(r.status === 402, 'insufficient coins -> 402');
  ok((await db.query('SELECT 1 FROM messages WHERE body=$1', ['again'])).rowCount === 0, 'unpaid message is not stored');

  r = await api('GET', '/wallet/history?page=0', user.token);
  ok(r.data.some((x) => x.kind === 'chat' && x.amount === -30), 'wallet history shows chat charge');

  r = await api('GET', '/account/me', user.token);
  ok(r.data.level === 'New' && r.data.minutes === 0, 'level starts at New');
  r = await api('PUT', '/account/gst', user.token, { gstNumber: 'bad' });
  ok(r.status === 400, 'invalid GST rejected');
  r = await api('PUT', '/account/gst', user.token, { gstNumber: '22AAAAA0000A1Z5' });
  ok(r.status === 200, 'valid GST saved');

  await api('POST', `/chat/${host.id}/block`, user.token);
  r = await api('POST', `/chat/${user.id}`, host.token, { body: 'hello again' });
  ok(r.status === 403, 'blocked thread rejects messages');
  r = await api('GET', '/chat/threads', user.token);
  ok(r.data.length === 0, 'blocked thread hidden from inbox');
  console.log(failures ? `\n${failures} FAILED` : '\nALL PASSED');
  await db.end(); process.exit(failures ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
