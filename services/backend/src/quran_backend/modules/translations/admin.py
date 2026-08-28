from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.translations.models import (
    AyahTranslation,
    QuranFoundationTranslationSyncState,
    TranslationEdition,
    TranslationEditionVersion,
)


@admin.register(TranslationEdition)
class TranslationEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("name", "language_code", "source_id", "environment", "is_available")
    list_filter = ("environment", "language_code", "is_available")
    search_fields = ("name", "author_name", "slug")


@admin.register(TranslationEditionVersion)
class TranslationEditionVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("edition", "sync_sequence", "status", "ayah_count", "published_at")
    list_filter = ("status",)


@admin.register(AyahTranslation)
class AyahTranslationAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("edition_version", "verse_key")
    search_fields = ("verse_key", "text")


@admin.register(QuranFoundationTranslationSyncState)
class QuranFoundationTranslationSyncStateAdmin(
    admin.ModelAdmin  # type: ignore[type-arg]
):
    list_display = (
        "environment",
        "resources_filter",
        "last_sync_sequence",
        "last_success_at",
        "consecutive_failures",
    )
