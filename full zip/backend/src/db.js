require('dotenv').config();
const { Pool } = require('pg');
const Redis = require('ioredis');
const jwt = require('jsonwebtoken');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

// A database or Redis restart (for example during a redeploy) drops idle connections. Log it and reconnect
// instead of letting the unhandled error crash the whole API.
pool.on('error', (e) => console.error('[db] idle connection error (will reconnect):', e.message));
redis.on('error', (e) => console.error('[redis] connection error:', e.message));

const signToken = (acc) =>
  jwt.sign({ id: acc.id, role: acc.role }, process.env.JWT_SECRET, { expiresIn: '30d' });

// Writes accounts.last_active_at at most once an hour per host; never slows or fails a request
function touchActive(id) {
  redis.set(`active:${id}`, 1, 'EX', 3600, 'NX')
    .then((ok) => ok && pool.query('UPDATE accounts SET last_active_at = now() WHERE id=$1', [id]))
    .catch(() => {});
}

function requireAuth(roles) {
  return async (req, res, next) => {
    let auth;
    try {
      auth = jwt.verify((req.headers.authorization || '').replace('Bearer ', ''), process.env.JWT_SECRET);
    } catch {
      return res.status(401).json({ error: 'unauthorized' });
    }
    try {
      if (await redis.sismember('blocked', auth.id)) return res.status(403).json({ error: 'account blocked' });
    } catch {
      return res.status(503).json({ error: 'try again' });
    }
    if (roles && !roles.includes(auth.role)) return res.status(403).json({ error: 'forbidden' });
    req.auth = auth;
    if (auth.role === 'partner') touchActive(auth.id); // remember when a host last used the app (once an hour)
    next();
  };
}

module.exports = { pool, redis, signToken, requireAuth };
