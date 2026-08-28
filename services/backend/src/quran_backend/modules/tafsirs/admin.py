from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.tafsirs.models import (
    AyahTafsir,
    QuranFoundationTafsirSyncState,
    TafsirEdition,
    TafsirEditionVersion,
)


@admin.register(TafsirEdition)
class TafsirEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("name", "language_code", "source_id", "environment", "is_available")
    list_filter = ("environment", "language_code", "is_available")
    search_fields = ("name", "author_name", "slug")


@admin.register(TafsirEditionVersion)
class TafsirEditionVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "edition",
        "sync_sequence",
        "status",
        "record_count",
        "covered_ayah_count",
        "published_at",
    )
    list_filter = ("status",)


@admin.register(AyahTafsir)
class AyahTafsirAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("edition_version", "verse_key", "start_verse_key", "end_verse_key")
    search_fields = ("verse_key", "text")


@admin.register(QuranFoundationTafsirSyncState)
class QuranFoundationTafsirSyncStateAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "environment",
        "resources_filter",
        "last_sync_sequence",
        "last_success_at",
        "consecutive_failures",
    )
