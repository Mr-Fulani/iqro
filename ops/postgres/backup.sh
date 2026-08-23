#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"

backup_dir=${BACKUP_DIR:-/backups}
retention_days=${BACKUP_RETENTION_DAYS:-14}
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

safe_database=$(printf '%s' "$PGDATABASE" | tr -c 'A-Za-z0-9_-' '_')
timestamp=$(date -u '+%Y%m%dT%H%M%SZ')
backup_file="${backup_dir}/${safe_database}_${timestamp}.dump"
partial_file="${backup_file}.partial"

cleanup_partial() {
    rm -f "$partial_file"
}
trap cleanup_partial EXIT HUP INT TERM

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
trap - EXIT HUP INT TERM

if [ "$retention_days" -gt 0 ]; then
    find "$backup_dir" -maxdepth 1 -type f \
        \( -name "${safe_database}_*.dump" -o -name "${safe_database}_*.dump.sha256" \) \
        -mtime "+${retention_days}" -delete
fi

echo "PostgreSQL backup created and archive structure verified."
echo "BACKUP_FILE=${backup_file}"
