from __future__ import annotations

from django.urls import path

from quran_backend.modules.salah.api import (
    SalahCourseDocumentView,
    SalahCourseListView,
    SalahOfflineManifestView,
)

urlpatterns = [
    path("courses", SalahCourseListView.as_view(), name="salah-courses"),
    path("courses/<slug:slug>", SalahCourseDocumentView.as_view(), name="salah-course"),
    path(
        "courses/<slug:slug>/offline-manifest",
        SalahOfflineManifestView.as_view(),
        name="salah-course-offline-manifest",
    ),
]
