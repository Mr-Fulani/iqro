from __future__ import annotations

from django.urls import path

from quran_backend.modules.quran.api import (
    AyahDetailView,
    AyahListView,
    JuzListView,
    MushafPageDetailView,
    QuranEditionDetailView,
    QuranEditionListView,
    SurahDetailView,
    SurahListView,
)

app_name = "quran"

urlpatterns = [
    path("editions", QuranEditionListView.as_view(), name="edition-list"),
    path("editions/<slug:edition>", QuranEditionDetailView.as_view(), name="edition-detail"),
    path("editions/<slug:edition>/surahs", SurahListView.as_view(), name="surah-list"),
    path(
        "editions/<slug:edition>/surahs/<int:surah>",
        SurahDetailView.as_view(),
        name="surah-detail",
    ),
    path(
        "editions/<slug:edition>/surahs/<int:surah>/ayahs",
        AyahListView.as_view(),
        name="ayah-list",
    ),
    path(
        "editions/<slug:edition>/ayahs/<int:surah>/<int:ayah>",
        AyahDetailView.as_view(),
        name="ayah-detail",
    ),
    path(
        "editions/<slug:edition>/pages/<int:page>",
        MushafPageDetailView.as_view(),
        name="page-detail",
    ),
    path("editions/<slug:edition>/juz", JuzListView.as_view(), name="juz-list"),
]
