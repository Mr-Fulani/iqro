from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured


@dataclass(frozen=True, slots=True)
class BookmarkIdPolicy:
    tombstone_retention_days: int
    new_id_max_age_days: int
    future_skew_seconds: int

    @property
    def is_safe(self) -> bool:
        return (
            self.tombstone_retention_days * 86_400
            > self.new_id_max_age_days * 86_400 + self.future_skew_seconds
        )


def bookmark_id_policy() -> BookmarkIdPolicy:
    return BookmarkIdPolicy(
        tombstone_retention_days=_positive_setting(
            "QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS",
            365,
        ),
        new_id_max_age_days=_positive_setting(
            "QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS",
            360,
        ),
        future_skew_seconds=_positive_setting(
            "QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS",
            86_400,
        ),
    )


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
