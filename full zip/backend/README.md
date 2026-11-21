# Talkory Backend

1. `createdb talkory && psql talkory -f schema.sql`
2. `cp .env.example .env` and fill in values (Agora keys from console.agora.io)
3. `npm install && npm run dev`  (needs Redis running)

## Endpoints
- POST /auth/request-otp, /auth/verify-otp  (role: user | partner)
- POST /partners/online  (partner)       GET /partners?language=hindi  (user)
- POST /calls  (user) -> POST /calls/:id/accept | reject  (partner) -> POST /calls/:id/end

## Before production
- Real SMS provider; WebSocket/push for ringing; BullMQ for ring/billing timers
- Run `UPDATE partner_profiles SET kyc='approved'` manually to test partners
- Payments (top-up) endpoint, payouts, admin panel
