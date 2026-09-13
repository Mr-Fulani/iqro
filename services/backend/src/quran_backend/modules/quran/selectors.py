from __future__ import annotations

from collections.abc import Collection

from django.db.models import F, IntegerField, Max, Min, QuerySet

from quran_backend.modules.quran.models import (
    Ayah,
    Hizb,
    Juz,
    PublicationStatus,
    QuranEdition,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    RubElHizb,
    Surah,
)


def published_editions() -> QuerySet[QuranEdition]:
    return (
        QuranEdition.objects.filter(active_version__status=PublicationStatus.PUBLISHED)
        .select_related("active_version")
        .order_by("code")
    )


def published_surahs(edition_code: str) -> QuerySet[Surah]:
    return (
        Surah.objects.filter(
            edition_version__edition__code=edition_code,
            edition_version__edition__active_version_id=F("edition_version_id"),
            edition_version__status=PublicationStatus.PUBLISHED,
        )
        .annotate(
            first_page=Min(
                "ayahs__page_mappings__page__number",
                output_field=IntegerField(),
            )
        )
        .order_by("number")
    )


def published_ayahs(edition_code: str, surah_number: int) -> QuerySet[Ayah]:
    return (
        Ayah.objects.filter(
            surah__edition_version__edition__code=edition_code,
            surah__edition_version__edition__active_version_id=F("surah__edition_version_id"),
            surah__edition_version__status=PublicationStatus.PUBLISHED,
            surah__number=surah_number,
        )
        .select_related("surah", "surah__edition_version", "surah__edition_version__edition")
        .prefetch_related("page_mappings__page")
        .order_by("number")
    )


def published_active_ayahs_by_id(ayah_ids: Collection[object]) -> QuerySet[Ayah]:
    """Resolve opaque ids without exposing draft or superseded Quran content."""

    return Ayah.objects.filter(
        id__in=ayah_ids,
        surah__edition_version__edition__active_version_id=F("surah__edition_version_id"),
        surah__edition_version__status=PublicationStatus.PUBLISHED,
    ).select_related("surah", "surah__edition_version", "surah__edition_version__edition")


def public_quran_foundation_mushafs(environment: str) -> QuerySet[QuranFoundationMushaf]:
    return (
        QuranFoundationMushaf.objects.filter(
            environment=environment,
            is_available=True,
        )
        .prefetch_related("native_publications")
        .order_by("source_id")
    )


def public_quran_foundation_mushaf_pages(
    environment: str,
    source_id: int,
) -> QuerySet[QuranFoundationMushafPage]:
    return (
        QuranFoundationMushafPage.objects.filter(
            mushaf__environment=environment,
            mushaf__source_id=source_id,
            mushaf__is_available=True,
        )
        .select_related("mushaf")
        .prefetch_related("mushaf__native_publications")
        .order_by("page_number")
    )


def published_juz(edition_code: str) -> QuerySet[Juz]:
    return (
        Juz.objects.filter(
            edition_version__edition__code=edition_code,
            edition_version__edition__active_version_id=F("edition_version_id"),
            edition_version__status=PublicationStatus.PUBLISHED,
        )
        .select_related(
            "start_ayah__surah",
            "end_ayah__surah",
        )
        .annotate(
            start_page=Min("start_ayah__page_mappings__page__number"),
            end_page=Max("end_ayah__page_mappings__page__number"),
        )
        .order_by("number")
    )


def published_hizb(edition_code: str) -> QuerySet[Hizb]:
    return (
        Hizb.objects.filter(
            edition_version__edition__code=edition_code,
            edition_version__edition__active_version_id=F("edition_version_id"),
            edition_version__status=PublicationStatus.PUBLISHED,
        )
        .select_related("start_ayah__surah", "end_ayah__surah")
        .annotate(
            start_page=Min("start_ayah__page_mappings__page__number"),
            end_page=Max("end_ayah__page_mappings__page__number"),
        )
        .order_by("number")
    )


def published_rub_el_hizb(edition_code: str) -> QuerySet[RubElHizb]:
    return (
        RubElHizb.objects.filter(
            edition_version__edition__code=edition_code,
            edition_version__edition__active_version_id=F("edition_version_id"),
            edition_version__status=PublicationStatus.PUBLISHED,
        )
        .select_related("hizb", "start_ayah__surah", "end_ayah__surah")
        .annotate(
            start_page=Min("start_ayah__page_mappings__page__number"),
            end_page=Max("end_ayah__page_mappings__page__number"),
        )
        .order_by("number")
    )
