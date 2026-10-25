# ruff: noqa: RUF001 -- Admin copy intentionally uses Cyrillic characters.

from __future__ import annotations

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, ClassVar, cast
from urllib.parse import urlencode

from django import forms
from django.contrib import admin, messages
from django.contrib.admin.utils import unquote
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.core.files.uploadedfile import UploadedFile
from django.db.models import Count, Q
from django.http import (
    Http404,
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    HttpResponseRedirect,
    JsonResponse,
)
from django.urls import path, reverse
from django.utils import timezone
from django.utils.html import format_html, format_html_join
from django.utils.safestring import mark_safe
from django.utils.text import slugify

from quran_backend.modules.audio.models import (
    AudioCatalogSettings,
    AudioPlaybackPosition,
    AudioRendition,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    PlayerBackground,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    QuranFoundationSyncState,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)
from quran_backend.modules.audio.mp3quran_timings import (
    Mp3QuranTimingError,
    cached_timing_read,
    import_mp3quran_timings,
    mp3quran_folder,
    prepare_mp3quran_timings,
    untimed_surah_tracks,
)
from quran_backend.modules.audio.player_background_upload import (
    MAX_PLAYER_BACKGROUND_KIB,
    PlayerBackgroundUploadError,
    upload_player_background,
)
from quran_backend.modules.audio.player_background_video import (
    MAX_VIDEO_SECONDS,
    MAX_VIDEO_UPLOAD_MIB,
    PlayerBackgroundVideoError,
    upload_player_background_video,
)
from quran_backend.modules.audio.portrait_upload import (
    MAX_RECITER_PORTRAIT_MIB,
    ReciterPortraitUploadError,
    upload_reciter_portrait,
)
from quran_backend.modules.audio.selectors import (
    forget_recitation_summaries,
    public_recitation_base,
    public_reciters,
    timed_recitation_candidates,
)
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.audio.surah_upload import (
    LISTENING_QURAN_EDITION,
    MAX_SURAH_UPLOAD_MIB,
    SurahUploadError,
    accepts_new_surahs,
    surah_number_from_filename,
    upload_surah_audio,
)
from quran_backend.modules.core.content_revalidation import (
    enqueue_audio_content_change,
    enqueue_reciter_content_change,
)
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.quran.models import QuranEdition

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
        if cleaned.get("portrait_upload") and cleaned.get("remove_portrait") is True:
            self.add_error(
                "portrait_upload",
                "Выберите загрузку нового портрета или удаление текущего, но не оба действия.",
            )
        return cleaned

    def _post_clean(self) -> None:
        super()._post_clean()  # type: ignore[misc]
        # Upload only once the model itself is valid (a taken code, say), so a
        # rejected form never leaves an immutable file behind in storage.
        uploaded = self.cleaned_data.get("portrait_upload")
        if uploaded and not self.errors:
            try:
                result = upload_reciter_portrait(
                    uploaded,
                    reciter_code=str(self.cleaned_data.get("code") or ""),
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


class PlayerBackgroundAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    image_upload = forms.FileField(
        required=False,
        label="Загрузить изображение",
        help_text=(
            f"WebP или JPEG до {MAX_PLAYER_BACKGROUND_KIB} КБ, вертикальное, около 1080×1920. "
            "Только природа, архитектура или орнамент: без людей, лиц и животных."
        ),
        widget=forms.ClearableFileInput(attrs={"accept": "image/webp,image/jpeg"}),
    )
    video_upload = forms.FileField(
        required=False,
        label="Загрузить видео",
        help_text=(
            f"MP4, MOV или WebM до {MAX_VIDEO_UPLOAD_MIB} МБ. Сервер уберёт звук, сожмёт "
            f"видео до 720p и обрежет до {MAX_VIDEO_SECONDS} с. В приложении оно идёт по кругу. "
            "Первый кадр станет изображением фона, если изображение не загружено отдельно."
        ),
        widget=forms.ClearableFileInput(attrs={"accept": "video/mp4,video/quicktime,video/webm"}),
    )
    remove_video = forms.BooleanField(
        required=False,
        label="Убрать видео",
        help_text="Фон останется неподвижным изображением.",
    )

    class Meta:
        model = PlayerBackground
        fields = (
            "title_ru",
            "title_en",
            "title_ar",
            "title_tr",
            "show_equalizer",
            "sort_order",
            "is_active",
        )
        labels: ClassVar[dict[str, str]] = {
            "title_ru": "Название на русском",
            "title_en": "Название на английском",
            "title_ar": "Название на арабском",
            "title_tr": "Название на турецком",
            "sort_order": "Порядок вывода",
            "is_active": "Показывать в приложении",
            "show_equalizer": "Показывать эквалайзер",
        }
        help_texts: ClassVar[dict[str, str]] = {
            "title_ru": (
                "Так фон подписан в приложении. Помечать видео не нужно: "
                "приложение само покажет значок камеры."
            ),
            "title_tr": "Если не заполнено, турецкий интерфейс покажет английское название.",
        }

    _uploaded_image_key: str | None = None
    _uploaded_video_key: str | None = None

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        uploaded = cleaned.get("image_upload")
        video = cleaned.get("video_upload")
        if video and cleaned.get("remove_video"):
            self.add_error("remove_video", "Либо загрузите новое видео, либо уберите текущее.")
            return cleaned
        if not uploaded and not video and not self.instance.image_object_key:
            self.add_error("image_upload", "Загрузите изображение или видео фона.")
            return cleaned
        if video and not self.errors:
            try:
                clip = upload_player_background_video(video)
            except PlayerBackgroundVideoError as exc:
                self.add_error("video_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Player background video upload failed")
                self.add_error(
                    "video_upload",
                    "Не удалось обработать или сохранить видео. Повторите позже.",
                )
            else:
                self._uploaded_video_key = clip.video_object_key
                # A separately uploaded image stays the poster.
                if not uploaded:
                    self._uploaded_image_key = clip.poster_object_key
        if uploaded and not self.errors:
            try:
                result = upload_player_background(uploaded)
            except PlayerBackgroundUploadError as exc:
                self.add_error("image_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Player background upload failed")
                self.add_error(
                    "image_upload",
                    "Не удалось загрузить фон в media-хранилище. Повторите позже.",
                )
            else:
                self._uploaded_image_key = result.object_key
        return cleaned

    def save(self, commit: bool = True) -> PlayerBackground:
        instance = cast("PlayerBackground", super().save(commit=False))
        if self._uploaded_image_key is not None:
            instance.image_object_key = self._uploaded_image_key
        if self._uploaded_video_key is not None:
            instance.video_object_key = self._uploaded_video_key
        elif self.cleaned_data.get("remove_video"):
            instance.video_object_key = ""
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


@admin.register(AudioPlaybackPosition)
class AudioPlaybackPositionAdmin(QuranFoundationReadOnlyAdmin):
    list_display = (
        "user",
        "track",
        "position_ms",
        "revision",
        "client_updated_at",
        "updated_at",
    )
    list_filter = (
        "repeat_enabled",
        "track__recitation_edition__status",
        "client_updated_at",
    )
    search_fields = ("=user__id", "user__email", "=track__id")
    list_select_related = ("user", "device", "track__recitation_edition")
    readonly_fields = tuple(field.name for field in AudioPlaybackPosition._meta.fields)


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


@admin.register(PlayerBackground)
class PlayerBackgroundAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = PlayerBackgroundAdminForm
    list_display = (
        "image_thumbnail",
        "title_ru",
        "title_en",
        "sort_order",
        "is_active",
        "show_equalizer",
    )
    list_display_links = ("image_thumbnail", "title_ru")
    list_editable = ("sort_order", "is_active", "show_equalizer")
    list_filter = ("is_active",)
    search_fields = ("title_ru", "title_en", "title_ar", "title_tr")
    ordering = ("sort_order", "created_at")
    readonly_fields = (
        "image_preview",
        "video_preview",
        "image_storage_key",
        "video_storage_key",
        "id",
        "created_at",
        "updated_at",
    )
    fieldsets = (
        ("Названия", {"fields": ("title_ru", "title_en", "title_ar", "title_tr")}),
        ("Изображение", {"fields": ("image_preview", "image_upload")}),
        ("Видео", {"fields": ("video_preview", "video_upload", "remove_video")}),
        ("Публикация", {"fields": ("is_active", "show_equalizer", "sort_order")}),
        (
            "Служебная информация",
            {
                "classes": ("collapse",),
                "fields": (
                    "image_storage_key",
                    "video_storage_key",
                    "id",
                    "created_at",
                    "updated_at",
                ),
            },
        ),
    )

    @admin.display(description="Фон")
    def image_thumbnail(self, obj: PlayerBackground) -> str:
        if not obj.image_object_key:
            return "—"
        return format_html(
            '<img src="{}" alt="" width="36" height="64" '
            'style="object-fit:cover;border-radius:6px" />',
            public_audio_url(obj.image_object_key),
        )

    @admin.display(description="Текущее изображение")
    def image_preview(self, obj: PlayerBackground | None) -> str:
        if obj is None or not obj.image_object_key:
            return "Изображение ещё не загружено"
        url = public_audio_url(obj.image_object_key)
        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">'
            '<img src="{}" alt="" width="135" height="240" '
            'style="object-fit:cover;border-radius:14px" /></a>',
            url,
            url,
        )

    @admin.display(description="Текущее видео")
    def video_preview(self, obj: PlayerBackground | None) -> str:
        if obj is None or not obj.video_object_key:
            return "Видео не загружено"
        return format_html(
            '<video src="{}" poster="{}" width="135" height="240" muted loop autoplay '
            'playsinline style="object-fit:cover;border-radius:14px"></video>',
            public_audio_url(obj.video_object_key),
            public_audio_url(obj.image_object_key),
        )

    @admin.display(description="Адрес файла в хранилище (служебное поле)")
    def image_storage_key(self, obj: PlayerBackground | None) -> str:
        if obj is None or not obj.image_object_key:
            return "—"
        return obj.image_object_key

    @admin.display(description="Адрес видео в хранилище (служебное поле)")
    def video_storage_key(self, obj: PlayerBackground | None) -> str:
        if obj is None or not obj.video_object_key:
            return "—"
        return obj.video_object_key


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
        "catalog_status",
        "recordings",
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
                    "catalog_status",
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
        ("Записи", {"fields": ("recordings",)}),
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

    @admin.display(description="В приложении")
    def catalog_status(self, obj: Reciter | None) -> str:
        if obj is None or obj._state.adding:
            return "Появится после сохранения и публикации первой записи."
        if not obj.is_active:
            return "Скрыт: выключен флажок «Показывать чтеца пользователям»."
        if public_reciters().filter(pk=obj.pk).exists():
            return "Виден в приложении и на сайте."
        return "Не виден: у чтеца нет опубликованной записи с сурами."

    @admin.display(description="Записи чтеца")
    def recordings(self, obj: Reciter | None) -> str:
        if obj is None or obj._state.adding:
            return "Сохраните чтеца, чтобы добавить записи."
        add_url = (
            reverse("admin:audio_recitationedition_add")
            + "?"
            + urlencode({"reciter": str(obj.pk), "listening_only": "1"})
        )
        rows = format_html_join(
            "",
            '<li><a href="{}">{}</a> — {}, {}</li>',
            (
                (
                    reverse("admin:audio_recitationedition_change", args=[recitation.pk]),
                    f"{recitation.get_style_display()} · v{recitation.version}",
                    recitation.get_status_display(),
                    "только Аудио" if recitation.listening_only else "Аудио, Мусхаф, Заучивание",
                )
                for recitation in obj.recitations.order_by("style", "-created_at")
            ),
        )
        return format_html(
            '<ul style="margin:0 0 8px;padding-left:18px">{}</ul>'
            '<a class="button" href="{}">Добавить запись для прослушивания</a>',
            rows or mark_safe("<li>Записей пока нет.</li>"),
            add_url,
        )

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


class RecitationEditionAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    class Meta:
        model = RecitationEdition
        fields = (
            "reciter",
            "style",
            "listening_only",
            "quran_edition_version",
            "status",
            "rights_holder",
            "license_name",
            "license_url",
            "license_spdx_id",
            "license_attribution",
            "stream_allowed",
            "offline_download_allowed",
            "rights_evidence_url",
            "rights_checked_on",
            "source_name",
            "source_url",
            "code",
            "version",
            "source_version",
            "source_checksum_sha256",
        )
        help_texts: ClassVar[dict[str, str]] = {
            "listening_only": (
                "Запись звучит только во вкладке «Аудио» и в мини-плеере, никогда в Мусхафе "
                "и Заучивании. Можно публиковать с любым числом сур и докладывать новые суры "
                "после публикации."
            ),
            "quran_edition_version": "Для записей прослушивания оставьте значение по умолчанию.",
            "status": (
                "Опубликовать можно, когда загружена хотя бы одна сура. "
                "Дата публикации проставится сама."
            ),
            "stream_allowed": "Выключите, чтобы скрыть запись из приложения и с сайта.",
            "offline_download_allowed": (
                "Разрешить скачивание записи в приложение; работает, когда загружены все 114 сур."
            ),
            "source_name": "Откуда получены файлы.",
            "code": "Для записей прослушивания заполнится сам из кода чтеца и стиля.",
            "version": "Для записей прослушивания заполнится сам: 1, 2, 3…",
            "source_version": "Если пусто, совпадёт с версией.",
            "source_checksum_sha256": "Нужна только для записей с таймкодами аятов.",
        }

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        for name in ("code", "version", "source_version"):
            if name in self.fields:
                self.fields[name].required = False
        if self.instance._state.adding:
            self.fields["listening_only"].initial = True
            self.fields["source_name"].initial = "Загружено редактором IQRO"
            # Choices from the model field carry the admin's Russian labels.
            cast("forms.ChoiceField", self.fields["status"]).choices = [
                (value, label)
                for value, label in RecitationEdition._meta.get_field("status").choices or ()
                if value == RecitationPublicationStatus.DRAFT
            ]
            default_version = (
                QuranEdition.objects.filter(code=LISTENING_QURAN_EDITION)
                .values_list("active_version_id", flat=True)
                .first()
            )
            if default_version is not None:
                self.fields["quran_edition_version"].initial = default_version

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        if self.instance._state.adding:
            self._fill_package_identity(cleaned)
        elif "code" in self.fields and not (cleaned.get("code") and cleaned.get("version")):
            self.add_error("code", "Код и версия обязательны.")
        if "source_version" in self.fields and not cleaned.get("source_version"):
            cleaned["source_version"] = cleaned.get("version") or self.instance.version
        persisted_status = (
            None
            if self.instance._state.adding
            else RecitationEdition.objects.filter(pk=self.instance.pk)
            .values_list("status", flat=True)
            .first()
        )
        if (
            cleaned.get("status") == RecitationPublicationStatus.PUBLISHED
            and persisted_status == RecitationPublicationStatus.DRAFT
        ):
            # Same as RecitationEdition.publish(); the date is never typed by hand.
            self.instance.published_at = timezone.now()
        return cleaned

    def _fill_package_identity(self, cleaned: dict[str, Any]) -> None:
        reciter = cleaned.get("reciter")
        style = cleaned.get("style")
        edition_version = cleaned.get("quran_edition_version")
        if cleaned.get("code") and cleaned.get("version"):
            return
        if not cleaned.get("listening_only"):
            self.add_error("code", "Для записи с таймкодами укажите код и версию.")
            return
        if reciter is None or not style or edition_version is None:
            return
        code = cleaned.get("code") or slugify(f"{reciter.code}-{style}")[:64]
        number = 1
        while (
            RecitationEdition.objects.filter(code=code, version=str(number)).exists()
            or RecitationEdition.objects.filter(
                reciter=reciter,
                quran_edition_version=edition_version,
                style=style,
                version=str(number),
            ).exists()
        ):
            number += 1
        cleaned["code"] = code
        cleaned["version"] = cleaned.get("version") or str(number)


