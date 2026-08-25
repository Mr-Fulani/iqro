from __future__ import annotations

from typing import Any

import pytest
from django.core.exceptions import ValidationError

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioRenditionQuality,
    AudioTrack,
    RecitationPublicationStatus,
    RecitationStyle,
)
from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationEnvironment,
    QuranFoundationError,
)
from quran_backend.modules.audio.quran_foundation_importer import (
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)
from quran_backend.modules.quran.models import Ayah, QuranEdition, QuranEditionVersion, Surah


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


class StaleMetadataSizeClient(FakeQuranFoundationClient):
    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        payload = super().get_chapter_audio(reciter_id, chapter_number)
        payload["file_size"] = 999_999
        return payload


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


class WarshKidsRepeatClient(FakeQuranFoundationClient):
    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]:
        rows = super().list_chapter_reciters(language=language)
        rows[0]["style"] = {"name": "Kids repeat"}
        rows[0]["qirat"] = {"name": "Warsh"}
        return rows


class MissingQiratClient(FakeQuranFoundationClient):
    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]:
        rows = super().list_chapter_reciters(language=language)
        rows[0]["qirat"] = None
        return rows


def _alternate_quran_version(
    quran_dataset: dict[str, Any],
    *,
    code: str,
    riwayah: str,
) -> QuranEditionVersion:
    edition = QuranEdition.objects.create(
        code=code,
        name_ar="مصحف للاختبار",
        name_en=f"{riwayah} test Mushaf",
        name_ru=f"Тестовый мусхаф {riwayah}",
        riwayah=riwayah,
        source_name="Approved synthetic test source",
        license_name="Test license",
    )
    version = QuranEditionVersion.objects.create(
        edition=edition,
        version="1.0.0-test",
        checksum_sha256="c" * 64,
        page_count=604,
        surah_count=114,
        juz_count=30,
    )
    source_surah = quran_dataset["surah"]
    surah = Surah.objects.create(
        edition_version=version,
        number=source_surah.number,
        name_ar=source_surah.name_ar,
        name_en=source_surah.name_en,
        name_ru=source_surah.name_ru,
        revelation_type=source_surah.revelation_type,
        ayah_count=source_surah.ayah_count,
    )
    Ayah.objects.bulk_create(
        [
            Ayah(
                surah=surah,
                number=source.number,
                text_uthmani=source.text_uthmani,
                text_search=source.text_search,
                juz_number=source.juz_number,
                hizb_number=source.hizb_number,
                rub_el_hizb_number=source.rub_el_hizb_number,
            )
            for source in (quran_dataset["first_ayah"], quran_dataset["second_ayah"])
        ]
    )
    return version


def _warsh_version(quran_dataset: dict[str, Any]) -> QuranEditionVersion:
    return _alternate_quran_version(
        quran_dataset,
        code="madani-warsh-test",
        riwayah="Warsh 'an Nafi",
    )


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
    rendition = AudioRendition.objects.get(track=track)
    assert rendition.quality == AudioRenditionQuality.STANDARD
    assert rendition.is_default is True
    assert rendition.object_key is None
    assert rendition.checksum_sha256 == ""
    assert rendition.external_url.endswith("/qdc/test/murattal/1.mp3")
    assert track.segments.count() == 2


@pytest.mark.django_db
def test_external_audio_uses_observed_size_when_provider_metadata_is_stale(
    quran_dataset: dict[str, Any],
) -> None:
    prepared = prepare_quran_foundation_recitation(
        StaleMetadataSizeClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )

    assert prepared.tracks[0].size_bytes == 192_000


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

    with pytest.raises(ValidationError, match="External provider renditions"):
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


@pytest.mark.django_db
def test_imports_warsh_audio_only_for_a_warsh_quran_version(
    quran_dataset: dict[str, Any],
) -> None:
    warsh_version = _warsh_version(quran_dataset)
    prepared = prepare_quran_foundation_recitation(
        WarshKidsRepeatClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=warsh_version,
    )

    result = import_quran_foundation_recitation(
        prepared,
        quran_version=warsh_version,
        content_version="2026.08.25-warsh-test",
        environment_name="prelive",
        publish=False,
    )

    assert prepared.source_qirat == "Warsh"
    assert result.recitation.style == RecitationStyle.KIDS_REPEAT
    assert result.recitation.quran_edition_version == warsh_version
    assert "source qira'ah: Warsh" in result.recitation.license_attribution


@pytest.mark.django_db
def test_same_audio_source_can_target_two_quran_versions_without_code_collision(
    quran_dataset: dict[str, Any],
) -> None:
    second_hafs_version = _alternate_quran_version(
        quran_dataset,
        code="madani-hafs-second-test",
        riwayah="Hafs 'an Asim",
    )
    first_prepared = prepare_quran_foundation_recitation(
        FakeQuranFoundationClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )
    second_prepared = prepare_quran_foundation_recitation(
        FakeQuranFoundationClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=second_hafs_version,
    )

    first = import_quran_foundation_recitation(
        first_prepared,
        quran_version=quran_dataset["version"],
        content_version="2026.08.25-shared-source",
        environment_name="prelive",
        publish=False,
    )
    second = import_quran_foundation_recitation(
        second_prepared,
        quran_version=second_hafs_version,
        content_version="2026.08.25-shared-source",
        environment_name="prelive",
        publish=False,
    )

    assert first.recitation.code != second.recitation.code
    assert first.recitation.quran_edition_version == quran_dataset["version"]
    assert second.recitation.quran_edition_version == second_hafs_version


@pytest.mark.django_db
def test_rejects_warsh_audio_for_a_hafs_quran_version(
    quran_dataset: dict[str, Any],
) -> None:
    with pytest.raises(QuranFoundationError, match="incompatible"):
        prepare_quran_foundation_recitation(
            WarshKidsRepeatClient(),
            reciter_id=7,
            surah_numbers=[1],
            quran_version=quran_dataset["version"],
        )


@pytest.mark.django_db
def test_rechecks_riwayah_when_importing_a_prepared_recitation(
    quran_dataset: dict[str, Any],
) -> None:
    prepared = prepare_quran_foundation_recitation(
        WarshKidsRepeatClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=_warsh_version(quran_dataset),
    )

    with pytest.raises(QuranFoundationError, match="incompatible"):
        import_quran_foundation_recitation(
            prepared,
            quran_version=quran_dataset["version"],
            content_version="2026.08.25-invalid-pair",
            environment_name="prelive",
            publish=False,
        )


@pytest.mark.django_db
def test_rejects_audio_without_qirat_metadata(
    quran_dataset: dict[str, Any],
) -> None:
    with pytest.raises(QuranFoundationError, match="no qira'ah metadata"):
        prepare_quran_foundation_recitation(
            MissingQiratClient(),
            reciter_id=7,
            surah_numbers=[1],
            quran_version=quran_dataset["version"],
        )
