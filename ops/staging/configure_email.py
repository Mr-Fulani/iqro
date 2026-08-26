from __future__ import annotations

import argparse
import getpass
import os
import sys
from email.utils import parseaddr
from pathlib import Path

try:
    from ops.staging.configure_media import _atomic_write, _replace_values
    from ops.staging.preflight import DEFAULT_ENV, load_env, validate
except ModuleNotFoundError:  # Direct execution: python ops/staging/configure_email.py
    from configure_media import _atomic_write, _replace_values
    from preflight import DEFAULT_ENV, load_env, validate


def _resend_replacements(*, from_email: str, api_key: str) -> dict[str, str]:
    normalized_email = from_email.strip().lower()
    _, parsed_email = parseaddr(normalized_email)
    if parsed_email != normalized_email or not normalized_email.endswith(
        "@auth.iqro.forum"
    ):
        raise ValueError("Resend sender must be an address at auth.iqro.forum")
    normalized_key = api_key.strip()
    if not normalized_key.startswith("re_") or len(normalized_key) < 20:
        raise ValueError("Resend API key has an invalid format")
    return {
        "STAGING_EMAIL_DELIVERY_MODE": "smtp",
        "DJANGO_EMAIL_HOST": "smtp.resend.com",
        "DJANGO_EMAIL_PORT": "587",
        "DJANGO_EMAIL_HOST_USER": "resend",
        "DJANGO_EMAIL_HOST_PASSWORD": normalized_key,
        "DJANGO_EMAIL_USE_TLS": "true",
        "DJANGO_DEFAULT_FROM_EMAIL": f"IQRO <{normalized_email}>",
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Enable Resend SMTP in staging.env without putting the API key in shell history."
        )
    )
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    parser.add_argument("--from-email", default="login@auth.iqro.forum")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if not args.env_file.exists():
        print(
            f"ERROR: {args.env_file} does not exist; run make staging-init first",
            file=sys.stderr,
        )
        return 2

    api_key = os.getenv("STAGING_RESEND_API_KEY") or getpass.getpass("Resend API key: ")
    try:
        original = args.env_file.read_text(encoding="utf-8")
        if "STAGING_EMAIL_DELIVERY_MODE=" not in original:
            original = (
                original.rstrip()
                + "\n\n# Staging email delivery\n"
                + "STAGING_EMAIL_DELIVERY_MODE=mailpit\n"
            )
        replacements = _resend_replacements(
            from_email=args.from_email,
            api_key=api_key,
        )
        updated = _replace_values(original, replacements)
        candidate_values: dict[str, str] = {}
        for line in updated.splitlines():
            if line and not line.lstrip().startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                candidate_values[key.strip()] = value.strip().strip('"').strip("'")
        validation_errors, _ = validate(candidate_values, require_media=False)
        if validation_errors:
            raise ValueError("updated staging env did not pass preflight")
        _, parse_errors = load_env(args.env_file)
        if parse_errors:
            raise ValueError("staging env is invalid; run make staging-preflight first")
        _atomic_write(args.env_file, updated)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Enabled Resend SMTP in {args.env_file}.")
    print("No API key value was printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
