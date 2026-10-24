from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import sentry_sdk
from django.core.exceptions import ImproperlyConfigured

# Telegram puts the bot token in the request path (modules/alerts/telegram.py).
TELEGRAM_API_HOST = "api.telegram.org"


def drop_telegram_breadcrumb(crumb: dict[str, Any], _hint: dict[str, Any]) -> dict[str, Any] | None:
    """Sentry records every outgoing HTTP request; those to Telegram carry the bot token."""
    data = crumb.get("data") or {}
    if TELEGRAM_API_HOST in f"{data.get('url', '')} {crumb.get('message', '')}":
        return None
    return crumb


def drop_telegram_spans(event: dict[str, Any], _hint: dict[str, Any]) -> dict[str, Any]:
    event["spans"] = [
        span
        for span in event.get("spans") or []
        if TELEGRAM_API_HOST
        not in f"{span.get('description', '')} {(span.get('data') or {}).get('url', '')}"
    ]
    return event


def sentry_options(environ: Mapping[str, str], *, release: str) -> dict[str, Any] | None:
    """Sentry client options, or None when no DSN is configured.

    Reports carry no personal data: no IP addresses, cookies or user ids
    (send_default_pii), no request bodies, which can hold emails or tokens, and
    no trace of requests to Telegram, whose URL holds the bot token.
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
        "before_breadcrumb": drop_telegram_breadcrumb,
        "before_send_transaction": drop_telegram_spans,
    }


def init_error_reporting(environ: Mapping[str, str], *, release: str) -> bool:
    options = sentry_options(environ, release=release)
    if options is None:
        return False
    sentry_sdk.init(**options)
    return True
