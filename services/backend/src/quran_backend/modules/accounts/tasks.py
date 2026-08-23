from __future__ import annotations

from typing import Any

from celery import shared_task
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.accounts.lifecycle import finalize_due_account_deletions
from quran_backend.modules.accounts.retention import prune_auth_sessions, prune_email_challenges


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


@shared_task(name="accounts.prune_email_challenges")  # type: ignore[untyped-decorator]
def prune_email_challenges_task() -> dict[str, Any]:
    """Drain bounded email-challenge retention batches."""

    max_batches = _positive_setting("QURAN_RETENTION_TASK_MAX_BATCHES", 10)
    total_challenges = 0
    batches = 0
    has_more = False
    retention_hours = 0
    for _ in range(max_batches):
        result = prune_email_challenges()
        batches += 1
        total_challenges += result["challenges"]
        has_more = result["has_more"]
        retention_hours = result["retention_hours"]
        if not has_more or result["challenges"] == 0:
            break
    return {
        "dry_run": False,
        "challenges": total_challenges,
        "batches": batches,
        "has_more": has_more,
        "retention_hours": retention_hours,
    }


@shared_task(name="accounts.finalize_due_deletions")  # type: ignore[untyped-decorator]
def finalize_due_account_deletions_task() -> dict[str, Any]:
    """Finalize one bounded batch of accounts whose deletion grace period ended."""

    return dict(finalize_due_account_deletions())


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
