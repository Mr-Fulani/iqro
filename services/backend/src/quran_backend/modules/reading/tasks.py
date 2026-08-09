from __future__ import annotations

from typing import Any

from celery import shared_task
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.reading.retention import prune_sync_history


@shared_task(name="reading.prune_sync_history")  # type: ignore[untyped-decorator]
def prune_sync_history_task() -> dict[str, Any]:
    """Drain several bounded batches without allowing one task to run indefinitely."""
    max_batches = _positive_setting("QURAN_RETENTION_TASK_MAX_BATCHES", 10)
    totals = {"changes": 0, "operations": 0, "tombstones": 0, "users": 0}
    result: dict[str, Any] = {}
    batches = 0
    for _ in range(max_batches):
        result = dict(prune_sync_history())
        batches += 1
        progress = 0
        for key in totals:
            count = int(result[key])
            totals[key] += count
            if key != "users":
                progress += count
        if not result["has_more"] or progress == 0:
            break

    result.update(totals)
    result["batches"] = batches
    return result


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
