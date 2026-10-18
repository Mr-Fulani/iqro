"""Admin of the prayer-learning course.

Content is edited as a snapshot in git and imported with
`manage.py import_salah_course`; here the owner reads the compiled course,
signs off the religious content and publishes. Versions are read-only.
"""

from __future__ import annotations

from typing import Any

from django.contrib import admin, messages
from django.db.models import QuerySet
from django.http import HttpRequest
from django.utils.html import format_html, format_html_join

from quran_backend.modules.salah.importer import compile_version, publish_salah_version
from quran_backend.modules.salah.models import (
    SalahCompiledDocument,
    SalahCourse,
    SalahCourseVersion,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import SalahSnapshotError

RULING_LABELS = {"rukn": "ркн", "wajib": "ваджиб", "sunnah": "сунна"}


@admin.register(SalahCourse)
class SalahCourseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("slug", "active_version")
    readonly_fields = ("slug", "active_version", "created_at", "updated_at")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False


@admin.register(SalahCourseVersion)
class SalahCourseVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("__str__", "status", "signed", "published_at")
    list_filter = ("status", "course")
    actions = ("sign_versions", "publish_versions", "recompile_versions")
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
            version.sign(request.user)
            compile_version(version)
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
