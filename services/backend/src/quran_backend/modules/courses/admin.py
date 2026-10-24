# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Admin of thematic courses (docs/courses/plan.md, sections 2 and 6.4).

The owner edits the course and its lessons freely; «Подготовить выпуск» freezes
them as a release that is signed, published, hidden or rolled back from the
status panel. Every action checks the right on the server as well: buttons are
only a hint.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Sequence
from typing import Any, ClassVar, cast

from django import forms
from django.conf import settings
from django.contrib import admin, messages
from django.contrib.admin.utils import unquote
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.db.models import QuerySet
from django.forms.models import BaseInlineFormSet
from django.http import (
    Http404,
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    HttpResponseRedirect,
)
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils.html import format_html

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.editorial.diff import line_diff
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.courses.document import (
    LANGUAGE_NAMES,
    build_document,
    build_snapshot,
    changes,
    checksum,
    editor_languages,
    readiness,
)
from quran_backend.modules.courses.media import CourseCoverError, upload_course_cover
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    Course,
    CourseDocument,
    CourseLesson,
    CourseRelease,
    CourseReleaseStatus,
)
from quran_backend.modules.courses.services import (
    CourseReleaseError,
    can_publish,
    can_sign,
    hide_course,
    prepare_release,
    publish_release,
    return_for_rework,
    roll_back,
    show_course,
    sign_release,
    withdraw_from_review,
)

logger = logging.getLogger(__name__)

TAB_LABELS = {"ru": "RU", "en": "EN", "ar": "العربية", "tr": "TR"}
NOTES_HELP = (
    "Пустая строка — новый абзац. «## » в начале строки — подзаголовок. «- » — пункт списка, "
    "«1. » — нумерованный пункт. «> » — цитата (аят, хадис, дуа); последняя строка цитаты "
    "«> — Источник». «! » — рамка «Важно». **слово** — жирный. Арабский текст можно вставлять "
    "прямо в абзац: он сам выровняется справа налево."
)
RELEASE_FIELDS = frozenset({"live_release", "hidden_at", "hidden_reason", "created_by"})
DIFF_FIELDS = (
    ("title", "Название"),
    ("summary", "Кратко"),
    ("notes", "Конспект"),
    ("sources", "Источники"),
)
CONFLICT = (
    "Ничего не сохранено: {what} изменили в другой вкладке. Ваш текст остался на экране — "
    "скопируйте его, откройте страницу заново и вставьте."
)


def released_lesson_ids(course_id: Any) -> set[str]:
    """Lessons that went into any release: their address is fixed from then on."""
    return {
        lesson["id"]
        for snapshot in CourseRelease.objects.filter(course_id=course_id).values_list(
            "snapshot", flat=True
        )
        for lesson in snapshot.get("lessons", [])
    }


class RevisionForm(forms.ModelForm):  # type: ignore[type-arg]
    """Refuses a save made from a page opened before someone else saved the same row."""

    conflict_subject = "запись"

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        if "revision" in self.fields:
            self.fields["revision"].widget = forms.HiddenInput()
        for name, field in self.fields.items():
            if name.endswith("_ar"):
                field.widget.attrs.update({"dir": "rtl", "lang": "ar"})

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        if self.instance.pk is not None and self.has_changed() and "revision" in self.fields:
            current = (
                type(self.instance)
                .objects.select_for_update()
                .filter(pk=self.instance.pk)
                .values_list("revision", flat=True)
                .first()
            )
            if current is not None and current != cleaned.get("revision"):
                raise forms.ValidationError(CONFLICT.format(what=self.conflict_subject))
        return cleaned

    def save(self, commit: bool = True) -> Any:
        instance = super().save(commit=False)
        if instance.pk is not None and self.has_changed():
            instance.revision = int(self.cleaned_data.get("revision") or instance.revision) + 1
        if commit:
            instance.save()
            self.save_m2m()
        return instance


