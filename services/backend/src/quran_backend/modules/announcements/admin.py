# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Admin of announcements: texts in four languages, a live preview, publishing.

The «Публикация» panel on top of the form says what the announcement is now, what
is still missing and offers one button, «Сохранить и опубликовать». A published
announcement stays read-only: «Изменить» opens an edit draft, and «Сохранить и
опубликовать снова» swaps the published content for it at once. «Показать снова
на главной» brings it back to those who closed it; «История показов» lists each wave.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any, ClassVar, cast

from django import forms
from django.contrib import admin, messages
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.db.models import Case, Q, QuerySet, Sum, Value, When
from django.forms.models import BaseInlineFormSet
from django.http import HttpRequest, HttpResponse, HttpResponseRedirect
from django.template.response import TemplateResponse
from django.urls import reverse
from django.utils import timezone
from django.utils.html import format_html, format_html_join

from quran_backend.modules.accounts.models import User
from quran_backend.modules.announcements.media import (
    MAX_IMAGE_KIB,
    AnnouncementMediaError,
    upload_announcement_image,
)
from quran_backend.modules.announcements.models import (
    LANGUAGE_NAMES,
    LANGUAGES,
    MAX_STEPS,
    PLATFORMS,
    ActionType,
    Announcement,
    AnnouncementSettings,
    AnnouncementStatus,
    AnnouncementStep,
    AnnouncementTranslation,
)
from quran_backend.modules.announcements.routes import SCREENS
from quran_backend.modules.announcements.services import (
    CHANGE_PERMISSION,
    EXTEND_DAYS,
    PUBLISH_PERMISSION,
    RELIGIOUS_PERMISSION,
    SENSITIVE_PERMISSION,
    AnnouncementNotReadyError,
    archive,
    cancel_edit,
    duplicate,
    extend_display,
    is_sensitive,
    publish,
    readiness,
    republish,
    reshow,
    sign_religious_review,
    start_edit,
    submit_for_review,
    uses_image,
    withdraw,
)
from quran_backend.modules.audio.models import Reciter
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.content_revalidation import enqueue_announcements_change
from quran_backend.modules.core.object_storage import ObjectStorageError

logger = logging.getLogger(__name__)

PLATFORM_NAMES = {"web": "Сайт", "android": "Android", "ios": "iOS"}
# Preview only; the site and the app label kinds through their own dictionaries.
KIND_EYEBROWS = {
    "reciter": {"ru": "Новый чтец", "en": "New reciter", "ar": "قارئ جديد", "tr": "Yeni kari"},
    "feature": {"ru": "Что нового", "en": "What's new", "ar": "ما الجديد", "tr": "Yenilikler"},
    "app_release": {
        "ru": "Новая версия",
        "en": "New version",
        "ar": "إصدار جديد",
        "tr": "Yeni sürüm",
    },
    "content": {
        "ru": "Новое содержание",
        "en": "New content",
        "ar": "محتوى جديد",
        "tr": "Yeni içerik",
    },
    "fundraising": {
        "ru": "Поддержать проект",
        "en": "Support the project",
        "ar": "ادعم المشروع",
        "tr": "Projeyi destekle",
    },
    "general": {"ru": "Объявление", "en": "Announcement", "ar": "إعلان", "tr": "Duyuru"},
}


class ReciterChoiceField(forms.ModelChoiceField):  # type: ignore[type-arg]
    def label_from_instance(self, obj: Reciter) -> str:
        return f"{obj.name_ru} · {obj.name_ar}"


class AnnouncementAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    action_reciter = ReciterChoiceField(
        queryset=Reciter.objects.filter(is_active=True).order_by("name_ru"),
        required=False,
        label="Чтец",
        help_text="Кнопка «Послушать» откроет этого чтеца в плеере.",
    )
    image_upload = forms.FileField(
        required=False,
        label="Загрузить картинку",
        help_text=(
            f"WebP или JPEG до {MAX_IMAGE_KIB} КБ. Сервер сам сделает миниатюру 96×96 "
            "для пузыря. У объявления о чтеце можно не загружать: возьмётся его портрет."
        ),
        widget=forms.ClearableFileInput(attrs={"accept": "image/webp,image/jpeg"}),
    )
    remove_image = forms.BooleanField(required=False, label="Убрать картинку")
    audience_languages = forms.MultipleChoiceField(
        required=False,
        label="Языки аудитории",
        choices=[(code, LANGUAGE_NAMES[code]) for code in LANGUAGES],
        widget=forms.CheckboxSelectMultiple,
        help_text="Ничего не отмечено — все языки, на которых заполнен текст.",
    )
    audience_platforms = forms.MultipleChoiceField(
        label="Платформы",
        choices=[(code, PLATFORM_NAMES[code]) for code in PLATFORMS],
        widget=forms.CheckboxSelectMultiple,
        help_text="Сбор средств в приложениях не показывается в любом случае.",
    )

    class Meta:
        model = Announcement
        fields = (
            "kind",
            "priority",
            "starts_at",
            "ends_at",
            "pinned",
            "needs_religious_review",
            "action_type",
            "action_reciter",
            "action_surah",
            "action_ayah",
            "action_slug",
            "action_url",
            "audience_languages",
            "audience_platforms",
            "app_version_min",
            "app_version_max",
            "audience_auth",
            "channel_bubble",
            "channel_home_card",
            "channel_modal",
            "channel_web_push",
            "bubble_frequency",
            "bubble_max_impressions",
            "bubble_icon",
            "review_note",
        )
        help_texts: ClassVar[dict[str, str]] = {
            "needs_religious_review": (
                "Тогда текст перед публикацией проверяет человек из группы «Проверяющий "
                "религиозные тексты». Владелец подтверждает проверку сам, когда публикует."
            ),
            "action_slug": (
                "Урок: slug из курса намаза, например wudu. Раздел: "
                + ", ".join(f"{code} ({screen.label})" for code, screen in SCREENS.items())
                + "."
            ),
        }

    _uploaded: Any = None

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        if not self.instance._state.adding:
            self.initial["audience_languages"] = list(self.instance.audience_languages or [])
            self.initial["audience_platforms"] = list(self.instance.audience_platforms or [])
        else:
            self.initial.setdefault("audience_platforms", list(PLATFORMS))

    def clean_action_reciter(self) -> Any:
        reciter = self.cleaned_data.get("action_reciter")
        return reciter.pk if reciter is not None else None

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        uploaded = cleaned.get("image_upload")
        if uploaded and cleaned.get("remove_image"):
            self.add_error("remove_image", "Либо загрузите новую картинку, либо уберите текущую.")
        elif uploaded and not self.errors:
            try:
                self._uploaded = upload_announcement_image(uploaded)
            except AnnouncementMediaError as exc:
                self.add_error("image_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Announcement image upload failed")
                self.add_error("image_upload", "Не удалось сохранить картинку. Повторите позже.")
        return cleaned

    def save(self, commit: bool = True) -> Announcement:
        instance = cast(Announcement, super().save(commit=False))
        # Published announcements render these as read-only; keep their values then.
        if "audience_languages" in self.fields:
            instance.audience_languages = list(self.cleaned_data.get("audience_languages") or [])
        if "audience_platforms" in self.fields:
            instance.audience_platforms = list(self.cleaned_data.get("audience_platforms") or [])
        if self._uploaded is not None:
            instance.image_object_key = self._uploaded.object_key
            instance.image_width = self._uploaded.width
            instance.image_height = self._uploaded.height
            instance.thumb_object_key = self._uploaded.thumb_object_key
        elif self.cleaned_data.get("remove_image"):
            instance.image_object_key = ""
            instance.image_width = None
            instance.image_height = None
            instance.thumb_object_key = ""
        if commit:
            instance.save()
            self.save_m2m()
        return instance


def _step_field_names(order: int) -> tuple[str, str]:
    return f"step_{order}_title", f"step_{order}_text"


class AnnouncementTranslationForm(forms.ModelForm):  # type: ignore[type-arg]
    class Meta:
        model = AnnouncementTranslation
        fields = ("language", "title", "summary", "body", "cta_label", "image_alt", "push_title")
        widgets: ClassVar[dict[str, Any]] = {
            "body": forms.Textarea(attrs={"rows": 4}),
            "summary": forms.Textarea(attrs={"rows": 2}),
        }
        help_texts: ClassVar[dict[str, str]] = {
            "summary": "Карточка на компьютере, текст для экранного диктора у пузыря и push.",
        }

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        steps = list(self.instance.steps or []) if not self.instance._state.adding else []
        for order in range(1, MAX_STEPS + 1):
            title_name, text_name = _step_field_names(order)
            step = steps[order - 1] if order <= len(steps) else {"title": "", "text": ""}
            self.fields[title_name] = forms.CharField(
                label=f"Шаг {order}: заголовок",
                max_length=50,
                required=False,
                initial=step["title"],
            )
            self.fields[text_name] = forms.CharField(
                label=f"Шаг {order}: текст",
                max_length=200,
                required=False,
                initial=step["text"],
                widget=forms.Textarea(attrs={"rows": 2}),
            )
        # Each language is its own tab; the language itself is fixed.
        self.fields["language"].disabled = True
        language = self.initial.get("language") or self.instance.language
        if language == "ar":
            for field in self.fields.values():
                if isinstance(field.widget, (forms.TextInput, forms.Textarea)):
                    field.widget.attrs.update({"dir": "rtl", "lang": "ar"})

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        steps = []
        gap = False
        for order in range(1, MAX_STEPS + 1):
            title_name, text_name = _step_field_names(order)
            title = (cleaned.get(title_name) or "").strip()
            text = (cleaned.get(text_name) or "").strip()
            if not title and not text:
                gap = True
                continue
            if gap:
                self.add_error(title_name, "Заполняйте шаги по порядку, без пропусков.")
            if not title:
                self.add_error(title_name, "У шага нужен заголовок.")
            steps.append({"title": title, "text": text})
        self.instance.steps = steps
        return cleaned


class AnnouncementTranslationFormSet(BaseInlineFormSet):  # type: ignore[type-arg]
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        instance = kwargs.get("instance")
        existing = (
            set(instance.translations.values_list("language", flat=True))
            if instance is not None and not instance._state.adding
            else set()
        )
        kwargs["initial"] = [{"language": code} for code in LANGUAGES if code not in existing]
        super().__init__(*args, **kwargs)


