const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Public support page, opened by the apps' "Customer Support" button. Edit the wording before launch.
module.exports = function supportPage(email) {
  const contact = email
    ? `Email us at <a href="mailto:${esc(email)}">${esc(email)}</a> and include the phone number registered on your account.`
    : 'Support contact details will be added here soon.';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Talkory Support</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:720px;margin:0 auto;padding:20px;color:#1c1e21;background:#fff}
@media(prefers-color-scheme:dark){body{background:#14151a;color:#eceef2}a{color:#9db4ff}}h1{font-size:26px}h2{font-size:18px;margin-top:26px}</style></head><body>
<h1>Talkory Support</h1><p>${contact}</p>
<h2>How is a call billed?</h2><p>Calls are charged per minute at the host's rate shown before you call. Billing runs in 15-second steps and each step is charged in advance, so the first 15 seconds of a connected call are always charged. The call ends automatically if your credits run out.</p>
<h2>My top-up did not show up</h2><p>Top-ups usually appear within a minute. Pull down to refresh the wallet. If it is still missing after 30 minutes, contact us with the payment reference from your bank or UPI app.</p>
<h2>Refunds</h2><p>[Describe your refund policy here: for example, unused credits within X days, and calls that failed to connect.]</p>
<h2>Someone behaved badly</h2><p>After any call you can tap <b>Report</b> or <b>Block</b>. Reports are reviewed by our team and accounts that break the rules are removed.</p>
<h2>Delete my account</h2><p>In the app: Profile, Privacy &amp; Security, Delete my account. See also <a href="/legal/delete-account">how deletion works</a>.</p>
<h2>Policies</h2><p><a href="/legal/terms">Terms of Service</a> &middot; <a href="/legal/privacy">Privacy Policy</a></p>
</body></html>`;
};
