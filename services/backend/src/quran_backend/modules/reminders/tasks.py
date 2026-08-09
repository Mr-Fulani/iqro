from __future__ import annotations

from typing import Any

from celery import shared_task
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.reminders.retention import prune_reminder_tombstones


@shared_task(name="reminders.prune_tombstones")  # type: ignore[untyped-decorator]
def prune_reminder_tombstones_task() -> dict[str, Any]:
    """Drain bounded batches without allowing one worker task to run forever."""

    max_batches = _positive_setting("QURAN_RETENTION_TASK_MAX_BATCHES", 10)
    total_tombstones = 0
    total_evicted = 0
    batches = 0
    result: dict[str, Any] = {}
    for _ in range(max_batches):
        result = dict(prune_reminder_tombstones())
        batches += 1
        total_tombstones += int(result["tombstones"])
        total_evicted += int(result["retired_ids_evicted"])
        if not result["has_more"] or int(result["tombstones"]) == 0:
            break
    result.update(
        {
            "tombstones": total_tombstones,
            "retired_ids_evicted": total_evicted,
            "batches": batches,
        }
    )
    return result


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
