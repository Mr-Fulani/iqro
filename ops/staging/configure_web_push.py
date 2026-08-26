from __future__ import annotations

import argparse
import base64
import subprocess
import sys
from pathlib import Path

try:
    from ops.staging.configure_media import _atomic_write
    from ops.staging.preflight import DEFAULT_ENV, load_env, validate
except ModuleNotFoundError:  # Direct execution: python ops/staging/configure_web_push.py
    from configure_media import _atomic_write
    from preflight import DEFAULT_ENV, load_env, validate


def _base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def generate_vapid_keys() -> tuple[str, str]:
    private_pem = subprocess.run(
        ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"],
        check=True,
        capture_output=True,
    ).stdout
    private_der = subprocess.run(
        ["openssl", "ec", "-outform", "DER"],
        input=private_pem,
        check=True,
        capture_output=True,
    ).stdout
    public_der = subprocess.run(
        ["openssl", "ec", "-pubout", "-outform", "DER"],
        input=private_pem,
        check=True,
        capture_output=True,
    ).stdout
    public_raw = public_der[-65:]
    if len(public_raw) != 65 or public_raw[0] != 4:
        raise ValueError("OpenSSL returned an invalid P-256 public key")
    return _base64url(public_raw), _base64url(private_der)


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
        lines.extend(["", "# Browser Web Push"])
        lines.extend(f"{key}={replacements[key]}" for key in missing)
    return "\n".join(lines).rstrip() + "\n"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate VAPID keys and enable Web Push without printing secrets."
    )
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if not args.env_file.exists():
        print(
            f"ERROR: {args.env_file} does not exist; run make staging-init first",
            file=sys.stderr,
        )
        return 2
    try:
        original = args.env_file.read_text(encoding="utf-8")
        values, parse_errors = load_env(args.env_file)
        if parse_errors:
            raise ValueError("staging env is invalid; run make staging-preflight first")
        if (
            values.get("WEB_PUSH_ENABLED", "").lower() == "true"
            and values.get("WEB_PUSH_VAPID_PUBLIC_KEY")
            and values.get("WEB_PUSH_VAPID_PRIVATE_KEY")
        ):
            print(f"Web Push is already configured in {args.env_file}; keys were not rotated.")
            return 0
        subject = values.get("WEB_PUSH_VAPID_SUBJECT") or values.get(
            "STAGING_ACME_EMAIL", ""
        )
        if subject and not subject.startswith(("mailto:", "https://")):
            subject = f"mailto:{subject}"
        if not subject:
            raise ValueError("a Web Push contact email or URL is required")
        public_key, private_key = generate_vapid_keys()
        updated = _upsert_values(
            original,
            {
                "WEB_PUSH_ENABLED": "true",
                "WEB_PUSH_VAPID_PUBLIC_KEY": public_key,
                "WEB_PUSH_VAPID_PRIVATE_KEY": private_key,
                "WEB_PUSH_VAPID_SUBJECT": subject,
            },
        )
        candidate = dict(values)
        candidate.update(
            {
                "WEB_PUSH_ENABLED": "true",
                "WEB_PUSH_VAPID_PUBLIC_KEY": public_key,
                "WEB_PUSH_VAPID_PRIVATE_KEY": private_key,
                "WEB_PUSH_VAPID_SUBJECT": subject,
            }
        )
        validation_errors, _ = validate(candidate, require_media=False)
        if validation_errors:
            raise ValueError("updated staging env did not pass preflight")
        _atomic_write(args.env_file, updated)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Enabled Web Push in {args.env_file}.")
    print("VAPID secret values were generated locally and were not printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
