#!/usr/bin/env bash
# One-command setup for a fresh Ubuntu VPS (e.g. Hostinger VPS). Run as root, from anywhere:
#   bash scripts/server-setup.sh api.talkory.tech
# Optional: ADMIN_PHONE=+91XXXXXXXXXX bash scripts/server-setup.sh api.talkory.tech   (also creates your admin login)
# Safe to run again: it keeps your existing .env and data.
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || { echo "Usage: bash scripts/server-setup.sh api.yourdomain.com"; exit 1; }
[[ $EUID -eq 0 || -n "${SETUP_TEST:-}" ]] || { echo "Please run as root (on Hostinger you are root by default)."; exit 1; }

echo "== 1/6 Docker"
if ! docker compose version >/dev/null 2>&1; then
  command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
  apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
fi
docker compose version

echo "== 2/6 DNS check"
IP="$(curl -fsS https://api.ipify.org 2>/dev/null || true)"
RESOLVED="$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || true)"
if [[ -n "$IP" && "$RESOLVED" != "$IP" ]]; then
  echo "WARNING: $DOMAIN points to '${RESOLVED:-nothing yet}' but this server is $IP."
  echo "         Add an A record  api -> $IP  at your DNS provider. HTTPS starts working once it resolves. Continuing..."
else
  echo "OK: $DOMAIN -> $IP"
fi

echo "== 3/6 Firewall"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 22/tcp >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
  echo "ufw: ports 22, 80, 443 open"
else
  echo "no active ufw firewall (if you enabled Hostinger's firewall in hPanel, allow ports 22, 80, 443 there)"
fi

echo "== 4/6 Settings (.env)"
mkdir -p secrets backups
if [[ ! -f .env ]]; then
  rnd() { openssl rand -hex 32; }
  cat > .env <<ENV_END
DOMAIN=$DOMAIN
POSTGRES_PASSWORD=$(rnd)
JWT_SECRET=$(rnd)
# true = login codes are printed in the server log instead of sent by SMS. Set false once Twilio is configured.
OTP_DEV_MODE=true
TERMS_VERSION=2026-10-03

AGORA_APP_ID=
AGORA_APP_CERT=
RAZORPAY_KEY_ID=
RAZORPAY_KEY_SECRET=
RAZORPAY_WEBHOOK_SECRET=
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_VERIFY_SID=
SENTRY_DSN=
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_BUNDLE_ID=
APNS_PRODUCTION=false
ENV_END
  chmod 600 .env
  echo "created .env with fresh random secrets"
else
  sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
  echo "kept existing .env (domain set to $DOMAIN)"
fi

echo "== 5/6 Starting everything (first build takes a few minutes)"
docker compose up -d --build

echo "== 6/6 Waiting for the server"
OK_LOCAL=""
for _ in $(seq 1 40); do
  if docker compose exec -T api wget -qO- http://localhost:3000/health 2>/dev/null | grep -q '"ok":true'; then OK_LOCAL=1; break; fi
  sleep 3
done
[[ -n "$OK_LOCAL" ]] && echo "API is running inside the server" || { echo "API did not start. Run: docker compose logs api --tail 80"; exit 1; }

if [[ -n "${ADMIN_PHONE:-}" ]]; then
  if [[ "$ADMIN_PHONE" =~ ^\+[0-9]{8,15}$ ]]; then
    docker compose exec -T db psql -U talkory -c "INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin','$ADMIN_PHONE','Admin',true) ON CONFLICT (phone) DO NOTHING;" >/dev/null
    echo "admin account ready for $ADMIN_PHONE (log in at https://$DOMAIN/panel/)"
  else
    echo "ADMIN_PHONE must look like +919876543210, skipped"
  fi
fi

# nightly backup at 03:00 (replaces any earlier entry)
( crontab -l 2>/dev/null | grep -v "scripts/backup.sh" || true; echo "0 3 * * * cd $PWD && bash scripts/backup.sh >> backups/backup.log 2>&1" ) | crontab -
echo "nightly backup scheduled (backups/ folder, 14 days kept)"

PUBLIC="$(curl -fsS "https://$DOMAIN/health" 2>/dev/null || true)"
echo
if echo "$PUBLIC" | grep -q '"ok":true'; then
  echo "SUCCESS: https://$DOMAIN/health works. Backend is live."
else
  echo "Server is up, but https://$DOMAIN/health does not answer yet. Usually the DNS record is still propagating:"
  echo "  wait 5-10 minutes and open https://$DOMAIN/health in a browser. Still failing? docker compose logs caddy --tail 40"
fi
cat <<'NEXT_END'

Next:
 - Login codes: while OTP_DEV_MODE=true, read them with:  docker compose logs api | grep DEV
 - To turn on calls, payments and real SMS, put your keys in .env (nano .env) and run:  docker compose up -d
     Agora (voice), Razorpay (payments), Twilio Verify (SMS), Firebase (see BUILD.md). Then set OTP_DEV_MODE=false.
 - Update later:  upload the new files, then  docker compose up -d --build
NEXT_END
