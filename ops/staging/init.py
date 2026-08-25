from __future__ import annotations

import argparse
import os
import re
import secrets
import sys
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

DEFAULT_TEMPLATE = Path("services/backend/.env.production.example")
DEFAULT_OUTPUT = Path("ops/staging/staging.env")
NOT_CONFIGURED = "staging-r2-not-configured"

SECRET_KEYS = (
    "DATABASE_PASSWORD",
    "DJANGO_SECRET_KEY",
    "QURAN_INSTALLATION_HASH_KEY",
    "QURAN_GUEST_CREDENTIAL_HASH_KEY",
    "QURAN_REFRESH_TOKEN_HASH_KEY",
    "QURAN_EMAIL_CODE_HASH_KEY",
    "QURAN_PRAYER_THROTTLE_HASH_KEY",
    "QURAN_OPERATIONS_TOKEN",
    "GRAFANA_ADMIN_PASSWORD",
    "WEB_CONTENT_REVALIDATION_SECRET",
)

HOST_RE = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"
)


def _host(value: str, label: str) -> str:
    normalized = value.strip().lower().rstrip(".")
    if not HOST_RE.fullmatch(normalized):
        raise ValueError(f"{label} must be a DNS hostname without scheme or path")
    return normalized


def _email(value: str) -> str:
    normalized = value.strip()
    if (
        normalized.count("@") != 1
        or normalized.startswith("@")
        or normalized.endswith("@")
    ):
        raise ValueError("ACME email must be a valid email address")
    return normalized


