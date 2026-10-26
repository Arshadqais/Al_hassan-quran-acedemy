#!/usr/bin/env bash
# Run on the academy server. Copy encrypted output to a separate, private device.
set -euo pipefail
: "${BACKUP_PASSPHRASE:?Set a strong backup passphrase securely in the server environment}"
output_dir="${1:?Usage: backup.sh /private/backup-directory}"
install -d -m 0700 "$output_dir"
umask 077
backup_path="$output_dir/academy-$(date -u +%Y%m%dT%H%M%SZ).dump.gpg"
if [[ -e "$backup_path" ]]; then
  echo 'Backup already exists for this second; refusing to overwrite.' >&2
  exit 1
fi
partial_path="$(mktemp "$output_dir/.academy-partial.XXXXXX")"
trap 'rm -f "$partial_path"' EXIT
install -d -m 0700 "$output_dir/.gnupg"
docker exec quran_academy_db pg_dump -U academy -d quran_academy -Fc |
  gpg --homedir "$output_dir/.gnupg" --batch --yes --no-symkey-cache \
    --pinentry-mode loopback --passphrase-fd 3 --symmetric --cipher-algo AES256 \
    --output "$partial_path" 3<<< "$BACKUP_PASSPHRASE"
# Do not announce an incomplete backup when pg_dump or encryption fails.
mv -n "$partial_path" "$backup_path"
printf 'Encrypted database backup saved: %s\n' "$backup_path"
