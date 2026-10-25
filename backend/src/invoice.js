const { pool, requireAuth } = require('./db');
const jwt = require('jsonwebtoken');
const { GST_PERCENT } = require('./paydays');

const CO = process.env.COMPANY_NAME || 'Talkory Tech';
const ADDRESS = process.env.COMPANY_ADDRESS || '105A, Green groov, Jeyam Nagar, Kanchivakkam, Sriperumbudur, Chennai - 601301, India';
const GSTIN = process.env.COMPANY_GSTIN || '';
const LOGO = require('./invoice_logo.json'); // Talkory Tech logo, 240x240, RGB + transparency, pre-compressed for the PDF

const rs = (paise) => 'Rs. ' + (Number(paise) / 100).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const dmy = (d) => new Date(d).toLocaleDateString('en-GB', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', year: 'numeric' });

// ---- a tiny one-page PDF writer (no libraries): lines of text in Helvetica
const imgRgb = Buffer.from(LOGO.rgb, 'base64'), imgAlpha = Buffer.from(LOGO.alpha, 'base64');
const clean = (s) => String(s ?? '').replace(/[^\x20-\x7e]/g, '?').replace(/([\\()])/g, '\\$1');
function makePdf(items) { // items: { t, x, y, size, bold } ; { rule: y } ; { logo: [x, y, size] }
  let c = '';
  for (const it of items) {
    if (it.logo) { const [x, y, sz] = it.logo; c += `q ${sz} 0 0 ${sz} ${x} ${y} cm /Im1 Do Q\n`; continue; }
    if (it.rule != null) { c += `0.6 w 50 ${it.rule} m 545 ${it.rule} l S\n`; continue; }
    c += `BT /${it.bold ? 'F2' : 'F1'} ${it.size || 11} Tf ${it.x} ${it.y} Td (${clean(it.t)}) Tj ET\n`;
  }
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> /XObject << /Im1 7 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Length ${Buffer.byteLength(c, 'latin1')} >>\nstream\n${c}endstream`,
    `<< /Type /XObject /Subtype /Image /Width ${LOGO.w} /Height ${LOGO.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /SMask 8 0 R /Length ${imgRgb.length} >>\nstream\n${imgRgb.toString('latin1')}\nendstream`,
    `<< /Type /XObject /Subtype /Image /Width ${LOGO.w} /Height ${LOGO.h} /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${imgAlpha.length} >>\nstream\n${imgAlpha.toString('latin1')}\nendstream`,
  ];
  let out = '%PDF-1.4\n';
  const offs = [];
  objs.forEach((o, i) => { offs.push(Buffer.byteLength(out, 'latin1')); out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = Buffer.byteLength(out, 'latin1');
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('');
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

function buildPdf(d) {
  const L = [];
  let y = 790;
  const line = (t, o = {}) => { L.push({ t, x: o.x ?? 50, y, size: o.size, bold: o.bold }); y -= o.gap ?? 18; };
  L.push({ logo: [50, 725, 72] });
  y = 772;
  line(CO, { x: 134, size: 18, bold: true, gap: 16 });
  line(ADDRESS, { x: 134, size: 8, gap: 12 });
  if (GSTIN) line('GSTIN: ' + GSTIN, { x: 134, size: 9, gap: 12 });
  y = 700;
  line('PAYOUT INVOICE', { size: 15, bold: true, gap: 22 });
  line('Invoice no: ' + d.invoice_no, { size: 11, gap: 15 });
  line('Date: ' + dmy(d.paid_at), { size: 11, gap: 15 });
  line('Payout ref: ' + d.id.slice(0, 8).toUpperCase(), { size: 11, gap: 22 });
  L.push({ rule: y + 10 }); y -= 8;
  line('Paid to', { bold: true, gap: 16 });
  line(d.host_name, { gap: 15 });
  line('UPI ID: ' + (d.upi_id || '-'), { gap: 15 });
  if (d.reference) line('Bank/UPI reference: ' + d.reference, { gap: 22 }); else y -= 7;
  L.push({ rule: y + 10 }); y -= 8;
  const row = (a, b, bold) => { L.push({ t: a, x: 50, y, bold }); L.push({ t: b, x: 400, y, bold }); y -= 20; };
  row('Description', 'Amount', true);
  row('Earnings withdrawn (requested ' + dmy(d.requested_at) + ')', rs(d.gross), false);
  row(`Less: GST deducted at ${GST_PERCENT}%`, '- ' + rs(d.gst), false);
  L.push({ rule: y + 12 }); y -= 6;
  row('Net amount paid to you', rs(d.net), true);
  y -= 14;
  line('The GST shown was deducted from your earnings and is kept by ' + CO + ' for payment to the tax authority.', { size: 9, gap: 12 });
  line('Please keep this invoice for your records. This is a computer-generated document and needs no signature.', { size: 9, gap: 12 });
  return makePdf(L);
}

// Receipt for a paid coin purchase (what the user paid by UPI / card)
const TOPUP_GST_PERCENT = Number(process.env.TOPUP_GST_PERCENT ?? 18);
function buildReceiptPdf(d) {
  const L = [];
  let y = 772;
  const line = (t, o = {}) => { L.push({ t, x: o.x ?? 50, y, size: o.size, bold: o.bold }); y -= o.gap ?? 18; };
  L.push({ logo: [50, 725, 72] });
  line(CO, { x: 134, size: 18, bold: true, gap: 16 });
  line(ADDRESS, { x: 134, size: 8, gap: 12 });
  if (GSTIN) line('GSTIN: ' + GSTIN, { x: 134, size: 9, gap: 12 });
  y = 700;
  line('PAYMENT INVOICE', { size: 15, bold: true, gap: 22 });
  line('Invoice no: ' + d.invoice_no, { gap: 15 });
  line('Date: ' + dmy(d.paid_at), { gap: 15 });
  line('Payment ID: ' + (d.payment_id || '-'), { gap: 22 });
  L.push({ rule: y + 10 }); y -= 8;
  line('Billed to', { bold: true, gap: 16 });
  line(d.user_name, { gap: 15 });
  line('Mobile: ' + d.phone_masked, { gap: 22 });
  L.push({ rule: y + 10 }); y -= 8;
  const row = (a, b, bold) => { L.push({ t: a, x: 50, y, bold }); L.push({ t: b, x: 400, y, bold }); y -= 20; };
  row('Description', 'Amount', true);
  row(`Talkory coins: ${d.coins} coins (1 coin = Rs. 1 of call and chat time)`, rs(d.pay), false);
  if (GSTIN && TOPUP_GST_PERCENT > 0) {
    const taxable = Math.round(d.pay * 100 / (100 + TOPUP_GST_PERCENT));
    row('   of which value of coins', rs(taxable), false);
    row(`   of which GST at ${TOPUP_GST_PERCENT}%`, rs(d.pay - taxable), false);
  }
  L.push({ rule: y + 12 }); y -= 6;
  row('Total paid', rs(d.pay), true);
  y -= 14;
  line('Paid online through UPI / card. The amount shown includes all applicable taxes.', { size: 9, gap: 12 });
  line('Coins are used for calls and chats in the app. This is a computer-generated document and needs no signature.', { size: 9, gap: 12 });
  return makePdf(L);
}

// Make (once) the receipt of a paid coin purchase. Safe to call again.
async function createReceipt(orderId) {
  const d = (await pool.query(
    `SELECT o.id, o.amount, o.pay_amount, o.razorpay_payment_id AS payment_id, o.paid_at, a.display_name AS user_name, a.phone
       FROM topup_orders o JOIN accounts a ON a.id=o.account_id
      WHERE o.id=$1 AND o.status='paid' AND NOT EXISTS (SELECT 1 FROM topup_invoices i WHERE i.order_id=o.id)`, [orderId])).rows[0];
  if (!d) return false;
  const no = (await pool.query(
    `SELECT 'TT/R/' || to_char(now() AT TIME ZONE 'Asia/Kolkata','YYMM') || '/' || lpad(nextval('receipt_seq')::text, 5, '0') AS n`)).rows[0].n;
  const ph = String(d.phone || '');
  const masked = ph.length > 4 ? ph.slice(0, 3) + 'XXXXXX' + ph.slice(-4) : 'XXXX';
  const pdf = buildReceiptPdf({
    invoice_no: no, paid_at: d.paid_at, payment_id: d.payment_id, user_name: d.user_name, phone_masked: masked,
    coins: Number(d.amount) / 100, pay: Number(d.pay_amount ?? d.amount),
  });
  await pool.query('INSERT INTO topup_invoices (order_id, invoice_no, pdf) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [orderId, no, pdf]);
  return true;
}

// Make (once) the invoice of a paid payout. Safe to call again.
async function create(payoutId) {
  const d = (await pool.query(
    `SELECT p.id, p.amount, p.gst_paise, p.net_paise, p.upi_id, p.reference, p.paid_at, p.requested_at, p.invoice_no,
            COALESCE(c.full_name, a.display_name) AS host_name
       FROM payouts p JOIN accounts a ON a.id=p.partner_id LEFT JOIN partner_contracts c ON c.partner_id=p.partner_id
      WHERE p.id=$1 AND p.status='paid' AND p.net_paise IS NOT NULL`, [payoutId])).rows[0];
  if (!d) return false;
  if (d.invoice_no) return true;
  const no = (await pool.query(
    `SELECT 'TT/' || to_char(now() AT TIME ZONE 'Asia/Kolkata','YYMM') || '/' || lpad(nextval('invoice_seq')::text, 5, '0') AS n`)).rows[0].n;
  const pdf = buildPdf({ ...d, invoice_no: no, gross: Number(d.amount), gst: Number(d.gst_paise), net: Number(d.net_paise) });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const upd = await client.query('UPDATE payouts SET invoice_no=$2 WHERE id=$1 AND invoice_no IS NULL', [payoutId, no]);
    if (upd.rowCount) await client.query('INSERT INTO payout_invoices (payout_id, invoice_no, pdf) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [payoutId, no, pdf]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  return true;
}

// Paid payouts that have no invoice yet (for example paid by hand a moment ago). Called from the minute sweep.
async function sweep() {
  const { rows } = await pool.query(`SELECT id FROM payouts WHERE status='paid' AND net_paise IS NOT NULL AND invoice_no IS NULL LIMIT 20`);
  for (const r of rows) await create(r.id);
  const t = await pool.query(`SELECT o.id FROM topup_orders o WHERE o.status='paid' AND NOT EXISTS (SELECT 1 FROM topup_invoices i WHERE i.order_id=o.id) LIMIT 20`);
  for (const r of t.rows) await createReceipt(r.id);
}

// ---- download links. The apps open a PDF in the browser, which cannot send the login header, so they ask for a 5-minute link.
const linkFor = (id, who) => `/invoices/${id}.pdf?t=${jwt.sign({ inv: id, who }, process.env.JWT_SECRET, { expiresIn: '5m' })}`;
const ID_RE = /^[0-9a-f-]{36}$/i;

const router = require('express').Router();
// host: link to one of my own invoices
router.get('/mine/:id/link', requireAuth(['partner']), async (req, res) => {
  if (!ID_RE.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const ok = (await pool.query('SELECT 1 FROM payout_invoices i JOIN payouts p ON p.id=i.payout_id WHERE i.payout_id=$1 AND p.partner_id=$2', [req.params.id, req.auth.id])).rowCount;
  if (!ok) return res.status(404).json({ error: 'Invoice is not ready yet' });
  res.json({ url: linkFor(req.params.id, 'host') });
});
// user: link to the receipt of one of my own coin purchases
router.get('/receipt/:id/link', requireAuth(['user']), async (req, res) => {
  if (!ID_RE.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const ok = (await pool.query('SELECT 1 FROM topup_invoices i JOIN topup_orders o ON o.id=i.order_id WHERE i.order_id=$1 AND o.account_id=$2', [req.params.id, req.auth.id])).rowCount;
  if (!ok) return res.status(404).json({ error: 'Invoice is not ready yet' });
  res.json({ url: linkFor(req.params.id, 'user') });
});
// admin: link to any receipt
router.get('/admin-receipt/:id/link', requireAuth(['admin']), async (req, res) => {
  if (!ID_RE.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const ok = (await pool.query('SELECT 1 FROM topup_invoices WHERE order_id=$1', [req.params.id])).rowCount;
  if (!ok) return res.status(404).json({ error: 'Invoice is not ready yet' });
  res.json({ url: linkFor(req.params.id, 'admin') });
});
// admin: link to any invoice
router.get('/admin/:id/link', requireAuth(['admin']), async (req, res) => {
  if (!ID_RE.test(req.params.id)) return res.status(404).json({ error: 'not found' });
  const ok = (await pool.query('SELECT 1 FROM payout_invoices WHERE payout_id=$1', [req.params.id])).rowCount;
  if (!ok) return res.status(404).json({ error: 'Invoice is not ready yet' });
  res.json({ url: linkFor(req.params.id, 'admin') });
});
// the PDF itself, opened from a link
router.get('/:file', async (req, res) => {
  const id = String(req.params.file).replace(/\.pdf$/, '');
  try {
    const t = jwt.verify(String(req.query.t || ''), process.env.JWT_SECRET);
    if (t.inv !== id || !ID_RE.test(id)) throw new Error('bad');
  } catch { return res.status(403).send('This link has expired. Open the invoice again from the app.'); }
  const row = (await pool.query('SELECT invoice_no, pdf FROM payout_invoices WHERE payout_id=$1 UNION ALL SELECT invoice_no, pdf FROM topup_invoices WHERE order_id=$1', [id])).rows[0];
  if (!row) return res.status(404).send('Not found');
  res.set({ 'Content-Type': 'application/pdf', 'Content-Disposition': `inline; filename="invoice-${row.invoice_no.replace(/\//g, '-')}.pdf"`, 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' }).send(row.pdf);
});

// admin list of all invoices (the admin's copy)
const admin = require('express').Router();
admin.use(requireAuth(['admin']));
admin.get('/', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT p.id, i.invoice_no, a.display_name, p.amount, p.gst_paise, p.net_paise, p.paid_at
       FROM payout_invoices i JOIN payouts p ON p.id=i.payout_id JOIN accounts a ON a.id=p.partner_id
      ORDER BY p.paid_at DESC LIMIT 200`);
  res.json(rows.map((r) => ({ ...r, amount: Number(r.amount), gst_paise: Number(r.gst_paise), net_paise: Number(r.net_paise) })));
});

admin.get('/receipts', async (req, res) => {
  const { rows } = await pool.query(
    `SELECT o.id, i.invoice_no, a.display_name, o.amount, COALESCE(o.pay_amount, o.amount) AS paid, o.paid_at
       FROM topup_invoices i JOIN topup_orders o ON o.id=i.order_id JOIN accounts a ON a.id=o.account_id
      ORDER BY o.paid_at DESC LIMIT 200`);
  res.json(rows.map((r) => ({ ...r, amount: Number(r.amount), paid: Number(r.paid) })));
});

module.exports = { create, createReceipt, sweep, router, admin, buildPdf, buildReceiptPdf };