def _origin(value: str) -> str:
    normalized = value.strip().rstrip("/")
    parsed = urlsplit(normalized)
    if (
        parsed.scheme != "https"
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("extra origins must be exact HTTPS origins without paths")
    return normalized


def _is_placeholder(value: str) -> bool:
    normalized = value.strip().strip('"').strip("'").lower()
    return not normalized or "replace-me" in normalized or normalized == "example.com"


def _random_secret() -> str:
    return secrets.token_urlsafe(48)


def _render(template: str, overrides: dict[str, str]) -> str:
    rendered: list[str] = []
    consumed: set[str] = set()
    for line in template.splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            rendered.append(line)
            continue
        key = line.split("=", 1)[0].strip()
        if key in overrides:
            rendered.append(f"{key}={overrides[key]}")
            consumed.add(key)
        else:
            rendered.append(line)

    missing = [key for key in overrides if key not in consumed]
    if missing:
        rendered.extend(["", "# Staging-only settings"])
        rendered.extend(f"{key}={overrides[key]}" for key in missing)
    return "\n".join(rendered).rstrip() + "\n"


def _template_values(template: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in template.splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def build_overrides(
    *,
    template: str,
    host: str,
    media_host: str,
    acme_email: str,
    extra_origins: list[str],
    r2_account_id: str,
    r2_bucket: str,
    r2_access_key_id: str,
    r2_secret_access_key: str,
) -> dict[str, str]:
    source = _template_values(template)
    origins = [f"https://{host}"]
    for origin in extra_origins:
        normalized = _origin(origin)
        if normalized not in origins:
            origins.append(normalized)

    legal_defaults = {
        "LEGAL_ENTITY_NAME": "Quran Platform Staging",
        "LEGAL_CONTACT_EMAIL": acme_email,
        "SECURITY_CONTACT_EMAIL": acme_email,
        "LEGAL_POSTAL_ADDRESS": "Staging environment; not a public legal notice",
        "LEGAL_JURISDICTION": "Staging only",
        "LEGAL_EFFECTIVE_DATE": datetime.now(tz=UTC).date().isoformat(),
    }
    legal_values = {
        key: (fallback if _is_placeholder(source.get(key, "")) else source[key])
        for key, fallback in legal_defaults.items()
    }

    account_id = r2_account_id.strip() or NOT_CONFIGURED
    bucket = r2_bucket.strip() or NOT_CONFIGURED
    access_key = r2_access_key_id.strip() or NOT_CONFIGURED
    secret_key = r2_secret_access_key.strip() or NOT_CONFIGURED
    overrides = {
        "COMPOSE_PROJECT_NAME": "quran-staging",
        "APP_VERSION": "staging",
        "SITE_URL": f"https://{host}",
        **legal_values,
        "DJANGO_ALLOWED_HOSTS": host,
        "DJANGO_CSRF_TRUSTED_ORIGINS": ",".join(origins),
        "DJANGO_CORS_ALLOWED_ORIGINS": ",".join(origins),
        "DJANGO_NUM_PROXIES": "2",
        "DJANGO_SECURE_SSL_REDIRECT": "true",
        "DATABASE_NAME": "quran_staging",
        "DATABASE_USER": "quran_staging",
        "DATABASE_HOST": "postgres",
        "DATABASE_CONN_MAX_AGE": "0",
        "CELERY_BEAT_LOCK_KEY": "quran-staging:celery-beat:lease",
        "REDIS_CACHE_URL": "redis://redis:6379/0",
        "REDIS_THROTTLE_URL": "redis://redis:6379/0",
        "CELERY_BROKER_URL": "redis://redis:6379/0",
        "CELERY_RESULT_BACKEND": "redis://redis:6379/0",
        "WEB_CACHE_REDIS_URL": "redis://redis:6379/0",
        "WEB_CACHE_KEY_PREFIX": "quran-staging:web-cache:v1",
        "PUBLIC_MEDIA_BASE_URL": f"https://{media_host}/",
        "PUBLIC_AUDIO_BASE_URL": f"https://{media_host}/",
        "MEDIA_OBJECT_STORAGE_ENDPOINT_URL": (
            f"https://{account_id}.r2.cloudflarestorage.com/"
        ),
        "MEDIA_OBJECT_STORAGE_BUCKET": bucket,
        "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID": access_key,
        "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY": secret_key,
        "MEDIA_OBJECT_STORAGE_REGION": "auto",
        "MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE": "path",
        "MEDIA_CDN_REQUIRED_ORIGINS": ",".join(origins),
        "OBSERVABILITY_MONTHLY_BUDGET_USD": "20",
        "OBSERVABILITY_MONTHLY_ORIGIN_EGRESS_BUDGET_BYTES": "21474836480",
        "PROMETHEUS_RETENTION_TIME": "7d",
        "PROMETHEUS_RETENTION_SIZE": "1GB",
        "DJANGO_EMAIL_HOST": "mailpit",
        "DJANGO_EMAIL_PORT": "1025",
        "DJANGO_EMAIL_HOST_USER": "staging-required-placeholder",
        "DJANGO_EMAIL_HOST_PASSWORD": "staging-required-placeholder",
        "DJANGO_EMAIL_USE_TLS": "false",
        "DJANGO_DEFAULT_FROM_EMAIL": f"Quran Staging <{acme_email}>",
        "QF_AUDIO_SYNC_ENABLED": "false",
        "GATEWAY_BIND_ADDRESS": "127.0.0.1",
        "GATEWAY_PORT": "3000",
        "QURAN_MEDIA_DIR": "./media/staging",
        "QURAN_BACKUP_DIR": "./backups/staging",
        "RESTORE_CHECK_DATABASE": "quran_restore_check_staging",
        "STAGING_HOST": host,
        "STAGING_MEDIA_HOST": media_host,
        "STAGING_ACME_EMAIL": acme_email,
        "MAILPIT_BIND_ADDRESS": "127.0.0.1",
        "MAILPIT_PORT": "8025",
    }
    overrides.update({key: _random_secret() for key in SECRET_KEYS})
    return overrides


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create a non-committed staging env with independent random secrets."
    )
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--host", default=os.getenv("STAGING_HOST", ""))
    parser.add_argument("--media-host", default=os.getenv("STAGING_MEDIA_HOST", ""))
    parser.add_argument("--acme-email", default=os.getenv("STAGING_ACME_EMAIL", ""))
    parser.add_argument("--extra-origin", action="append", default=[])
    parser.add_argument(
        "--r2-account-id", default=os.getenv("STAGING_R2_ACCOUNT_ID", "")
    )
    parser.add_argument("--r2-bucket", default=os.getenv("STAGING_R2_BUCKET", ""))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        host = _host(args.host, "staging host")
        media_host = _host(args.media_host or f"media.{host}", "media host")
        acme_email = _email(args.acme_email)
        template = args.template.read_text(encoding="utf-8")
        overrides = build_overrides(
            template=template,
            host=host,
            media_host=media_host,
            acme_email=acme_email,
            extra_origins=args.extra_origin,
            r2_account_id=args.r2_account_id,
            r2_bucket=args.r2_bucket,
            r2_access_key_id=os.getenv("STAGING_R2_ACCESS_KEY_ID", ""),
            r2_secret_access_key=os.getenv("STAGING_R2_SECRET_ACCESS_KEY", ""),
        )
        rendered = _render(template, overrides)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(rendered)
    except FileExistsError:
        print(
            f"ERROR: {args.output} already exists; refusing to overwrite it",
            file=sys.stderr,
        )
        return 2
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print(f"Created {args.output} with mode 0600.")
    print(f"Application URL: https://{host}")
    print(f"Media URL: https://{media_host}")
    if overrides["MEDIA_OBJECT_STORAGE_BUCKET"] == NOT_CONFIGURED:
        print(
            "Media is not configured yet; staging app startup is allowed, media release is not."
        )
    print("No secret values were printed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
