from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import sentry_sdk
from django.core.exceptions import ImproperlyConfigured


def sentry_options(environ: Mapping[str, str], *, release: str) -> dict[str, Any] | None:
    """Sentry client options, or None when no DSN is configured.

    Reports carry no personal data: no IP addresses, cookies or user ids
    (send_default_pii), and no request bodies, which can hold emails or tokens.
    """
    dsn = environ.get("SENTRY_DSN", "").strip()
    if not dsn:
        return None
    raw_rate = environ.get("SENTRY_TRACES_SAMPLE_RATE", "0").strip() or "0"
    try:
        traces_sample_rate = float(raw_rate)
    except ValueError as exc:
        raise ImproperlyConfigured("SENTRY_TRACES_SAMPLE_RATE must be a number") from exc
    if not 0 <= traces_sample_rate <= 1:
        raise ImproperlyConfigured("SENTRY_TRACES_SAMPLE_RATE must be between 0 and 1")
    return {
        "dsn": dsn,
        "environment": environ.get("SENTRY_ENVIRONMENT", "production").strip() or "production",
        "release": f"quran-platform-backend@{release}",
        "send_default_pii": False,
        "max_request_body_size": "never",
        "traces_sample_rate": traces_sample_rate,
    }


def init_error_reporting(environ: Mapping[str, str], *, release: str) -> bool:
    options = sentry_options(environ, release=release)
    if options is None:
        return False
    sentry_sdk.init(**options)
    return True
