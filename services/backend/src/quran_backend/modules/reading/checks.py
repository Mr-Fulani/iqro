from __future__ import annotations

from django.core.checks import Error, register
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.reading.policies import bookmark_id_policy


@register()
def check_bookmark_id_retention_policy(**_kwargs: object) -> list[Error]:
    try:
        policy = bookmark_id_policy()
    except ImproperlyConfigured as exc:
        return [Error(str(exc), id="reading.E001")]
    if policy.is_safe:
        return []
    return [
        Error(
            "Bookmark tombstone retention must exceed the unseen UUIDv7 age window "
            "plus accepted future clock skew.",
            hint=(
                "Increase QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS or reduce "
                "QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS / "
                "QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS."
            ),
            id="reading.E002",
        )
    ]
