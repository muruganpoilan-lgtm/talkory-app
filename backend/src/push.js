const path = require('path');
const admin = require('firebase-admin');
const { pool } = require('./db');
const apns = require('./apns');

let enabled = false;
try {
  const file = process.env.FIREBASE_SERVICE_ACCOUNT;
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64; // the whole key file, base64 encoded, on one line
  if (b64) {
    const key = JSON.parse(Buffer.from(b64.trim(), 'base64').toString('utf8'));
    admin.initializeApp({ credential: admin.credential.cert(key) });
    enabled = true;
    console.log('[push] Firebase ready for project', key.project_id);
  } else if (file) {
    admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(file))) });
    enabled = true;
  } else {
    console.warn('[push] FIREBASE_SERVICE_ACCOUNT(_B64) not set: push notifications disabled');
  }
} catch (e) {
  console.error('[push] init failed:', e.message);
}

const DEAD_TOKEN_CODES = ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'];

async function sendFcm(device, message) {
  try {
    await admin.messaging().send({ token: device.push_token, ...message });
  } catch (e) {
    if (DEAD_TOKEN_CODES.includes(e.code)) await pool.query('DELETE FROM devices WHERE push_token=$1', [device.push_token]);
    else console.error('[push] send failed:', e.code || e.message);
  }
}

const devicesOf = async (accountId) =>
  (await pool.query('SELECT push_token, platform, voip_token FROM devices WHERE account_id=$1', [accountId])).rows;

// Ring the partner. Android: data-only high-priority FCM (the app builds the native call screen).
// iOS with a VoIP token: APNs VoIP push (full-screen CallKit ring). Otherwise: a visible time-sensitive notification.
async function notifyIncomingCall(partnerId, callId, callerName) {
  const expiry = String(Math.floor(Date.now() / 1000) + 20);
  await Promise.all((await devicesOf(partnerId)).map(async (d) => {
    if (d.platform === 'ios' && d.voip_token && apns.enabled) {
      try {
        await apns.sendVoip(d.voip_token, { id: callId, nameCaller: callerName, handle: 'Voice call', isVideo: false });
        return; // VoIP push delivered: do not also send an FCM alert (it would ring twice)
      } catch (e) {
        if (apns.isDeadToken(e)) await pool.query('UPDATE devices SET voip_token=NULL WHERE voip_token=$1', [d.voip_token]);
        else console.error('[apns] send failed:', e.message);
      }
    }
    if (!enabled) return;
    await sendFcm(d, {
      data: { type: 'incoming_call', callId, callerName },
      android: { priority: 'high', ttl: 20000 },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert', 'apns-expiration': expiry },
        payload: { aps: { alert: { title: 'Incoming call', body: `${callerName} wants to talk` }, sound: 'default', 'interruption-level': 'time-sensitive' } },
      },
    });
  }));
}

// Stop ringing: caller hung up, the call timed out, or another device answered.
async function notifyCallCancelled(partnerId, callId) {
  if (!enabled) return;
  await Promise.all((await devicesOf(partnerId)).map((d) => sendFcm(d, {
    data: { type: 'call_cancelled', callId },
    android: { priority: 'high', ttl: 20000 },
    apns: { headers: { 'apns-priority': '5', 'apns-push-type': 'background' }, payload: { aps: { 'content-available': 1 } } },
  })));
}

// New chat message: a plain notification (never includes the message text)
async function notifyMessage(accountId, fromName) {
  if (!enabled) return;
  await Promise.all((await devicesOf(accountId)).map((d) => sendFcm(d, {
    notification: { title: 'New message', body: `${fromName} sent you a message` },
    data: { type: 'chat_message' },
    android: { priority: 'high' },
  })));
}

// The Talkory team is video calling this person from the admin panel. A plain notification; tapping it opens the app, which then rings.
async function notifyAdminVideoCall(accountId) {
  if (!enabled) return;
  await Promise.all((await devicesOf(accountId)).map((d) => sendFcm(d, {
    notification: { title: 'Talkory is calling you', body: 'Open the app to answer the video call' },
    data: { type: 'admin_video_call' },
    android: { priority: 'high', ttl: 40000 },
  })));
}

// A host just went online: tell every user's phone. Plain notification, no call data.
async function notifyHostOnline(hostId, hostName) {
  if (!enabled) return;
  const first = String(hostName || 'A host').split(/\s+/)[0].slice(0, 30);
  const { rows } = await pool.query(
    `SELECT DISTINCT d.push_token FROM devices d JOIN accounts a ON a.id=d.account_id
      WHERE a.role='user' AND a.id<>$1 LIMIT 20000`, [hostId]);
  const tokens = rows.map((r) => r.push_token);
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: { title: `${first} is online now`, body: 'Say hello! Tap to open Talkory.' },
        data: { type: 'host_online', hostId: String(hostId) },
        android: { priority: 'normal', ttl: 60 * 60 * 1000 },
      });
      const dead = [];
      res.responses.forEach((r, k) => { if (!r.success && DEAD_TOKEN_CODES.includes(r.error?.code)) dead.push(chunk[k]); });
      if (dead.length) await pool.query('DELETE FROM devices WHERE push_token = ANY($1)', [dead]);
    } catch (e) {
      console.error('[push] host-online send failed:', e.code || e.message);
    }
  }
}

// An admin arranged a meeting (or started one). A plain notification to everyone invited; tapping it opens the app, which then offers to join.
async function notifyMeeting(accountIds, { title, body }) {
  if (!enabled || !accountIds.length) return;
  const tokens = [];
  for (let i = 0; i < accountIds.length; i += 5000) {
    const { rows } = await pool.query('SELECT DISTINCT push_token FROM devices WHERE account_id = ANY($1)', [accountIds.slice(i, i + 5000)]);
    tokens.push(...rows.map((r) => r.push_token));
  }
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: { title, body },
        data: { type: 'meeting' },
        android: { priority: 'high', ttl: 60 * 60 * 1000 },
      });
      const dead = [];
      res.responses.forEach((r, k) => { if (!r.success && DEAD_TOKEN_CODES.includes(r.error?.code)) dead.push(chunk[k]); });
      if (dead.length) await pool.query('DELETE FROM devices WHERE push_token = ANY($1)', [dead]);
    } catch (e) {
      console.error('[push] meeting send failed:', e.code || e.message);
    }
  }
}

module.exports = { notifyIncomingCall, notifyCallCancelled, notifyMessage, notifyHostOnline, notifyAdminVideoCall, notifyMeeting };
