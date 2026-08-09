from __future__ import annotations

import uuid

from django.db.models import QuerySet

from quran_backend.modules.accounts.models import User
from quran_backend.modules.reminders.exceptions import ReminderNotFoundError
from quran_backend.modules.reminders.models import ReminderRule


def reminder_queryset(*, for_update: bool = False) -> QuerySet[ReminderRule]:
    queryset = ReminderRule.objects.select_related(
        "device",
        "start_ayah__surah",
        "end_ayah__surah",
    )
    # Lock only ReminderRule. Nullable select_related joins otherwise make
    # PostgreSQL reject FOR UPDATE against the nullable side of an outer join.
    return queryset.select_for_update(of=("self",)) if for_update else queryset


def list_reminders(user: User) -> QuerySet[ReminderRule]:
    """Return the bounded authoritative set, including tombstones."""

    return reminder_queryset().filter(user=user).order_by("created_at", "id")


def get_reminder(user: User, reminder_id: uuid.UUID) -> ReminderRule:
    reminder = reminder_queryset().filter(user=user, id=reminder_id).first()
    if reminder is None:
        raise ReminderNotFoundError
    return reminder
