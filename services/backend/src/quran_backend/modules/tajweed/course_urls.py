from __future__ import annotations

from django.urls import path

from quran_backend.modules.tajweed.course_api import (
    TajweedCourseDocumentView,
    TajweedCourseListView,
    TajweedLessonExamplesView,
    TajweedPracticeView,
)

urlpatterns = [
    path("courses", TajweedCourseListView.as_view(), name="tajweed-courses"),
    path("courses/<slug:slug>", TajweedCourseDocumentView.as_view(), name="tajweed-course"),
    path(
        "courses/<slug:slug>/lessons/<slug:lesson>/examples",
        TajweedLessonExamplesView.as_view(),
        name="tajweed-lesson-examples",
    ),
    path(
        "courses/<slug:slug>/practice", TajweedPracticeView.as_view(), name="tajweed-practice-tasks"
    ),
]
