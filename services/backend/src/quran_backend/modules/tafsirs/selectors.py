from __future__ import annotations

from django.db import models
from django.db.models import QuerySet

from quran_backend.modules.tafsirs.models import AyahTafsir, TafsirEdition


def published_tafsir_editions(
    environment: str,
    *,
    language_code: str | None = None,
) -> QuerySet[TafsirEdition]:
    editions = TafsirEdition.objects.filter(
        environment=environment,
        is_available=True,
        active_version__isnull=False,
        active_version__status="published",
    ).select_related("active_version")
    if language_code:
        editions = editions.filter(language_code=language_code.lower())
    return editions


def published_surah_tafsir(
    environment: str,
    *,
    source_id: int,
    surah_number: int,
) -> QuerySet[AyahTafsir]:
    grouped_source_text = AyahTafsir.objects.filter(
        edition_version_id=models.OuterRef("edition_version_id"),
        source_id=models.OuterRef("provider_group_id"),
        start_verse_key=models.OuterRef("start_verse_key"),
        end_verse_key=models.OuterRef("end_verse_key"),
    ).values("text")[:1]
    return (
        AyahTafsir.objects.filter(
            edition_version__edition__environment=environment,
            edition_version__edition__source_id=source_id,
            edition_version__edition__is_available=True,
            edition_version__edition__active_version=models.F("edition_version"),
            edition_version__status="published",
            surah_number=surah_number,
        )
        .annotate(
            resolved_text=models.Case(
                models.When(text="", then=models.Subquery(grouped_source_text)),
                default=models.F("text"),
                output_field=models.TextField(),
            )
        )
        .order_by("ayah_number")
    )
