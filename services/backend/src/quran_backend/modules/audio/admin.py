# ruff: noqa: RUF001 -- Admin copy intentionally uses Cyrillic characters.

from __future__ import annotations

import logging
from typing import Any, ClassVar, cast

from django import forms
from django.contrib import admin
from django.core.exceptions import ImproperlyConfigured
from django.http import HttpRequest
from django.utils.html import format_html

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTimingVersion,
    AudioTrack,
    AyahAudioSegment,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    QuranFoundationSyncState,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)
from quran_backend.modules.audio.portrait_upload import (
    MAX_RECITER_PORTRAIT_MIB,
    ReciterPortraitUploadError,
    upload_reciter_portrait,
)
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.content_revalidation import (
    enqueue_audio_content_change,
    enqueue_reciter_content_change,
)
from quran_backend.modules.core.object_storage import ObjectStorageError

logger = logging.getLogger(__name__)


class ReciterAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    portrait_upload = forms.FileField(
        required=False,
        label="Загрузить новый портрет",
        help_text=(
            f"Выберите WebP, JPEG или PNG размером до {MAX_RECITER_PORTRAIT_MIB} МБ. "
            "Файл будет загружен в media-хранилище автоматически."
        ),
        widget=forms.ClearableFileInput(attrs={"accept": "image/webp,image/jpeg,image/png"}),
    )
    remove_portrait = forms.BooleanField(
        required=False,
        label="Удалить текущий портрет",
        help_text="Убирает портрет из профиля. Загруженный immutable-файл не удаляется из CDN.",
    )

    class Meta:
        model = Reciter
        fields = (
            "code",
            "name_ar",
            "name_en",
            "name_ru",
            "name_tr",
            "biography_ar",
            "biography_en",
            "biography_ru",
            "biography_tr",
            "profile_source_url",
            "profile_source_checked_on",
            "country_code",
            "is_active",
        )
        labels: ClassVar[dict[str, str]] = {
            "code": "Код чтеца",
            "name_ar": "Имя на арабском",
            "name_en": "Имя на английском",
            "name_ru": "Имя на русском",
            "name_tr": "Имя на турецком",
            "biography_ar": "Биография на арабском",
            "biography_en": "Биография на английском",
            "biography_ru": "Биография на русском",
            "biography_tr": "Биография на турецком",
            "profile_source_url": "Публичный источник данных",
            "profile_source_checked_on": "Источник проверен",
            "country_code": "Код страны",
            "is_active": "Показывать чтеца пользователям",
        }
        help_texts: ClassVar[dict[str, str]] = {
            "code": "Постоянный уникальный код латиницей, например saad-al-ghamdi.",
            "name_tr": "Если не заполнено, турецкий интерфейс покажет английское имя.",
            "biography_tr": ("Если не заполнено, турецкий интерфейс покажет английскую биографию."),
            "profile_source_url": (
                "Ссылка для проверки биографических фактов. Тексты IQRO — самостоятельные краткие "
                "описания, а не копии материала источника."
            ),
            "profile_source_checked_on": "Дата последней ручной проверки источника.",
            "country_code": "Двухбуквенный ISO-код страны, например SA или EG.",
        }

    _uploaded_portrait_key: str | None = None

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        if not self.instance.portrait_object_key:
            self.fields["remove_portrait"].disabled = True

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        uploaded = cleaned.get("portrait_upload")
        remove = cleaned.get("remove_portrait") is True
        if uploaded and remove:
            self.add_error(
                "portrait_upload",
                "Выберите загрузку нового портрета или удаление текущего, но не оба действия.",
            )
            return cleaned
        if uploaded and not self.errors:
            try:
                result = upload_reciter_portrait(
                    uploaded,
                    reciter_code=str(cleaned.get("code") or ""),
                )
            except ReciterPortraitUploadError as exc:
                self.add_error("portrait_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Reciter portrait upload failed")
                self.add_error(
                    "portrait_upload",
                    "Не удалось загрузить портрет в media-хранилище. Повторите позже.",
                )
            else:
                self._uploaded_portrait_key = result.object_key
        return cleaned

    def save(self, commit: bool = True) -> Reciter:
        instance = cast("Reciter", super().save(commit=False))
        if self.cleaned_data.get("remove_portrait") is True:
            instance.portrait_object_key = ""
        elif self._uploaded_portrait_key is not None:
            instance.portrait_object_key = self._uploaded_portrait_key
        if commit:
            instance.save()
            self.save_m2m()
        return instance


class QuranFoundationReadOnlyAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False


@admin.register(QuranFoundationAyahRecitation)
class QuranFoundationAyahRecitationAdmin(QuranFoundationReadOnlyAdmin):
    list_display = (
        "source_id",
        "name_en",
        "style",
        "environment",
        "quran_edition_version",
        "is_available",
        "last_synced_at",
    )
    list_filter = ("environment", "is_available", "style", "quran_edition_version")
    search_fields = ("=source_id", "name_ar", "name_en", "name_ru")
    list_select_related = ("quran_edition_version__edition",)
    readonly_fields = tuple(field.name for field in QuranFoundationAyahRecitation._meta.fields)


