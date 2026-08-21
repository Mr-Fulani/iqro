from __future__ import annotations

from typing import Any

import pytest
from django.core.exceptions import ValidationError

from quran_backend.modules.audio.models import AudioTrack, RecitationPublicationStatus
from quran_backend.modules.audio.quran_foundation import QuranFoundationEnvironment
from quran_backend.modules.audio.quran_foundation_importer import (
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)


class FakeQuranFoundationClient:
    environment = QuranFoundationEnvironment(
        name="prelive",
        oauth_base_url="https://prelive-oauth2.quran.foundation",
        api_base_url="https://apis-prelive.quran.foundation",
    )

    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]:
        names = {"en": "Test Reciter", "ar": "قارئ الاختبار", "ru": "Тестовый чтец"}
        return [
            {
                "id": 7,
                "name": "Test Reciter",
                "translated_name": {"name": names[language]},
                "style": {"name": "Murattal"},
                "qirat": {"name": "Hafs"},
            }
        ]

    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        assert reciter_id == 7
        assert chapter_number == 1
        return {
            "id": 911,
            "chapter_id": 1,
            "file_size": 192_000,
            "format": "",
            "audio_url": "https://download.quranicaudio.com/qdc/test/murattal/1.mp3",
            "timestamps": [
                {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 5_000},
                {"verse_key": "1:2", "timestamp_from": 5_000, "timestamp_to": 10_000},
            ],
        }

    def get_external_audio_size(self, url: str) -> int:
        assert url.startswith("https://download.quranicaudio.com/")
        return 192_000


class OverlappingAyahClient(FakeQuranFoundationClient):
    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        payload = super().get_chapter_audio(reciter_id, chapter_number)
        payload["timestamps"] = [
            {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 6_000},
            {"verse_key": "1:2", "timestamp_from": 5_000, "timestamp_to": 10_000},
        ]
        return payload


class MultiFormatClient(FakeQuranFoundationClient):
    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        payload = super().get_chapter_audio(reciter_id, chapter_number)
        payload["format"] = "mp3,opus"
        return payload


@pytest.mark.django_db
def test_imports_external_quran_foundation_audio_as_streaming_only(
    quran_dataset: dict[str, Any],
) -> None:
    client = FakeQuranFoundationClient()
    prepared = prepare_quran_foundation_recitation(
        client,
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )

    result = import_quran_foundation_recitation(
        prepared,
        quran_version=quran_dataset["version"],
        content_version="2026.08.21-prelive",
        environment_name="prelive",
        publish=True,
    )

    assert result.created is True
    assert result.recitation.status == RecitationPublicationStatus.PUBLISHED
    assert result.recitation.stream_allowed is True
    assert result.recitation.offline_download_allowed is False
    track = AudioTrack.objects.get(recitation_edition=result.recitation)
    assert track.object_key is None
    assert track.checksum_sha256 == ""
    assert track.external_url.endswith("/qdc/test/murattal/1.mp3")
    assert track.segments.count() == 2


@pytest.mark.django_db
def test_external_audio_cannot_be_published_for_offline_download(
    quran_dataset: dict[str, Any],
) -> None:
    client = FakeQuranFoundationClient()
    prepared = prepare_quran_foundation_recitation(
        client,
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )
    result = import_quran_foundation_recitation(
        prepared,
        quran_version=quran_dataset["version"],
        content_version="2026.08.21-draft",
        environment_name="prelive",
        publish=False,
    )
    result.recitation.offline_download_allowed = True
    result.recitation.publish()

    with pytest.raises(ValidationError, match="External provider tracks"):
        result.recitation.save()


@pytest.mark.django_db
def test_normalizes_ordered_quran_foundation_ayah_ranges_that_overlap(
    quran_dataset: dict[str, Any],
) -> None:
    prepared = prepare_quran_foundation_recitation(
        OverlappingAyahClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )

    assert [(segment.start_ms, segment.end_ms) for segment in prepared.tracks[0].segments] == [
        (0, 5_000),
        (5_000, 10_000),
    ]


@pytest.mark.django_db
def test_accepts_mp3_when_quran_foundation_advertises_multiple_formats(
    quran_dataset: dict[str, Any],
) -> None:
    prepared = prepare_quran_foundation_recitation(
        MultiFormatClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )

    assert prepared.tracks[0].external_url.endswith(".mp3")
