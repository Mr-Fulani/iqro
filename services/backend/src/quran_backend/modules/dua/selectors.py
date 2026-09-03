from __future__ import annotations

from collections.abc import Iterable

from django.db.models import Count, Exists, F, OuterRef, Prefetch, Q, QuerySet

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


def publishable_dua_audio_assets() -> QuerySet[DuaAudioAsset]:
    """Return active external audio and managed audio with complete CDN evidence."""

    return DuaAudioAsset.objects.filter(is_active=True).filter(
        (Q(object_key__isnull=True) & ~Q(external_url=""))
        | (
            Q(object_key__isnull=False)
            & Q(external_url="")
            & ~Q(checksum_sha256="")
            & Q(size_bytes__gt=0)
            & ~Q(origin_etag="")
            & ~Q(etag="")
            & Q(cdn_contract_verified_at__isnull=False)
        )
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


def published_dua_categories(
    language: str,
    *,
    collection: str = "",
) -> QuerySet[DuaCategory]:
    localized_translations = DuaCategoryTranslation.objects.filter(language_code=language)
    localized_category_rows = localized_translations.filter(category_id=OuterRef("pk"))
    localized_sources = DuaSourceEdition.objects.filter(language_code=language)
    queryset = (
        DuaCategory.objects.annotate(
            has_localized_category=Exists(localized_category_rows),
        )
        .filter(
            collection_version__collection__active_version_id=F("collection_version_id"),
            collection_version__status=DuaPublicationStatus.PUBLISHED,
            has_localized_category=True,
        )
        .annotate(
            entry_count=Count(
                "entries",
                filter=(
                    Q(entries__collection_version_id=F("collection_version_id"))
                    & Q(entries__translations__language_code=language)
                ),
                distinct=True,
            )
        )
        .select_related("collection_version", "collection_version__collection")
        .prefetch_related(
            Prefetch(
                "translations",
                queryset=localized_translations,
                to_attr="localized_category_translations",
            ),
            Prefetch(
                "collection_version__source_editions",
                queryset=localized_sources,
                to_attr="localized_source_editions",
            ),
        )
    )
    if collection:
        queryset = queryset.filter(collection_version__collection__slug=collection)
    return queryset.order_by(
        "collection_version__collection__slug",
        "sort_order",
        "source_number",
        "id",
    )


def published_dua_entries(
    language: str,
    *,
    collection: str = "",
    category: str = "",
    query: str = "",
) -> QuerySet[DuaEntry]:
    localized_entries = DuaEntryTranslation.objects.filter(language_code=language)
    localized_entry_rows = localized_entries.filter(entry_id=OuterRef("pk"))
    localized_categories = DuaCategoryTranslation.objects.filter(language_code=language)
    localized_category_rows = localized_categories.filter(category_id=OuterRef("category_id"))
    localized_sources = DuaSourceEdition.objects.filter(language_code=language)
    queryset = (
        DuaEntry.objects.annotate(
            has_localized_entry=Exists(localized_entry_rows),
            has_localized_category=Exists(localized_category_rows),
        )
        .filter(
            collection_version__collection__active_version_id=F("collection_version_id"),
            collection_version__status=DuaPublicationStatus.PUBLISHED,
            has_localized_entry=True,
            has_localized_category=True,
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
                "collection_version__audio_assets",
                queryset=publishable_dua_audio_assets().order_by("sort_order"),
                to_attr="active_audio_assets",
            ),
            Prefetch("evidence", queryset=DuaEvidence.objects.order_by("sort_order")),
        )
    )
    if collection:
        queryset = queryset.filter(collection_version__collection__slug=collection)
    if category:
        queryset = queryset.filter(category__slug=category)
    if query:
        queryset = queryset.annotate(
            matches_localized_entry=Exists(
                localized_entry_rows.filter(
                    Q(meaning_text__icontains=query) | Q(transliteration__icontains=query)
                )
            ),
            matches_localized_category=Exists(
                localized_category_rows.filter(title__icontains=query)
            ),
        ).filter(
            Q(arabic_text__icontains=query)
            | Q(matches_localized_entry=True)
            | Q(matches_localized_category=True)
        )
    return queryset.distinct().order_by("sort_order", "id")


def published_dua_entries_for_keys(
    language: str,
    keys: Iterable[tuple[str, int]],
) -> QuerySet[DuaEntry]:
    """Return published entries matching exact canonical collection/number pairs."""

    numbers_by_collection: dict[str, set[int]] = {}
    for collection_slug, source_number in keys:
        numbers_by_collection.setdefault(collection_slug, set()).add(source_number)
    if not numbers_by_collection:
        return published_dua_entries(language).none()

    pair_filter = Q(pk__isnull=True)
    for collection_slug, source_numbers in numbers_by_collection.items():
        pair_filter |= Q(
            collection_version__collection__slug=collection_slug,
            source_number__in=source_numbers,
        )
    return published_dua_entries(language).filter(pair_filter)
