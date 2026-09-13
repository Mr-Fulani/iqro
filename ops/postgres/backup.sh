#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"

backup_dir=${BACKUP_DIR:-/backups}
retention_days=${BACKUP_RETENTION_DAYS:-0}
minimum_free_mb=${BACKUP_MIN_FREE_MB:-1024}

case "$backup_dir" in
    ""|/)
        echo "BACKUP_DIR must be a dedicated directory, not '/'." >&2
        exit 2
        ;;
esac
case "$retention_days" in
    *[!0-9]*|"")
        echo "BACKUP_RETENTION_DAYS must be a non-negative integer." >&2
        exit 2
        ;;
esac
case "$minimum_free_mb" in
    *[!0-9]*|"")
        echo "BACKUP_MIN_FREE_MB must be a non-negative integer." >&2
        exit 2
        ;;
esac

umask 077
mkdir -p "$backup_dir"

available_kb=$(df -Pk "$backup_dir" | awk 'NR == 2 {print $4}')
required_kb=$((minimum_free_mb * 1024))
if [ "$available_kb" -lt "$required_kb" ]; then
    echo "Backup refused: less than ${minimum_free_mb} MiB is free in BACKUP_DIR." >&2
    exit 1
fi

# Serialize manual and scheduled invocations that share this backup directory.
lock_dir="${backup_dir}/.backup.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "Another backup holds the directory lock; refusing concurrent writes." >&2
    exit 1
fi
partial_file=
cleanup_partial() {
    if [ -n "$partial_file" ]; then
        rm -f "$partial_file"
    fi
    rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup_partial EXIT HUP INT TERM

safe_database=$(printf '%s' "$PGDATABASE" | tr -c 'A-Za-z0-9_-' '_')
timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
backup_file="${backup_dir}/${safe_database}_${timestamp}.dump"
if [ -e "$backup_file" ] || [ -e "${backup_file}.partial" ] || [ -e "${backup_file}.sha256" ]; then
    echo "Backup filename already exists; refusing to overwrite it." >&2
    exit 1
fi
partial_file="${backup_file}.partial"

pg_dump \
    --dbname="$PGDATABASE" \
    --format=custom \
    --compress=9 \
    --no-owner \
    --no-privileges \
    --file="$partial_file"
pg_restore --list "$partial_file" >/dev/null
mv "$partial_file" "$backup_file"

backup_name=$(basename "$backup_file")
(
    cd "$backup_dir"
    sha256sum "$backup_name" >"${backup_name}.sha256"
)
rmdir "$lock_dir"
trap - EXIT HUP INT TERM

# Retention is never executed by a backup job. Cleanup requires separate approval.

echo "PostgreSQL backup created and archive structure verified."
echo "BACKUP_FILE=${backup_file}"
