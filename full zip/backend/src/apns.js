const fs = require('fs');
const http2 = require('http2');
const jwt = require('jsonwebtoken');

// iOS only shows the full-screen CallKit ring for VoIP pushes, which Firebase cannot send; we call APNs directly.
const { APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID } = process.env;
const enabled = !!(APNS_KEY_PATH && APNS_KEY_ID && APNS_TEAM_ID && APNS_BUNDLE_ID);
if (!enabled) console.warn('[apns] APNS_* not set: iOS VoIP ring disabled (iPhones get a normal notification)');

let cached;
function providerToken() { // APNs accepts a token for up to 60 minutes; refresh at 50
  if (cached && Date.now() - cached.at < 50 * 60 * 1000) return cached.token;
  const token = jwt.sign({}, fs.readFileSync(APNS_KEY_PATH), { algorithm: 'ES256', keyid: APNS_KEY_ID, issuer: APNS_TEAM_ID });
  cached = { token, at: Date.now() };
  return token;
}

function sendVoip(deviceToken, payload) {
  return new Promise((resolve, reject) => {
    const host = process.env.APNS_PRODUCTION === 'true' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
    const client = http2.connect(host);
    client.on('error', reject);
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      'apns-topic': `${APNS_BUNDLE_ID}.voip`,
      'apns-push-type': 'voip',
      'apns-priority': '10',
      'apns-expiration': '0', // a missed ring is worthless: deliver now or drop
    });
    let status; let body = '';
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (d) => { body += d; });
    req.on('end', () => {
      client.close();
      if (status === 200) return resolve();
      let reason; try { reason = JSON.parse(body).reason; } catch {}
      reject(Object.assign(new Error(`APNs ${status} ${reason || ''}`), { status, reason }));
    });
    req.on('error', (e) => { client.close(); reject(e); });
    req.end(JSON.stringify(payload));
  });
}

const isDeadToken = (e) => e.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(e.reason);

module.exports = { enabled, sendVoip, isDeadToken };
