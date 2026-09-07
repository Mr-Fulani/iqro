from __future__ import annotations

from django.contrib import admin

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageRegion,
    Hizb,
    Juz,
    MushafPage,
    MushafRendition,
    MushafRenditionPage,
    MushafRenditionRelease,
    QuranEdition,
    QuranEditionVersion,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationMushafSyncState,
    QuranFoundationNativePageAsset,
    QuranFoundationNativePublication,
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


@admin.register(MushafRendition)
class MushafRenditionAdmin(CanonicalReadOnlyAdmin):
    list_display = ("code", "names", "active_release")
    search_fields = ("code",)


@admin.register(MushafRenditionRelease)
class MushafRenditionReleaseAdmin(CanonicalReadOnlyAdmin):
    list_display = ("rendition", "version", "page_count", "staging_only", "published_at")
    list_filter = ("staging_only", "rendition")


@admin.register(MushafRenditionPage)
class MushafRenditionPageAdmin(CanonicalReadOnlyAdmin):
    list_display = ("release", "number", "image_width", "image_height")
    list_filter = ("release",)


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


@admin.register(QuranFoundationMushafSyncState)
class QuranFoundationMushafSyncStateAdmin(CanonicalReadOnlyAdmin):
    list_display = (
        "environment",
        "resources_filter",
        "last_sync_sequence",
        "last_success_at",
        "consecutive_failures",
    )
    list_filter = ("environment",)


@admin.register(QuranFoundationMushaf)
class QuranFoundationMushafAdmin(CanonicalReadOnlyAdmin):
    list_display = (
        "source_id",
        "environment",
        "name",
        "qirat_name",
        "pages_count",
        "default_font_name",
        "is_available",
        "last_synced_at",
    )
    list_filter = ("environment", "qirat_name", "is_available")
    search_fields = ("name", "description", "qirat_name")


@admin.register(QuranFoundationMushafPage)
class QuranFoundationMushafPageAdmin(CanonicalReadOnlyAdmin):
    list_display = ("mushaf", "page_number", "verses_count")
    list_filter = ("mushaf",)


@admin.register(QuranFoundationNativePublication)
class QuranFoundationNativePublicationAdmin(CanonicalReadOnlyAdmin):
    list_display = (
        "mushaf",
        "render_version",
        "status",
        "is_active",
        "coverage",
        "assets_count",
        "renderer_name",
        "renderer_version",
        "source_checksum",
        "manifest_checksum",
        "published_at",
        "last_error_code",
        "last_error_message",
    )
    list_filter = ("status", "is_active", "mushaf__environment", "mushaf__source_id")
    search_fields = ("render_version", "source_checksum_sha256", "manifest_checksum_sha256")

    @admin.display(description="Подготовлено страниц")
    def coverage(self, obj: QuranFoundationNativePublication) -> str:
        return f"{obj.prepared_pages} / {obj.expected_pages}"

    @admin.display(description="SHA источника")
    def source_checksum(self, obj: QuranFoundationNativePublication) -> str:
        return obj.source_checksum_sha256[:12]

    @admin.display(description="SHA манифеста")
    def manifest_checksum(self, obj: QuranFoundationNativePublication) -> str:
        return obj.manifest_checksum_sha256[:12] or "—"


@admin.register(QuranFoundationNativePageAsset)
class QuranFoundationNativePageAssetAdmin(CanonicalReadOnlyAdmin):
    list_display = (
        "publication",
        "page_number",
        "width",
        "height",
        "content_type",
        "size_bytes",
    )
    list_filter = ("publication__mushaf", "publication__render_version", "width")
    search_fields = ("storage_key", "checksum_sha256")