@admin.register(QuranFoundationAyahRecitationChapter)
class QuranFoundationAyahRecitationChapterAdmin(QuranFoundationReadOnlyAdmin):
    list_display = ("recitation", "chapter_number", "ayah_count")
    list_filter = ("recitation",)
    search_fields = ("=recitation__source_id", "=chapter_number")
    list_select_related = ("recitation",)
    readonly_fields = tuple(
        field.name for field in QuranFoundationAyahRecitationChapter._meta.fields
    )


@admin.register(QuranFoundationSyncState)
class QuranFoundationSyncStateAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "source_reciter_id",
        "environment",
        "content_sync_resource_id",
        "last_success_at",
        "consecutive_failures",
        "last_error_code",
    )
    list_filter = ("environment", "last_success_at", "consecutive_failures")
    search_fields = ("=source_reciter_id", "=content_sync_resource_id")
    readonly_fields = tuple(field.name for field in QuranFoundationSyncState._meta.fields)

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self,
        request: HttpRequest,
        obj: QuranFoundationSyncState | None = None,
    ) -> bool:
        return bool(super().has_change_permission(request, obj) and obj is not None)

    def has_delete_permission(
        self,
        _request: HttpRequest,
        _obj: QuranFoundationSyncState | None = None,
    ) -> bool:
        return False


@admin.register(Reciter)
class ReciterAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = ReciterAdminForm
    list_display = (
        "portrait_available",
        "code",
        "name_ar",
        "name_en",
        "name_ru",
        "name_tr",
        "country_code",
        "is_active",
    )
    list_filter = ("is_active", "country_code")
    search_fields = ("=code", "name_ar", "name_en", "name_ru", "name_tr")
    readonly_fields = (
        "portrait_preview",
        "portrait_storage_key",
        "id",
        "created_at",
        "updated_at",
    )
    fieldsets = (
        (
            "Основная информация",
            {
                "fields": (
                    "code",
                    "name_ar",
                    "name_en",
                    "name_ru",
                    "name_tr",
                    "country_code",
                    "is_active",
                )
            },
        ),
        (
            "Биографии",
            {
                "fields": (
                    "biography_ar",
                    "biography_en",
                    "biography_ru",
                    "biography_tr",
                )
            },
        ),
        (
            "Источник данных",
            {"fields": ("profile_source_url", "profile_source_checked_on")},
        ),
        (
            "Портрет чтеца",
            {"fields": ("portrait_preview", "portrait_upload", "remove_portrait")},
        ),
        (
            "Служебная информация",
            {
                "classes": ("collapse",),
                "fields": ("portrait_storage_key", "id", "created_at", "updated_at"),
            },
        ),
    )

    @admin.display(boolean=True, description="Портрет")
    def portrait_available(self, obj: Reciter) -> bool:
        return bool(obj.portrait_object_key)

    @admin.display(description="Текущий портрет")
    def portrait_preview(self, obj: Reciter | None) -> str:
        if obj is None or not obj.portrait_object_key:
            return "Портрет ещё не загружен"
        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">'
            '<img src="{}" alt="" width="160" height="160" '
            'style="object-fit:cover;border-radius:18px" /></a>',
            public_audio_url(obj.portrait_object_key),
            public_audio_url(obj.portrait_object_key),
        )

    @admin.display(description="Адрес файла в хранилище (служебное поле)")
    def portrait_storage_key(self, obj: Reciter | None) -> str:
        if obj is None or not obj.portrait_object_key:
            return "—"
        return obj.portrait_object_key

    def save_model(
        self,
        request: HttpRequest,
        obj: Reciter,
        form: Any,
        change: bool,
    ) -> None:
        super().save_model(request, obj, form, change)
        enqueue_reciter_content_change(
            action="updated" if change else "created",
            reciter_id=obj.id,
        )


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

    def save_model(
        self,
        request: HttpRequest,
        obj: RecitationEdition,
        form: Any,
        change: bool,
    ) -> None:
        previous_status = None
        if change:
            previous_status = (
                RecitationEdition.objects.filter(pk=obj.pk).values_list("status", flat=True).first()
            )
        super().save_model(request, obj, form, change)
        if previous_status != obj.status and obj.status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        }:
            enqueue_audio_content_change(
                action=obj.status,
                recitation_id=obj.id,
                reciter_id=obj.reciter_id,
                version=obj.version,
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
    )
    list_filter = ("scope", "recitation_edition__status")
    search_fields = ("recitation_edition__code",)
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


@admin.register(AudioRendition)
class AudioRenditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "track",
        "quality",
        "is_default",
        "codec",
        "bitrate_kbps",
        "size_bytes",
        "cdn_contract_verified_at",
    )
    list_filter = (
        "quality",
        "codec",
        "is_default",
        "cdn_contract_verified_at",
        "track__recitation_edition__status",
    )
    search_fields = (
        "object_key",
        "checksum_sha256",
        "origin_etag",
        "etag",
        "track__recitation_edition__code",
    )
    list_select_related = ("track__recitation_edition",)
    readonly_fields = (
        "id",
        "origin_etag",
        "etag",
        "cdn_contract_verified_at",
        "created_at",
        "updated_at",
    )

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: AudioRendition | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.track.recitation_edition.status != RecitationPublicationStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: AudioRendition | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.track.recitation_edition.status == RecitationPublicationStatus.DRAFT
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
