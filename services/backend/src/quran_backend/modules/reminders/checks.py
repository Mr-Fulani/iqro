from __future__ import annotations

from django.core.checks import Error, register
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.reminders.policies import reminder_id_policy, reminder_quota_policy


@register()
def check_reminder_id_retention_policy(**_kwargs: object) -> list[Error]:
    try:
        policy = reminder_id_policy()
    except ImproperlyConfigured as exc:
        return [Error(str(exc), id="reminders.E001")]
    if policy.is_safe:
        return []
    return [
        Error(
            "Reminder tombstone retention must exceed the unseen UUIDv7 age window "
            "plus accepted future clock skew.",
            hint=(
                "Increase QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS or reduce "
                "QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS / "
                "QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS."
            ),
            id="reminders.E002",
        )
    ]


@register()
def check_reminder_quota_policy(**_kwargs: object) -> list[Error]:
    try:
        reminder_quota_policy()
    except ImproperlyConfigured as exc:
        return [Error(str(exc), id="reminders.E003")]
    return []
