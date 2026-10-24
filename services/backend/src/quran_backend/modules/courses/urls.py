from __future__ import annotations

from django.urls import path

from quran_backend.modules.courses.api import CourseDocumentView, CourseListView

app_name = "courses"

urlpatterns = [
    path("courses", CourseListView.as_view(), name="list"),
    path("courses/<slug:slug>", CourseDocumentView.as_view(), name="detail"),
]
