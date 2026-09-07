from __future__ import annotations

from django.urls import path

from quran_backend.modules.quran.api import (
    AyahDetailView,
    AyahListView,
    HizbListView,
    JuzListView,
    MushafPageDetailView,
    QuranEditionDetailView,
    QuranEditionListView,
    QuranEditionMushafOfflineManifestView,
    QuranFoundationMushafListView,
    QuranFoundationMushafOfflineManifestView,
    QuranFoundationMushafPageDetailView,
    RubElHizbListView,
    SurahDetailView,
    SurahListView,
)
from quran_backend.modules.quran.rendition_api import (
    MushafRenditionListView,
    MushafRenditionOfflineView,
    MushafRenditionPageView,
)

app_name = "quran"

urlpatterns = [
    path("mushaf-renditions", MushafRenditionListView.as_view(), name="rendition-list"),
    path("mushaf-renditions/<slug:code>/pages/<int:page>",
         MushafRenditionPageView.as_view(), name="rendition-page"),
    path("mushaf-renditions/<slug:code>/offline-manifest",
         MushafRenditionOfflineView.as_view(), name="rendition-offline"),
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
    path(
        "editions/<slug:edition>/offline-manifest",
        QuranEditionMushafOfflineManifestView.as_view(),
        name="edition-offline-manifest",
    ),
    path(
        "foundation/mushafs",
        QuranFoundationMushafListView.as_view(),
        name="quran-foundation-mushaf-list",
    ),
    path(
        "foundation/mushafs/<int:mushaf>/pages/<int:page>",
        QuranFoundationMushafPageDetailView.as_view(),
        name="quran-foundation-mushaf-page-detail",
    ),
    path(
        "foundation/mushafs/<int:mushaf>/offline-manifest",
        QuranFoundationMushafOfflineManifestView.as_view(),
        name="quran-foundation-mushaf-offline-manifest",
    ),
    path("editions/<slug:edition>/juz", JuzListView.as_view(), name="juz-list"),
    path("editions/<slug:edition>/hizb", HizbListView.as_view(), name="hizb-list"),
    path(
        "editions/<slug:edition>/rub-el-hizb",
        RubElHizbListView.as_view(),
        name="rub-el-hizb-list",
    ),
]
