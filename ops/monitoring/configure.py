from __future__ import annotations

import argparse
import getpass
import os
import stat
import sys
import tempfile
from pathlib import Path

from ops.monitoring.heartbeat import HeartbeatError, load_settings


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Write a secret-safe systemd environment file for the release heartbeat."
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--site-url", required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    return parser


def _quote(value: str) -> str:
    if any(character in value for character in ("\x00", "\r", "\n")):
        raise HeartbeatError("systemd environment values must be single-line")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    success_url = os.getenv("UPTIME_HEARTBEAT_URL") or getpass.getpass(
        "External success heartbeat URL: "
    )
    failure_url = os.getenv("UPTIME_HEARTBEAT_FAILURE_URL") or getpass.getpass(
        "External failure heartbeat URL (optional): "
    )
    values = {
        "SITE_URL": args.site_url.strip().rstrip("/"),
        "UPTIME_HEARTBEAT_URL": success_url.strip(),
        "UPTIME_HEARTBEAT_FAILURE_URL": failure_url.strip(),
        "UPTIME_BACKUP_DIR": str(args.backup_dir.resolve()),
        "UPTIME_BACKUP_MAX_AGE_SECONDS": "93600",
        "UPTIME_REQUEST_TIMEOUT_SECONDS": "10",
    }
    try:
        load_settings(values)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{args.output.name}.", dir=args.output.parent
        )
        temporary = Path(temporary_name)
        try:
            os.fchmod(descriptor, stat.S_IRUSR | stat.S_IWUSR)
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                for key, value in values.items():
                    stream.write(f"{key}={_quote(value)}\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, args.output)
        finally:
            temporary.unlink(missing_ok=True)
    except (HeartbeatError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Wrote {args.output} with mode 0600; no heartbeat URLs were printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
