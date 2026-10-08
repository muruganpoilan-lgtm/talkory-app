require('dotenv').config();
const Sentry = require('@sentry/node');
if (process.env.SENTRY_DSN) Sentry.init({ dsn: process.env.SENTRY_DSN, sendDefaultPii: false, tracesSampleRate: 0, environment: process.env.NODE_ENV });
require('express-async-errors'); // errors thrown in async routes reach the error handler instead of crashing the process
const express = require('express');
const rateLimit = require('express-rate-limit');
const path = require('path');
const wallet = require('./wallet');
const { pool, redis } = require('./db');
const { startWorker } = require('./queue');
const bootstrap = require('./bootstrap');

const app = express();
app.set('trust proxy', 1); // behind Caddy: use the real client IP

// Must come BEFORE express.json() and the rate limiter: webhook signature is computed over the raw body
app.post('/webhooks/razorpay', express.raw({ type: 'application/json' }), wallet.webhook);

// Phones on one mobile carrier often share a single IP, so the general limit is generous.
const limit = (windowMs, max) => rateLimit({ windowMs, limit: max, standardHeaders: true, legacyHeaders: false, message: { error: 'Too many requests. Please slow down.' } });
app.get('/health', (_, res) => res.json({ ok: true }));
app.use(limit(60 * 1000, 600));
app.use('/auth/request-otp', limit(10 * 60 * 1000, 20)); // protects your SMS bill (there is also a 30s cooldown per phone)
app.use('/auth/verify-otp', limit(10 * 60 * 1000, 60));

app.use('/partner/kyc', express.json({ limit: '6mb' })); // base64 photos
app.use('/partner/avatar', express.json({ limit: '3mb' }));
app.use(express.json());
app.use('/auth', require('./auth'));
app.use('/partners', require('./partners'));
app.use('/calls', require('./calls'));
app.use('/wallet', wallet.router);
app.use('/legal', express.static(path.join(__dirname, '../legal'), { extensions: ['html'] })); // /legal/terms, /legal/privacy
app.use('/account', require('./account').router);
const avatars = require('./avatars');
app.use('/avatars', express.static(avatars.PUBLIC, { maxAge: '30d', immutable: true, index: false })); // approved photos only
app.use('/admin/avatars', avatars.admin);
app.use('/admin', require('./admin'));
app.use('/panel', express.static(path.join(__dirname, '../admin'))); // admin web panel
app.use('/devices', require('./devices'));
app.use('/partner/kyc', require('./kyc').router);
app.use('/partner/avatar', avatars.router);
app.use('/partner', require('./payouts')); // earnings, payouts, admin payout actions

if (process.env.SENTRY_DSN) Sentry.setupExpressErrorHandler(app);
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'server error' });
});

process.on('unhandledRejection', (e) => { console.error('unhandledRejection', e); Sentry.captureException(e); });
process.on('uncaughtException', (e) => { // state may be corrupt: report, then let Docker restart us
  console.error('uncaughtException', e);
  Sentry.captureException(e);
  Sentry.close(2000).finally(() => process.exit(1));
});

async function start() {
  await bootstrap(); // creates tables on a brand-new database
  // Rebuild the "blocked" set from the database. Calls in progress are NOT touched: their timers live in Redis now.
  const blocked = await pool.query('SELECT id FROM accounts WHERE is_blocked');
  await redis.del('blocked');
  if (blocked.rowCount) await redis.sadd('blocked', ...blocked.rows.map((r) => r.id));

  const worker = startWorker();
  const server = app.listen(process.env.PORT || 3000, () => console.log('Talkory backend running'));
  process.on('SIGTERM', async () => { // docker stop / deploy: finish the job in hand, then exit
    server.close();
    await worker.close();
    process.exit(0);
  });
}
start().catch((e) => { console.error('startup failed', e); process.exit(1); });
