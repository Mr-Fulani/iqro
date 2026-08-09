from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.http import HttpRequest

from quran_backend.modules.audio.models import (
    AudioTimingVersion,
    AudioTrack,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)


@admin.register(Reciter)
class ReciterAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("code", "name_ar", "name_en", "name_ru", "country_code", "is_active")
    list_filter = ("is_active", "country_code")
    search_fields = ("=code", "name_ar", "name_en", "name_ru")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(RecitationEdition)
class RecitationEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "code",
        "version",
        "style",
        "reciter",
        "quran_edition_version",
        "status",
        "published_at",
    )
    list_filter = ("status", "style", "quran_edition_version", "reciter")
    search_fields = ("=code", "version", "reciter__name_ar", "reciter__name_en")
    list_select_related = (
        "reciter",
        "quran_edition_version__edition",
    )
    readonly_fields = ("id", "created_at", "updated_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: RecitationEdition | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.status != RecitationPublicationStatus.DRAFT:
            editable_status = (
                {"status"} if obj.status == RecitationPublicationStatus.PUBLISHED else set()
            )
            immutable = tuple(
                field.name for field in obj._meta.fields if field.name not in editable_status
            )
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: RecitationEdition | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.status == RecitationPublicationStatus.DRAFT
        )


@admin.register(AudioTimingVersion)
class AudioTimingVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "recitation_edition",
        "version",
        "source_name",
        "source_version",
        "verified_at",
    )
    list_filter = ("recitation_edition__status", "verified_at")
    search_fields = (
        "version",
        "source_name",
        "source_version",
        "source_checksum_sha256",
        "recitation_edition__code",
    )
    list_select_related = ("recitation_edition",)
    readonly_fields = ("id", "created_at", "updated_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: AudioTimingVersion | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.recitation_edition.status != RecitationPublicationStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: AudioTimingVersion | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.recitation_edition.status == RecitationPublicationStatus.DRAFT
        )


@admin.register(AudioTrack)
class AudioTrackAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "recitation_edition",
        "timing_version",
        "scope",
        "surah_number",
        "juz_number",
        "duration_ms",
        "codec",
        "bitrate_kbps",
    )
    list_filter = ("scope", "codec", "recitation_edition__status")
    search_fields = ("object_key", "checksum_sha256", "recitation_edition__code")
    list_select_related = (
        "recitation_edition",
        "timing_version__recitation_edition",
    )
    readonly_fields = ("id", "created_at", "updated_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: AudioTrack | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.recitation_edition.status != RecitationPublicationStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_add_permission(self, request: HttpRequest) -> bool:
        return super().has_add_permission(request)

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: AudioTrack | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.recitation_edition.status == RecitationPublicationStatus.DRAFT
        )


@admin.register(AyahAudioSegment)
class AyahAudioSegmentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = ("track", "ayah", "start_ms", "end_ms")
    list_filter = ("track__recitation_edition", "track__scope")
    search_fields = ("=track__id", "=ayah__id")
    list_select_related = (
        "track__recitation_edition",
        "ayah__surah__edition_version__edition",
    )
    readonly_fields = ("id", "created_at", "updated_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: AyahAudioSegment | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.track.recitation_edition.status != RecitationPublicationStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: AyahAudioSegment | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.track.recitation_edition.status == RecitationPublicationStatus.DRAFT
        )

    def get_queryset(self, request: HttpRequest) -> Any:
        return (
            super()
            .get_queryset(request)
            .select_related(
                "track__recitation_edition",
                "ayah__surah__edition_version__edition",
            )
        )
