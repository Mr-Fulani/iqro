from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import sys
import tempfile
from pathlib import Path

try:
    from ops.staging.preflight import DEFAULT_ENV, load_env, validate
except ModuleNotFoundError:  # Direct execution: python ops/staging/configure_media.py
    from preflight import DEFAULT_ENV, load_env, validate

DEFAULT_CORS_OUTPUT = Path("ops/staging/r2-cors.json")
ACCOUNT_ID_RE = re.compile(r"^[a-fA-F0-9]{32}$")


def _single_line_secret(value: str, label: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{label} is required")
    if any(character in normalized for character in ("\x00", "\r", "\n")):
        raise ValueError(f"{label} must be a single-line value")
    return normalized


def _replace_values(text: str, replacements: dict[str, str]) -> str:
    lines: list[str] = []
    replaced: set[str] = set()
    for line in text.splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in replacements:
            lines.append(f"{key}={replacements[key]}")
            replaced.add(key)
        else:
            lines.append(line)
    missing = set(replacements) - replaced
    if missing:
        raise ValueError(
            "staging env is missing media keys: " + ", ".join(sorted(missing))
        )
    return "\n".join(lines).rstrip() + "\n"


def _atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_path, path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def build_cors(origins: list[str]) -> str:
    policy = [
        {
            "AllowedOrigins": origins,
            "AllowedMethods": ["GET", "HEAD"],
            "AllowedHeaders": ["Range"],
            "ExposeHeaders": [
                "Accept-Ranges",
                "Content-Length",
                "Content-Range",
                "ETag",
                "Last-Modified",
            ],
            "MaxAgeSeconds": 3600,
        }
    ]
    return json.dumps(policy, indent=2, ensure_ascii=False) + "\n"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Store R2 credentials in staging.env without putting them in shell history."
    )
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    parser.add_argument("--cors-output", type=Path, default=DEFAULT_CORS_OUTPUT)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--bucket", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    account_id = args.account_id.strip()
    bucket = args.bucket.strip()
    if not ACCOUNT_ID_RE.fullmatch(account_id):
        print(
            "ERROR: R2 account ID must be the 32-character hexadecimal Account ID",
            file=sys.stderr,
        )
        return 2
    if len(bucket) < 3 or len(bucket) > 64 or any(char.isspace() for char in bucket):
        print(
            "ERROR: R2 bucket name must be 3-64 characters without spaces",
            file=sys.stderr,
        )
        return 2
    if not args.env_file.exists():
        print(
            f"ERROR: {args.env_file} does not exist; run make staging-init first",
            file=sys.stderr,
        )
        return 2

    access_key = os.getenv("STAGING_R2_ACCESS_KEY_ID") or getpass.getpass(
        "R2 Access Key ID: "
    )
    secret_key = os.getenv("STAGING_R2_SECRET_ACCESS_KEY") or getpass.getpass(
        "R2 Secret Access Key: "
    )
    try:
        access_key = _single_line_secret(access_key, "R2 Access Key ID")
        secret_key = _single_line_secret(secret_key, "R2 Secret Access Key")
        original = args.env_file.read_text(encoding="utf-8")
        replacements = {
            "MEDIA_OBJECT_STORAGE_ENDPOINT_URL": (
                f"https://{account_id}.r2.cloudflarestorage.com/"
            ),
            "MEDIA_OBJECT_STORAGE_BUCKET": bucket,
            "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID": access_key,
            "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY": secret_key,
        }
        updated = _replace_values(original, replacements)
        parsed, parse_errors = load_env(args.env_file)
        origins = [
            origin.strip()
            for origin in parsed.get("MEDIA_CDN_REQUIRED_ORIGINS", "").split(",")
            if origin.strip()
        ]
        if parse_errors or not origins:
            raise ValueError(
                "staging env is invalid; run make staging-preflight before R2 setup"
            )
        candidate, candidate_path = tempfile.mkstemp(
            prefix="quran-staging-media-", suffix=".env"
        )
        os.close(candidate)
        validation_path = Path(candidate_path)
        try:
            validation_path.write_text(updated, encoding="utf-8")
            candidate_values, candidate_errors = load_env(validation_path)
            strict_errors, _ = validate(candidate_values, require_media=True)
            if candidate_errors or strict_errors:
                raise ValueError(
                    "updated staging env did not pass strict media preflight"
                )
        finally:
            validation_path.unlink(missing_ok=True)
        _atomic_write(args.env_file, updated)
        _atomic_write(args.cors_output, build_cors(origins))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Updated {args.env_file} and generated {args.cors_output}.")
    print("No R2 credential values were printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
