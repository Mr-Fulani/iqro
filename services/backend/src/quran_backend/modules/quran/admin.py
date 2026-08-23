from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageRegion,
    Hizb,
    Juz,
    MushafPage,
    QuranEdition,
    QuranEditionVersion,
    RubElHizb,
    SourceManifest,
    Surah,
)


class CanonicalReadOnlyAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None

    def has_add_permission(self, request: object) -> bool:  # noqa: ARG002
        return False

    def has_change_permission(self, request: object, obj: object | None = None) -> bool:  # noqa: ARG002
        return False

    def has_delete_permission(self, request: object, obj: object | None = None) -> bool:  # noqa: ARG002
        return False


@admin.register(QuranEdition)
class QuranEditionAdmin(CanonicalReadOnlyAdmin):
    list_display = ("code", "riwayah", "active_version")
    list_filter = ("riwayah",)
    search_fields = ("code", "name_ar", "name_en", "name_ru", "source_name")


@admin.register(QuranEditionVersion)
class QuranEditionVersionAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition", "version", "status", "published_at")
    list_filter = ("status", "edition")


@admin.register(Surah)
class SurahAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "number", "name_ar", "name_en", "ayah_count")
    list_filter = ("edition_version", "revelation_type")
    search_fields = ("name_ar", "name_en", "name_ru")


@admin.register(Ayah)
class AyahAdmin(CanonicalReadOnlyAdmin):
    list_display = ("surah", "number", "juz_number", "hizb_number", "rub_el_hizb_number")
    list_filter = ("surah__edition_version", "juz_number", "hizb_number")
    search_fields = ("text_uthmani",)


@admin.register(MushafPage)
class MushafPageAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "number", "image_width", "image_height")
    list_filter = ("edition_version",)


@admin.register(AyahPageRegion)
class AyahPageRegionAdmin(CanonicalReadOnlyAdmin):
    list_display = ("page", "ayah", "reading_order")
    list_filter = ("page__edition_version",)


@admin.register(Juz)
class JuzAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "number", "start_ayah", "end_ayah")
    list_filter = ("edition_version",)


@admin.register(Hizb)
class HizbAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "number", "start_ayah", "end_ayah")
    list_filter = ("edition_version",)


@admin.register(RubElHizb)
class RubElHizbAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "number", "hizb", "start_ayah", "end_ayah")
    list_filter = ("edition_version", "hizb")


@admin.register(SourceManifest)
class SourceManifestAdmin(CanonicalReadOnlyAdmin):
    list_display = ("edition_version", "source_version", "expected_ayahs", "imported_at")
    list_filter = ("edition_version",)
