from __future__ import annotations

from django.urls import path

from quran_backend.modules.audio.api import (
    AudioTrackListView,
    AyahPlaybackView,
    RecitationDetailView,
    RecitationListView,
    ReciterDetailView,
    ReciterListView,
    SurahPlaybackView,
)

app_name = "audio"

urlpatterns = [
    path("reciters", ReciterListView.as_view(), name="reciter-list"),
    path("reciters/<uuid:reciter_id>", ReciterDetailView.as_view(), name="reciter-detail"),
    path("recitations", RecitationListView.as_view(), name="recitation-list"),
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
