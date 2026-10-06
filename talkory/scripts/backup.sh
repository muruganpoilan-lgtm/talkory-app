#!/bin/sh
# Nightly Postgres backup, keeps 14 days. Run from the project folder.
set -e
mkdir -p backups
docker compose exec -T db pg_dump -U talkory talkory | gzip > "backups/talkory-$(date +%F).sql.gz"
find backups -name 'talkory-*.sql.gz' -mtime +14 -delete
docker compose exec -T api tar czf - -C /data kyc > "backups/kyc-$(date +%F).tar.gz"
find backups -name 'kyc-*.tar.gz' -mtime +14 -delete
docker compose exec -T api tar czf - -C /data avatars > "backups/avatars-$(date +%F).tar.gz"
find backups -name 'avatars-*.tar.gz' -mtime +14 -delete
