from __future__ import annotations

import uuid
from typing import Any

from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.reading.change_log import current_sync_cursor
from quran_backend.modules.reading.models import SyncAction, SyncOutcome
from quran_backend.modules.reminders.exceptions import (
    ReminderCreateConflictError,
    ReminderDeletedError,
    ReminderIdNotReusableError,
    ReminderNotFoundError,
    ReminderQuotaExceededError,
    ReminderRevisionConflictError,
)
from quran_backend.modules.reminders.models import RetiredReminderId
from quran_backend.modules.reminders.selectors import reminder_queryset
from quran_backend.modules.reminders.services import (
    create_reminder,
    delete_reminder,
    patch_reminder,
    reminder_sync_snapshot,
)


@sensitive_variables("operation")
def apply_reminder_sync_operation(  # noqa: PLR0911
    *,
    user: User,
    device: Device | None,
    operation: dict[str, Any],
) -> dict[str, Any]:
    """Apply one validated reminder operation using the direct mutation core."""

    entity_id = operation["entity_id"]
    action = operation["action"]
    base_revision = operation["base_revision"]
    common = {
        "base_revision": base_revision,
        "client_updated_at": operation["client_updated_at"],
    }
    try:
        if action == SyncAction.DELETE:
            entity = delete_reminder(
                user=user,
                device=device,
                reminder_id=entity_id,
                data=common,
            )
        elif base_revision == 0:
            entity, _created = create_reminder(
                user=user,
                device=device,
                data={"id": entity_id, **common, **operation["payload"]},
            )
        elif action == SyncAction.UPSERT:
            entity = patch_reminder(
                user=user,
                device=device,
                reminder_id=entity_id,
                data={**common, **operation["payload"]},
            )
        else:  # pragma: no cover - guarded by the strict input serializer.
            raise RuntimeError(f"Unsupported reminder sync action: {action}")
    except ReminderRevisionConflictError:
        return _conflict(user, entity_id, "revision_mismatch")
    except ReminderNotFoundError:
        if RetiredReminderId.objects.filter(user=user, reminder_id=entity_id).exists():
            return _conflict(user, entity_id, "entity_id_not_reusable")
        return _conflict(user, entity_id, "entity_missing")
    except ReminderDeletedError:
        return _conflict(user, entity_id, "entity_id_not_reusable")
    except ReminderIdNotReusableError:
        return _conflict(user, entity_id, "entity_id_not_reusable")
    except ReminderQuotaExceededError:
        return _conflict(user, entity_id, "reminder_quota_exceeded")
    except ReminderCreateConflictError:
        current = current_reminder_sync_entity(user, entity_id)
        reason = "revision_mismatch" if current is not None else "entity_id_unavailable"
        return {
            "outcome": SyncOutcome.CONFLICT,
            "conflict_reason": reason,
            "entity": current,
            "cursor": current_sync_cursor(user),
        }

    return {
        "outcome": SyncOutcome.ACCEPTED,
        "entity": {"entity_type": "reminder", **entity},
        "cursor": current_sync_cursor(user),
    }


def full_resync_reminders(
    user: User,
    *,
    after: uuid.UUID | None,
    limit: int,
) -> list[dict[str, Any]]:
    queryset = reminder_queryset().filter(user=user).order_by("id")
    if after is not None:
        queryset = queryset.filter(id__gt=after)
    return [reminder_sync_snapshot(reminder) for reminder in queryset[:limit]]


def _conflict(user: User, entity_id: uuid.UUID, reason: str) -> dict[str, Any]:
    return {
        "outcome": SyncOutcome.CONFLICT,
        "conflict_reason": reason,
        "entity": current_reminder_sync_entity(user, entity_id),
        "cursor": current_sync_cursor(user),
    }


def current_reminder_sync_entity(
    user: User,
    entity_id: uuid.UUID,
) -> dict[str, Any] | None:
    reminder = reminder_queryset().filter(user=user, id=entity_id).first()
    return reminder_sync_snapshot(reminder) if reminder is not None else None
