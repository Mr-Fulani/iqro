from __future__ import annotations

import uuid
from typing import Any

from celery import shared_task
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.reminders.push import (
    claim_due_web_push_schedules,
    deliver_claimed_web_push_schedule,
)
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


@shared_task(name="reminders.dispatch_web_push_due")  # type: ignore[untyped-decorator]
def dispatch_web_push_due_task() -> dict[str, int]:
    if not settings.WEB_PUSH_ENABLED:
        return {"claimed": 0, "batches": 0}
    claimed_count = 0
    batches = 0
    for _ in range(settings.WEB_PUSH_DISPATCH_MAX_BATCHES):
        claimed = claim_due_web_push_schedules()
        if not claimed:
            break
        batches += 1
        claimed_count += len(claimed)
        for item in claimed:
            deliver_web_push_schedule_task.delay(
                str(item.schedule_id),
                str(item.claim_token),
            )
        if len(claimed) < settings.WEB_PUSH_DISPATCH_BATCH_SIZE:
            break
    return {"claimed": claimed_count, "batches": batches}


@shared_task(name="reminders.deliver_web_push")  # type: ignore[untyped-decorator]
def deliver_web_push_schedule_task(schedule_id: str, claim_token: str) -> str:
    return deliver_claimed_web_push_schedule(
        schedule_id=uuid.UUID(schedule_id),
        claim_token=uuid.UUID(claim_token),
    )


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
