from __future__ import annotations

from django.db.models import QuerySet

from quran_backend.modules.tajweed.models import (
    AyahTajweed,
    TajweedEdition,
    TajweedPublicationStatus,
)
from quran_backend.modules.tajweed.quran_foundation_sync import EDITION_CODE, PROVIDER


def published_tajweed_edition(environment: str) -> TajweedEdition | None:
    return (
        TajweedEdition.objects.filter(
            environment=environment,
            provider=PROVIDER,
            code=EDITION_CODE,
            active_version__status=TajweedPublicationStatus.PUBLISHED,
        )
        .select_related("active_version")
        .first()
    )


def published_tajweed_ayahs(edition: TajweedEdition) -> QuerySet[AyahTajweed]:
    # Provider markup stays in the database for audits; it is never serialized.
    return AyahTajweed.objects.filter(edition_version=edition.active_version_id).defer(
        "source_text"
    )
