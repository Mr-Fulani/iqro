from __future__ import annotations

from django.urls import path

from quran_backend.modules.courses.personal_api import CourseProgressView

urlpatterns = [
    path(
        "me/courses/progress/<slug:kind>/<slug:course>",
        CourseProgressView.as_view(),
        name="courses-progress",
    ),
]
