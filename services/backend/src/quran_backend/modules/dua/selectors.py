from __future__ import annotations

from django.db.models import Count, F, Prefetch, Q, QuerySet

from quran_backend.modules.dua.models import (
    DuaAudioAsset,
    DuaCategory,
    DuaCategoryTranslation,
    DuaCollection,
    DuaEntry,
    DuaEntryTranslation,
    DuaEvidence,
    DuaPublicationStatus,
    DuaSourceEdition,
)


def published_dua_collections(language: str) -> QuerySet[DuaCollection]:
    localized_sources = DuaSourceEdition.objects.filter(language_code=language)
    return (
        DuaCollection.objects.filter(
            active_version__status=DuaPublicationStatus.PUBLISHED,
        )
        .select_related("active_version")
        .prefetch_related(
            Prefetch(
                "active_version__source_editions",
                queryset=localized_sources,
                to_attr="localized_source_editions",
            )
        )
        .order_by("slug")
    )


def published_dua_categories(language: str) -> QuerySet[DuaCategory]:
    localized_translations = DuaCategoryTranslation.objects.filter(language_code=language)
    return (
        DuaCategory.objects.filter(
            collection_version__collection__active_version_id=F("collection_version_id"),
            collection_version__status=DuaPublicationStatus.PUBLISHED,
        )
        .annotate(entry_count=Count("entries"))
        .prefetch_related(
            Prefetch(
                "translations",
                queryset=localized_translations,
                to_attr="localized_category_translations",
            )
        )
        .order_by("sort_order", "source_number")
    )


def published_dua_entries(
    language: str,
    *,
    category: str = "",
    query: str = "",
) -> QuerySet[DuaEntry]:
    localized_entries = DuaEntryTranslation.objects.filter(language_code=language)
    localized_categories = DuaCategoryTranslation.objects.filter(language_code=language)
    localized_sources = DuaSourceEdition.objects.filter(language_code=language)
    queryset = (
        DuaEntry.objects.filter(
            collection_version__collection__active_version_id=F("collection_version_id"),
            collection_version__status=DuaPublicationStatus.PUBLISHED,
            translations__language_code=language,
            category__translations__language_code=language,
        )
        .select_related("category", "collection_version", "collection_version__collection")
        .prefetch_related(
            Prefetch(
                "translations",
                queryset=localized_entries,
                to_attr="localized_entry_translations",
            ),
            Prefetch(
                "category__translations",
                queryset=localized_categories,
                to_attr="localized_category_translations",
            ),
            Prefetch(
                "collection_version__source_editions",
                queryset=localized_sources,
                to_attr="localized_source_editions",
            ),
            Prefetch(
                "collection_version__collection__audio_assets",
                queryset=DuaAudioAsset.objects.filter(is_active=True).order_by("sort_order"),
                to_attr="active_audio_assets",
            ),
            Prefetch("evidence", queryset=DuaEvidence.objects.order_by("sort_order")),
        )
    )
    if category:
        queryset = queryset.filter(category__slug=category)
    if query:
        queryset = queryset.filter(
            Q(arabic_text__icontains=query)
            | Q(translations__meaning_text__icontains=query)
            | Q(translations__transliteration__icontains=query)
            | Q(category__translations__title__icontains=query)
        )
    return queryset.distinct().order_by("sort_order", "id")
