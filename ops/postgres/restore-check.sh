#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${BACKUP_FILE:?BACKUP_FILE is required}"

check_database=${RESTORE_CHECK_DATABASE:-quran_restore_check}
case "$check_database" in
    *[!A-Za-z0-9_]*|"")
        echo "RESTORE_CHECK_DATABASE contains invalid characters." >&2
        exit 2
        ;;
esac
case "$check_database" in
    quran_restore_check|quran_restore_check_*) ;;
    *)
        echo "RESTORE_CHECK_DATABASE must start with quran_restore_check." >&2
        exit 2
        ;;
esac

/ops/verify.sh "$BACKUP_FILE"

database_exists=$(psql --dbname=postgres --tuples-only --no-align \
    --command="SELECT 1 FROM pg_database WHERE datname = '${check_database}'")
if [ "$database_exists" = "1" ]; then
    echo "Restore-check database already exists; refusing to overwrite it." >&2
    exit 1
fi

cleanup_database() {
    dropdb --if-exists --force "$check_database" >/dev/null 2>&1 || true
}
trap cleanup_database EXIT HUP INT TERM

createdb --template=template0 "$check_database"
pg_restore \
    --dbname="$check_database" \
    --exit-on-error \
    --single-transaction \
    --no-owner \
    --no-privileges \
    "$BACKUP_FILE"

schema_ready=$(psql --dbname="$check_database" --tuples-only --no-align \
    --command="SELECT to_regclass('public.django_migrations') IS NOT NULL")
if [ "$schema_ready" != "t" ]; then
    echo "Restore drill failed: django_migrations is missing." >&2
    exit 1
fi

cleanup_database
trap - EXIT HUP INT TERM
echo "Restore drill passed in an isolated temporary database."
