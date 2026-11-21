const express = require('express');
const { pool, requireAuth } = require('./db');

const MAX_SUBJECT = 80;
const MAX_BODY = 2000;
const MAX_OPEN = 5;           // open tickets per customer
const MAX_PER_HOUR = 20;      // messages a customer can send per hour
const isUuid = (s) => /^[0-9a-f-]{36}$/i.test(String(s));

function clean(v, max) {
  return String(v ?? '').replace(/\r\n/g, '\n').trim().slice(0, max);
}

// ---- customers (users and hosts), mounted at /support-tickets
const router = express.Router();
router.use(requireAuth(['user', 'partner']));

// My tickets, newest activity first
router.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT t.id, t.subject, t.status, t.customer_unread, t.updated_at,
            (SELECT body FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.id DESC LIMIT 1) AS last_body
       FROM support_tickets t WHERE t.account_id=$1 ORDER BY t.updated_at DESC LIMIT 50`, [req.auth.id]);
  res.json(rows);
});

// Open a ticket with its first message
router.post('/', async (req, res) => {
  const subject = clean(req.body.subject, MAX_SUBJECT);
  const body = clean(req.body.body, MAX_BODY);
  if (!subject) return res.status(400).json({ error: 'Please add a short subject' });
  if (!body) return res.status(400).json({ error: 'Please describe the problem' });

  const open = await pool.query(`SELECT COUNT(*)::int AS n FROM support_tickets WHERE account_id=$1 AND status='open'`, [req.auth.id]);
  if (open.rows[0].n >= MAX_OPEN) return res.status(429).json({ error: 'You already have several open requests. Please wait for a reply.' });
  if (await tooFast(req.auth.id)) return res.status(429).json({ error: 'You are sending too fast. Please try again later.' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const t = (await client.query(
      'INSERT INTO support_tickets (account_id, subject) VALUES ($1,$2) RETURNING id', [req.auth.id, subject])).rows[0];
    await client.query('INSERT INTO support_messages (ticket_id, from_admin, body) VALUES ($1,false,$2)', [t.id, body]);
    await client.query('COMMIT');
    res.json({ id: t.id });
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
});

async function tooFast(accountId) {
  const r = await pool.query(
    `SELECT COUNT(*)::int AS n FROM support_messages m JOIN support_tickets t ON t.id=m.ticket_id
      WHERE t.account_id=$1 AND NOT m.from_admin AND m.created_at > now() - interval '1 hour'`, [accountId]);
  return r.rows[0].n >= MAX_PER_HOUR;
}

// Messages of one of my tickets (also marks the admin's replies as read)
router.get('/:id', async (req, res) => {
  if (!isUuid(req.params.id)) return res.status(404).json({ error: 'not found' });
  const t = (await pool.query(
    'SELECT id, subject, status FROM support_tickets WHERE id=$1 AND account_id=$2', [req.params.id, req.auth.id])).rows[0];
  if (!t) return res.status(404).json({ error: 'not found' });
  const { rows } = await pool.query(
    'SELECT id, from_admin, body, created_at FROM support_messages WHERE ticket_id=$1 ORDER BY id', [t.id]);
  await pool.query('UPDATE support_tickets SET customer_unread=false WHERE id=$1 AND customer_unread', [t.id]);
  res.json({ ticket: t, messages: rows });
});

// Add a message to my open ticket
router.post('/:id/reply', async (req, res) => {
  if (!isUuid(req.params.id)) return res.status(404).json({ error: 'not found' });
  const body = clean(req.body.body, MAX_BODY);
  if (!body) return res.status(400).json({ error: 'Message is empty' });
  if (await tooFast(req.auth.id)) return res.status(429).json({ error: 'You are sending too fast. Please try again later.' });
  const t = (await pool.query(
    `UPDATE support_tickets SET needs_reply=true, updated_at=now()
      WHERE id=$1 AND account_id=$2 AND status='open' RETURNING id`, [req.params.id, req.auth.id])).rows[0];
  if (!t) return res.status(409).json({ error: 'This request is closed. Please open a new one.' });
  await pool.query('INSERT INTO support_messages (ticket_id, from_admin, body) VALUES ($1,false,$2)', [t.id, body]);
  res.json({ ok: true });
});

// ---- admin, mounted at /admin/tickets (before /admin)
const admin = express.Router();
admin.use(requireAuth(['admin']));

admin.get('/', async (req, res) => {
  const status = req.query.status === 'closed' ? 'closed' : 'open';
  const { rows } = await pool.query(
    `SELECT t.id, t.subject, t.status, t.needs_reply, t.updated_at, a.display_name, a.role, a.phone,
            (SELECT body FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.id DESC LIMIT 1) AS last_body
       FROM support_tickets t JOIN accounts a ON a.id=t.account_id
      WHERE t.status=$1 ORDER BY t.needs_reply DESC, t.updated_at DESC LIMIT 100`, [status]);
  res.json(rows);
});

admin.get('/:id', async (req, res) => {
  if (!isUuid(req.params.id)) return res.status(404).json({ error: 'not found' });
  const t = (await pool.query(
    `SELECT t.id, t.subject, t.status, a.display_name, a.role, a.phone
       FROM support_tickets t JOIN accounts a ON a.id=t.account_id WHERE t.id=$1`, [req.params.id])).rows[0];
  if (!t) return res.status(404).json({ error: 'not found' });
  const { rows } = await pool.query(
    'SELECT id, from_admin, body, created_at FROM support_messages WHERE ticket_id=$1 ORDER BY id', [t.id]);
  res.json({ ticket: t, messages: rows });
});

admin.post('/:id/reply', async (req, res) => {
  if (!isUuid(req.params.id)) return res.status(404).json({ error: 'not found' });
  const body = clean(req.body.body, MAX_BODY);
  if (!body) return res.status(400).json({ error: 'Reply is empty' });
  const t = (await pool.query(
    `UPDATE support_tickets SET needs_reply=false, customer_unread=true, updated_at=now()
      WHERE id=$1 AND status='open' RETURNING id`, [req.params.id])).rows[0];
  if (!t) return res.status(409).json({ error: 'Ticket is closed' });
  await pool.query('INSERT INTO support_messages (ticket_id, from_admin, body) VALUES ($1,true,$2)', [t.id, body]);
  res.json({ ok: true });
});

admin.post('/:id/close', async (req, res) => {
  if (!isUuid(req.params.id)) return res.status(404).json({ error: 'not found' });
  await pool.query(`UPDATE support_tickets SET status='closed', needs_reply=false, customer_unread=true, updated_at=now() WHERE id=$1`, [req.params.id]);
  res.json({ ok: true });
});

module.exports = { router, admin };