class CourseAdminForm(RevisionForm):
    conflict_subject = "курс"
    cover_upload = forms.FileField(
        required=False,
        label="Загрузить обложку",
        help_text="JPEG, PNG или WebP. Админка сама обрежет её до 16:9 по центру.",
        widget=forms.ClearableFileInput(attrs={"accept": "image/jpeg,image/png,image/webp"}),
    )
    remove_cover = forms.BooleanField(required=False, label="Убрать обложку")

    class Meta:
        model = Course
        fields = (
            "slug",
            "position",
            *(
                f"{field}_{language}"
                for language in editor_languages()
                for field in ("title", "summary", "source")
            ),
            "revision",
        )
        widgets: ClassVar[dict[str, Any]] = {
            f"summary_{language}": forms.Textarea(attrs={"rows": 3})
            for language in COURSE_LANGUAGES
        }

    _cover: Any = None

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean()
        uploaded = cleaned.get("cover_upload")
        if uploaded and cleaned.get("remove_cover"):
            self.add_error("remove_cover", "Либо загрузите новую обложку, либо уберите текущую.")
        elif uploaded and not self.errors:
            try:
                self._cover = upload_course_cover(uploaded)
            except CourseCoverError as exc:
                self.add_error("cover_upload", str(exc))
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Course cover upload failed")
                self.add_error("cover_upload", "Не удалось сохранить обложку. Повторите позже.")
        return cleaned

    def save(self, commit: bool = True) -> Course:
        course = cast(Course, super().save(commit=False))
        if self._cover is not None:
            course.cover_object_key = self._cover.object_key
            course.cover_thumb_object_key = self._cover.thumb_object_key
            course.cover_width = self._cover.width
            course.cover_height = self._cover.height
        elif self.cleaned_data.get("remove_cover"):
            course.cover_object_key = ""
            course.cover_thumb_object_key = ""
            course.cover_width = None
            course.cover_height = None
        if commit:
            course.save()
        return course


