# Talkory: open gaps before launch

## Must build (the app is not usable without these)
- [x] ~~Partner profile editing~~ built (name, bio, languages, rate). Profile photos built (admin reviews each one; metadata such as GPS is stripped).
- [ ] (old note) **Partner profile editing.** Partners sign up with an empty bio, no languages and a default ₹10/min rate, and nothing lets them change it.
      Users filter hosts by language, so partners without languages never show up. Needs an endpoint + screen (name, photo, bio, languages, rate).
- [x] **KYC submission** built (photos live in the `kycdata` Docker volume, backed up by scripts/backup.sh; decide how long you keep them). Old note: Partners cannot upload ID/selfie; the admin KYC tab approves blindly. Add document upload (private storage) and show it in the panel.
- [x] **Terms + privacy policy**: pages, signup acceptance and in-app links built. The text is a DRAFT: fill the [PLACEHOLDERS] in backend/legal/*.html and have a lawyer review it.

- [x] **Account deletion**: in-app flow + public page `/legal/delete-account` built. Fill in its [PLACEHOLDERS] and retention periods, and enter that URL in the Play Console data-safety/deletion section.

## Should build
- [x] User wallet activity (top-ups, calls, refunds) and balance on the home screen: built.
- [x] Per-IP rate limiting (general 600/min, OTP 20 per 10 min). Tune in server.js if real users get blocked.
- [x] Sentry error monitoring (backend + both apps) built: set SENTRY_DSN. Still do: an uptime monitor on /health (e.g. UptimeRobot) and a load test before a launch push.
- [x] iOS VoIP ring: backend + Dart done; one native Xcode step left, see IOS_VOIP.md (needs a Mac and a real iPhone).
- [x] Ring/billing timers now run on a BullMQ queue in Redis: restarts no longer drop calls and several API containers are safe.

## Business / legal (ask a professional, not me)
- [ ] Taxes on payouts and platform fees (e.g. TDS, GST in India) and how partners are classified.
- [ ] Refund and top-up policy; age verification beyond the 18+ checkbox; content moderation and a response process for reports.
- [ ] Whether and how you record or store calls (disclose it; the app does not record today).
- [ ] App store policies for apps that connect strangers (Google Play and Apple have rules on user-generated content and safety).

## Testing
- [ ] `npm run smoke` passes (README > Testing).
- [ ] `TEST_PLAN.md` done on real phones, including a restart of the backend during a call.
