from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured


@dataclass(frozen=True, slots=True)
class ReminderIdPolicy:
    tombstone_retention_days: int
    new_id_max_age_days: int
    future_skew_seconds: int

    @property
    def is_safe(self) -> bool:
        return (
            self.tombstone_retention_days * 86_400
            > self.new_id_max_age_days * 86_400 + self.future_skew_seconds
        )

    def accepts_new_id(self, reminder_id: uuid.UUID, *, now: datetime) -> bool:
        """Accept only UUIDv7 identities inside the configured unseen-ID window."""

        if reminder_id.version != 7 or not self.is_safe:
            return False
        now_milliseconds = int(now.timestamp() * 1_000)
        return (
            now_milliseconds - self.new_id_max_age_days * 86_400_000
            <= reminder_id.time
            <= now_milliseconds + self.future_skew_seconds * 1_000
        )


@dataclass(frozen=True, slots=True)
class ReminderQuotaPolicy:
    max_active_per_user: int
    max_total_per_user: int

    @property
    def is_safe(self) -> bool:
        return (
            self.max_active_per_user <= 64
            and self.max_total_per_user <= 256
            and self.max_active_per_user <= self.max_total_per_user
        )


def reminder_id_policy() -> ReminderIdPolicy:
    return ReminderIdPolicy(
        tombstone_retention_days=_positive_setting(
            "QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS",
            365,
        ),
        new_id_max_age_days=_positive_setting(
            "QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS",
            360,
        ),
        future_skew_seconds=_positive_setting(
            "QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS",
            86_400,
        ),
    )


def reminder_quota_policy() -> ReminderQuotaPolicy:
    policy = ReminderQuotaPolicy(
        max_active_per_user=_positive_setting(
            "QURAN_REMINDER_MAX_ACTIVE_PER_USER",
            64,
        ),
        max_total_per_user=_positive_setting(
            "QURAN_REMINDER_MAX_TOTAL_PER_USER",
            256,
        ),
    )
    if not policy.is_safe:
        raise ImproperlyConfigured(
            "Reminder quotas require active <= 64, total <= 256, and active <= total."
        )
    return policy


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