class CourseLessonForm(RevisionForm):
    conflict_subject = "тему"

    def __init__(self, *args: Any, released: set[str] | None = None, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        if released is None and self.instance.pk is not None:
            released = released_lesson_ids(self.instance.course_id)
        if "slug" in self.fields and str(self.instance.pk) in (released or set()):
            self.fields["slug"].disabled = True
            self.fields["slug"].help_text = "Тема уже была в выпуске: адрес не меняется."
        for language in COURSE_LANGUAGES:
            if f"notes_{language}" in self.fields:
                self.fields[f"notes_{language}"].help_text = NOTES_HELP
            if f"sources_{language}" in self.fields:
                self.fields[f"sources_{language}"].help_text = "По одному источнику на строку."


class CourseLessonFormSet(BaseInlineFormSet):  # type: ignore[type-arg]
    """Reads the releases once for every row of the table."""

    def get_form_kwargs(self, index: int | None) -> dict[str, Any]:
        if not hasattr(self, "_released"):
            self._released = (
                released_lesson_ids(self.instance.pk) if self.instance.pk is not None else set()
            )
        return {**super().get_form_kwargs(index), "released": self._released}


class CourseLessonInline(admin.TabularInline):  # type: ignore[type-arg]
    model = CourseLesson
    form = CourseLessonForm
    formset = CourseLessonFormSet
    fields = ("position", "title_ru", "slug", "minutes", "ready", "revision")
    readonly_fields = ("ready",)
    prepopulated_fields: ClassVar[dict[str, Sequence[str]]] = {"slug": ("title_ru",)}
    ordering = ("position", "created_at")
    show_change_link = True
    extra = 0
    verbose_name = "тема"
    verbose_name_plural = "Темы"

    @admin.display(description="Конспект готов")
    def ready(self, obj: CourseLesson) -> str:
        if obj._state.adding:
            return "—"
        return " · ".join(
            TAB_LABELS[language]
            + (" ✓" if obj.text("title", language) and obj.text("notes", language) else " —")
            for language in editor_languages()
        )


@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = CourseAdminForm
    inlines = (CourseLessonInline,)
    list_display = ("__str__", "slug", "position", "site_state")
    list_display_links = ("__str__",)
    search_fields = ("slug", "title_ru")
    prepopulated_fields: ClassVar[dict[str, Sequence[str]]] = {"slug": ("title_ru",)}
    readonly_fields = ("current_cover",)
    change_form_template = "admin/courses/course/change_form.html"

    def get_fieldsets(self, _request: HttpRequest, _obj: Course | None = None) -> Any:
        language_sets = [
            (
                f"Тексты: {LANGUAGE_NAMES[language]}",
                {
                    "fields": tuple(
                        f"{field}_{language}" for field in ("title", "summary", "source")
                    ),
                    "classes": () if language == "ru" else ("collapse",),
                },
            )
            for language in editor_languages()
        ]
        return [
            (None, {"fields": ("slug", "position", "revision")}),
            *language_sets,
            ("Обложка 16:9", {"fields": ("current_cover", "cover_upload", "remove_cover")}),
        ]

    def get_readonly_fields(self, request: HttpRequest, obj: Course | None = None) -> Any:
        fields = list(super().get_readonly_fields(request, obj))
        if obj is not None and obj.releases.exists():
            fields.append("slug")
        return fields

    def get_prepopulated_fields(
        self, request: HttpRequest, obj: Course | None = None
    ) -> dict[str, Sequence[str]]:
        if obj is not None and obj.releases.exists():
            return {}
        return super().get_prepopulated_fields(request, obj)

    def has_delete_permission(self, request: HttpRequest, obj: Course | None = None) -> bool:
        if obj is not None and obj.releases.exists():
            return False
        return super().has_delete_permission(request, obj)

    def save_model(self, request: HttpRequest, obj: Course, _form: Any, change: bool) -> None:
        if not change:
            obj.created_by = cast(Any, request.user)
            obj.save()
            return
        # The release actions own these fields; a form opened earlier must not reset them.
        obj.save(
            update_fields=[
                field.name
                for field in Course._meta.concrete_fields
                if not field.primary_key and field.name not in RELEASE_FIELDS
            ]
        )

    def save_formset(self, request: HttpRequest, form: Any, formset: Any, change: bool) -> None:
        for lesson_form in formset.forms:
            if lesson_form.has_changed():
                lesson_form.instance.updated_by = request.user
        super().save_formset(request, form, formset, change)

    @admin.display(description="На сайте")
    def site_state(self, obj: Course) -> str:
        if obj.live_release_id is None:
            return "нет"
        live = cast(CourseRelease, obj.live_release)
        if obj.hidden_at is not None:
            return f"скрыт (выпуск {live.number})"
        return f"выпуск {live.number}"

    @admin.display(description="Обложка")
    def current_cover(self, obj: Course) -> str:
        if not obj.cover_thumb_object_key:
            return "—"
        return format_html(
            '<img src="{}" alt="" width="320" height="180" style="border-radius:6px">',
            public_audio_url(obj.cover_thumb_object_key),
        )

    def get_queryset(self, request: HttpRequest) -> QuerySet[Course]:
        return super().get_queryset(request).select_related("live_release")

    # Status panel -------------------------------------------------------

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        course = self.get_object(request, unquote(object_id))
        context = dict(extra_context or {})
        if course is not None:
            context["course_panel"] = course_panel(request, course)
        return super().change_view(request, object_id, form_url, context)

    def get_urls(self) -> list[Any]:
        view = self.admin_site.admin_view
        return [
            path("<path:object_id>/submit/", view(self.prepare_view), name="courses_course_submit"),
            path(
                "<path:object_id>/preview/", view(self.preview_view), name="courses_course_preview"
            ),
            path("<path:object_id>/hide/", view(self.hide_view), name="courses_course_hide"),
            path("<path:object_id>/show/", view(self.show_view), name="courses_course_show"),
            path(
                "<path:object_id>/rollback/<uuid:release_id>/",
                view(self.rollback_view),
                name="courses_course_rollback",
            ),
            *super().get_urls(),
        ]

    def _course(self, request: HttpRequest, object_id: str) -> Course:
        course = cast(Course | None, self.get_object(request, unquote(object_id)))
        if course is None:
            raise Http404
        if not self.has_view_permission(request, course):
            raise PermissionDenied
        return course

    def _back(self, course: Course) -> HttpResponseRedirect:
        return HttpResponseRedirect(reverse("admin:courses_course_change", args=[course.pk]))

    def prepare_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        course = self._course(request, object_id)
        if not request.user.has_perm("courses.change_course"):
            raise PermissionDenied
        snapshot = build_snapshot(course)
        missing = readiness(snapshot)
        live = course.live_release
        chosen = list(live.languages) if live else ["ru"]
        note = ""
        errors: list[str] = []
        if request.method == "POST":
            chosen = request.POST.getlist("languages")
            note = str(request.POST.get("change_note", ""))
            try:
                release = prepare_release(course, request.user, languages=chosen, change_note=note)
            except CourseReleaseError as error:
                errors = error.problems
            else:
                self.log_change(
                    request,
                    course,
                    f"Подготовлен выпуск {release.number} ({', '.join(release.languages)}): "
                    f"{release.change_note}",
                )
                messages.success(
                    request,
                    f"Выпуск {release.number} на проверке. Правки можно продолжать: "
                    "они войдут в следующий выпуск.",
                )
                return self._back(course)
        return TemplateResponse(
            request,
            "admin/courses/course/prepare.html",
            {
                **self.admin_site.each_context(request),
                "opts": self.model._meta,
                "original": course,
                "title": f"Подготовить выпуск курса «{course}»",
                "languages": [
                    {
                        "code": language,
                        "label": LANGUAGE_NAMES[language],
                        "ready": not missing[language],
                        "problems": missing[language],
                        "checked": language in chosen and not missing[language],
                    }
                    for language in editor_languages()
                ],
                "changes": changes(live.snapshot if live else None, snapshot),
                "live": live,
                "change_note": note,
                "errors": errors,
            },
            status=400 if errors else 200,
        )

    def preview_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        course = self._course(request, object_id)
        return preview_response(
            self.admin_site.each_context(request),
            request,
            build_snapshot(course),
            title=f"Предпросмотр курса «{course}»",
            back=reverse("admin:courses_course_change", args=[course.pk]),
        )

    def hide_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        return self._course_action(
            request,
            object_id,
            lambda course: hide_course(
                course, request.user, reason=str(request.POST.get("reason", ""))
            ),
            lambda course: (
                f"Курс скрыт с сайта: {course.hidden_reason}",
                "Курс скрыт: на сайте и в приложении он пропадёт в течение минуты.",
            ),
        )

    def show_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        return self._course_action(
            request,
            object_id,
            lambda course: show_course(course, request.user),
            lambda _: (
                f"Курс возвращён на сайт. {request.POST.get('reason', '')}".strip(),
                "Курс снова на сайте.",
            ),
        )

    def rollback_view(self, request: HttpRequest, object_id: str, release_id: Any) -> HttpResponse:
        course = self._course(request, object_id)
        target = CourseRelease.objects.filter(pk=release_id, course=course).first()
        if target is None:
            raise Http404
        previous = course.live_release
        faulty = request.POST.get("faulty") == "on"
        return self._course_action(
            request,
            object_id,
            lambda course: roll_back(
                course,
                target,
                request.user,
                reason=str(request.POST.get("reason", "")),
                faulty=faulty,
            ),
            lambda _: (
                f"Возвращён выпуск {target.number} вместо выпуска "
                f"{previous.number if previous else '—'}"
                f"{' (отозван как ошибочный)' if faulty else ''}: "
                f"{request.POST.get('reason', '')}",
                f"На сайте снова выпуск {target.number}.",
            ),
        )

    def _course_action(
        self,
        request: HttpRequest,
        object_id: str,
        operation: Callable[[Course], object],
        describe: Callable[[Course], tuple[str, str]],
    ) -> HttpResponse:
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        course = self._course(request, object_id)
        try:
            operation(course)
        except CourseReleaseError as error:
            for problem in error.problems:
                messages.error(request, problem)
        else:
            course.refresh_from_db()
            log, shown = describe(course)
            self.log_change(request, course, log)
            messages.success(request, shown)
        return self._back(course)


def course_panel(request: HttpRequest, course: Course) -> dict[str, Any]:
    """The state above the course form: site, review, readiness and changes."""
    user = request.user
    snapshot = build_snapshot(course)
    live = course.live_release
    releases = list(course.releases.select_related("reviewed_by", "submitted_by"))
    pending = next(
        (
            release
            for release in releases
            if release.status in {CourseReleaseStatus.IN_REVIEW, CourseReleaseStatus.SIGNED}
        ),
        None,
    )
    latest = releases[0] if releases else None
    returned = latest if latest and latest.status == CourseReleaseStatus.RETURNED else None
    change_url = reverse("admin:courses_course_change", args=[course.pk])
    missing = readiness(snapshot)
    next_number = (latest.number if latest else 0) + 1
    draft_checksum = checksum(snapshot)
    return {
        "live": live,
        "hidden": course.hidden_at is not None,
        "pending": pending,
        "pending_url": reverse("admin:courses_courserelease_change", args=[pending.pk])
        if pending
        else "",
        "pending_outdated": pending is not None and pending.checksum_sha256 != draft_checksum,
        "returned": returned,
        "next_number": next_number,
        "changes": changes(live.snapshot if live else None, snapshot),
        "unchanged": live is not None and live.checksum_sha256 == draft_checksum,
        "languages": [
            {
                "label": LANGUAGE_NAMES[language],
                "code": language,
                "problems": [
                    {
                        "text": problem.text,
                        "url": reverse("admin:courses_courselesson_change", args=[problem.lesson])
                        if problem.lesson
                        else change_url,
                    }
                    for problem in missing[language]
                ],
            }
            for language in editor_languages()
        ],
        "releases": releases,
        "can_prepare": user.has_perm("courses.change_course") and pending is None,
        "can_publish": can_publish(user),
        "submit_url": reverse("admin:courses_course_submit", args=[course.pk]),
        "preview_url": reverse("admin:courses_course_preview", args=[course.pk]),
        "hide_url": reverse("admin:courses_course_hide", args=[course.pk]),
        "show_url": reverse("admin:courses_course_show", args=[course.pk]),
    }


def preview_response(  # noqa: PLR0913 - the page needs each of them
    each_context: dict[str, Any],
    request: HttpRequest,
    snapshot: dict[str, Any],
    *,
    title: str,
    back: str,
    lesson_id: str = "",
    languages: list[str] | None = None,
    version: str = "черновик",
    documents: dict[str, dict[str, Any]] | None = None,
) -> HttpResponse:
    """Blocks of a course or of one lesson on one language, as the site draws them."""
    available = languages or editor_languages()
    language = str(request.GET.get("language", available[0]))
    if language not in available:
        language = available[0]
    if documents is not None:
        payload = documents[language]
    else:
        payload = build_document(snapshot, language=language, version=version, languages=available)
    lessons = [
        lesson
        for lesson, source in zip(payload["lessons"], snapshot["lessons"], strict=True)
        if not lesson_id or source["id"] == lesson_id
    ]
    return TemplateResponse(
        request,
        "admin/courses/preview.html",
        {
            **each_context,
            "title": title,
            "back": back,
            "tabs": [
                {"code": code, "label": TAB_LABELS[code], "active": code == language}
                for code in available
            ],
            "language": language,
            "direction": "rtl" if language == "ar" else "ltr",
            "course": payload["course"],
            "lessons": lessons,
            "whole_course": not lesson_id,
            "missing": readiness(snapshot)[language],
        },
    )


@admin.register(CourseLesson)
class CourseLessonAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = CourseLessonForm
    list_display = ("__str__", "course", "position", "slug")
    list_filter = ("course",)
    search_fields = ("title_ru", "slug")
    prepopulated_fields: ClassVar[dict[str, Sequence[str]]] = {"slug": ("title_ru",)}
    change_form_template = "admin/courses/courselesson/change_form.html"

    def get_fieldsets(self, _request: HttpRequest, _obj: CourseLesson | None = None) -> Any:
        return [
            (None, {"fields": ("course", "position", "slug", "minutes", "revision")}),
            *(
                (
                    f"Тексты: {LANGUAGE_NAMES[language]}",
                    {
                        "fields": tuple(
                            f"{field}_{language}"
                            for field in ("title", "summary", "notes", "sources")
                        ),
                        "classes": () if language == "ru" else ("collapse",),
                    },
                )
                for language in editor_languages()
            ),
        ]

    def get_readonly_fields(self, _request: HttpRequest, obj: CourseLesson | None = None) -> Any:
        return ("course",) if obj is not None else ()

    def get_model_perms(self, _request: HttpRequest) -> dict[str, bool]:
        # Lessons are reached from their course; the index lists courses only.
        return {}

    def save_model(self, request: HttpRequest, obj: CourseLesson, form: Any, change: bool) -> None:
        obj.updated_by = cast(Any, request.user)
        super().save_model(request, obj, form, change)

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        lesson = self.get_object(request, unquote(object_id))
        context = dict(extra_context or {})
        if lesson is not None:
            siblings = list(lesson.course.lessons.order_by("position", "created_at"))
            index = next(i for i, item in enumerate(siblings) if item.pk == lesson.pk)
            context["lesson_nav"] = {
                "number": index + 1,
                "count": len(siblings),
                "previous": siblings[index - 1] if index > 0 else None,
                "next": siblings[index + 1] if index + 1 < len(siblings) else None,
                "course": lesson.course,
                "preview_url": reverse("admin:courses_courselesson_preview", args=[lesson.pk]),
            }
        return super().change_view(request, object_id, form_url, context)

    def response_change(self, request: HttpRequest, obj: CourseLesson) -> HttpResponse:
        if "_continue" not in request.POST and "_addanother" not in request.POST:
            return HttpResponseRedirect(
                reverse("admin:courses_course_change", args=[obj.course_id])
            )
        return super().response_change(request, obj)

    def get_urls(self) -> list[Any]:
        return [
            path(
                "<path:object_id>/preview/",
                self.admin_site.admin_view(self.preview_view),
                name="courses_courselesson_preview",
            ),
            *super().get_urls(),
        ]

    def preview_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        lesson = self.get_object(request, unquote(object_id))
        if lesson is None:
            raise Http404
        if not self.has_view_permission(request, lesson):
            raise PermissionDenied
        return preview_response(
            self.admin_site.each_context(request),
            request,
            build_snapshot(lesson.course),
            title=f"Предпросмотр темы «{lesson}»",
            back=reverse("admin:courses_courselesson_change", args=[lesson.pk]),
            lesson_id=str(lesson.pk),
        )


@admin.register(CourseRelease)
class CourseReleaseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "__str__",
        "status",
        "language_list",
        "submitted_by",
        "submitted_at",
        "reviewed_by",
        "published_at",
    )
    list_filter = ("status", "course")
    actions = ("sign_selected", "publish_selected")
    change_form_template = "admin/courses/courserelease/change_form.html"
    fields = (
        "course",
        "number",
        "status",
        "language_list",
        "change_note",
        "based_on",
        "submitted_by",
        "submitted_at",
        "reviewed_by",
        "reviewed_at",
        "review_note",
        "published_by",
        "published_at",
        "ended_by",
        "ended_at",
        "end_reason",
        "checksum_sha256",
    )
    readonly_fields = fields

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def has_sign_permission(self, request: HttpRequest) -> bool:
        return can_sign(request.user)

    def has_publish_permission(self, request: HttpRequest) -> bool:
        return can_publish(request.user)

    @admin.display(description="Языки")
    def language_list(self, obj: CourseRelease) -> str:
        return ", ".join(obj.languages)

    def get_urls(self) -> list[Any]:
        view = self.admin_site.admin_view
        return [
            path(
                "<path:object_id>/review/<str:operation>/",
                view(self.review_view),
                name="courses_courserelease_review",
            ),
            path(
                "<path:object_id>/preview/",
                view(self.preview_view),
                name="courses_courserelease_preview",
            ),
            *super().get_urls(),
        ]

    def _release(self, request: HttpRequest, object_id: str) -> CourseRelease:
        release = cast(CourseRelease | None, self.get_object(request, unquote(object_id)))
        if release is None:
            raise Http404
        if not self.has_view_permission(request, release):
            raise PermissionDenied
        return release

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        release = self.get_object(request, unquote(object_id))
        context = dict(extra_context or {})
        if release is not None:
            context["review"] = review_panel(request, release)
        return super().change_view(request, object_id, form_url, context)

    def preview_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """Exactly what clients will get: the stored document of the release."""
        release = self._release(request, object_id)
        return preview_response(
            self.admin_site.each_context(request),
            request,
            release.snapshot,
            title=f"{release}: как увидят ученики",
            back=reverse("admin:courses_courserelease_change", args=[release.pk]),
            languages=list(release.languages),
            version=release.version,
            documents={document.language: document.payload for document in release.documents.all()},
        )

    def review_view(self, request: HttpRequest, object_id: str, operation: str) -> HttpResponse:
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        release = self._release(request, object_id)
        user = request.user
        text = str(request.POST.get("text", ""))
        live = release.course.live_release
        replaced = f" вместо выпуска {live.number}" if live else ""
        operations: dict[str, tuple[Callable[[], object], str, str]] = {
            "withdraw": (
                lambda: withdraw_from_review(release, user),
                f"Выпуск {release.number} отозван с проверки.",
                "Выпуск отозван с проверки. Поправьте курс и подготовьте выпуск заново.",
            ),
            "return": (
                lambda: return_for_rework(release, user, comment=text),
                f"Выпуск {release.number} возвращён на доработку: {text}",
                "Выпуск возвращён на доработку. Комментарий виден на странице курса.",
            ),
            "sign": (
                lambda: sign_release(release, user, note=text),
                f"Выпуск {release.number} подписан. {text}".strip(),
                "Выпуск подписан. Теперь его можно опубликовать.",
            ),
            "publish": (
                lambda: publish_release(release, user),
                f"Опубликован выпуск {release.number}{replaced}.",
                "Курс опубликован: на сайте он появится в течение минуты, "
                "в приложении — при следующем открытии раздела.",
            ),
        }
        if operation not in operations:
            raise Http404
        run, log, shown = operations[operation]
        try:
            run()
        except CourseReleaseError as error:
            for problem in error.problems:
                messages.error(request, problem)
            return HttpResponseRedirect(
                reverse("admin:courses_courserelease_change", args=[release.pk])
            )
        self.log_change(request, release, log)
        self.log_change(request, release.course, log)
        messages.success(request, shown)
        return HttpResponseRedirect(
            reverse("admin:courses_course_change", args=[release.course_id])
        )

    def _bulk(
        self,
        request: HttpRequest,
        queryset: QuerySet[CourseRelease],
        operation: Callable[[CourseRelease], object],
        done: str,
    ) -> None:
        for release in queryset.select_related("course"):
            try:
                operation(release)
            except CourseReleaseError as error:
                self.message_user(
                    request, f"{release}: не сделано — {' '.join(error.problems)}", messages.WARNING
                )
            else:
                self.log_change(request, release, f"Выпуск {release.number} {done}.")
                self.log_change(request, release.course, f"Выпуск {release.number} {done}.")
                self.message_user(request, f"{release}: {done}.", messages.SUCCESS)

    @admin.action(description="Подписать проверку", permissions=("sign",))
    def sign_selected(self, request: HttpRequest, queryset: QuerySet[CourseRelease]) -> None:
        self._bulk(
            request, queryset, lambda release: sign_release(release, request.user), "подписан"
        )

    @admin.action(description="Опубликовать", permissions=("publish",))
    def publish_selected(self, request: HttpRequest, queryset: QuerySet[CourseRelease]) -> None:
        self._bulk(
            request, queryset, lambda release: publish_release(release, request.user), "опубликован"
        )


