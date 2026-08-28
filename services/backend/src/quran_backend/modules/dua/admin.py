from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.dua.models import (
    DuaCategory,
    DuaCategoryTranslation,
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaEntryTranslation,
    DuaEvidence,
    DuaSourceEdition,
)


@admin.register(DuaCollection)
class DuaCollectionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("slug", "active_version", "updated_at")
    search_fields = ("slug",)


@admin.register(DuaCollectionVersion)
class DuaCollectionVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "collection",
        "version",
        "status",
        "category_count",
        "entry_count",
        "published_at",
    )
    list_filter = ("status", "schema_version")
    search_fields = ("collection__slug", "version", "checksum_sha256")


@admin.register(DuaSourceEdition)
class DuaSourceEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("title", "language_code", "provider", "source_item_id")
    list_filter = ("language_code", "provider")
    search_fields = ("title", "author", "translator", "source_item_id")


@admin.register(DuaCategory)
class DuaCategoryAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("source_number", "slug", "collection_version", "sort_order")
    search_fields = ("slug", "translations__title")


@admin.register(DuaCategoryTranslation)
class DuaCategoryTranslationAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("category", "language_code", "title")
    list_filter = ("language_code",)
    search_fields = ("title",)


@admin.register(DuaEntry)
class DuaEntryAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "source_number",
        "slug",
        "category",
        "repetitions",
        "repetition_label",
        "sort_order",
    )
    list_filter = ("collection_version", "category")
    search_fields = ("slug", "arabic_text", "translations__meaning_text")


@admin.register(DuaEntryTranslation)
class DuaEntryTranslationAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("entry", "language_code")
    list_filter = ("language_code",)
    search_fields = ("meaning_text", "transliteration")


@admin.register(DuaEvidence)
class DuaEvidenceAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "entry",
        "kind",
        "source_reference",
        "verification_status",
    )
    list_filter = ("kind", "provider", "verification_status")
    search_fields = ("source_name", "source_reference", "external_id")
