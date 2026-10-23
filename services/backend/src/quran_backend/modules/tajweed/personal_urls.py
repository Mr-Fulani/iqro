from __future__ import annotations

from django.urls import path

from quran_backend.modules.tajweed.personal_api import TajweedProgressView

urlpatterns = [
    path(
        "me/tajweed/progress/<slug:course>",
        TajweedProgressView.as_view(),
        name="tajweed-progress",
    ),
]
