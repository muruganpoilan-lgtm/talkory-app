# Deploying Talkory

## Fast path (Ubuntu VPS, e.g. Hostinger): one command
1. At your DNS provider add an **A record** `api` -> your server IP (so `api.talkory.tech` points to it).
2. Copy the project to the server and run the script (as root):
```
scp talkory.tar.gz root@SERVER_IP:~/ && ssh root@SERVER_IP
tar xzf talkory.tar.gz && cd talkory
ADMIN_PHONE=+91XXXXXXXXXX bash scripts/server-setup.sh api.talkory.tech
```
It installs Docker if needed, generates the secrets, starts everything, schedules nightly backups and checks the result.
Afterwards add your Agora/Razorpay/Twilio/Firebase keys to `.env` and run `docker compose up -d`. The manual steps below explain what the script does.

One small server runs everything with Docker: API, Postgres, Redis and Caddy (free automatic HTTPS).

## 1. Server and domain
- Rent a Linux VPS (Ubuntu 24.04, 2 vCPU / 4 GB RAM is plenty to start) in or near India, e.g. DigitalOcean Bangalore or AWS Lightsail Mumbai.
- Point a DNS **A record** (e.g. `api.yourdomain.com`) at the server's IP. Open ports 80 and 443 in the firewall.
- Install Docker: `curl -fsSL https://get.docker.com | sh`

## 2. Configure
```
scp -r talkory user@SERVER:~/ && ssh user@SERVER && cd talkory
cp .env.example .env && nano .env          # fill every value (openssl rand -hex 32 makes good secrets)
cp /path/to/firebase-service-account.json secrets/firebase-service-account.json
```

## 3. Start
```
docker compose up -d --build
docker compose logs -f api                  # expect: "Talkory backend running"
curl https://api.yourdomain.com/health      # {"ok":true}
```
The database schema is created automatically on the very first start.

## 4. Create your admin, then approve partners
```
docker compose exec db psql -U talkory -c "INSERT INTO accounts (role, phone, display_name, is_adult) VALUES ('admin','+91XXXXXXXXXX','Admin',true);"
```
Open `https://api.yourdomain.com/panel/` to log in. Partners are approved in the KYC tab.

## 5. Connect the services
- **Razorpay:** switch to Live keys in `.env`; webhook URL `https://api.yourdomain.com/webhooks/razorpay` (events `payment.captured`, `order.paid`).
- **Apps:** build releases pointing at your server:
  `flutter build appbundle --dart-define=API_URL=https://api.yourdomain.com` (run in each app folder). Remove `usesCleartextTraffic` from the Android manifest.

## 6. Backups and updates
- Backups: `crontab -e` then add `0 3 * * * cd ~/talkory && ./scripts/backup.sh`. Copy the `backups/` folder off the server regularly.
- Update: upload the new code, then `docker compose up -d --build`. On restart, any call in progress is closed automatically.

## Before real users (important)
1. **Twilio SMS login:** in the Twilio console create a **Verify service** (Verify > Services), then put the Account SID, Auth Token and the
   Service SID (starts with `VA`) into `.env` and keep `OTP_DEV_MODE=false`. A Twilio **trial** account can only text numbers you have verified
   in the console, so upgrade before real users. Sending SMS to Indian numbers has local registration (DLT) rules: check Twilio's current
   India requirements for your account before launch. Phone numbers must include the country code (+91...).
2. **Redis must keep its data.** Call timers now live in Redis (the compose file already enables persistence). Do not wipe the `redisdata` volume while calls are in progress. You may now run more than one API container.
3. Lock down `/panel` (see the Caddyfile comment) and never expose Postgres or Redis ports.
4. Have a privacy policy, terms of service and refund policy ready: the app stores phone numbers and call history, and app stores and Razorpay will ask for them.
5. Do a full test on real phones: sign up, top up, call, low-balance cut-off, rating, withdrawal.

## Monitoring
- Create a free Sentry project, put its DSN in `SENTRY_DSN` (backend) and pass `--dart-define=SENTRY_DSN=...` when building the apps.
- Add an uptime monitor (e.g. UptimeRobot) on `https://api.yourdomain.com/health` with email/SMS alerts.

## Alternative: Hostinger Docker Manager, no terminal (Compose from URL)
1. **Build the API image on GitHub (once):** repository > Actions > **Publish API image** > Run workflow. Wait for the green tick. Then GitHub profile > Packages > `talkory-api` > Package settings > Change visibility > **Public**.
2. **Put the compose file on a link:** gist.github.com > filename `docker-compose.yml` > paste `docker-compose.hostinger.yml` (with REPLACE_GITHUB_USERNAME changed) > **Create secret gist** > click **Raw** > copy that address. The file holds no passwords, so a secret gist (anyone with the link) is fine.
3. **Docker Manager > Compose > Compose from URL:** paste the Raw link, project name `talkory`, add environment variable `ADMIN_PHONE=+91...`, Deploy.
First start creates the database tables, your admin login and the login-token secret automatically. Add Agora/Razorpay/Twilio keys later as environment variables and redeploy; then set `OTP_DEV_MODE=false`.
Prefer to keep the code private? Use the terminal path above instead.
