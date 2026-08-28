from __future__ import annotations

from django.urls import path

from quran_backend.modules.tafsirs.api import SurahTafsirListView, TafsirEditionListView

app_name = "tafsirs"

urlpatterns = [
    path("tafsirs", TafsirEditionListView.as_view(), name="edition-list"),
    path(
        "tafsirs/<int:tafsir>/surahs/<int:surah>",
        SurahTafsirListView.as_view(),
        name="surah-list",
    ),
]
