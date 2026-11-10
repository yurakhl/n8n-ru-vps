#!/usr/bin/env bash
# Backup: PostgreSQL dump + n8n data volume (contains the encryption key config).
# Usage: ./backup.sh            (works from cron; run from any directory)
# Optional env: BACKUP_DIR (default ./backups), KEEP_BACKUPS (default 7)
set -euo pipefail

cd "$(dirname "$0")"
BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"
KEEP_BACKUPS="${KEEP_BACKUPS:-7}"

umask 077
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dest="$BACKUP_DIR/$stamp"
mkdir -p "$dest"

# Remove a half-written backup if anything fails.
trap 'rc=$?; if [ $rc -ne 0 ]; then rm -rf "$dest"; echo "Backup FAILED" >&2; fi' EXIT

docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$dest/n8n.dump"
docker compose exec -T n8n tar -czf - -C /home/node/.n8n . > "$dest/n8n-data.tar.gz"
cp .env "$dest/env.backup"

# Sanity checks: files are non-empty and readable.
[ -s "$dest/n8n.dump" ] && [ -s "$dest/n8n-data.tar.gz" ]
tar -tzf "$dest/n8n-data.tar.gz" > /dev/null

# Keep only the last KEEP_BACKUPS copies.
ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | sort | head -n "-$KEEP_BACKUPS" | while read -r old; do
  rm -rf "$old"
done

echo "Backup saved: $dest"
