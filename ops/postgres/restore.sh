#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${BACKUP_FILE:?BACKUP_FILE is required}"
: "${RESTORE_DATABASE_NAME:?RESTORE_DATABASE_NAME is required}"

case "$RESTORE_DATABASE_NAME" in
    *[!A-Za-z0-9_]*|""|postgres|template0|template1)
        echo "RESTORE_DATABASE_NAME is invalid or reserved." >&2
        exit 2
        ;;
esac

expected_confirmation="restore:${RESTORE_DATABASE_NAME}"
if [ "${CONFIRM_RESTORE:-}" != "$expected_confirmation" ]; then
    echo "Restore refused. Set CONFIRM_RESTORE=${expected_confirmation}" >&2
    exit 2
fi

/ops/verify.sh "$BACKUP_FILE"

cleanup_failed_restore() {
    dropdb --if-exists --force "$RESTORE_DATABASE_NAME" >/dev/null 2>&1 || true
}
trap cleanup_failed_restore EXIT HUP INT TERM

dropdb --if-exists --force "$RESTORE_DATABASE_NAME"
createdb --template=template0 "$RESTORE_DATABASE_NAME"
pg_restore \
    --dbname="$RESTORE_DATABASE_NAME" \
    --exit-on-error \
    --single-transaction \
    --no-owner \
    --no-privileges \
    "$BACKUP_FILE"

trap - EXIT HUP INT TERM
echo "Restore completed successfully into database ${RESTORE_DATABASE_NAME}."
