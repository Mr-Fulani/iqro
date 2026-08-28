from __future__ import annotations

from django.db import models
from django.db.models import QuerySet

from quran_backend.modules.translations.models import AyahTranslation, TranslationEdition


def published_translation_editions(
    environment: str,
    *,
    language_code: str | None = None,
) -> QuerySet[TranslationEdition]:
    editions = TranslationEdition.objects.filter(
        environment=environment,
        is_available=True,
        active_version__isnull=False,
        active_version__status="published",
    ).select_related("active_version")
    if language_code:
        editions = editions.filter(language_code=language_code.lower())
    return editions


def published_surah_translation(
    environment: str,
    *,
    source_id: int,
    surah_number: int,
) -> QuerySet[AyahTranslation]:
    return AyahTranslation.objects.filter(
        edition_version__edition__environment=environment,
        edition_version__edition__source_id=source_id,
        edition_version__edition__is_available=True,
        edition_version__edition__active_version=models.F("edition_version"),
        edition_version__status="published",
        surah_number=surah_number,
    ).order_by("ayah_number")
