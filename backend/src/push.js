const path = require('path');
const admin = require('firebase-admin');
const { pool } = require('./db');
const apns = require('./apns');

let enabled = false;
try {
  const file = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (file) {
    admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(file))) });
    enabled = true;
  } else {
    console.warn('[push] FIREBASE_SERVICE_ACCOUNT not set: push notifications disabled');
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

module.exports = { notifyIncomingCall, notifyCallCancelled };
