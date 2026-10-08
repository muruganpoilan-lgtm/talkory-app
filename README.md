# Talkory (monorepo)

- `backend/`                 Node.js + PostgreSQL + Redis (see backend/README.md)
- `packages/talkory_core/`   shared API client, OTP login, in-call screen (Agora)
- `apps/talkory_user/`       Talkory (users)
- `apps/talkory_partner/`    Talkory Partner (hosts)

## First run
1. Start the backend (backend/README.md). Put your Agora App ID + certificate in backend/.env.
2. Generate platform folders (one time per app):
   cd apps/talkory_user    && flutter create . --org com.yourcompany --project-name talkory_user
   cd apps/talkory_partner && flutter create . --org com.yourcompany --project-name talkory_partner
   (keeps lib/ and pubspec.yaml; adds android/ and ios/)
3. Android: in android/app/src/main/AndroidManifest.xml add
   INTERNET, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, BLUETOOTH_CONNECT permissions; set minSdkVersion 21+.
   For a plain-http dev server add android:usesCleartextTraffic="true" to <application> (dev only).
4. iOS: add NSMicrophoneUsageDescription to ios/Runner/Info.plist.
5. Run: flutter run --dart-define=API_URL=http://10.0.2.2:3000
   (physical phone: use your computer's LAN IP; production: your https URL)

## Test a call end to end
- Backend OTP_DEV_MODE=true prints OTPs in the server console.
- Sign up one partner and approve KYC:  UPDATE partner_profiles SET kyc='approved';
- Give the user credits:                UPDATE wallets SET balance = 100000 WHERE account_id = '<user id>';
- Partner app: go online. User app: pick the host and call.

## Not built yet
Wallet top-up (Razorpay/Stripe), earnings/payout screens, push + CallKit for incoming calls,
ratings screen after call, report/block buttons, admin panel.

## Razorpay wallet top-up
1. Create a Razorpay account, use **Test Mode** first. Copy Key ID + Key Secret into backend/.env.
2. Run the new table: `psql talkory -f backend/schema.sql` (only the topup_orders block is new; skip the rest if already applied).
3. Dashboard > Settings > Webhooks: add `https://<your-public-url>/webhooks/razorpay`,
   events `payment.captured` and `order.paid`, and put the secret you choose in RAZORPAY_WEBHOOK_SECRET.
   (Local dev: expose the backend with ngrok.)
4. In the user app run `flutter pub get`, then top up with Razorpay test cards/UPI.
Amounts are always computed on the server (₹100 to ₹10,000), the app only sends a rupee value.

## Partner earnings & payouts
- Existing database: `psql talkory -f backend/migrations/002_payouts.sql` (fresh installs get it via schema.sql).
- Partner app: Earnings screen (balance, today, total, pending, withdrawn, call history, payout history),
  UPI ID, withdrawal requests (min ₹500, one open request at a time, KYC approved only).
- A withdrawal request holds the money immediately (wallet debit + ledger entry). You then pay it manually and mark it paid;
  rejecting returns the money to the partner's wallet.

### Admin (no panel yet, use curl)
1. Create an admin: `INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin', '+91XXXXXXXXXX', 'Admin', true);`
2. Log in: request-otp, then verify-otp with `"role": "admin"` to get a token.
3. List pending:  `GET  /partner/admin/payouts?status=requested`
4. After sending the money:  `POST /partner/admin/payouts/<id>/paid`   body `{"reference": "UPI txn id"}`
5. Or reject + refund:        `POST /partner/admin/payouts/<id>/reject`
Later you can automate step 4 with RazorpayX Payouts. Bank details are not collected here; keep UPI IDs access-restricted.

## Push notifications for incoming calls (partner app)
**How it works:** user starts a call -> backend sends an FCM push to the partner's phone(s) -> the app shows a native
full-screen incoming-call UI (flutter_callkit_incoming), even when closed -> Accept calls the backend and joins the call.
If the caller hangs up or the 20s ring times out, a cancel push dismisses the ringing screen.

### One-time setup
1. Firebase console: create a project, add an Android app (package name = the one you gave `flutter create --org`) and an iOS app.
2. Android: download `google-services.json` into `apps/talkory_partner/android/app/`, then add the Google services
   Gradle plugin (follow the Firebase "Add Firebase to your Flutter app" Android steps). Alternatively run `flutterfire configure`.
3. AndroidManifest.xml permissions: POST_NOTIFICATIONS, USE_FULL_SCREEN_INTENT, FOREGROUND_SERVICE,
   FOREGROUND_SERVICE_MICROPHONE, WAKE_LOCK, VIBRATE (plus the earlier INTERNET / RECORD_AUDIO ones).
4. Backend: Firebase console > Project settings > Service accounts > Generate new private key. Save it as
   `backend/firebase-service-account.json` (it is git-ignored) and keep `FIREBASE_SERVICE_ACCOUNT` in .env. Then `npm install`.
5. `cd apps/talkory_partner && flutter pub get`, then test on a **real Android phone** (emulators are unreliable for push).

### Test
Partner phone: log in, go online, then close the app completely. Call that partner from the user app: the phone should ring
with an Accept / Decline screen.

### iOS (read this)
- Needs Push Notifications + Background Modes (Remote notifications, Audio) enabled in Xcode, and an APNs key uploaded in Firebase.
- Today iOS gets a normal time-sensitive notification, not the full-screen CallKit ring. Apple only allows the full ring for
  VoIP (PushKit) pushes, which FCM cannot send. To get it later: send a VoIP push from the backend through APNs (`apns2` / `node-apn`)
  and pass the token from `FlutterCallkitIncoming.getDevicePushTokenVoIP()`.
- Calls stay audible with the screen off on Android once connected, but keeping the mic alive when the app is backgrounded
  needs a foreground service. Test this early on real devices.

## Admin web panel
- Run `psql talkory -f backend/migrations/003_reports_status.sql`, restart the backend, open `http://localhost:3000/panel/`.
- Log in with an admin phone (see "Admin" above) and its OTP. Tabs: **Payouts** (mark paid / reject + refund), **KYC** (approve / reject partners), **Reports** (dismiss or block the reported account).
- Reports only appear once the user app has a report button (next feature); the table and panel are ready.
- Serve it over HTTPS in production and restrict `/panel` by IP or VPN.

## Post-call screen (rating, report, block)
After a connected call both apps open a screen: users give 1-5 stars + comment (updates the host's average rating);
either side can report (shows up in the admin panel's Reports tab) or block. Blocked pairs are hidden from each other's
host list and the server refuses calls between them. No database changes are needed.

## Low-balance warning
During a call the screen checks `GET /calls/:id/status` every 5s. When the user has 60s or less of talk time left a banner appears
(red at 30s) with an "Add credits" button that opens the wallet over the call, plus a vibration. After a top-up the banner clears.
The same check makes both phones leave the call as soon as the server ends it (balance used up), so audio can't continue unbilled.

## KYC documents
Partners submit an ID photo and a selfie (Verification card). Photos are stored in the private `kycdata` volume (never served publicly),
and only admins can view them in the panel's KYC tab, where you approve or reject with a reason the partner sees.
Run `psql talkory -f backend/migrations/004_kyc.sql` on an existing database, then `flutter pub get` in the partner app.
iOS Info.plist needs `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.

## User wallet
The user app's wallet shows the balance, top-up (Razorpay) and an Activity list: top-ups, refunds and one line per call
(host, duration, amount) instead of one per 15-second charge. The balance is also shown in the home screen's top bar.
No database changes are needed.

## Terms and Privacy
- Draft pages are served at `/legal/terms` and `/legal/privacy` (edit `backend/legal/*.html`). Use these public URLs in the Play Store/App Store listings and for Razorpay.
- Signup and login now require ticking "I agree to the Terms and Privacy Policy"; the accepted version and time are stored on the account.
- When you change the text, bump `TERMS_VERSION` (env var, e.g. in `.env` and docker-compose) so everyone must accept again at next login.
- Run `psql talkory -f backend/migrations/005_terms.sql` on an existing database (existing users will be asked to accept once). Then `flutter pub get` in both apps.

## Account deletion
- In both apps: info icon > Delete my account > type DELETE. Personal data is removed (phone, name, bio, UPI ID, KYC photos, push tokens, rating comments);
  payment/call records stay without personal details so your accounting still balances. The same phone number can later sign up as a new account.
- Hosts with ₹500+ in their wallet or a withdrawal in progress must finish that first. Users/hosts with a smaller balance lose it (the dialog says so).
- Public page for the app stores: `https://<your-domain>/legal/delete-account`.
- Requests that arrive by email: verify the person owns the number, then `POST /admin/accounts/<account id>/delete` with an admin token.
- Run `psql talkory -f backend/migrations/006_account_deletion.sql` on an existing database.

## Hardening round
- **Call timers in Redis (BullMQ):** ring timeout, 15s billing and a once-a-minute safety sweep run from a queue, so deploys/restarts no longer end calls and billing continues. Run `npm install` (new packages: bullmq, @sentry/node, express-rate-limit, express-async-errors).
- **Errors:** async route errors now return a 500 instead of crashing the server; Sentry (optional) captures them. Apps: `--dart-define=SENTRY_DSN=...`.
- **Rate limits:** per-IP limits on the API, tighter on OTP requests.
- **iOS ring:** run `migrations/007_voip_token.sql`, then follow IOS_VOIP.md.

## Testing
**Automated API check (about 100s, dev database only):**
```
# 1) Postgres + Redis locally
docker run -d --name tk-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=talkory -p 5432:5432 postgres:16-alpine
docker run -d --name tk-redis -p 6379:6379 redis:7-alpine
cd backend && psql postgres://postgres:postgres@localhost:5432/talkory -f schema.sql

# 2) backend/.env (copy .env.example, then set):
DATABASE_URL=postgres://postgres:postgres@localhost:5432/talkory
REDIS_URL=redis://localhost:6379
JWT_SECRET=test-secret
OTP_DEV_MODE=true
OTP_TEST_CODE=123456
AGORA_APP_ID=0123456789abcdef0123456789abcdef
AGORA_APP_CERT=0123456789abcdef0123456789abcdef

# 3) run
npm install && npm run dev        # terminal 1
npm run smoke                     # terminal 2
```
`OTP_TEST_CODE` is ignored when `NODE_ENV=production` (the Docker image), so it cannot be abused on the live server. The script refuses to run against a non-local database.
The OTP rate limit is 20 per 10 minutes per IP, enough for about three runs in a row.

**On phones:** follow `TEST_PLAN.md`.

## Profile photos
Hosts add a photo in My profile (camera or gallery). It waits in a private folder until you approve it in the admin panel's **Photos** tab;
only then does it appear in the user app's host list. GPS/camera metadata is stripped on upload. Replacing a photo keeps the old one visible
until the new one is approved. Run `psql talkory -f backend/migrations/008_avatars.sql` on an existing database. Photos live in the `avatars` Docker volume (included in the nightly backup).

Build instructions for the apps: see BUILD.md (one command: bash scripts/build-apps.sh).
