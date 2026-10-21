from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.tajweed.models import AyahTajweed, TajweedEdition, TajweedEditionVersion


@admin.register(TajweedEdition)
class TajweedEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("name", "code", "environment", "active_version")
    list_filter = ("environment",)
    search_fields = ("name", "code")


@admin.register(TajweedEditionVersion)
class TajweedEditionVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("edition", "status", "ayah_count", "fragment_count", "published_at")
    list_filter = ("status",)


@admin.register(AyahTajweed)
class AyahTajweedAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("edition_version", "verse_key", "page_number")
    search_fields = ("verse_key",)
