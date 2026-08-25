from __future__ import annotations

from typing import Any

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from quran_backend.modules.audio.models import (
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
)
from quran_backend.modules.audio.quran_foundation import ENVIRONMENTS
from quran_backend.modules.audio.quran_foundation_ayah_sync import (
    sync_quran_foundation_ayah_recitations,
)
from quran_backend.modules.quran.models import Ayah, RevelationType, Surah


class FakeAyahAudioClient:
    environment = ENVIRONMENTS["production"]

    def __init__(self, verse_keys: list[str], *, incomplete: bool = False) -> None:
        self.verse_keys = verse_keys[:-1] if incomplete else verse_keys
        self.delivery_urls: list[str] = []

    def list_ayah_recitations(self, *, language: str = "en") -> list[dict[str, Any]]:
        names = {
            "en": "Test Ayah Reciter",
            "ar": "قارئ الآيات",
            "ru": "Чтец аятов",
        }
        return [
            {
                "id": 8,
                "reciter_name": "Test Ayah Reciter",
                "translated_name": {"name": names[language]},
                "style": "Mujawwad",
            }
        ]

    def get_ayah_recitation_audio(self, recitation_id: int) -> dict[str, Any]:
        assert recitation_id == 8
        return {
            "audio_files": [
                {
                    "verse_key": verse_key,
                    "url": f"Test/Mujawwad/mp3/{verse_key.replace(':', '')}.mp3",
                }
                for verse_key in self.verse_keys
            ],
            "meta": {"reciter_name": "Test Ayah Reciter"},
        }

    def normalize_ayah_audio_url(self, value: object) -> str:
        assert isinstance(value, str)
        return f"https://verses.quran.foundation/{value}"

    def get_external_ayah_audio_size(self, url: str) -> int:
        self.delivery_urls.append(url)
        return 12_345


def _complete_test_quran(quran_dataset: dict[str, Any]) -> list[str]:
    version = quran_dataset["version"]
    surahs = Surah.objects.bulk_create(
        [
            Surah(
                edition_version=version,
                number=number,
                name_ar=f"سورة {number}",
                name_en=f"Surah {number}",
                name_ru=f"Surah {number}",
                revelation_type=RevelationType.MECCAN,
                ayah_count=1,
            )
            for number in range(2, 115)
        ]
    )
    Ayah.objects.bulk_create(
        [
            Ayah(
                surah=surah,
                number=1,
                text_uthmani="ن",
                text_search="ن",
                juz_number=1,
                hizb_number=1,
                rub_el_hizb_number=1,
            )
            for surah in surahs
        ]
    )
    return [
        f"{surah_number}:{ayah_number}"
        for surah_number, ayah_number in Ayah.objects.filter(
            surah__edition_version=version,
        )
        .order_by("surah__number", "number")
        .values_list("surah__number", "number")
    ]


@pytest.mark.django_db
def test_sync_caches_complete_ayah_audio_catalog_and_is_idempotent(
    quran_dataset: dict[str, Any],
) -> None:
    verse_keys = _complete_test_quran(quran_dataset)
    client = FakeAyahAudioClient(verse_keys)

    first = sync_quran_foundation_ayah_recitations(
        quran_version=quran_dataset["version"],
        client=client,
    )
    second = sync_quran_foundation_ayah_recitations(
        quran_version=quran_dataset["version"],
        client=client,
    )

    assert first.selected == 1
    assert first.available == 1
    assert first.created == 1
    assert first.chapters == 114
    assert first.audio_files == len(verse_keys)
    assert first.delivery_samples == 2
    assert second.unchanged == 1
    assert QuranFoundationAyahRecitation.objects.get(source_id=8).name_ru == "Чтец аятов"
    chapter = QuranFoundationAyahRecitationChapter.objects.get(chapter_number=1)
    assert [row["verse_key"] for row in chapter.audio_files] == ["1:1", "1:2"]
    assert len(client.delivery_urls) == 4


@pytest.mark.django_db
def test_incomplete_refresh_hides_previous_ayah_catalog(
    quran_dataset: dict[str, Any],
) -> None:
    verse_keys = _complete_test_quran(quran_dataset)
    sync_quran_foundation_ayah_recitations(
        quran_version=quran_dataset["version"],
        client=FakeAyahAudioClient(verse_keys),
    )

    result = sync_quran_foundation_ayah_recitations(
        quran_version=quran_dataset["version"],
        client=FakeAyahAudioClient(verse_keys, incomplete=True),
    )

    assert result.available == 0
    assert result.failures[0][0] == 8
    assert "incomplete" in result.failures[0][1]
    assert QuranFoundationAyahRecitation.objects.get(source_id=8).is_available is False


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_public_ayah_recitation_catalog_and_chapter_api(
    quran_dataset: dict[str, Any],
    api_client: APIClient,
) -> None:
    verse_keys = _complete_test_quran(quran_dataset)
    sync_quran_foundation_ayah_recitations(
        quran_version=quran_dataset["version"],
        client=FakeAyahAudioClient(verse_keys),
    )

    catalog = api_client.get("/api/v1/quran-foundation/ayah-recitations")
    chapter = api_client.get("/api/v1/quran-foundation/ayah-recitations/8/surahs/1")

    assert catalog.status_code == 200
    assert catalog.json()[0]["source_id"] == 8
    assert catalog.json()[0]["coverage"] == {
        "chapter_count": 114,
        "audio_file_count": len(verse_keys),
        "complete": True,
    }
    assert catalog.json()[0]["rights"] == {"stream": True, "offline_download": False}
    assert chapter.status_code == 200
    assert chapter.json()["ayah_count"] == 2
    assert chapter.json()["audio_files"][0]["url"].startswith("https://verses.quran.foundation/")
