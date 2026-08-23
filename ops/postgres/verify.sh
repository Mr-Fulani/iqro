#!/bin/sh
set -eu

backup_file=${BACKUP_FILE:-${1:-}}
if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
    echo "Set BACKUP_FILE to an existing custom-format PostgreSQL dump." >&2
    exit 2
fi
case "$backup_file" in
    *.dump) ;;
    *)
        echo "BACKUP_FILE must end with .dump." >&2
        exit 2
        ;;
esac

backup_dir=$(dirname "$backup_file")
backup_name=$(basename "$backup_file")
checksum_file="${backup_file}.sha256"
if [ ! -f "$checksum_file" ]; then
    echo "Missing checksum: ${checksum_file}" >&2
    exit 1
fi

(
    cd "$backup_dir"
    sha256sum -c "${backup_name}.sha256"
)
pg_restore --list "$backup_file" >/dev/null

echo "PostgreSQL backup checksum and archive structure are valid."
