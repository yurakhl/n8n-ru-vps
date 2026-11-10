#!/usr/bin/env bash
# Restore from a backup directory made by backup.sh.
# Usage: ./restore.sh backups/20261110T030000Z
# WARNING: replaces the current database and n8n data volume contents.
set -euo pipefail

cd "$(dirname "$0")"
src="${1:-}"
if [ -z "$src" ] || [ ! -s "$src/n8n.dump" ] || [ ! -s "$src/n8n-data.tar.gz" ]; then
  echo "Usage: $0 <backup-dir> (must contain n8n.dump and n8n-data.tar.gz)" >&2
  exit 1
fi
src="$(cd "$src" && pwd)"

echo "This will OVERWRITE the current n8n database and data with: $src"
read -r -p "Type YES to continue: " answer
[ "$answer" = "YES" ] || { echo "Cancelled."; exit 1; }

docker compose stop n8n
docker compose up -d postgres

echo "Waiting for PostgreSQL..."
for _ in $(seq 1 30); do
  if docker compose exec -T postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < "$src/n8n.dump"

docker compose run --rm --no-deps -T --user root --entrypoint sh n8n \
  -c 'find /home/node/.n8n -mindepth 1 -delete && tar -xzf - -C /home/node/.n8n && chown -R node:node /home/node/.n8n' \
  < "$src/n8n-data.tar.gz"

docker compose up -d
echo "Restore finished. Check the editor and your credentials."
echo "Note: .env must contain the same N8N_ENCRYPTION_KEY (see $src/env.backup)."
