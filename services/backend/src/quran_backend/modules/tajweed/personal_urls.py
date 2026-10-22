from __future__ import annotations

from django.urls import path

from quran_backend.modules.tajweed.personal_api import (
    TajweedPracticeSessionView,
    TajweedPracticeStateView,
    TajweedProgressView,
)

urlpatterns = [
    path(
        "me/tajweed/progress/<slug:course>",
        TajweedProgressView.as_view(),
        name="tajweed-progress",
    ),
    path(
        "me/tajweed/practice/<slug:course>",
        TajweedPracticeStateView.as_view(),
        name="tajweed-practice",
    ),
    path(
        "me/tajweed/practice-sessions",
        TajweedPracticeSessionView.as_view(),
        name="tajweed-practice-sessions",
    ),
]
