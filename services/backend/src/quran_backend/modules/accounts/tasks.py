from __future__ import annotations

from typing import Any

from celery import shared_task
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.accounts.retention import prune_auth_sessions


@shared_task(name="accounts.prune_auth_sessions")  # type: ignore[untyped-decorator]
def prune_auth_sessions_task() -> dict[str, Any]:
    """Drain several bounded auth-retention batches without monopolising a worker."""

    max_batches = _positive_setting("QURAN_RETENTION_TASK_MAX_BATCHES", 10)
    total_sessions = 0
    total_tokens = 0
    batches = 0
    has_more = False
    retention_days = 0

    for _ in range(max_batches):
        result = prune_auth_sessions()
        batches += 1
        total_sessions += result["sessions"]
        total_tokens += result["tokens"]
        has_more = result["has_more"]
        retention_days = result["retention_days"]
        made_progress = result["sessions"] > 0 or result["tokens"] > 0
        if not has_more or not made_progress:
            break

    return {
        "dry_run": False,
        "sessions": total_sessions,
        "tokens": total_tokens,
        "batches": batches,
        "has_more": has_more,
        "retention_days": retention_days,
    }


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
