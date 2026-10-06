require('dotenv').config();
const { Pool } = require('pg');
const Redis = require('ioredis');
const jwt = require('jsonwebtoken');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

const signToken = (acc) =>
  jwt.sign({ id: acc.id, role: acc.role }, process.env.JWT_SECRET, { expiresIn: '30d' });

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
    next();
  };
}

module.exports = { pool, redis, signToken, requireAuth };