class AnnouncementTranslationInline(admin.StackedInline):  # type: ignore[type-arg]
    model = AnnouncementTranslation
    form = AnnouncementTranslationForm
    formset = AnnouncementTranslationFormSet
    max_num = len(LANGUAGES)
    can_delete = False
    verbose_name = "текст"
    verbose_name_plural = "Тексты на языках"
    classes = ("announcement-languages",)

    def get_queryset(self, request: HttpRequest) -> QuerySet[AnnouncementTranslation]:
        # Tabs follow the interface order (ru, en, ar, tr), not the alphabet.
        order = Case(
            *(When(language=code, then=Value(index)) for index, code in enumerate(LANGUAGES))
        )
        return cast(
            QuerySet[AnnouncementTranslation], super().get_queryset(request).order_by(order)
        )

    def get_extra(
        self,
        request: HttpRequest,  # noqa: ARG002 - Django's signature
        obj: Any = None,
        **kwargs: Any,  # noqa: ARG002
    ) -> int:
        if obj is None:
            return len(LANGUAGES)
        return len(LANGUAGES) - int(obj.translations.count())

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        if obj is not None and not obj.is_editable:
            return False
        return super().has_change_permission(request, obj)

    def has_add_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        if obj is not None and not obj.is_editable:
            return False
        return super().has_add_permission(request, obj)


class AnnouncementStepForm(forms.ModelForm):  # type: ignore[type-arg]
    image_upload = forms.FileField(
        required=False,
        label="Загрузить иллюстрацию",
        help_text=f"WebP или JPEG до {MAX_IMAGE_KIB} КБ.",
        widget=forms.ClearableFileInput(attrs={"accept": "image/webp,image/jpeg"}),
    )

    class Meta:
        model = AnnouncementStep
        fields = ("order",)

    _uploaded: Any = None

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        uploaded = cleaned.get("image_upload")
        if not uploaded and not self.instance.image_object_key:
            if cleaned.get("order"):
                self.add_error("image_upload", "Загрузите иллюстрацию шага.")
            return cleaned
        if uploaded and not self.errors:
            try:
                self._uploaded = upload_announcement_image(uploaded, with_thumbnail=False)
            except AnnouncementMediaError as exc:
                self.add_error("image_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Announcement step upload failed")
                self.add_error("image_upload", "Не удалось сохранить картинку. Повторите позже.")
        return cleaned

    def save(self, commit: bool = True) -> AnnouncementStep:
        instance = cast(AnnouncementStep, super().save(commit=False))
        if self._uploaded is not None:
            instance.image_object_key = self._uploaded.object_key
            instance.image_width = self._uploaded.width
            instance.image_height = self._uploaded.height
        if commit:
            instance.save()
        return instance


class AnnouncementStepInline(admin.TabularInline):  # type: ignore[type-arg]
    model = AnnouncementStep
    form = AnnouncementStepForm
    extra = 0
    max_num = MAX_STEPS
    verbose_name = "иллюстрация шага"
    verbose_name_plural = "Иллюстрации шагов (необязательно)"
    readonly_fields = ("picture",)
    fields = ("order", "image_upload", "picture")

    @admin.display(description="Сейчас")
    def picture(self, obj: AnnouncementStep) -> str:
        if not obj.image_object_key:
            return "—"
        return format_html(
            '<img src="{}" alt="" style="height:64px;border-radius:8px">',
            public_audio_url(obj.image_object_key),
        )

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        if obj is not None and not obj.is_editable:
            return False
        return super().has_change_permission(request, obj)

    def has_add_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        if obj is not None and not obj.is_editable:
            return False
        return super().has_add_permission(request, obj)

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        if obj is not None and not obj.is_editable:
            return False
        return super().has_delete_permission(request, obj)


OPERATIONS: dict[str, tuple[Callable[[Announcement, User], object], str]] = {
    "_publish": (publish, "Опубликовано. На сайте и в приложении появится в течение минуты."),
    "_submit_review": (
        lambda announcement, _user: submit_for_review(announcement),
        "Отправлено владельцу на публикацию.",
    ),
    "_religious_review": (
        sign_religious_review,
        "Отмечено: религиозный текст проверен.",
    ),
    "_reshow": (
        reshow,
        "Объявление снова на главной у всех, кто его закрыл или прочитал. На сайте — в "
        "течение минуты.",
    ),
    "_republish": (
        republish,
        "Опубликовано снова. Всем, кто его закрывал, оно снова покажется на главной; на сайте "
        "и в приложении — в течение минуты.",
    ),
    "_withdraw": (withdraw, "Снято с публикации."),
    "_archive": (archive, "Перенесено в архив."),
}


