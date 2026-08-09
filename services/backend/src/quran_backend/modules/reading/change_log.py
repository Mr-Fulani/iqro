from __future__ import annotations

import uuid
from typing import Any

from django.db import IntegrityError, transaction

from quran_backend.modules.accounts.models import User
from quran_backend.modules.reading.models import SyncChange, UserSyncCursor


def current_sync_cursor(user: User) -> int:
    """Return the latest global sync sequence for one user."""

    return UserSyncCursor.objects.filter(user=user).values_list("value", flat=True).first() or 0


def append_sync_change(  # noqa: PLR0913
    *,
    user: User,
    entity_type: str,
    entity_id: uuid.UUID,
    action: str,
    revision: int,
    snapshot: dict[str, Any],
) -> int:
    """Atomically allocate a cursor and append one authoritative entity snapshot."""

    cursor = UserSyncCursor.objects.select_for_update().filter(user=user).first()
    if cursor is None:
        try:
            with transaction.atomic():
                cursor = UserSyncCursor.objects.create(user=user)
        except IntegrityError:
            cursor = UserSyncCursor.objects.select_for_update().get(user=user)
    cursor.value += 1
    cursor.save(update_fields=["value", "updated_at"])
    SyncChange.objects.create(
        user=user,
        sequence=cursor.value,
        entity_type=entity_type,
        entity_id=entity_id,
        action=action,
        revision=revision,
        snapshot=snapshot,
    )
    return cursor.value
