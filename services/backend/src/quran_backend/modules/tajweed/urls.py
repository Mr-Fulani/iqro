from __future__ import annotations

from django.urls import path

from quran_backend.modules.tajweed.api import (
    TajweedAyahView,
    TajweedPageView,
    TajweedRuleListView,
)

app_name = "tajweed"

urlpatterns = [
    path("tajweed/rules", TajweedRuleListView.as_view(), name="rule-list"),
    path("tajweed/pages/<int:page>", TajweedPageView.as_view(), name="page-detail"),
    path(
        "tajweed/surahs/<int:surah>/ayahs/<int:ayah>",
        TajweedAyahView.as_view(),
        name="ayah-detail",
    ),
]
