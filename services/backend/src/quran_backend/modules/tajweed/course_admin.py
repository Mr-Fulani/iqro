# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""Admin of the tajweed course: draft → editor → sign-off → publication.

A version starts as the snapshot imported from git (`manage.py
import_tajweed_course`) or as a draft copied from another version here. The
editor changes the texts of a draft in every language and the few lesson
settings (minutes, letters, preferred examples); the structure of the course
changes only in git. Signed and published versions are read-only.
"""

from __future__ import annotations

import copy
import logging
import re
from collections.abc import Callable, Mapping
from typing import Any

from django.conf import settings
from django.contrib import admin, messages
from django.contrib.admin.utils import unquote
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.db.models import QuerySet
from django.http import (
    Http404,
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    HttpResponseRedirect,
    JsonResponse,
)
from django.template.loader import render_to_string
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils import timezone
from django.utils.html import format_html, format_html_join
from django.utils.http import urlencode

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.courses.admin import (
    TAB_LABELS,
    VIDEO_INSTRUCTION_URL,
    _received_file,
    clock,
    megabytes,
)
from quran_backend.modules.courses.document import LANGUAGE_NAMES, video_payload
from quran_backend.modules.courses.lesson_media import LessonMediaError
from quran_backend.modules.courses.lesson_media_admin import (
    Change,
    MediaPage,
    render_media,
    run_media_action,
)
from quran_backend.modules.courses.models import SPOKEN_LANGUAGES
from quran_backend.modules.courses.video import (
    MAX_DUB_MIB,
    MAX_VIDEO_MIB,
    SPEECH_NAMES,
    CourseVideoError,
)
from quran_backend.modules.tajweed.course import (
    COLOR,
    LESSON_TEXTS,
    VERSION_NAME,
    TajweedCourseError,
    lesson_video,
    missing_texts,
    snapshot_json,
)
from quran_backend.modules.tajweed.course_publication import (
    compile_course_version,
    copy_tajweed_course,
    mark_tajweed_watched,
    new_videos,
    publish_tajweed_course,
    save_course_draft,
    sign_tajweed_course,
)
from quran_backend.modules.tajweed.lesson_media import (
    change_lesson,
    delete_dub,
    remove_video,
    set_poster,
    set_spoken_language,
    upload_dub,
    upload_video,
)
from quran_backend.modules.tajweed.models import (
    TAJWEED_COURSE_LANGUAGES,
    TajweedCourse,
    TajweedCourseDocument,
    TajweedCourseStatus,
    TajweedCourseVersion,
)
from quran_backend.modules.tajweed.rules import RULES_BY_CODE

TEXT_LABELS = {
    "title": "Название",
    "summary": "Кратко",
    "explanation": "Объяснение правила",
    "how": "Как читать",
    "name": "Название",
}
REVIEW_LABELS = {
    "pending_teacher_review": "На проверке у преподавателя: показывать пометку",
    "reviewed": "Проверено преподавателем",
}
SHOWN_PROBLEMS = 12

logger = logging.getLogger(__name__)


def editor_languages() -> list[str]:
    """Russian first: the course is written in it and translated from it."""
    return sorted(TAJWEED_COURSE_LANGUAGES, key=lambda code: (code != "ru", code))


def editor_editable(user: Any, version: TajweedCourseVersion) -> bool:
    return (
        version.status == TajweedCourseStatus.DRAFT
        and not version.is_signed
        and user.has_perm("tajweed.change_tajweedcourseversion")
    )


def readonly_reason(user: Any, version: TajweedCourseVersion) -> str:
    if version.status == TajweedCourseStatus.PUBLISHED:
        return (
            "Версия опубликована: её показывают приложение и сайт, поэтому она не меняется. "
            "Чтобы что-то поправить, создайте из неё черновик."
        )
    if version.status == TajweedCourseStatus.WITHDRAWN:
        return "Версия отозвана: её заменила более новая. Из неё можно сделать новый черновик."
    if version.is_signed:
        return (
            "Черновик подписан и ждёт публикации: подписанный текст не меняется. "
            "Чтобы поправить, создайте из него новый черновик и подпишите его заново."
        )
    if not user.has_perm("tajweed.change_tajweedcourseversion"):
        return "У вас право только на просмотр курса."
    return ""


def free_version_name(version: TajweedCourseVersion, base: str) -> str:
    taken = set(version.course.versions.values_list("version", flat=True))
    if base not in taken:
        return base
    number = 2
    while f"{base}-{number}" in taken:
        number += 1
    return f"{base}-{number}"


def _node(snapshot: Mapping[str, Any], node_id: str) -> tuple[str, dict[str, Any]] | None:
    """(kind, snapshot object) for `course`, `target:<key>`, `section:<slug>`, `lesson:<slug>`."""
    kind, _, key = node_id.partition(":")
    if kind == "course":
        return kind, snapshot["course"]
    collection, field = {
        "target": ("targets", "key"),
        "section": ("sections", "slug"),
        "lesson": ("lessons", "slug"),
    }.get(kind, ("", ""))
    for item in snapshot.get(collection, []) if collection else []:
        if item.get(field) == key:
            return kind, item
    return None


def _text_fields(kind: str) -> tuple[str, ...]:
    return {
        "course": ("title", "summary"),
        "target": ("name",),
        "section": ("title",),
        "lesson": LESSON_TEXTS,
    }[kind]


@admin.register(TajweedCourse)
class TajweedCourseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("slug", "active_version")
    readonly_fields = ("slug", "active_version", "created_at", "updated_at")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False


@admin.register(TajweedCourseVersion)
class TajweedCourseVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("__str__", "status", "signed", "published_at", "editor_link")
    list_filter = ("status", "course")
    actions = ("sign_versions", "publish_versions", "recompile_versions")
    change_form_template = "admin/tajweed/tajweedcourseversion/change_form.html"
    readonly_fields = (
        "course",
        "version",
        "status",
        "checksum_sha256",
        "reviewed_by",
        "reviewed_at",
        "review_note",
        "published_at",
        "documents_summary",
    )
    exclude = ("snapshot", "schema_version")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self, request: HttpRequest, obj: TajweedCourseVersion | None = None
    ) -> bool:
        return False if obj is not None else super().has_change_permission(request, obj)

    def has_delete_permission(
        self, request: HttpRequest, obj: TajweedCourseVersion | None = None
    ) -> bool:
        return super().has_delete_permission(request, obj) and (
            obj is None or obj.status == TajweedCourseStatus.DRAFT
        )

    @admin.display(boolean=True, description="Подписана")
    def signed(self, obj: TajweedCourseVersion) -> bool:
        return obj.is_signed

    @admin.display(description="Редактор")
    def editor_link(self, obj: TajweedCourseVersion) -> str:
        label = "Редактировать" if obj.status == TajweedCourseStatus.DRAFT else "Открыть"
        return format_html('<a href="{}">{}</a>', self._editor_url(obj), label)

    @admin.display(description="Документы по языкам")
    def documents_summary(self, obj: TajweedCourseVersion) -> str:
        rows = [
            (document.language, f"{document.bytes / 1024:.0f} КБ")
            for document in obj.documents.all()
        ]
        return format_html_join(", ", "{}: {}", rows) or "—"

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        version = self.get_object(request, unquote(object_id))
        context = dict(extra_context or {})
        if version is not None:
            context["tajweed_editor"] = {
                "url": self._editor_url(version),
                "editable": editor_editable(request.user, version),
                "reason": readonly_reason(request.user, version),
                "copy_url": reverse(
                    "admin:tajweed_tajweedcourseversion_new_draft", args=[version.pk]
                )
                if request.user.has_perm("tajweed.add_tajweedcourseversion")
                else "",
                "download_url": reverse(
                    "admin:tajweed_tajweedcourseversion_snapshot", args=[version.pk]
                ),
            }
        return super().change_view(request, object_id, form_url, context)

    def get_urls(self) -> list[Any]:
        view = self.admin_site.admin_view
        return [
            path(
                "<path:object_id>/editor/",
                view(self.editor_view),
                name="tajweed_tajweedcourseversion_editor",
            ),
            path(
                "<path:object_id>/new-draft/",
                view(self.new_draft_view),
                name="tajweed_tajweedcourseversion_new_draft",
            ),
            path(
                "<path:object_id>/snapshot.json",
                view(self.snapshot_view),
                name="tajweed_tajweedcourseversion_snapshot",
            ),
            path(
                "<path:object_id>/review/",
                view(self.review_view),
                name="tajweed_tajweedcourseversion_review",
            ),
            path(
                "<path:object_id>/lessons/<slug:lesson>/media/",
                view(self.lesson_media_view),
                name="tajweed_tajweedcourseversion_media",
            ),
            path(
                "<path:object_id>/lessons/<slug:lesson>/video/<str:operation>/",
                view(self.lesson_video_view),
                name="tajweed_tajweedcourseversion_video",
            ),
            path(
                "<path:object_id>/lessons/<slug:lesson>/video/dubs/<str:language>/<str:operation>/",
                view(self.lesson_video_view),
                name="tajweed_tajweedcourseversion_dub",
            ),
            path(
                "<path:object_id>/watched/<str:sha256>/",
                view(self.watched_view),
                name="tajweed_tajweedcourseversion_watched",
            ),
            *super().get_urls(),
        ]

    # Editor -------------------------------------------------------------

    def _version(self, request: HttpRequest, object_id: str) -> TajweedCourseVersion:
        version: TajweedCourseVersion | None = self.get_object(request, unquote(object_id))
        if version is None:
            raise Http404
        if not request.user.has_perm("tajweed.view_tajweedcourseversion"):
            raise PermissionDenied
        return version

    @staticmethod
    def _editor_url(version: TajweedCourseVersion, node_id: str = "course") -> str:
        url = reverse("admin:tajweed_tajweedcourseversion_editor", args=[version.pk])
        return f"{url}?{urlencode({'node': node_id})}"

    def editor_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        version = self._version(request, object_id)
        node_id = str(request.GET.get("node") or request.POST.get("node") or "course")
        found = _node(version.snapshot, node_id)
        if found is None:
            raise Http404
        kind, _ = found
        editable = editor_editable(request.user, version)
        posted: Mapping[str, Any] | None = None
        if request.method == "POST":
            if not editable:
                raise PermissionDenied
            posted = request.POST
            if self._save(request, version, node_id):
                return HttpResponseRedirect(self._editor_url(version, node_id))
        return self._render(
            request, version, node_id=node_id, kind=kind, editable=editable, posted=posted
        )

    def _save(self, request: HttpRequest, version: TajweedCourseVersion, node_id: str) -> bool:
        snapshot = copy.deepcopy(version.snapshot)
        found = _node(snapshot, node_id)
        if found is None:
            raise Http404
        kind, target = found
        data = request.POST
        for field in _text_fields(kind):
            texts = dict(target.get(field) or {})
            for language in TAJWEED_COURSE_LANGUAGES:
                texts[language] = str(data.get(f"{field}__{language}", "")).strip()
            target[field] = texts
        problems: list[str] = []
        if kind == "course":
            target["review_status"] = str(data.get("review_status", ""))
        elif kind == "target":
            target["arabic_name"] = str(data.get("arabic_name", "")).strip()
            target["color"] = str(data.get("color", "")).strip().upper()
            if not COLOR.match(target["color"]):
                problems.append("Цвет: в виде #RRGGBB.")
        elif kind == "lesson":
            try:
                target["minutes"] = int(str(data.get("minutes", "")))
            except ValueError:
                problems.append("Минуты: целое число.")
            target["letters"] = str(data.get("letters", "")).strip()
            target["examples"] = [
                key for key in re.split(r"[\s,]+", str(data.get("examples", ""))) if key
            ]
        try:
            if problems:
                raise TajweedCourseError(problems)
            save_course_draft(version, snapshot)
        except TajweedCourseError as error:
            shown = "; ".join(error.problems[:SHOWN_PROBLEMS])
            messages.error(request, f"Не сохранено: {shown}")
            return False
        self.log_change(request, version, f"Изменено в редакторе: {node_id}.")
        messages.success(request, "Сохранено. Документы курса пересобраны.")
        return True

    def _render(  # noqa: PLR0913 - the form shows what a refused save sent
        self,
        request: HttpRequest,
        version: TajweedCourseVersion,
        *,
        node_id: str,
        kind: str,
        editable: bool,
        posted: Mapping[str, Any] | None,
    ) -> HttpResponse:
        snapshot = version.snapshot
        _, item = _node(snapshot, node_id) or ("", {})
        names = dict(settings.LANGUAGES)
        languages = editor_languages()

        def value(name: str, stored: object) -> str:
            return str(posted.get(name, "")) if posted is not None else str(stored or "")

        fields = [
            {
                "name": field,
                "label": TEXT_LABELS[field],
                "multiline": field in {"explanation", "how", "summary"},
                "values": [
                    {
                        "code": language,
                        "label": names.get(language, language),
                        "input": f"{field}__{language}",
                        "value": value(
                            f"{field}__{language}", (item.get(field) or {}).get(language)
                        ),
                        "rtl": language == "ar",
                    }
                    for language in languages
                ],
            }
            for field in _text_fields(kind)
        ]
        settings_fields: list[dict[str, Any]] = []
        if kind == "course":
            settings_fields.append(
                {
                    "name": "review_status",
                    "label": "Проверка преподавателем",
                    "choices": [
                        (code, label, value("review_status", item.get("review_status")) == code)
                        for code, label in REVIEW_LABELS.items()
                    ],
                }
            )
        elif kind == "target":
            settings_fields += [
                {
                    "name": "arabic_name",
                    "label": "Арабское название",
                    "value": value("arabic_name", item.get("arabic_name")),
                    "rtl": True,
                },
                {
                    "name": "color",
                    "label": "Цвет подсветки (#RRGGBB)",
                    "value": value("color", item.get("color")),
                },
            ]
        elif kind == "lesson":
            target = str(item.get("target", ""))
            rule = RULES_BY_CODE.get(target)
            settings_fields += [
                {
                    "name": "minutes",
                    "label": "Минут на урок",
                    "value": value("minutes", item.get("minutes")),
                },
                {
                    "name": "letters",
                    "label": "Буквы правила",
                    "rtl": True,
                    "value": value("letters", item.get("letters")),
                },
                {
                    "name": "examples",
                    "label": "Свои примеры: ключи аятов через запятую",
                    "value": value("examples", ", ".join(item.get("examples", []))),
                },
            ]
            settings_fields.append(
                {
                    "name": "",
                    "label": "Цель урока",
                    "static": f"{target}"
                    + (
                        f" — класс Quran.Foundation «{rule.name['ru']}»"
                        if rule
                        else " — выводится из букв (course_markers.py)"
                    ),
                }
            )
        media_block = (
            render_media(media_page(request, version, item["slug"]), request)
            if kind == "lesson"
            else ""
        )
        missing = missing_texts(snapshot)
        tree = [{"id": "course", "label": "Курс", "indent": 0}]
        tree += [
            {
                "id": f"target:{target['key']}",
                "label": f"Цель: {target['name'].get('ru') or target['key']}",
                "indent": 1,
            }
            for target in snapshot.get("targets", [])
        ]
        lessons = {lesson["slug"]: lesson for lesson in snapshot.get("lessons", [])}
        for section in snapshot.get("sections", []):
            tree.append(
                {
                    "id": f"section:{section['slug']}",
                    "label": section["title"].get("ru") or section["slug"],
                    "indent": 0,
                }
            )
            tree += [
                {
                    "id": f"lesson:{slug}",
                    "label": lessons[slug]["title"].get("ru") or slug,
                    "indent": 1,
                }
                for slug in section["lessons"]
                if slug in lessons
            ]
        return TemplateResponse(
            request,
            "admin/tajweed/tajweedcourseversion/editor.html",
            {
                **self.admin_site.each_context(request),
                "opts": self.model._meta,
                "original": version,
                "title": f"Редактор курса {version}",
                "node_id": node_id,
                "tree": tree,
                "fields": fields,
                "settings_fields": settings_fields,
                "editable": editable,
                "readonly_reason": readonly_reason(request.user, version),
                "status_label": self._status_label(version),
                "missing": [
                    (names.get(code, code), missing[code]) for code in languages if missing[code]
                ],
                "can_copy": request.user.has_perm("tajweed.add_tajweedcourseversion"),
                "can_review": request.user.has_perm("tajweed.change_tajweedcourseversion"),
                "media_block": media_block,
                "videos": review_videos(version, node_id) if version.status == "draft" else [],
            },
            status=400 if posted is not None else 200,
        )

    @staticmethod
    def _status_label(version: TajweedCourseVersion) -> str:
        if version.status == TajweedCourseStatus.DRAFT:
            return "Черновик, подписан" if version.is_signed else "Черновик"
        return str(TajweedCourseStatus(version.status).label)

    # Lesson media -------------------------------------------------------
    # JSON answers with the block drawn anew, as on a lesson of a thematic course.

    def _draft(self, request: HttpRequest, object_id: str, lesson: str) -> TajweedCourseVersion:
        version = self._version(request, object_id)
        if _node(version.snapshot, f"lesson:{lesson}") is None:
            raise Http404
        if not editor_editable(request.user, version):
            raise PermissionDenied
        return version

    def lesson_media_view(self, request: HttpRequest, object_id: str, lesson: str) -> HttpResponse:
        """The «Медиа» block of a lesson: the button says what to do in `action`."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        version = self._draft(request, object_id, lesson)

        def update(change: Change) -> None:
            change_lesson(
                version,
                lesson,
                lambda item: item.__setitem__("media", change(list(item.get("media") or []))),
            )

        def answer() -> str:
            # The video block goes with its data: removing it removes the video.
            return run_media_action(
                request, media_page(request, version, lesson), update=update, remove_video=_keep
            )

        response = self._media_answer(request, version, lesson, answer)
        if response is not None:
            return response
        if request.POST.get("action") == "texts":
            return JsonResponse({"ok": True})
        version.refresh_from_db()
        return JsonResponse({"html": render_media(media_page(request, version, lesson), request)})

    def lesson_video_view(
        self, request: HttpRequest, object_id: str, lesson: str, operation: str, language: str = ""
    ) -> HttpResponse:
        """The video block of a lesson: upload, poster, language of speech, dubs."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        version = self._draft(request, object_id, lesson)
        run = _video_operation(request, version, lesson, operation, language)
        response = self._media_answer(request, version, lesson, run)
        if response is not None:
            return response
        version.refresh_from_db()
        return JsonResponse(
            {
                "html": render_to_string(
                    "admin/courses/courselesson/video.html",
                    {"block": video_block(request, version, lesson)},
                    request=request,
                )
            }
        )

    def _media_answer(
        self,
        request: HttpRequest,
        version: TajweedCourseVersion,
        lesson: str,
        run: Callable[[], str],
    ) -> HttpResponse | None:
        """Runs the change and logs it; an error is the answer, success gives None."""
        try:
            log = run()
        except (LessonMediaError, CourseVideoError) as error:
            return JsonResponse({"error": str(error)}, status=error.status)
        except ImproperlyConfigured, ObjectStorageError, OSError:
            logger.exception("Tajweed lesson media operation failed")
            return JsonResponse({"error": "Хранилище недоступно, повторите."}, status=502)
        self.log_change(request, version, f"Медиа урока {lesson}: {log}")
        return None

    def watched_view(self, request: HttpRequest, object_id: str, sha256: str) -> HttpResponse:
        """«Просмотрено» on one new video or dub of the draft, or the mark taken back."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        version = self._version(request, object_id)
        if not editor_editable(request.user, version):
            raise PermissionDenied
        watched = request.POST.get("watched") != "0"
        try:
            mark_tajweed_watched(version, sha256=sha256, watched=watched)
        except TajweedCourseError as error:
            messages.error(request, str(error))
        else:
            self.log_change(
                request,
                version,
                f"{'Просмотрено' if watched else 'Снята отметка «Просмотрено»'}: {sha256[:12]}",
            )
        node = str(request.POST.get("node") or "course")
        return HttpResponseRedirect(self._editor_url(version, node) + "#videos")

    # New draft, download, review ---------------------------------------

    def new_draft_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        source = self._version(request, object_id)
        if not request.user.has_perm("tajweed.add_tajweedcourseversion"):
            raise PermissionDenied
        name = free_version_name(source, timezone.localdate().isoformat())
        error = ""
        if request.method == "POST":
            name = str(request.POST.get("version", "")).strip()
            if not VERSION_NAME.match(name):
                error = "Имя версии: латинские буквы, цифры, точка, дефис, до 64 знаков."
            elif source.course.versions.filter(version=name).exists():
                error = f"Версия «{name}» уже есть. Выберите другое имя."
            else:
                draft = copy_tajweed_course(source, name)
                self.log_addition(request, draft, f"Черновик из версии {source.version}.")
                messages.success(
                    request,
                    f"Создан черновик {draft}: копия версии {source.version}. "
                    "Исходная версия не изменилась.",
                )
                return HttpResponseRedirect(self._editor_url(draft))
        return TemplateResponse(
            request,
            "admin/tajweed/tajweedcourseversion/new_draft.html",
            {
                **self.admin_site.each_context(request),
                "opts": self.model._meta,
                "original": source,
                "title": f"Новый черновик из версии {source.version}",
                "name": name,
                "error": error,
            },
            status=400 if error else 200,
        )

    def snapshot_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """The snapshot as JSON, to keep it in git like `tajweed-course-v1.json`."""
        version = self._version(request, object_id)
        response = HttpResponse(
            snapshot_json(version.snapshot), content_type="application/json; charset=utf-8"
        )
        filename = f"{version.course.slug}-{version.version}.json"
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response

    def review_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """Sign-off and publication from the editor's status bar."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        version = self._version(request, object_id)
        if not request.user.has_perm("tajweed.change_tajweedcourseversion"):
            raise PermissionDenied
        action = request.POST.get("action")
        back = HttpResponseRedirect(self._editor_url(version, request.POST.get("node") or "course"))
        if action == "sign":
            if not editor_editable(request.user, version):
                messages.error(request, "Подписать можно только неподписанный черновик.")
            else:
                self._sign(request, version)
        elif action == "publish":
            try:
                publish_tajweed_course(version)
            except TajweedCourseError as error:
                messages.error(request, f"Не опубликовано: {error}")
            else:
                self.log_change(request, version, "Опубликована из редактора.")
                messages.success(
                    request,
                    f"{version} опубликована: приложение и сайт покажут её "
                    "в течение нескольких минут.",
                )
        return back

    def _sign(self, request: HttpRequest, version: TajweedCourseVersion) -> bool:
        try:
            sign_tajweed_course(version, request.user)
        except TajweedCourseError as error:
            problems = list(dict.fromkeys(error.problems))
            more = (
                f" И ещё {len(problems) - SHOWN_PROBLEMS}."
                if len(problems) > SHOWN_PROBLEMS
                else ""
            )
            messages.error(
                request, f"{version}: не подписана. {'; '.join(problems[:SHOWN_PROBLEMS])}.{more}"
            )
            return False
        self.log_change(request, version, "Подписана.")
        messages.success(request, f"{version}: подписана. Теперь её можно опубликовать.")
        return True

    # Actions -------------------------------------------------------------
    # They change a version: like the editor's sign-off, they need the change permission.

    @admin.action(permissions=["change"], description="Подписать: тексты проверены")
    def sign_versions(self, request: HttpRequest, queryset: QuerySet[TajweedCourseVersion]) -> None:
        for version in queryset.filter(status=TajweedCourseStatus.DRAFT, reviewed_at=None):
            self._sign(request, version)

    @admin.action(permissions=["change"], description="Опубликовать")
    def publish_versions(
        self, request: HttpRequest, queryset: QuerySet[TajweedCourseVersion]
    ) -> None:
        for version in queryset:
            try:
                publish_tajweed_course(version)
            except TajweedCourseError as error:
                self.message_user(request, f"{version}: {error}", messages.ERROR)
            else:
                self.message_user(request, f"{version}: опубликована.", messages.SUCCESS)

    @admin.action(permissions=["change"], description="Пересобрать документы")
    def recompile_versions(
        self, request: HttpRequest, queryset: QuerySet[TajweedCourseVersion]
    ) -> None:
        for version in queryset.filter(status=TajweedCourseStatus.DRAFT):
            compile_course_version(version)
            self.message_user(request, f"{version}: пересобрана.", messages.SUCCESS)


@admin.register(TajweedCourseDocument)
class TajweedCourseDocumentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("version", "language", "bytes")
    list_filter = ("language",)
    readonly_fields = ("version", "language", "checksum_sha256", "bytes", "payload")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self, request: HttpRequest, obj: TajweedCourseDocument | None = None
    ) -> bool:
        return False if obj is not None else super().has_change_permission(request, obj)

    def has_delete_permission(
        self, request: HttpRequest, obj: TajweedCourseDocument | None = None
    ) -> bool:
        """A published or withdrawn version keeps its documents: the API serves them,
        and only a draft's are compiled again."""
        return super().has_delete_permission(request, obj) and (
            obj is None or obj.version.status == TajweedCourseStatus.DRAFT
        )


