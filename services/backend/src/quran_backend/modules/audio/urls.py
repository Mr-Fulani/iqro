from __future__ import annotations

from django.urls import path

from quran_backend.modules.audio.api import (
    AudioOfflineManifestView,
    AudioTrackListView,
    AyahPlaybackView,
    QuranFoundationAyahRecitationChapterView,
    QuranFoundationAyahRecitationListView,
    RecitationDetailView,
    RecitationListView,
    ReciterDetailView,
    ReciterListView,
    SurahPlaybackView,
)
from quran_backend.modules.audio.playback_position_api import AudioPlaybackPositionView

app_name = "audio"

urlpatterns = [
    path(
        "me/audio-playback-position",
        AudioPlaybackPositionView.as_view(),
        name="playback-position",
    ),
    path("reciters", ReciterListView.as_view(), name="reciter-list"),
    path("reciters/<uuid:reciter_id>", ReciterDetailView.as_view(), name="reciter-detail"),
    path("recitations", RecitationListView.as_view(), name="recitation-list"),
    path(
        "quran-foundation/ayah-recitations",
        QuranFoundationAyahRecitationListView.as_view(),
        name="quran-foundation-ayah-recitation-list",
    ),
    path(
        "quran-foundation/ayah-recitations/<int:recitation>/surahs/<int:surah>",
        QuranFoundationAyahRecitationChapterView.as_view(),
        name="quran-foundation-ayah-recitation-chapter",
    ),
    path(
        "recitations/<uuid:recitation_id>",
        RecitationDetailView.as_view(),
        name="recitation-detail",
    ),
    path(
        "recitations/<uuid:recitation_id>/tracks",
        AudioTrackListView.as_view(),
        name="track-list",
    ),
    path(
        "recitations/<uuid:recitation_id>/offline-manifest",
        AudioOfflineManifestView.as_view(),
        name="offline-manifest",
    ),
    path(
        "recitations/<uuid:recitation_id>/surahs/<int:surah>",
        SurahPlaybackView.as_view(),
        name="surah-playback",
    ),
    path(
        "recitations/<uuid:recitation_id>/ayahs/<int:surah>/<int:ayah>",
        AyahPlaybackView.as_view(),
        name="ayah-playback",
    ),
]