def review_panel(request: HttpRequest, release: CourseRelease) -> dict[str, Any]:
    """What the reviewer reads: the change note, the changed texts line by line, buttons."""
    user = request.user
    old = release.based_on.snapshot if release.based_on else None
    old_lessons = {lesson["id"]: lesson for lesson in (old or {}).get("lessons", [])}
    diffs = []
    for number, lesson in enumerate(release.snapshot["lessons"], start=1):
        before = old_lessons.get(lesson["id"])
        if before is not None and before["checksum"] == lesson["checksum"]:
            continue
        fields = []
        for language in release.languages:
            for field, label in DIFF_FIELDS:
                previous = before[field][language] if before else ""
                if previous != lesson[field][language]:
                    fields.append(
                        {
                            "label": f"{label} ({language})",
                            "rows": line_diff(previous, lesson[field][language]),
                        }
                    )
        diffs.append(
            {
                "name": f"Тема {number} «{lesson['title']['ru'] or lesson['slug']}»"
                + ("" if before else " — новая"),
                "fields": fields,
            }
        )
    in_review = release.status == CourseReleaseStatus.IN_REVIEW
    return {
        "changes": changes(old, release.snapshot),
        "diffs": diffs,
        "first": old is None,
        "preview_urls": [
            (
                TAB_LABELS[language],
                reverse("admin:courses_courserelease_preview", args=[release.pk])
                + f"?language={language}",
            )
            for language in release.languages
        ],
        "can_withdraw": in_review and (release.submitted_by_id == user.pk or can_sign(user)),
        "can_review": in_review and can_sign(user),
        "can_publish": release.status == CourseReleaseStatus.SIGNED and can_publish(user),
        "strict": settings.COURSES_STRICT_REVIEW,
        "course_url": reverse("admin:courses_course_change", args=[release.course_id]),
        "urls": {
            operation: reverse("admin:courses_courserelease_review", args=[release.pk, operation])
            for operation in ("withdraw", "return", "sign", "publish")
        },
    }


@admin.register(CourseDocument)
class CourseDocumentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("release", "language", "bytes")
    list_filter = ("language",)
    readonly_fields = ("release", "language", "checksum_sha256", "bytes", "card", "payload")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False
