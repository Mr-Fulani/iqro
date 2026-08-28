from __future__ import annotations

from django.urls import path

from quran_backend.modules.translations.api import (
    SurahTranslationListView,
    TranslationEditionListView,
)

app_name = "translations"

urlpatterns = [
    path("translations", TranslationEditionListView.as_view(), name="edition-list"),
    path(
        "translations/<int:translation>/surahs/<int:surah>",
        SurahTranslationListView.as_view(),
        name="surah-list",
    ),
]
