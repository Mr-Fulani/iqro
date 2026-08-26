from __future__ import annotations

import argparse
import os
import stat
import sys
from pathlib import Path
from urllib.parse import urlsplit

try:
    from ops.staging.init import NOT_CONFIGURED, SECRET_KEYS
except ModuleNotFoundError:  # Direct execution: python ops/staging/preflight.py
    from init import NOT_CONFIGURED, SECRET_KEYS

DEFAULT_ENV = Path("ops/staging/staging.env")


def load_env(path: Path) -> tuple[dict[str, str], list[str]]:
    values: dict[str, str] = {}
    errors: list[str] = []
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in line:
            errors.append(f"line {line_number} is not KEY=VALUE")
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key in values:
            errors.append(f"duplicate key: {key}")
        values[key] = value.strip().strip('"').strip("'")
    return values, errors


def _https_host(value: str) -> str | None:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.hostname is None
        or parsed.username
        or parsed.password
    ):
        return None
    return parsed.hostname


def validate(
    values: dict[str, str], *, require_media: bool
) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    required = (
        "COMPOSE_PROJECT_NAME",
        "SITE_URL",
        "STAGING_HOST",
        "STAGING_MEDIA_HOST",
        "STAGING_ACME_EMAIL",
        "DJANGO_ALLOWED_HOSTS",
        "DJANGO_CSRF_TRUSTED_ORIGINS",
        "DJANGO_CORS_ALLOWED_ORIGINS",
        "DJANGO_NUM_PROXIES",
        "DJANGO_SECURE_SSL_REDIRECT",
        "DATABASE_NAME",
        "DATABASE_USER",
        "DATABASE_PASSWORD",
        "DATABASE_CONN_MAX_AGE",
        "STAGING_EMAIL_DELIVERY_MODE",
        "DJANGO_EMAIL_HOST",
        "DJANGO_EMAIL_PORT",
        "DJANGO_EMAIL_HOST_USER",
        "DJANGO_EMAIL_HOST_PASSWORD",
        "DJANGO_EMAIL_USE_TLS",
        "DJANGO_DEFAULT_FROM_EMAIL",
        "PUBLIC_MEDIA_BASE_URL",
        "PUBLIC_AUDIO_BASE_URL",
        "MEDIA_OBJECT_STORAGE_ENDPOINT_URL",
        "MEDIA_OBJECT_STORAGE_BUCKET",
        "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID",
        "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY",
        "MEDIA_CDN_REQUIRED_ORIGINS",
        "GATEWAY_BIND_ADDRESS",
    ) + SECRET_KEYS
    for key in required:
        if not values.get(key):
            errors.append(f"missing value: {key}")

    if errors:
        return errors, warnings

    host = values["STAGING_HOST"]
    media_host = values["STAGING_MEDIA_HOST"]
    site_origin = f"https://{host}"
    if values["COMPOSE_PROJECT_NAME"] == "quran-production":
        errors.append("COMPOSE_PROJECT_NAME must not reuse the production project")
    if values["SITE_URL"].rstrip("/") != site_origin:
        errors.append("SITE_URL must match STAGING_HOST over HTTPS")
    if values["DJANGO_ALLOWED_HOSTS"] != host:
        errors.append(
            "DJANGO_ALLOWED_HOSTS must contain only STAGING_HOST for the initial deploy"
        )
    for key in (
        "DJANGO_CSRF_TRUSTED_ORIGINS",
        "DJANGO_CORS_ALLOWED_ORIGINS",
        "MEDIA_CDN_REQUIRED_ORIGINS",
    ):
        if site_origin not in values[key].split(","):
            errors.append(f"{key} must include the staging site origin")
    if values["DJANGO_NUM_PROXIES"] != "2":
        errors.append("DJANGO_NUM_PROXIES must be 2 for Caddy -> gateway -> backend")
    if values["DJANGO_SECURE_SSL_REDIRECT"].lower() != "true":
        errors.append("DJANGO_SECURE_SSL_REDIRECT must be true")
    if values["DATABASE_CONN_MAX_AGE"] != "0":
        errors.append("DATABASE_CONN_MAX_AGE must be 0 under ASGI")
    email_mode = values["STAGING_EMAIL_DELIVERY_MODE"].lower()
    if email_mode not in {"mailpit", "smtp"}:
        errors.append("STAGING_EMAIL_DELIVERY_MODE must be mailpit or smtp")
    elif email_mode == "mailpit":
        if values["DJANGO_EMAIL_HOST"] != "mailpit":
            errors.append("mailpit mode must use DJANGO_EMAIL_HOST=mailpit")
        if values["DJANGO_EMAIL_PORT"] != "1025":
            errors.append("mailpit mode must use DJANGO_EMAIL_PORT=1025")
        if values["DJANGO_EMAIL_USE_TLS"].lower() != "false":
            errors.append("mailpit mode must disable DJANGO_EMAIL_USE_TLS")
    else:
        if values["DJANGO_EMAIL_HOST"] in {"mailpit", "localhost", "127.0.0.1"}:
            errors.append("smtp mode must use an external DJANGO_EMAIL_HOST")
        try:
            email_port = int(values["DJANGO_EMAIL_PORT"])
        except ValueError:
            email_port = 0
        if not 1 <= email_port <= 65535:
            errors.append("DJANGO_EMAIL_PORT must be between 1 and 65535")
        if values["DJANGO_EMAIL_USE_TLS"].lower() != "true":
            errors.append("smtp mode must enable DJANGO_EMAIL_USE_TLS")
        if not values["DJANGO_EMAIL_HOST_USER"].strip():
            errors.append("smtp mode requires DJANGO_EMAIL_HOST_USER")
        if not values["DJANGO_EMAIL_HOST_PASSWORD"].strip():
            errors.append("smtp mode requires DJANGO_EMAIL_HOST_PASSWORD")
        if "@" not in values["DJANGO_DEFAULT_FROM_EMAIL"]:
            errors.append(
                "smtp mode requires an email address in DJANGO_DEFAULT_FROM_EMAIL"
            )
    if (
        "staging" not in values["DATABASE_NAME"]
        or "staging" not in values["DATABASE_USER"]
    ):
        errors.append("staging must use clearly separate database credentials")
    if values["GATEWAY_BIND_ADDRESS"] != "127.0.0.1":
        errors.append("gateway debug port must stay bound to loopback")
    if _https_host(values["PUBLIC_MEDIA_BASE_URL"]) != media_host:
        errors.append("PUBLIC_MEDIA_BASE_URL must use STAGING_MEDIA_HOST over HTTPS")
    if _https_host(values["PUBLIC_AUDIO_BASE_URL"]) != media_host:
        errors.append("PUBLIC_AUDIO_BASE_URL must use STAGING_MEDIA_HOST over HTTPS")
    if _https_host(values["MEDIA_OBJECT_STORAGE_ENDPOINT_URL"]) is None:
        errors.append("MEDIA_OBJECT_STORAGE_ENDPOINT_URL must be HTTPS")

    secret_values = [values[key] for key in SECRET_KEYS]
    for key in SECRET_KEYS:
        if len(values[key]) < 32 or "replace-me" in values[key].lower():
            errors.append(
                f"{key} must be an independent generated secret of at least 32 chars"
            )
    if len(set(secret_values)) != len(secret_values):
        errors.append("generated application secrets must not be reused")

    placeholder_keys = [
        key
        for key in (
            "MEDIA_OBJECT_STORAGE_ENDPOINT_URL",
            "MEDIA_OBJECT_STORAGE_BUCKET",
            "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID",
            "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY",
        )
        if NOT_CONFIGURED in values[key]
    ]
    if placeholder_keys:
        message = "R2 is not configured: " + ", ".join(placeholder_keys)
        if require_media:
            errors.append(message)
        else:
            warnings.append(
                message + "; text/API staging may start, media release may not"
            )

    for key, value in values.items():
        if "replace-me" in value.lower():
            errors.append(f"placeholder remains in {key}")
    return errors, warnings


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate staging config without printing secrets."
    )
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV)
    parser.add_argument("--require-media", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if not args.env_file.exists():
        print(
            f"ERROR: {args.env_file} does not exist; run make staging-init",
            file=sys.stderr,
        )
        return 2
    try:
        values, errors = load_env(args.env_file)
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if os.name != "nt":
        mode = stat.S_IMODE(args.env_file.stat().st_mode)
        if mode & 0o077:
            errors.append(f"{args.env_file} permissions must be 0600, found {mode:04o}")
    validation_errors, warnings = validate(values, require_media=args.require_media)
    errors.extend(validation_errors)
    for warning in warnings:
        print(f"WARN: {warning}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("OK: staging configuration passed preflight; no secret values were printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
