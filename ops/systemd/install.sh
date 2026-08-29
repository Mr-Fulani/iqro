#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer as root." >&2
    exit 2
fi

source_dir=${1:-/opt/quran/ops/systemd}
case "$source_dir" in
    ""|/)
        echo "Use a dedicated systemd source directory." >&2
        exit 2
        ;;
esac

for unit in \
    quran-backup@.service \
    quran-backup@.timer \
    quran-heartbeat@.service \
    quran-heartbeat@.timer
do
    if [ ! -f "$source_dir/$unit" ]; then
        echo "Missing unit: $source_dir/$unit" >&2
        exit 1
    fi
    install -o root -g root -m 0644 "$source_dir/$unit" "/etc/systemd/system/$unit"
done

install -d -o root -g root -m 0700 /etc/iqro
systemctl daemon-reload
echo "IQRO systemd units installed but not enabled. Configure credentials and heartbeat first."