def _keep() -> None:
    """Nothing to do apart: a tajweed lesson's video lives in its block."""


def media_page(request: HttpRequest, version: TajweedCourseVersion, lesson: str) -> MediaPage:
    item = next(entry for entry in version.snapshot["lessons"] if entry["slug"] == lesson)
    return MediaPage(
        media=item.get("media") or [],
        has_video=lesson_video(item) is not None,
        languages=editor_languages(),
        action_url=reverse("admin:tajweed_tajweedcourseversion_media", args=[version.pk, lesson]),
        can_edit=editor_editable(request.user, version),
        video_html=render_to_string(
            "admin/courses/courselesson/video.html",
            {"block": video_block(request, version, lesson)},
            request=request,
        ),
        prefix="courses",
    )


def video_block(request: HttpRequest, version: TajweedCourseVersion, lesson: str) -> dict[str, Any]:
    """The lesson's video for the video block of thematic courses, which reads these names."""
    editable = editor_editable(request.user, version)
    item = next(entry for entry in version.snapshot["lessons"] if entry["slug"] == lesson)

    def video_url(operation: str) -> str:
        return reverse(
            "admin:tajweed_tajweedcourseversion_video", args=[version.pk, lesson, operation]
        )

    def dub_url(code: str, operation: str) -> str:
        return reverse(
            "admin:tajweed_tajweedcourseversion_dub", args=[version.pk, lesson, code, operation]
        )

    block: dict[str, Any] = {
        "instruction_url": VIDEO_INSTRUCTION_URL,
        "languages": SPOKEN_LANGUAGES,
        "max_video_mib": MAX_VIDEO_MIB,
        "max_dub_mib": MAX_DUB_MIB,
        "can_upload": editable,
        "upload_url": video_url("upload"),
        "video": None,
    }
    video = lesson_video(item)
    if video is None:
        return block
    poster = video["poster"]
    dubs = video["dubs"]
    block.update(
        {
            "video": {
                **video,
                "pk": video["sha256"],
                "poster_width": poster["width"],
                "poster_height": poster["height"],
            },
            "url": public_audio_url(video["object_key"]),
            "poster_url": public_audio_url(poster["small_object_key"]),
            "duration": clock(video["duration_ms"]),
            "size": megabytes(video["bytes"]),
            "fps": f"{video['fps']:g}".replace(".", ","),
            "speech": SPEECH_NAMES[video["spoken_language"]],
            "poster_second": min(3, video["duration_ms"] // 10_000),
            "last_second": max(0, video["duration_ms"] // 1000 - 1),
            "can_edit": editable,
            "can_remove": editable,
            "can_dub": editable,
            "can_delete_dub": editable,
            "poster_url_action": video_url("poster"),
            "language_url": video_url("language"),
            "remove_url": video_url("remove"),
            "dubs": [
                {
                    "code": code,
                    "label": LANGUAGE_NAMES[code],
                    "tab": TAB_LABELS[code],
                    "dub": dubs.get(code),
                    "url": public_audio_url(dubs[code]["object_key"]) if code in dubs else "",
                    "duration": clock(dubs[code]["duration_ms"]) if code in dubs else "",
                    "size": megabytes(dubs[code]["bytes"]) if code in dubs else "",
                    "upload_url": dub_url(code, "upload"),
                    "delete_url": dub_url(code, "delete"),
                }
                for code in editor_languages()
                if code != video["spoken_language"]
            ],
        }
    )
    return block


def _video_operation(
    request: HttpRequest,
    version: TajweedCourseVersion,
    lesson: str,
    operation: str,
    language: str,
) -> Callable[[], str]:
    """What a button of the video block does, as a change that names itself for the log."""
    post = request.POST
    video_id = post.get("video")

    def upload() -> str:
        with _received_file(request, MAX_VIDEO_MIB) as (uploaded, source):
            video = upload_video(
                version,
                lesson,
                source,
                spoken_language=str(post.get("spoken_language", "ru")),
                original_name=uploaded.name or "",
            )
        return f"видео «{video['original_name']}», {clock(video['duration_ms'])}"

    def poster() -> str:
        image = request.FILES.get("image")
        raw = str(post.get("second", "")).replace(",", ".").strip()
        try:
            second = float(raw) if raw else None
        except ValueError:
            second = None
        set_poster(version, lesson, video_id, second=second, image=image)
        return f"обложка из картинки «{image.name}»" if image else f"обложка — кадр на {raw} с"

    def speech() -> str:
        spoken = str(post.get("spoken_language", ""))
        set_spoken_language(version, lesson, video_id, spoken)
        return f"язык речи — {SPEECH_NAMES.get(spoken, spoken)}"

    def remove() -> str:
        remove_video(version, lesson, video_id)
        return "видео убрано"

    def dub() -> str:
        with _received_file(request, MAX_DUB_MIB) as (uploaded, source):
            upload_dub(
                version, lesson, video_id, language, source, original_name=uploaded.name or ""
            )
        return f"озвучка ({language})"

    def undub() -> str:
        delete_dub(version, lesson, video_id, language)
        return f"удалена озвучка ({language})"

    operations: dict[str, Callable[[], str]] = (
        {"upload": dub, "delete": undub}
        if language
        else {"upload": upload, "poster": poster, "language": speech, "remove": remove}
    )
    if operation not in operations:
        raise Http404
    return operations[operation]


def review_videos(version: TajweedCourseVersion, node_id: str) -> list[dict[str, Any]]:
    """Every new video and dub of the draft, each with its own «Просмотрено»."""
    new = new_videos(version)
    watched = set(version.watched_videos)
    found = []
    for lesson in version.snapshot.get("lessons", []):
        video = lesson_video(lesson)
        if video is None:
            continue
        name = f"Урок «{lesson['title'].get('ru') or lesson['slug']}»"
        files = [(video["sha256"], f"основное видео, {SPEECH_NAMES[video['spoken_language']]}", "")]
        files += [
            (dub["sha256"], f"озвучка, {LANGUAGE_NAMES[code]}", code)
            for code, dub in sorted(video["dubs"].items())
        ]
        for sha256, label, code in files:
            if sha256 not in new:
                continue
            payload = video_payload(video, code)
            assert payload is not None
            found.append(
                {
                    "name": f"{name}: {label}",
                    "sha256": sha256,
                    "url": payload["url"],
                    "poster_url": payload["poster"]["small_url"],
                    "duration": clock(payload["duration_ms"]),
                    "size": megabytes(payload["bytes"]),
                    "watched": sha256 in watched,
                    "mark_url": reverse(
                        "admin:tajweed_tajweedcourseversion_watched", args=[version.pk, sha256]
                    ),
                    "node": node_id,
                }
            )
    return found
