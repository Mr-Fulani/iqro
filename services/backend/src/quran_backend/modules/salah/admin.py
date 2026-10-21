"""Admin of the prayer-learning course.

A version starts as a snapshot imported from git (`manage.py
import_salah_course`) or as a draft copied from another version here. The
owner edits a draft in the course editor (`editor_admin.py`): texts in every
language, «?» and «!» notes, recordings; uploads its illustrations, signs off
the religious content and publishes. Signed and published versions are
read-only.
"""

from __future__ import annotations

import logging
from typing import Any

from django.contrib import admin, messages
from django.contrib.admin.utils import unquote
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.db.models import QuerySet
from django.http import Http404, HttpRequest, HttpResponse, HttpResponseRedirect
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils.html import format_html, format_html_join

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.salah.editor_admin import (
    SalahEditorAdminMixin,
    editor_editable,
    readonly_reason,
)
from quran_backend.modules.salah.importer import (
    compile_version,
    publish_salah_version,
    sign_salah_version,
)
from quran_backend.modules.salah.media_upload import (
    IMAGE_SIDE,
    MAX_SOURCE_MIB,
    SalahMediaUploadError,
    image_keys,
    upload_salah_image,
)
from quran_backend.modules.salah.models import (
    SalahCompiledDocument,
    SalahCourse,
    SalahCourseVersion,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import SalahSnapshotError

logger = logging.getLogger(__name__)

RULING_LABELS = {"shart": "шарт", "rukn": "рукн", "wajib": "ваджиб", "sunnah": "сунна"}


@admin.register(SalahCourse)
class SalahCourseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("slug", "active_version")
    readonly_fields = ("slug", "active_version", "created_at", "updated_at")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False


@admin.register(SalahCourseVersion)
class SalahCourseVersionAdmin(SalahEditorAdminMixin, admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("__str__", "status", "signed", "published_at", "editor_link")
    list_filter = ("status", "course")
    actions = ("sign_versions", "publish_versions", "recompile_versions")
    change_form_template = "admin/salah/salahcourseversion/change_form.html"
    readonly_fields = (
        "course",
        "version",
        "status",
        "methodology",
        "source_title",
        "checksum_sha256",
        "reviewed_by",
        "reviewed_at",
        "review_note",
        "published_at",
        "illustrations",
        "documents_summary",
        "review_preview",
    )
    exclude = ("snapshot", "schema_version")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self, request: HttpRequest, obj: SalahCourseVersion | None = None
    ) -> bool:
        return False if obj is not None else super().has_change_permission(request, obj)

    def has_delete_permission(
        self, _request: HttpRequest, obj: SalahCourseVersion | None = None
    ) -> bool:
        return obj is None or obj.status == SalahPublicationStatus.DRAFT

    @admin.display(boolean=True, description="Подписана")
    def signed(self, obj: SalahCourseVersion) -> bool:
        return obj.is_signed

    @admin.display(description="Редактор")
    def editor_link(self, obj: SalahCourseVersion) -> str:
        label = "Редактировать" if obj.status == SalahPublicationStatus.DRAFT else "Открыть"
        return format_html(
            '<a href="{}">{}</a>',
            reverse("admin:salah_salahcourseversion_editor", args=[obj.pk]),
            label,
        )

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        """The way into the editor above the fields, and why a version is read-only."""
        version = self.get_object(request, unquote(object_id))
        context = dict(extra_context or {})
        if version is not None:
            context["salah_editor"] = {
                "url": reverse("admin:salah_salahcourseversion_editor", args=[version.pk]),
                "editable": editor_editable(request.user, version),
                "reason": readonly_reason(request.user, version),
                "copy_url": reverse("admin:salah_salahcourseversion_new_draft", args=[version.pk])
                if request.user.has_perm("salah.add_salahcourseversion")
                else "",
                "download_url": reverse(
                    "admin:salah_salahcourseversion_snapshot", args=[version.pk]
                ),
            }
        return super().change_view(request, object_id, form_url, context)

    @admin.display(description="Иллюстрации")
    def illustrations(self, obj: SalahCourseVersion) -> str:
        keys = {asset["key"] for asset in image_keys(obj)}
        uploaded = obj.media.filter(key__in=keys).count()
        return format_html(
            '{} из {} загружено. <a class="button" href="{}">Открыть иллюстрации</a>',
            uploaded,
            len(keys),
            reverse("admin:salah_salahcourseversion_media", args=[obj.pk]),
        )

    def get_urls(self) -> list[Any]:
        return [
            path(
                "<path:object_id>/media/",
                self.admin_site.admin_view(self.media_view),
                name="salah_salahcourseversion_media",
            ),
            *self.editor_urls(),
            *super().get_urls(),
        ]

    def media_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """One row per illustration of the snapshot: preview, alt text and upload."""
        version = self.get_object(request, unquote(object_id))
        if version is None:
            raise Http404
        if not request.user.has_perm("salah.view_salahcourseversion"):
            raise PermissionDenied
        editable = version.status == SalahPublicationStatus.DRAFT and request.user.has_perm(
            "salah.change_salahcourseversion"
        )
        if request.method == "POST":
            if not editable:
                raise PermissionDenied
            self._upload_image(request, version)
            return HttpResponseRedirect(request.path)
        stored = {asset.key: asset for asset in version.media.all()}
        rows = []
        for asset in image_keys(version):
            current = stored.get(str(asset["key"]))
            alt = asset.get("alt", {})
            rows.append(
                {
                    "key": asset["key"],
                    "alt": alt.get("ru", "") if isinstance(alt, dict) else "",
                    "url": public_audio_url(current.object_key) if current else "",
                    "kib": round(current.bytes / 1024) if current else None,
                }
            )
        return TemplateResponse(
            request,
            "admin/salah/salahcourseversion/media.html",
            {
                **self.admin_site.each_context(request),
                "opts": self.model._meta,
                "original": version,
                "title": f"Иллюстрации: {version}",
                "rows": rows,
                "editable": editable,
                "image_side": IMAGE_SIDE,
                "max_source_mib": MAX_SOURCE_MIB,
            },
        )

    def _upload_image(self, request: HttpRequest, version: SalahCourseVersion) -> None:
        key = str(request.POST.get("key") or "")
        uploaded = request.FILES.get("file")
        if uploaded is None:
            self.message_user(request, f"{key}: файл не выбран.", messages.ERROR)
            return
        try:
            asset = upload_salah_image(version, key, uploaded)
        except (SalahMediaUploadError, SalahFormulaError) as error:
            self.message_user(request, f"{key}: {error}", messages.ERROR)
        except ImproperlyConfigured, ObjectStorageError, OSError:
            logger.exception("Salah illustration upload failed")
            self.message_user(
                request,
                f"{key}: не удалось сохранить файл в хранилище. Повторите позже.",
                messages.ERROR,
            )
        else:
            self.log_change(request, version, f"Загружена иллюстрация {key}.")
            self.message_user(
                request,
                f"{key}: загружено, {round(asset.bytes / 1024)} КБ. Документы пересобраны.",
                messages.SUCCESS,
            )

    @admin.display(description="Документы по языкам")
    def documents_summary(self, obj: SalahCourseVersion) -> str:
        rows = [
            (document.language, f"{document.bytes / 1024:.0f} КБ")
            for document in obj.documents.all()
        ]
        return format_html_join(", ", "{}: {}", rows) or "—"

    @admin.display(description="Содержание курса для проверки (русский)")
    def review_preview(self, obj: SalahCourseVersion) -> str:
        """Every lesson and step as the learner sees it, for the religious sign-off."""
        document = obj.documents.filter(language="ru").first()
        if document is None:
            return "Документ не собран."
        payload: dict[str, Any] = document.payload
        formulas = payload.get("formulas", {})
        blocks = []
        for lesson in payload.get("lessons", []):
            steps = format_html_join(
                "",
                "<li><b>{}{}</b>{} — {}{}</li>",
                (
                    (
                        f"Ракаат {step['rakat']}: " if step.get("rakat") else "",
                        step["title"],
                        f" ({RULING_LABELS.get(step.get('ruling', ''), '')})"
                        if step.get("ruling")
                        else "",
                        step["instruction"],
                        format_html_join(
                            "",
                            '<div dir="rtl" lang="ar" style="font-size:20px;margin:4px 0">{}</div>',
                            ((formulas[formula_id]["arabic"],) for formula_id in step["formulas"]),
                        ),
                    )
                    for step in lesson["steps"]
                ),
            )
            blocks.append(format_html("<h3>{}</h3><ol>{}</ol>", lesson["title"], steps))
        return format_html_join("", "{}", ((block,) for block in blocks))

    @admin.action(description="Подписать: религиозная проверка пройдена")
    def sign_versions(self, request: HttpRequest, queryset: QuerySet[SalahCourseVersion]) -> None:
        for version in queryset.filter(status=SalahPublicationStatus.DRAFT):
            try:
                sign_salah_version(version, request.user)
            except (SalahSnapshotError, SalahFormulaError) as error:
                problems = list(dict.fromkeys(str(error).splitlines()))
                more = f" И ещё {len(problems) - 5}." if len(problems) > 5 else ""
                self.message_user(
                    request,
                    f"{version}: не подписана. {'; '.join(problems[:5])}.{more} "
                    "Откройте редактор: он покажет, что не переведено.",
                    messages.ERROR,
                )
            else:
                self.message_user(request, f"{version}: подписана.", messages.SUCCESS)

    @admin.action(description="Опубликовать")
    def publish_versions(
        self, request: HttpRequest, queryset: QuerySet[SalahCourseVersion]
    ) -> None:
        for version in queryset:
            try:
                publish_salah_version(version)
            except (SalahSnapshotError, SalahFormulaError) as error:
                self.message_user(request, f"{version}: {error}", messages.ERROR)
            else:
                self.message_user(request, f"{version}: опубликована.", messages.SUCCESS)

    @admin.action(description="Пересобрать документы")
    def recompile_versions(
        self, request: HttpRequest, queryset: QuerySet[SalahCourseVersion]
    ) -> None:
        for version in queryset.filter(status=SalahPublicationStatus.DRAFT):
            try:
                compile_version(version)
            except SalahFormulaError as error:
                self.message_user(request, f"{version}: {error}", messages.ERROR)
            else:
                self.message_user(request, f"{version}: пересобрана.", messages.SUCCESS)


@admin.register(SalahCompiledDocument)
class SalahCompiledDocumentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("version", "language", "bytes")
    list_filter = ("language",)
    readonly_fields = ("version", "language", "checksum_sha256", "bytes", "payload")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self, request: HttpRequest, obj: SalahCompiledDocument | None = None
    ) -> bool:
        return False if obj is not None else super().has_change_permission(request, obj)