def _publish_panel(user: User, announcement: Announcement | None) -> dict[str, Any]:
    """What the announcement is now, what is still missing and which buttons apply."""
    can_publish = user.has_perm(PUBLISH_PERMISSION)
    if announcement is None:
        return {
            "state": "Новое объявление",
            "tone": "draft",
            "hint": (
                "Заполните тексты и нажмите «Сохранить и опубликовать». "
                "«Сохранить» оставит его черновиком — на сайте его не будет видно."
            ),
            "missing": [],
            "notes": [],
            "publish_label": "Сохранить и опубликовать",
            "show_publish": can_publish,
        }
    status = announcement.status
    editable = announcement.is_editable
    original = announcement.edit_of
    sensitive = is_sensitive(announcement) or (original is not None and is_sensitive(original))
    can_publish_this = can_publish and (not sensitive or user.has_perm(SENSITIVE_PERMISSION))
    checks_religion = user.has_perm(RELIGIOUS_PERMISSION)
    report = (
        readiness(
            announcement,
            publisher_checks_religion=checks_religion and can_publish_this,
        )
        if editable or status == AnnouncementStatus.WITHDRAWN
        else None
    )
    now = timezone.now()
    if status == AnnouncementStatus.PUBLISHED and announcement.starts_at > now:
        state, tone = "Запланировано", "scheduled"
        hint = f"Появится {timezone.localtime(announcement.starts_at):%d.%m.%Y в %H:%M}."
    elif status == AnnouncementStatus.PUBLISHED:
        state, tone = "Опубликовано", "published"
        hint = (
            f"На главной сайта и приложения до "
            f"{timezone.localtime(announcement.display_until):%d.%m.%Y}, в ленте — дальше."
        )
    elif original is not None:
        state = (
            "Правка ждёт публикации"
            if status == AnnouncementStatus.IN_REVIEW
            else "Правка опубликованного"
        )
        tone = "draft"
        hint = (
            "На сайте и в приложении пока прежняя версия. «Сохранить и опубликовать снова» "
            "заменит её сразу везде."
        )
    else:
        state, tone, hint = PANEL_STATES[AnnouncementStatus(status)]
    if editable and report is not None and not report.problems and can_publish_this:
        hint = f"Всё готово: нажмите «{_publish_label(announcement)}»."
    pending_edit = (
        Announcement.objects.filter(edit_of=announcement).first()
        if status == AnnouncementStatus.PUBLISHED
        else None
    )
    return {
        "state": state,
        "tone": tone,
        "hint": hint,
        "missing": report.problems if report else [],
        "notes": report.notes if report else [],
        "revised": _revised_note(announcement),
        "publish_label": _publish_label(announcement),
        "original_url": _change_url(original) if original is not None else None,
        "show_start_edit": status == AnnouncementStatus.PUBLISHED
        and user.has_perm(CHANGE_PERMISSION),
        "start_edit_label": "Открыть начатую правку" if pending_edit else "Изменить",
        "show_cancel_edit": original is not None and editable,
        "owner_only": editable and can_publish and not can_publish_this,
        "show_publish": editable and can_publish_this,
        "show_submit_review": status == AnnouncementStatus.DRAFT and not can_publish_this,
        "show_religious_review": bool(
            editable
            and not can_publish_this
            and checks_religion
            and announcement.needs_religious_review
            and announcement.religious_reviewed_at is None
        ),
        "show_reshow": can_publish_this
        and status == AnnouncementStatus.PUBLISHED
        and (announcement.channel_bubble or announcement.channel_home_card)
        and announcement.starts_at <= now < announcement.display_until,
        "show_reshow_on_publish": original is not None and editable and can_publish_this,
        "waves": announcement.wave if status == AnnouncementStatus.PUBLISHED else 0,
        "show_republish": can_publish_this and status == AnnouncementStatus.WITHDRAWN,
        "show_withdraw": can_publish and status == AnnouncementStatus.PUBLISHED,
        "show_archive": can_publish
        and status in {AnnouncementStatus.PUBLISHED, AnnouncementStatus.WITHDRAWN},
        "show_duplicate": original is None,
    }


def _publish_label(announcement: Announcement) -> str:
    return "Сохранить и опубликовать снова" if announcement.is_edit else "Сохранить и опубликовать"


def _revised_note(announcement: Announcement) -> str:
    if announcement.revised_at is None:
        return ""
    return (
        f"Изменено после публикации {timezone.localtime(announcement.revised_at):%d.%m.%Y в %H:%M}"
        f" (редакция {announcement.revision})."
    )


PANEL_STATES = {
    AnnouncementStatus.DRAFT: (
        "Черновик",
        "draft",
        "На сайте и в приложении не видно, пока вы не опубликуете.",
    ),
    AnnouncementStatus.IN_REVIEW: (
        "Ждёт публикации",
        "draft",
        "Редактор подготовил объявление; опубликовать его может владелец.",
    ),
    AnnouncementStatus.WITHDRAWN: (
        "Снято",
        "off",
        "Не показывается ни в ленте, ни на главной. «Опубликовать снова» вернёт его всем, "
        "в том числе тем, кто его закрыл. Можно и перенести в архив или сделать копию.",
    ),
    AnnouncementStatus.ARCHIVED: ("В архиве", "off", "Убрано и из ленты «Что нового»."),
}


WAVE_EVENTS = ("impression", "open", "click", "dismiss")
NO_RIGHT = (
    "нет права. Сбор средств, окно с шагами, push и обязательное обновление публикует, "
    "снимает с главной и показывает снова только владелец."
)


def _change_url(announcement: Announcement) -> str:
    return reverse("admin:announcements_announcement_change", args=(announcement.pk,))


