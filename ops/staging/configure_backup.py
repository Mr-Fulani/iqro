from __future__ import annotations

import argparse
import getpass
import os
import re
import sys
import tempfile
from pathlib import Path

try:
    from ops.staging.configure_media import _atomic_write, _single_line_secret
    from ops.staging.preflight import DEFAULT_ENV, load_env, validate
except ModuleNotFoundError:  # Direct execution
    from configure_media import _atomic_write, _single_line_secret
    from preflight import DEFAULT_ENV, load_env, validate


ACCOUNT_ID_RE = re.compile(r"^[a-fA-F0-9]{32}$")


def _upsert_values(text: str, replacements: dict[str, str]) -> str:
    lines: list[str] = []
    replaced: set[str] = set()
    for line in text.splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in replacements:
            lines.append(f"{key}={replacements[key]}")
            replaced.add(key)
        else:
            lines.append(line)
    missing = [key for key in replacements if key not in replaced]
    if missing:
        lines.extend(["", "# Separate private offsite PostgreSQL backups"])
        lines.extend(f"{key}={replacements[key]}" for key in missing)
    return "\n".join(lines).rstrip() + "\n"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Configure a separate private R2 bucket for PostgreSQL backups."
    )
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--bucket", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    account_id = args.account_id.strip()
    bucket = args.bucket.strip()
    if not ACCOUNT_ID_RE.fullmatch(account_id):
        print("ERROR: R2 account ID must be 32 hexadecimal characters", file=sys.stderr)
        return 2
    if (
        len(bucket) < 3
        or len(bucket) > 64
        or any(character.isspace() for character in bucket)
    ):
        print(
            "ERROR: backup bucket must be 3-64 characters without spaces",
            file=sys.stderr,
        )
        return 2
    if not args.env_file.exists():
        print(f"ERROR: {args.env_file} does not exist", file=sys.stderr)
        return 2

    access_key = os.getenv("STAGING_BACKUP_R2_ACCESS_KEY_ID") or getpass.getpass(
        "Backup R2 Access Key ID: "
    )
    secret_key = os.getenv("STAGING_BACKUP_R2_SECRET_ACCESS_KEY") or getpass.getpass(
        "Backup R2 Secret Access Key: "
    )
    try:
        access_key = _single_line_secret(access_key, "Backup R2 Access Key ID")
        secret_key = _single_line_secret(secret_key, "Backup R2 Secret Access Key")
        original = args.env_file.read_text(encoding="utf-8")
        values, parse_errors = load_env(args.env_file)
        if parse_errors:
            raise ValueError("staging env is invalid")
        if bucket == values.get("MEDIA_OBJECT_STORAGE_BUCKET"):
            raise ValueError(
                "backup bucket must be separate from the public media bucket"
            )
        if access_key == values.get("MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID"):
            raise ValueError("backup storage must use a separately scoped token")
        updated = _upsert_values(
            original,
            {
                "BACKUP_OBJECT_STORAGE_ENDPOINT_URL": (
                    f"https://{account_id}.r2.cloudflarestorage.com"
                ),
                "BACKUP_OBJECT_STORAGE_BUCKET": bucket,
                "BACKUP_OBJECT_STORAGE_ACCESS_KEY_ID": access_key,
                "BACKUP_OBJECT_STORAGE_SECRET_ACCESS_KEY": secret_key,
                "BACKUP_ENVIRONMENT": "staging",
                "BACKUP_OBJECT_STORAGE_REGION": "auto",
                "BACKUP_OBJECT_STORAGE_ADDRESSING_STYLE": "path",
                "BACKUP_OBJECT_STORAGE_PREFIX": "quran-platform/postgres",
                "BACKUP_OBJECT_STORAGE_RETENTION_DAYS": "30",
            },
        )
        descriptor, candidate_name = tempfile.mkstemp(
            prefix="quran-staging-backup-", suffix=".env"
        )
        os.close(descriptor)
        candidate = Path(candidate_name)
        try:
            candidate.write_text(updated, encoding="utf-8")
            candidate_values, candidate_errors = load_env(candidate)
            validation_errors, _warnings = validate(
                candidate_values,
                require_media=True,
                require_offsite_backup=True,
            )
            if candidate_errors or validation_errors:
                raise ValueError(
                    "updated env did not pass strict offsite backup preflight"
                )
        finally:
            candidate.unlink(missing_ok=True)
        _atomic_write(args.env_file, updated)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Updated {args.env_file} with a separate private backup target.")
    print("No backup credential values were printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