@admin.register(RecitationEdition)
class RecitationEditionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = RecitationEditionAdminForm
    actions = None
    list_display = (
        "reciter",
        "style",
        "listening_only",
        "status",
        "surah_count",
        "version",
        "quran_edition_version",
        "published_at",
    )
    list_filter = ("status", "listening_only", "style", "quran_edition_version", "reciter")
    search_fields = ("=code", "version", "reciter__name_ar", "reciter__name_en", "reciter__name_ru")
    list_select_related = (
        "reciter",
        "quran_edition_version__edition",
    )
    readonly_fields = (
        "catalog_status",
        "surah_coverage",
        "ayah_timings",
        "published_at",
        "id",
        "created_at",
        "updated_at",
    )
    fieldsets = (
        (
            "Чтец и назначение",
            {"fields": ("reciter", "style", "listening_only", "quran_edition_version")},
        ),
        ("Публикация", {"fields": ("status", "published_at", "catalog_status")}),
        ("Суры", {"fields": ("surah_coverage", "ayah_timings")}),
        (
            "Источник и права",
            {
                "classes": ("collapse",),
                "fields": (
                    "rights_holder",
                    "stream_allowed",
                    "offline_download_allowed",
                    "rights_evidence_url",
                    "rights_checked_on",
                    "license_name",
                    "license_url",
                    "license_spdx_id",
                    "license_attribution",
                    "source_name",
                    "source_url",
                ),
            },
        ),
        (
            "Служебная информация",
            {
                "classes": ("collapse",),
                "fields": (
                    "code",
                    "version",
                    "source_version",
                    "source_checksum_sha256",
                    "id",
                    "created_at",
                    "updated_at",
                ),
            },
        ),
    )

    class Media:
        js = ("audio/admin/surah_upload.js",)

    def get_queryset(self, request: HttpRequest) -> Any:
        return (
            super()
            .get_queryset(request)
            .annotate(
                surah_total=Count("tracks", filter=Q(tracks__scope=AudioTrackScope.SURAH)),
            )
        )

    @admin.display(description="Сур", ordering="surah_total")
    def surah_count(self, obj: RecitationEdition) -> int:
        return int(getattr(obj, "surah_total", 0))

    @admin.display(description="Где звучит")
    def catalog_status(self, obj: RecitationEdition | None) -> str:  # noqa: PLR0911
        if obj is None or obj._state.adding:
            return "Сохраните черновик, затем загрузите суры."
        if obj.status == RecitationPublicationStatus.WITHDRAWN:
            return "Отозвана: нигде не звучит."
        if obj.status == RecitationPublicationStatus.DRAFT:
            return "Черновик: пользователи его не видят."
        if not public_recitation_base().filter(pk=obj.pk).exists():
            if not obj.reciter.is_active:
                return "Не звучит: чтец скрыт."
            if not obj.listening_only:
                return (
                    "Не звучит: запись для Мусхафа и Заучивания должна содержать все 114 сур. "
                    "Для неполной записи включите «Только для вкладки «Аудио»»."
                )
            if not obj.stream_allowed:
                return "Не звучит: выключено воспроизведение."
            return "Не звучит: проверьте издание Корана."
        if obj.listening_only:
            return "Звучит во вкладке «Аудио» и в мини-плеере."
        return "Звучит во вкладке «Аудио»; в Мусхафе и Заучивании — если есть все таймкоды."

    @admin.display(description="Загруженные суры")
    def surah_coverage(self, obj: RecitationEdition | None) -> str:
        if obj is None or obj._state.adding:
            return "Сохраните черновик, чтобы загрузить суры."
        numbers = [
            number
            for number in obj.tracks.filter(scope=AudioTrackScope.SURAH)
            .order_by("surah_number")
            .values_list("surah_number", flat=True)
            if number is not None
        ]
        summary = (
            f"{len(numbers)} из 114: {_number_ranges(numbers)}" if numbers else "Пока ни одной."
        )
        if not accepts_new_surahs(obj):
            return summary
        return format_html(
            '<p style="margin:0 0 8px">{}</p>'
            '<div data-surah-upload="{}" data-max-mib="{}">'
            '<input type="file" accept="audio/mpeg,.mp3" multiple data-surah-files>'
            '<p class="help">MP3, каждый файл — одна сура. Номер берётся из начала имени '
            "файла (001.mp3, 2.mp3, «112 Аль-Ихлас.mp3»), его можно поправить перед "
            "загрузкой. До {} МБ на файл.</p>"
            '<table data-surah-queue style="margin-top:8px"></table>'
            '<button type="button" class="button" data-surah-start disabled>Загрузить</button>'
            "</div>",
            summary,
            reverse("admin:audio_recitationedition_upload_surah", args=[obj.pk]),
            MAX_SURAH_UPLOAD_MIB,
            MAX_SURAH_UPLOAD_MIB,
        )

    @admin.display(description="Таймкоды аятов")
    def ayah_timings(self, obj: RecitationEdition | None) -> str:
        if obj is None or obj._state.adding:
            return "—"
        surah_total = obj.tracks.filter(scope=AudioTrackScope.SURAH).count()
        untimed = len(untimed_surah_tracks(obj))
        timed = surah_total - untimed
        summary = f"Есть у {timed} из {surah_total} сур." if surah_total else "Сур пока нет."
        if not untimed or obj.status == RecitationPublicationStatus.WITHDRAWN:
            return summary
        folder = mp3quran_folder(obj)
        if folder is None:
            return format_html(
                "{} Таймкоды можно подтянуть из MP3Quran, если файлы записи взяты из папки "
                "MP3Quran и её адрес (https://{}/audio/…/) указан в «Адресе источника».",
                summary,
                "cdn.mp3quran.net",
            )
        try:
            read = cached_timing_read(obj)
        except Mp3QuranTimingError:
            note = "Не удалось спросить MP3Quran, есть ли у него таймкоды; можно попробовать."
        else:
            if read is None:
                return format_html(
                    "{} У MP3Quran нет таймкодов аятов для папки {}.", summary, folder
                )
            note = f"У MP3Quran есть таймкоды для этой папки (чтец №{read.read_id}, {read.rewaya})."
        return format_html(
            '<p style="margin:0 0 8px">{} {}</p>'
            '<button type="submit" class="button" formmethod="post" formnovalidate '
            'formaction="{}">Подтянуть таймкоды из MP3Quran</button>'
            '<p class="help">Сначала проверим, что каждый файл записи — тот же, что у MP3Quran '
            "(размер и MD5), иначе таймкоды не добавятся. Звук и суры не меняются. "
            "Когда таймкоды будут у всех аятов, запись зазвучит в Мусхафе и Заучивании. "
            "Проверка занимает до минуты; несохранённые правки формы не сохранятся.</p>",
            summary,
            note,
            reverse("admin:audio_recitationedition_mp3quran_timings", args=[obj.pk]),
        )

    def get_urls(self) -> list[Any]:
        return [
            path(
                "<path:object_id>/surahs/upload/",
                self.admin_site.admin_view(self.upload_surah_view),
                name="audio_recitationedition_upload_surah",
            ),
            path(
                "<path:object_id>/timings/mp3quran/",
                self.admin_site.admin_view(self.mp3quran_timings_view),
                name="audio_recitationedition_mp3quran_timings",
            ),
            *super().get_urls(),
        ]

    def upload_surah_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        recitation = self.get_object(request, unquote(object_id))
        if recitation is None:
            raise Http404
        if not (
            self.has_change_permission(request, recitation)
            and request.user.has_perm("audio.add_audiotrack")
            and request.user.has_perm("audio.add_audiorendition")
        ):
            raise PermissionDenied
        uploaded = request.FILES.get("file")
        if uploaded is None:
            return JsonResponse({"error": "Файл не получен."}, status=400)
        raw_number = str(request.POST.get("surah_number") or "").strip()
        surah_number = (
            int(raw_number)
            if raw_number.isdigit()
            else surah_number_from_filename(uploaded.name or "")
        )
        if surah_number is None:
            return JsonResponse({"error": "Укажите номер суры."}, status=400)
        try:
            with _uploaded_file_path(uploaded) as source_path:
                result = upload_surah_audio(recitation.pk, surah_number, source_path)
        except SurahUploadError as exc:
            return JsonResponse({"error": str(exc)}, status=400)
        except ImproperlyConfigured, ObjectStorageError, OSError:
            logger.exception("Surah audio upload failed")
            return JsonResponse(
                {"error": "Не удалось сохранить файл в хранилище. Повторите позже."},
                status=502,
            )
        self.log_change(request, recitation, f"Загружена сура {result.surah_number}.")
        return JsonResponse(
            {
                "surah_number": result.surah_number,
                "duration_ms": result.duration_ms,
                "bitrate_kbps": result.bitrate_kbps,
                "size_bytes": result.size_bytes,
            }
        )

    def mp3quran_timings_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        recitation = self.get_object(request, unquote(object_id))
        if recitation is None:
            raise Http404
        if not (
            self.has_change_permission(request, recitation)
            and request.user.has_perm("audio.add_audiotimingversion")
            and request.user.has_perm("audio.add_ayahaudiosegment")
        ):
            raise PermissionDenied
        change_url = reverse("admin:audio_recitationedition_change", args=[recitation.pk])
        try:
            result = import_mp3quran_timings(prepare_mp3quran_timings(recitation))
        except Mp3QuranTimingError as exc:
            self.message_user(request, str(exc), messages.ERROR)
            return HttpResponseRedirect(change_url)
        message = (
            f"Таймкоды MP3Quran добавлены: {result.surah_count} сур, {result.ayah_count} аятов "
            f"(версия {result.timing_version.version})."
        )
        self.log_change(request, recitation, message)
        self.message_user(request, message, messages.SUCCESS)
        return HttpResponseRedirect(change_url)

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: RecitationEdition | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.status != RecitationPublicationStatus.DRAFT:
            # Withdrawal and the rights paperwork stay editable; the package itself does not.
            editable = (
                {"status", "listening_only", "rights_evidence_url", "rights_checked_on"}
                if obj.status == RecitationPublicationStatus.PUBLISHED
                else {"rights_evidence_url", "rights_checked_on"}
            )
            immutable = tuple(
                field.name for field in obj._meta.fields if field.name not in editable
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
        previous = (
            RecitationEdition.objects.filter(pk=obj.pk).values("status", "listening_only").first()
            if change
            else None
        )
        super().save_model(request, obj, form, change)
        previous_status = previous["status"] if previous else None
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
        elif (
            previous is not None
            and previous["listening_only"] != obj.listening_only
            and obj.status == RecitationPublicationStatus.PUBLISHED
        ):
            # Where a live recitation plays changed; clients must drop cached roles.
            forget_recitation_summaries()
            enqueue_audio_content_change(
                action=obj.status,
                recitation_id=obj.id,
                reciter_id=obj.reciter_id,
                version=obj.version,
            )


def _number_ranges(numbers: list[int]) -> str:
    ranges: list[str] = []
    start = previous = None
    for number in [*numbers, None]:
        if number is not None and previous is not None and number == previous + 1:
            previous = number
            continue
        if start is not None:
            ranges.append(str(start) if start == previous else f"{start}–{previous}")
        start = previous = number
    return ", ".join(ranges)


@contextmanager
def _uploaded_file_path(uploaded: UploadedFile) -> Iterator[Path]:
    temporary_path = getattr(uploaded, "temporary_file_path", None)
    if callable(temporary_path):
        yield Path(temporary_path())
        return
    with NamedTemporaryFile(prefix="iqro-surah-", suffix=".upload") as temporary:
        for chunk in uploaded.chunks():
            temporary.write(chunk)
        temporary.flush()
        yield Path(temporary.name)


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


@admin.register(AudioCatalogSettings)
class AudioCatalogSettingsAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """One row: which published, timed recitation teaches by default."""

    list_display = ("__str__", "updated_at")
    fields = ("teaching_recitation",)

    def formfield_for_foreignkey(self, db_field: Any, request: HttpRequest, **kwargs: Any) -> Any:
        if db_field.name == "teaching_recitation":
            kwargs["queryset"] = timed_recitation_candidates().order_by(
                "reciter__name_ru", "style", "-published_at"
            )
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return not AudioCatalogSettings.objects.exists() and super().has_add_permission(request)

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False