def _image_url(announcement: Announcement) -> str | None:
    if announcement.thumb_object_key:
        return public_audio_url(announcement.thumb_object_key)
    if announcement.image_object_key:
        return public_audio_url(announcement.image_object_key)
    reciter = announcement.reciter
    if announcement.action_type == ActionType.RECITER and reciter and reciter.portrait_object_key:
        return public_audio_url(reciter.portrait_object_key)
    return None


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = AnnouncementAdminForm
    change_form_template = "admin/announcements/announcement/change_form.html"
    inlines = (AnnouncementTranslationInline, AnnouncementStepInline)
    list_display = (
        "title_ru",
        "kind",
        "status_badge",
        "period",
        "languages",
        "channels",
        "impressions",
        "clicks",
        "ctr",
        "dismisses",
    )
    list_filter = ("status", "kind", "source")
    search_fields = ("translations__title",)
    date_hierarchy = "starts_at"
    actions = (
        "publish_selected",
        "republish_selected",
        "reshow_selected",
        "extend_selected",
        "withdraw_selected",
        "archive_selected",
        "duplicate_selected",
    )
    readonly_fields = (
        "status",
        "source",
        "preview",
        "current_image",
        "stats_summary",
        "waves_history",
        "religious_reviewed_by",
        "religious_reviewed_at",
        "created_by",
        "reviewed_by",
        "reviewed_at",
        "published_at",
        "withdrawn_at",
        "edit_of",
        "revision",
        "revised_at",
        "revised_by",
        "created_at",
        "updated_at",
    )
    fieldsets = (
        ("Как увидят", {"fields": ("preview",)}),
        (
            "Основное",
            {
                "fields": (
                    "kind",
                    "priority",
                    ("starts_at", "ends_at"),
                    "pinned",
                    "needs_religious_review",
                ),
            },
        ),
        (
            "Картинка и кнопка",
            {
                "fields": (
                    "current_image",
                    "image_upload",
                    "remove_image",
                    "action_type",
                    "action_reciter",
                    ("action_surah", "action_ayah"),
                    "action_slug",
                    "action_url",
                ),
            },
        ),
        (
            "Аудитория",
            {
                "fields": (
                    "audience_languages",
                    "audience_platforms",
                    ("app_version_min", "app_version_max"),
                    "audience_auth",
                ),
            },
        ),
        (
            "Каналы и частота",
            {
                "fields": (
                    "channel_bubble",
                    ("bubble_frequency", "bubble_max_impressions"),
                    "bubble_icon",
                    "channel_home_card",
                    "channel_modal",
                    "channel_web_push",
                ),
                "description": (
                    "Лента «Что нового» — всегда. Пузырь на телефоне (сайт и приложение) "
                    "лопается по нажатию и раскрывает окно; один пузырь одновременно. "
                    "Окно с шагами и push публикует только владелец."
                ),
            },
        ),
        (
            "Кто и когда",
            {
                "fields": (
                    "review_note",
                    "created_by",
                    "reviewed_by",
                    "published_at",
                    "religious_reviewed_by",
                    "religious_reviewed_at",
                    "withdrawn_at",
                    ("revised_at", "revised_by", "revision"),
                    "edit_of",
                ),
            },
        ),
        ("История показов", {"fields": ("waves_history",)}),
        ("Счётчики", {"fields": ("stats_summary",)}),
        (
            "Служебные данные",
            {"fields": ("source", "created_at", "updated_at"), "classes": ("collapse",)},
        ),
    )

    def get_queryset(self, request: HttpRequest) -> QuerySet[Announcement]:
        def total(event: str) -> Sum:
            return Sum("daily_stats__count", filter=Q(daily_stats__event=event))

        return cast(
            QuerySet[Announcement],
            super()
            .get_queryset(request)
            .prefetch_related("translations")
            .annotate(
                impression_total=total("impression"),
                click_total=total("click"),
                dismiss_total=total("dismiss"),
            ),
        )

    def get_readonly_fields(self, _request: HttpRequest, obj: Any = None) -> tuple[str, ...]:
        if obj is not None and not obj.is_editable:
            editable = [name for name in self.form.Meta.fields if name != "review_note"]
            return (*self.readonly_fields, *editable)
        return self.readonly_fields

    def get_fieldsets(self, request: HttpRequest, obj: Any = None) -> Any:
        fieldsets = super().get_fieldsets(request, obj)
        if obj is not None and not obj.is_editable:
            hidden = {"image_upload", "remove_image"}
            return [
                (
                    title,
                    {
                        **options,
                        "fields": [
                            field
                            for field in options["fields"]
                            if not (isinstance(field, str) and field in hidden)
                        ],
                    },
                )
                for title, options in fieldsets
            ]
        return fieldsets

    def save_model(self, request: HttpRequest, obj: Announcement, form: Any, change: bool) -> None:
        if not change:
            obj.created_by = cast(User, request.user)
        super().save_model(request, obj, form, change)

    # List columns

    @admin.display(description="Заголовок")
    def title_ru(self, obj: Announcement) -> str:
        return f"Правка: {obj}" if obj.is_edit else str(obj)

    @admin.display(description="Статус", ordering="status")
    def status_badge(self, obj: Announcement) -> str:
        colors = {
            AnnouncementStatus.DRAFT: ("#fff3c4", "#6b4b00"),
            AnnouncementStatus.IN_REVIEW: ("#e1eef5", "#205067"),
            AnnouncementStatus.PUBLISHED: ("#e3f3e5", "#1b5e20"),
        }
        background, color = colors.get(AnnouncementStatus(obj.status), ("#eeeeee", "#555555"))
        label = "Правка" if obj.is_edit and obj.is_editable else obj.get_status_display()
        extra = " · авто" if obj.source == "auto" else ""
        if obj.revised_at is not None:
            extra += f" · изменено {timezone.localtime(obj.revised_at):%d.%m}"
        return format_html(
            '<span style="padding:2px 7px;border-radius:4px;background:{};color:{};'
            'font-weight:700;font-size:11px;text-transform:uppercase">{}{}</span>',
            background,
            color,
            label,
            extra,
        )

    @admin.display(description="Период", ordering="starts_at")
    def period(self, obj: Announcement) -> str:
        return f"{obj.starts_at:%d.%m}–{obj.display_until:%d.%m}"

    @admin.display(description="Языки")
    def languages(self, obj: Announcement) -> str:
        filled = {item.language for item in obj.translations.all() if item.is_filled}
        return format_html_join(
            " ",
            '<span style="{}">{}</span>',
            (
                (
                    "" if code in filled else "color:#8a5a00;font-weight:700",
                    code + ("" if code in filled else "!"),
                )
                for code in LANGUAGES
            ),
        )

    @admin.display(description="Каналы")
    def channels(self, obj: Announcement) -> str:
        names = [
            name
            for enabled, name in (
                (obj.channel_bubble, "пузырь"),
                (obj.channel_home_card, "карточка"),
                (obj.channel_modal, "окно"),
                (obj.channel_web_push, "push"),
            )
            if enabled
        ]
        return ", ".join([*names, "лента"])

    @admin.display(description="Показы")
    def impressions(self, obj: Any) -> int:
        return int(obj.impression_total or 0)

    @admin.display(description="Клики")
    def clicks(self, obj: Any) -> int:
        return int(obj.click_total or 0)

    @admin.display(description="CTR")
    def ctr(self, obj: Any) -> str:
        shown = int(obj.impression_total or 0)
        if not shown:
            return "—"
        return f"{100 * int(obj.click_total or 0) / shown:.1f} %".replace(".", ",")

    @admin.display(description="Закрытия")
    def dismisses(self, obj: Any) -> int:
        return int(obj.dismiss_total or 0)

    # Read-only panels

    @admin.display(description="Картинка сейчас")
    def current_image(self, obj: Announcement) -> str:
        url = _image_url(obj)
        if url is None:
            return "Нет. Пузырь покажет иконку."
        source = "своя" if obj.image_object_key else "портрет чтеца"
        return format_html(
            '<img src="{}" alt="" style="width:64px;height:64px;object-fit:cover;'
            'border-radius:50%;vertical-align:middle"> <span style="color:#666">{}</span>',
            url,
            source,
        )

    @admin.display(description="Как увидят — окно из пузыря")
    def preview(self, obj: Announcement) -> str:
        if obj._state.adding:
            return "Появится после сохранения черновика."
        translations = {item.language: item for item in obj.translations.all() if item.is_filled}
        if not translations:
            return "Заполните заголовок и «Кратко» хотя бы на одном языке."
        image = _image_url(obj) if uses_image(obj) or obj.image_object_key else None
        cards = []
        for code in LANGUAGES:
            translation = translations.get(code)
            if translation is None:
                continue
            direction = "rtl" if code == "ar" else "ltr"
            picture = (
                format_html(
                    '<img src="{}" alt="" style="width:76px;height:76px;object-fit:cover;'
                    'border-radius:50%;box-shadow:0 0 0 4px #d9eee7">',
                    image,
                )
                if image
                else ""
            )
            steps = format_html_join(
                "",
                "<li><b>{}</b> {}</li>",
                ((step["title"], step["text"]) for step in translation.steps or []),
            )
            button = (
                format_html(
                    '<div style="margin-top:10px;padding:10px;border-radius:14px;'
                    'background:#0b5d4a;color:#fff;font-weight:700;text-align:center">{}</div>',
                    translation.cta_label,
                )
                if obj.action_type != ActionType.NONE
                else ""
            )
            cards.append(
                format_html(
                    '<div dir="{}" lang="{}" style="width:300px;padding:16px;border-radius:24px;'
                    "background:#fffdf8;border:1px solid #dcd8ce;color:#17201d;"
                    'font:14px/1.5 system-ui,sans-serif">'
                    '<div style="font-size:12px;color:#4b5b53;margin-bottom:8px">{}</div>'
                    '<div style="text-align:center">{}'
                    '<div style="font-size:11px;font-weight:800;color:#0b5d4a;'
                    'margin-top:8px">{}</div>'
                    '<div style="font-size:19px;font-weight:700">{}</div>'
                    '<div style="color:#4b5b53">{}</div></div>'
                    '<ol style="margin:8px 0 0;padding-inline-start:20px">{}</ol>{}</div>',
                    direction,
                    code,
                    LANGUAGE_NAMES[code],
                    picture,
                    KIND_EYEBROWS[obj.kind][code],
                    translation.title,
                    translation.summary,
                    steps,
                    button,
                )
            )
        return format_html(
            '<div style="display:flex;flex-wrap:wrap;gap:16px;padding:16px;'
            'background:#f7f4ec;border-radius:8px">{}</div>',
            format_html_join("", "{}", ((card,) for card in cards)),
        )

    @admin.display(description="Показы, клики и закрытия по платформам")
    def stats_summary(self, obj: Announcement) -> str:
        if obj._state.adding:
            return "—"
        rows = (
            obj.daily_stats.values("platform", "event")
            .annotate(total=Sum("count"))
            .order_by("platform", "event")
        )
        if not rows:
            return "Пока ничего. Хранятся только суммы по дням, без людей и устройств."
        return format_html_join(
            "",
            "<div>{}: {} — {}</div>",
            (
                (PLATFORM_NAMES.get(row["platform"], row["platform"]), row["event"], row["total"])
                for row in rows
            ),
        )

    @admin.display(description="Сколько раз выводили на главную")
    def waves_history(self, obj: Announcement) -> str:
        if obj._state.adding:
            return "—"
        waves = list(obj.waves.select_related("started_by"))
        if not waves:
            return "Ещё не публиковалось."
        totals: dict[tuple[int, str], int] = {
            (row["wave"], row["event"]): row["total"]
            for row in obj.daily_stats.values("wave", "event").annotate(total=Sum("count"))
        }
        shown = sum(count for (_, event), count in totals.items() if event == "impression")
        rows = format_html_join(
            "",
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td>"
            "<td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
            (
                (
                    wave.number,
                    f"{timezone.localtime(wave.created_at):%d.%m.%Y %H:%M}",
                    wave.started_by or "—",
                    wave.get_reason_display(),
                    wave.revision,
                    *(totals.get((wave.number, event), 0) for event in WAVE_EVENTS),
                )
                for wave in waves
            ),
        )
        return format_html(
            "<p><b>На главную выводилось: {} раз(а). Всего показов: {}.</b> "
            "Только суммы по дням, без людей, устройств и адресов.</p>"
            "<table><thead><tr><th>Волна</th><th>Когда</th><th>Кто</th><th>Повод</th>"
            "<th>Редакция</th><th>Показы</th><th>Открытия</th><th>Нажатия</th>"
            "<th>Закрытия</th></tr></thead><tbody>{}</tbody></table>",
            len(waves),
            shown,
            rows,
        )

    # The «Публикация» panel on top of the form

    def render_change_form(  # noqa: PLR0913, PLR0917 - Django's signature
        self,
        request: HttpRequest,
        context: dict[str, Any],
        add: bool = False,
        change: bool = False,
        form_url: str = "",
        obj: Announcement | None = None,
    ) -> HttpResponse:
        context.update(
            {
                "publish_panel": _publish_panel(cast(User, request.user), obj),
                "language_names": LANGUAGE_NAMES,
            }
        )
        return super().render_change_form(request, context, add, change, form_url, obj)

    def response_add(
        self,
        request: HttpRequest,
        obj: Announcement,
        post_url_continue: str | None = None,
    ) -> HttpResponse:
        if "_publish" in request.POST:
            self._run(request, obj, "_publish")
            return HttpResponseRedirect(
                reverse("admin:announcements_announcement_change", args=(obj.pk,))
            )
        return super().response_add(request, obj, post_url_continue)

    def response_change(self, request: HttpRequest, obj: Announcement) -> HttpResponse:
        edit_response = self._respond_to_edit(request, obj)
        if edit_response is not None:
            return edit_response
        if "_duplicate" in request.POST:
            copy = duplicate(obj, cast(User, request.user))
            self.message_user(request, "Создан новый черновик-копия.", messages.SUCCESS)
            return HttpResponseRedirect(
                reverse("admin:announcements_announcement_change", args=(copy.pk,))
            )
        for name in OPERATIONS:
            if name in request.POST:
                self._run(request, obj, name)
                return HttpResponseRedirect(request.path)
        return super().response_change(request, obj)

    def _respond_to_edit(self, request: HttpRequest, obj: Announcement) -> HttpResponse | None:
        """«Изменить», «Отменить правку» and publishing an edit, which leaves its own page."""
        user = cast(User, request.user)
        if "_publish" in request.POST and obj.edit_of_id is not None:
            original_id = obj.edit_of_id
            self._run(request, obj, "_publish", reshow="_reshow_on_publish" in request.POST)
            published = not Announcement.objects.filter(pk=obj.pk).exists()
            return HttpResponseRedirect(
                reverse("admin:announcements_announcement_change", args=(original_id,))
                if published
                else request.path
            )
        if "_start_edit" in request.POST:
            operation: Callable[[Announcement, User], Announcement] = start_edit
            success = (
                "Это правка. Пока вы её не опубликуете, на сайте и в приложении прежняя версия."
            )
        elif "_cancel_edit" in request.POST:
            operation = cancel_edit
            success = "Правка отменена, на сайте всё как было."
        else:
            return None
        try:
            target = operation(obj, user)
        except PermissionDenied:
            self.message_user(request, "Нет права изменять объявления.", messages.ERROR)
            return HttpResponseRedirect(request.path)
        except AnnouncementNotReadyError as error:
            for problem in error.problems:
                self.message_user(request, problem, messages.ERROR)
            return HttpResponseRedirect(request.path)
        self.message_user(request, success, messages.INFO)
        return HttpResponseRedirect(_change_url(target))

    def _run(
        self,
        request: HttpRequest,
        obj: Announcement,
        name: str,
        *,
        reshow: bool = False,
    ) -> None:
        operation, success = OPERATIONS[name]
        if name == "_publish" and obj.is_edit:
            success = "Изменения опубликованы. На сайте и в приложении обновятся в течение минуты."
            if reshow:
                success += " Тем, кто его закрыл, оно снова покажется на главной."
        try:
            if name == "_publish":
                publish(obj, cast(User, request.user), reshow=reshow)
            else:
                operation(obj, cast(User, request.user))
        except PermissionDenied:
            self.message_user(
                request,
                "Нет права на это действие. Сбор средств, окно с шагами, push и обязательное "
                "обновление публикует только владелец.",
                messages.ERROR,
            )
        except AnnouncementNotReadyError as error:
            self.message_user(
                request,
                {
                    "_reshow": "Снова не показано:",
                    "_republish": "Не опубликовано снова. Что осталось:",
                }.get(name, "Объявление сохранено, но не опубликовано. Что осталось:"),
                messages.WARNING,
            )
            for problem in error.problems:
                self.message_user(request, problem, messages.ERROR)
        else:
            self.log_change(request, obj, success)
            self.message_user(request, success, messages.SUCCESS)

    # Actions on the list: every selected announcement gets its own message.

    def _bulk(
        self,
        request: HttpRequest,
        queryset: QuerySet[Announcement],
        operation: Callable[[Announcement, User], object],
        done: Callable[[Announcement, Any], str],
    ) -> None:
        user = cast(User, request.user)
        for announcement in queryset:
            try:
                result = operation(announcement, user)
            except PermissionDenied:
                self.message_user(request, f"{announcement}: {NO_RIGHT}", messages.ERROR)
            except AnnouncementNotReadyError as error:
                self.message_user(
                    request,
                    f"{announcement}: не сделано — {' '.join(error.problems)}",
                    messages.WARNING,
                )
            else:
                self.log_change(request, announcement, done(announcement, result))
                self.message_user(request, done(announcement, result), messages.SUCCESS)

    @admin.action(description="Опубликовать")
    def publish_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(request, queryset, publish, lambda item, _: f"{item}: опубликовано.")

    @admin.action(description="Опубликовать снова (снятые)")
    def republish_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(
            request,
            queryset,
            republish,
            lambda item, _: f"{item}: опубликовано снова, вернётся на главную и тем, кто закрыл.",
        )

    @admin.action(description="Показать снова на главной")
    def reshow_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(
            request,
            queryset,
            reshow,
            lambda item, result: f"{item}: снова на главной, волна {result.wave}.",
        )

    @admin.action(description=f"Продлить показ на главной на {EXTEND_DAYS} дней")
    def extend_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(
            request,
            queryset,
            extend_display,
            lambda item, result: (
                f"{item}: на главной до {timezone.localtime(result.ends_at):%d.%m.%Y}."
            ),
        )

    @admin.action(description="Снять с публикации")
    def withdraw_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(
            request,
            queryset,
            withdraw,
            lambda item, _: f"{item}: снято. Вернуть можно «Опубликовать снова».",
        )

    @admin.action(description="Перенести в архив…")
    def archive_selected(
        self, request: HttpRequest, queryset: QuerySet[Announcement]
    ) -> TemplateResponse | None:
        # Archived announcements leave the feed and cannot come back: ask first.
        if "confirmed" not in request.POST:
            return TemplateResponse(
                request,
                "admin/announcements/announcement/archive_confirmation.html",
                {
                    **self.admin_site.each_context(request),
                    "title": "Перенести в архив?",
                    "opts": self.model._meta,
                    "announcements": list(queryset),
                    "action": "archive_selected",
                    "action_checkbox_name": ACTION_CHECKBOX_NAME,
                },
            )
        self._bulk(
            request,
            queryset,
            archive,
            lambda item, _: f"{item}: в архиве, убрано и из ленты.",
        )
        return None

    @admin.action(description="Сделать копию (черновик)")
    def duplicate_selected(self, request: HttpRequest, queryset: QuerySet[Announcement]) -> None:
        self._bulk(request, queryset, duplicate, lambda item, _: f"{item}: создан черновик-копия.")


@admin.register(AnnouncementSettings)
class AnnouncementSettingsAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("__str__", "updated_at")
    fields = ("is_enabled",)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return not AnnouncementSettings.objects.exists() and super().has_add_permission(request)

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def save_model(
        self,
        request: HttpRequest,
        obj: AnnouncementSettings,
        form: Any,
        change: bool,
    ) -> None:
        super().save_model(request, obj, form, change)
        enqueue_announcements_change(action="enabled" if obj.is_enabled else "disabled")
