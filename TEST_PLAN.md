# Real-device test plan

Use two phones (one Android for the partner app, any phone for the user app), a Razorpay **test mode** account and a Twilio account that can text both numbers.
Run `backend && npm run smoke` first (see README "Testing"): it covers the server rules. This list covers what only phones can show.

## Accounts and onboarding
- [ ] Sign up the user app and the partner app with real SMS codes; the "agree to Terms" box is required and the links open.
- [ ] Partner: fill My profile (languages, rate), submit KYC photos; approve it in the admin panel; the rejected path shows your reason.
- [ ] Partner cannot go online before approval; after approval going online works.

## Money
- [ ] User tops up with a Razorpay test payment: balance updates; Activity shows it. Kill the app right after paying: balance still arrives (webhook).
- [ ] Failed/cancelled payment shows a message and does not change the balance.

## Calls
- [ ] Partner app fully closed and phone locked: a call rings full screen with Accept/Decline (Android). iPhone: after IOS_VOIP.md, same.
- [ ] Both sides hear each other clearly; mute works; the timer matches on both phones.
- [ ] Caller hangs up before answer: partner's ring stops. Partner declines: caller is told.
- [ ] Partner ends: the user's call screen closes and the post-call screen opens. Same the other way round.
- [ ] Low balance: banner at 60s left (red at 30s), "Add credits" opens the wallet, top-up clears it; with no top-up the call ends by itself.
- [ ] Switch Wi-Fi/mobile data during a call, lock the screen for 2 minutes, take a phone call: note what happens (audio, billing).
- [ ] Kill both apps mid-call: the call ends on the server within about a minute and billing stops.
- [ ] Restart the backend container during a call (`docker compose restart api`): the call continues and billing carries on.

## After the call
- [ ] Rating changes the host's average; report shows in the admin Reports tab; block hides the host and stops further calls.
- [ ] Partner earnings screen: today, total and per-call lines match what the user paid (60% share). Withdrawal request, admin marks paid, status updates.

## Safety and cleanup
- [ ] Delete account in both apps; log in again with the same number: it is a brand-new account.
- [ ] Trigger an error on purpose (stop Postgres for a minute): the app shows a friendly message and Sentry gets the event.
- [ ] Rough load check: `npx autocannon -c 100 -d 20 -H "Authorization: Bearer <user token>" https://api.yourdomain.com/partners`. Errors should stay near zero; watch CPU on the server.
