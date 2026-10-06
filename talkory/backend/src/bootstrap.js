const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { pool } = require('./db');

// First start on an empty database: create all tables from schema.sql (one transaction: all or nothing).
// Optional ADMIN_PHONE: makes sure that number has an admin account. Safe to run on every start.
function ensureJwtSecret() {
  if (process.env.JWT_SECRET) return;
  const file = process.env.SECRET_FILE || '/data/app/jwt.secret';
  try {
    process.env.JWT_SECRET = fs.readFileSync(file, 'utf8').trim();
  } catch {
    try {
      const secret = crypto.randomBytes(48).toString('hex');
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, secret, { mode: 0o600 });
      process.env.JWT_SECRET = secret;
      console.log('[bootstrap] generated a login-token secret and stored it in', file);
    } catch (e) {
      throw new Error(`Set JWT_SECRET (could not create ${file}: ${e.message})`);
    }
  }
}

async function bootstrap() {
  ensureJwtSecret();
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock(727274)'); // two API containers starting together must not both create tables
    const exists = (await client.query(`SELECT to_regclass('public.accounts') AS t`)).rows[0].t;
    if (!exists) {
      console.log('[bootstrap] empty database: creating tables');
      await client.query(fs.readFileSync(path.join(__dirname, '../schema.sql'), 'utf8'));
    }
    const phone = process.env.ADMIN_PHONE;
    if (phone && /^\+\d{8,15}$/.test(phone)) {
      await client.query(
        `INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin', $1, 'Admin', true) ON CONFLICT (phone) DO NOTHING`, [phone]);
    } else if (phone) {
      console.warn('[bootstrap] ADMIN_PHONE must look like +919876543210, ignored');
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock(727274)').catch(() => {});
    client.release();
  }
}

module.exports = bootstrap;
