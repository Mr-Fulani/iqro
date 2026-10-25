# Operator-facing text is intentionally Russian.
from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.core.exceptions import PermissionDenied
from django.db.models import QuerySet
from django.http import Http404, HttpRequest, HttpResponse
from django.template.response import TemplateResponse
from django.urls import reverse

from quran_backend.modules.course_feedback.analytics import course_report, period_days, summary
from quran_backend.modules.course_feedback.models import CourseAnalytics


@admin.register(CourseAnalytics)
class CourseAnalyticsAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """Read-only pages: the list is «Курсы: сводка», a course opens its «Аналитика»."""

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False

    def get_queryset(self, request: HttpRequest) -> QuerySet[CourseAnalytics]:
        return super().get_queryset(request).select_related("live_release")

    def _context(self, request: HttpRequest, title: str) -> dict[str, Any]:
        if not self.has_view_permission(request):
            raise PermissionDenied
        return {
            **self.admin_site.each_context(request),
            "opts": self.model._meta,
            "title": title,
            "summary_url": reverse("admin:course_feedback_courseanalytics_changelist"),
        }

    def changelist_view(
        self, request: HttpRequest, extra_context: dict[str, Any] | None = None
    ) -> HttpResponse:
        context = self._context(request, "Курсы: сводка")
        report = summary(period_days(request.GET.get("days")))
        for row in report["rows"]:
            row["url"] = reverse(
                "admin:course_feedback_courseanalytics_change", args=[row["course"].pk]
            )
        context.update(report=report, **(extra_context or {}))
        return TemplateResponse(request, "admin/course_feedback/summary.html", context)

    def change_view(
        self,
        request: HttpRequest,
        object_id: str,
        form_url: str = "",  # noqa: ARG002
        extra_context: dict[str, Any] | None = None,
    ) -> HttpResponse:
        course = self.get_object(request, object_id)
        if course is None:
            raise Http404
        context = self._context(request, f"Аналитика: {course}")
        context.update(
            course=course,
            report=course_report(course, period_days(request.GET.get("days"))),
            course_url=reverse("admin:courses_course_change", args=[course.pk]),
            reports_url=(
                reverse("admin:feedback_feedbackticket_changelist") + f"?course={course.slug}"
            ),
            **(extra_context or {}),
        )
        return TemplateResponse(request, "admin/course_feedback/analytics.html", context)
