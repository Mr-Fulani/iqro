# ruff: noqa: RUF001 -- Admin messages intentionally use Cyrillic characters.

from __future__ import annotations

import json
from io import StringIO
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib.messages import get_messages
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.management import CommandError, call_command
from django.test import Client
from django.urls import reverse
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioRendition,
    AudioRenditionQuality,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    Reciter,
)
from quran_backend.modules.audio.mp3quran_timings import (
    TIMING_SOURCE_NAME,
    Mp3QuranTimingError,
    RemoteAudio,
    find_timing_read,
    import_mp3quran_timings,
    mp3quran_folder,
    prepare_mp3quran_timings,
)
from quran_backend.modules.quran.models import Ayah, RevelationType, Surah

FIXTURES = Path(__file__).parent / "fixtures" / "mp3quran"
FOLDER = "https://cdn.mp3quran.net/audio/idrees-abkar/r1/"
# Sizes and content MD5s the MP3Quran CDN serves for these two files.
REAL_FILES = {
    1: (659_676, "e98b742c9da782efce876027e78d8cc6"),
    36: (17_004_971, "7b37ef4389749f1c38cd007a987b97bf"),
    112: (247_338, "4f08969a44e880ccba3c8ba905129410"),
}
REAL_DURATIONS_MS = {1: 40_803, 36: 1_060_130, 112: 15_020}


def _fixture(name: str) -> Any:
    return json.loads((FIXTURES / name).read_text())


def _size(surah: int) -> int:
    return REAL_FILES.get(surah, (1_000_000 + surah, ""))[0]


def _md5(surah: int) -> str:
    return REAL_FILES.get(surah, (0, f"{surah:032x}"))[1]


class FakeMp3Quran:
    """The MP3Quran API as recorded for Idris Abkar (read 12), without the network."""

    def __init__(self, **overrides: Any) -> None:
        self.sizes: dict[int, int] = overrides.get("sizes", {})
        self.md5s: dict[int, str | None] = overrides.get("md5s", {})
        self.timings: dict[int, list[dict[str, Any]]] = overrides.get("timings", {})
        self.reads: list[dict[str, Any]] = overrides.get(
            "reads", _fixture("ayat_timing_reads.json")
        )

    def timing_reads(self) -> list[dict[str, Any]]:
        return self.reads

    def surah_timings(self, read_id: int, surah_number: int) -> list[dict[str, Any]]:
        assert read_id == 12
        if surah_number in self.timings:
            return self.timings[surah_number]
        recorded = FIXTURES / f"ayat_timing_read12_surah{surah_number:03d}.json"
        if recorded.exists():
            return _fixture(recorded.name)
        # Surahs the test corpus holds with a single ayah.
        return [{"ayah": 1, "start_time": 4000, "end_time": 9000, "page": "x"}]

    def audio_head(self, url: str) -> RemoteAudio:
        surah = int(url.removeprefix(FOLDER).removesuffix(".mp3"))
        return RemoteAudio(
            size_bytes=self.sizes.get(surah, _size(surah)),
            md5=self.md5s.get(surah, _md5(surah)),
        )


@pytest.fixture(autouse=True)
def _clear_cache() -> None:
    cache.clear()


@pytest.fixture
def full_quran(quran_dataset: dict[str, Any]) -> dict[str, Any]:
    """Al-Fatihah with its 7 ayahs, Al-Ikhlas with 4, every other surah with one."""
    version = quran_dataset["version"]
    fatiha = Surah.objects.get(edition_version=version, number=1)
    fatiha.ayah_count = 7
    fatiha.save(update_fields=["ayah_count"])
    for number in range(3, 8):
        _ayah(fatiha, number)
    for number in range(2, 115):
        surah = Surah.objects.create(
            edition_version=version,
            number=number,
            name_ar=f"سورة {number}",
            name_en=f"Surah {number}",
            name_ru=f"Сура {number}",
            revelation_type=RevelationType.MECCAN,
            ayah_count=4 if number == 112 else 1,
        )
        for ayah_number in range(1, surah.ayah_count + 1):
            _ayah(surah, ayah_number)
    return quran_dataset


def _ayah(surah: Surah, number: int) -> Ayah:
    return Ayah.objects.create(
        surah=surah,
        number=number,
        text_uthmani="آية",
        text_search="ايه",
        juz_number=1,
        hizb_number=1,
        rub_el_hizb_number=1,
    )


def _recitation(
    dataset: dict[str, Any],
    *,
    source_url: str = FOLDER,
    surahs: range | tuple[int, ...] = range(1, 115),
    external: bool = False,
) -> RecitationEdition:
    recitation = RecitationEdition.objects.create(
        code="idris-abkar-murattal",
        version="1",
        reciter=Reciter.objects.create(
            code="idris-abkar", name_ar="إدريس أبكر", name_en="Idris Abkar", name_ru="Идрис Абкар"
        ),
        quran_edition_version=dataset["version"],
        source_name="Загружено редактором IQRO",
        source_url=source_url,
        source_version="1",
        source_checksum_sha256="c" * 64,
        rights_holder="MP3Quran",
        license_name="Permission",
    )
    for surah in surahs:
        track = AudioTrack.objects.create(
            recitation_edition=recitation,
            scope=AudioTrackScope.SURAH,
            surah_number=surah,
            duration_ms=REAL_DURATIONS_MS.get(surah, 60_000),
        )
        delivery: dict[str, Any] = (
            {"external_url": f"{FOLDER}{surah:03d}.mp3"}
            if external
            else {
                "object_key": f"audio/recitations/idris/1/surah-{surah:03d}.mp3",
                "checksum_sha256": f"{surah:064x}",
                "origin_etag": f'"{_md5(surah)}"',
                "etag": f'"{_md5(surah)}"',
                "cdn_contract_verified_at": timezone.now(),
            }
        )
        AudioRendition.objects.create(
            track=track,
            quality=AudioRenditionQuality.STANDARD,
            is_default=True,
            codec=AudioCodec.MP3,
            content_type=AudioContentType.MPEG,
            bitrate_kbps=128,
            size_bytes=_size(surah),
            **delivery,
        )
    recitation.stream_allowed = True
    recitation.offline_download_allowed = False
    recitation.publish()
    recitation.save()
    return recitation


@pytest.fixture
def idris(full_quran: dict[str, Any]) -> RecitationEdition:
    return _recitation(full_quran)


def test_folder_and_read_are_found_from_the_source_url(idris: RecitationEdition) -> None:
    idris.source_url = FOLDER.rstrip("/")
    assert mp3quran_folder(idris) == FOLDER
    idris.source_url = "https://example.com/audio/idrees-abkar/r1/"
    assert mp3quran_folder(idris) is None

    read = find_timing_read(_fixture("ayat_timing_reads.json"), FOLDER)
    assert read is not None
    assert (read.read_id, read.rewaya) == (12, "حفص عن عاصم")
    assert find_timing_read(_fixture("ayat_timing_reads.json"), f"{FOLDER}x/") is None


def test_published_recitation_gains_timings_and_plays_in_the_mushaf(
    api_client: Any,
    idris: RecitationEdition,
) -> None:
    detail = reverse("audio:recitation-detail", args=[idris.pk])
    before = api_client.get(detail).json()
    assert before["coverage"]["timings_complete"] is False
    assert before["capabilities"]["ayah_playback"] is False
    track_ids = set(idris.tracks.values_list("id", flat=True))

    result = import_mp3quran_timings(prepare_mp3quran_timings(idris, FakeMp3Quran()))

    assert (result.surah_count, result.ayah_count) == (114, 7 + 4 + 112)
    timing = result.timing_version
    assert (timing.version, timing.source_name) == ("mp3quran-12", TIMING_SOURCE_NAME)
    assert timing.verified_at is not None
    # The same tracks and files keep playing; only the timeline is new.
    assert set(idris.tracks.values_list("id", flat=True)) == track_ids
    cache.clear()
    after = api_client.get(detail).json()
    assert after["coverage"]["timed_ayahs"] == after["coverage"]["expected_ayahs"] == 123
    assert after["coverage"]["timings_complete"] is True
    assert after["capabilities"]["ayah_playback"] is True
    assert after["capabilities"]["memorization"] is True

    fatiha = api_client.get(reverse("audio:surah-playback", args=[idris.pk, 1])).json()
    # Ayah 1 starts the file (MP3Quran has it at 300 ms), as Quran.Foundation's timings do.
    assert [(row["start_ms"], row["end_ms"]) for row in fatiha["segments"]][:2] == [
        (0, 3300),
        (3300, 6740),
    ]
    assert len(fatiha["segments"]) == 7
    baqarah = api_client.get(reverse("audio:surah-playback", args=[idris.pk, 2])).json()
    assert baqarah["segments"][0]["start_ms"] == 0


def test_import_refuses_files_of_a_different_size(idris: RecitationEdition) -> None:
    source = FakeMp3Quran(sizes={2: 123})

    with pytest.raises(
        Mp3QuranTimingError,
        match=r"сура 2: наш файл не тот, что у MP3Quran \(размер у нас 1000002 байт",
    ):
        prepare_mp3quran_timings(idris, source)
    assert not AudioTimingVersion.objects.exists()


def test_import_refuses_files_with_other_content(idris: RecitationEdition) -> None:
    source = FakeMp3Quran(md5s={112: "0" * 32})

    with pytest.raises(
        Mp3QuranTimingError, match="сура 112: наш файл не тот, что у MP3Quran \\(размер тот же"
    ):
        prepare_mp3quran_timings(idris, source)


def test_size_alone_is_enough_when_the_cdn_hides_the_md5(idris: RecitationEdition) -> None:
    prepared = prepare_mp3quran_timings(idris, FakeMp3Quran(md5s={1: None, 112: None}))

    assert len(prepared.tracks) == 114


def test_external_audio_must_come_from_the_same_folder(full_quran: dict[str, Any]) -> None:
    recitation = _recitation(full_quran, external=True)
    rendition = AudioRendition.objects.get(track__surah_number=5)
    AudioRendition.objects.filter(pk=rendition.pk).update(
        external_url="https://cdn.mp3quran.net/audio/other/r1/005.mp3"
    )

    with pytest.raises(Mp3QuranTimingError, match="сура 5: файл берётся не из папки MP3Quran"):
        prepare_mp3quran_timings(recitation, FakeMp3Quran())


def test_pauses_between_ayahs_join_the_ayah_before(idris: RecitationEdition) -> None:
    ikhlas = [
        {"ayah": 1, "start_time": 3969, "end_time": 6406},
        {"ayah": 2, "start_time": 6426, "end_time": 8778},
        {"ayah": 3, "start_time": 8778, "end_time": 11613},
        {"ayah": 4, "start_time": 11633, "end_time": 15498},
    ]
    prepared = prepare_mp3quran_timings(idris, FakeMp3Quran(timings={112: ikhlas}))

    track = next(item for item in prepared.tracks if item.surah_number == 112)
    assert [(item.start_ms, item.end_ms) for item in track.segments] == [
        (0, 6426),
        (6426, 8778),
        (8778, 11633),
        # MP3Quran ends Al-Ikhlas 478 ms past the file's measured end.
        (11633, REAL_DURATIONS_MS[112]),
    ]


def test_ya_sin_timed_on_another_recording_stops_the_import(idris: RecitationEdition) -> None:
    # Recorded 2026-10-25: Idris Abkar's 036.mp3 at MP3Quran lasts 1060 s, while its
    # Ya-Sin timings run to 1129 s and fit the file's pauses nowhere consistently.
    ya_sin = Surah.objects.get(edition_version=idris.quran_edition_version, number=36)
    ya_sin.ayah_count = 83
    ya_sin.save(update_fields=["ayah_count"])
    for number in range(2, 84):
        _ayah(ya_sin, number)
    source = FakeMp3Quran(timings={36: _fixture("ya_sin_read12_other_recording.json")})

    with pytest.raises(Mp3QuranTimingError) as error:
        prepare_mp3quran_timings(idris, source)

    assert str(error.value) == (
        "Таймкоды не добавлены, запись не изменилась. Таймкоды MP3Quran верны только для "
        "его же файлов, а здесь есть расхождения: сура 36: таймкоды MP3Quran не подходят к "
        "файлу — последний аят кончается на 1129 с, а файл длится 1060 с (MP3Quran, видимо, "
        "размечал другую запись этой суры)."
    )


def test_last_ayah_slightly_past_the_file_end_is_clamped(idris: RecitationEdition) -> None:
    ikhlas = _fixture("ayat_timing_read12_surah112.json")
    ikhlas[-1]["end_time"] = REAL_DURATIONS_MS[112] + 900
    prepared = prepare_mp3quran_timings(idris, FakeMp3Quran(timings={112: ikhlas}))

    track = next(item for item in prepared.tracks if item.surah_number == 112)
    assert track.segments[-1].end_ms == REAL_DURATIONS_MS[112]

    ikhlas[-1]["end_time"] = REAL_DURATIONS_MS[112] + 30_000
    with pytest.raises(
        Mp3QuranTimingError, match="сура 112: таймкоды MP3Quran не подходят к файлу"
    ):
        prepare_mp3quran_timings(idris, FakeMp3Quran(timings={112: ikhlas}))


def test_timings_must_cover_every_ayah_of_our_edition(idris: RecitationEdition) -> None:
    fatiha = _fixture("ayat_timing_read12_surah001.json")[:6]

    with pytest.raises(Mp3QuranTimingError, match="сура 1: таймкоды MP3Quran не ложатся"):
        prepare_mp3quran_timings(idris, FakeMp3Quran(timings={1: fatiha}))


def test_import_needs_an_mp3quran_folder_with_timings_and_the_same_riwayah(
    full_quran: dict[str, Any],
) -> None:
    recitation = _recitation(full_quran, source_url="https://example.com/abkar/", surahs=(1,))
    with pytest.raises(Mp3QuranTimingError, match="Источник записи не MP3Quran"):
        prepare_mp3quran_timings(recitation, FakeMp3Quran())

    no_timings = FakeMp3Quran(reads=[])
    RecitationEdition.objects.filter(pk=recitation.pk).update(source_url=FOLDER)
    recitation.refresh_from_db()
    with pytest.raises(Mp3QuranTimingError, match="нет таймкодов аятов для папки"):
        prepare_mp3quran_timings(recitation, no_timings)

    warsh = FakeMp3Quran(reads=[{"id": 12, "rewaya": "ورش عن نافع", "folder_url": FOLDER}])
    with pytest.raises(Mp3QuranTimingError, match="Риваят MP3Quran «ورش عن نافع»"):
        prepare_mp3quran_timings(recitation, warsh)


def test_imported_timings_are_immutable_and_not_imported_twice(idris: RecitationEdition) -> None:
    result = import_mp3quran_timings(prepare_mp3quran_timings(idris, FakeMp3Quran()))

    timing = AudioTimingVersion.objects.get(pk=result.timing_version.pk)
    timing.source_version = "edited"
    with pytest.raises(ValidationError, match="immutable"):
        timing.save()
    track = AudioTrack.objects.get(recitation_edition=idris, surah_number=1)
    track.timing_version = None
    with pytest.raises(ValidationError, match="immutable"):
        track.save()
    segment = AyahAudioSegment.objects.filter(track=track).first()
    assert segment is not None
    segment.start_ms += 1
    with pytest.raises(ValidationError, match="immutable"):
        segment.save()
    with pytest.raises(Mp3QuranTimingError, match="уже есть таймкоды"):
        prepare_mp3quran_timings(idris, FakeMp3Quran())


def test_published_tracks_stay_immutable_apart_from_gaining_timings(
    idris: RecitationEdition,
) -> None:
    track = AudioTrack.objects.get(recitation_edition=idris, surah_number=2)
    track.duration_ms += 1
    with pytest.raises(ValidationError, match="immutable"):
        track.save()

    track.refresh_from_db()
    unverified = AudioTimingVersion.objects.create(
        recitation_edition=idris,
        version="manual",
        source_name="Manual",
        source_version="1",
        source_checksum_sha256="d" * 64,
        verified_at=timezone.now(),
    )
    AudioTimingVersion.objects.filter(pk=unverified.pk).update(verified_at=None)
    track.timing_version = unverified
    with pytest.raises(ValidationError, match="immutable"):
        track.save()


def test_partial_listening_recitation_times_the_surahs_it_has(
    full_quran: dict[str, Any],
) -> None:
    recitation = _recitation(full_quran, surahs=(1, 112))
    RecitationEdition.objects.filter(pk=recitation.pk).update(listening_only=True)
    recitation.refresh_from_db()

    result = import_mp3quran_timings(prepare_mp3quran_timings(recitation, FakeMp3Quran()))

    assert (result.surah_count, result.ayah_count) == (2, 11)


def _staff() -> User:
    return User.objects.create_superuser(email="owner@example.com", password="pw-123456789")


def test_admin_offers_the_import_and_reports_the_result(idris: RecitationEdition) -> None:
    client = Client()
    client.force_login(_staff())
    change_url = reverse("admin:audio_recitationedition_change", args=[idris.pk])
    import_url = reverse("admin:audio_recitationedition_mp3quran_timings", args=[idris.pk])

    with patch(
        "quran_backend.modules.audio.mp3quran_timings.Mp3QuranClient",
        return_value=FakeMp3Quran(),
    ):
        page = client.get(change_url).content.decode()
        assert "Есть у 0 из 114 сур." in page
        assert "Подтянуть таймкоды из MP3Quran" in page
        assert import_url in page

        assert client.get(import_url).status_code == 405
        response = client.post(import_url)

    assert response.status_code == 302
    assert response["Location"] == change_url
    notes = [str(message) for message in get_messages(response.wsgi_request)]
    assert notes == ["Таймкоды MP3Quran добавлены: 114 сур, 123 аятов (версия mp3quran-12)."]
    page = client.get(change_url).content.decode()
    assert "Есть у 114 из 114 сур." in page
    assert "Подтянуть таймкоды из MP3Quran" not in page


def test_admin_explains_a_file_mismatch(idris: RecitationEdition) -> None:
    client = Client()
    client.force_login(_staff())
    import_url = reverse("admin:audio_recitationedition_mp3quran_timings", args=[idris.pk])

    with patch(
        "quran_backend.modules.audio.mp3quran_timings.Mp3QuranClient",
        return_value=FakeMp3Quran(sizes={7: 5}),
    ):
        response = client.post(import_url)

    notes = [str(message) for message in get_messages(response.wsgi_request)]
    assert len(notes) == 1
    assert notes[0].startswith("Таймкоды не добавлены, запись не изменилась.")
    assert (
        "сура 7: наш файл не тот, что у MP3Quran (размер у нас 1000007 байт, у MP3Quran 5 байт)"
        in notes[0]
    )
    assert not AudioTimingVersion.objects.exists()


def test_admin_says_when_mp3quran_has_no_timings_for_the_folder(
    idris: RecitationEdition,
) -> None:
    client = Client()
    client.force_login(_staff())

    with patch(
        "quran_backend.modules.audio.mp3quran_timings.Mp3QuranClient",
        return_value=FakeMp3Quran(reads=[]),
    ):
        page = client.get(
            reverse("admin:audio_recitationedition_change", args=[idris.pk])
        ).content.decode()

    assert f"У MP3Quran нет таймкодов аятов для папки {FOLDER}" in page
    assert "Подтянуть таймкоды из MP3Quran" not in page


def test_command_checks_then_imports(idris: RecitationEdition) -> None:
    out = StringIO()
    with patch(
        "quran_backend.modules.audio.mp3quran_timings.Mp3QuranClient",
        return_value=FakeMp3Quran(),
    ):
        call_command("import_mp3quran_timings", "idris-abkar-murattal", "--dry-run", stdout=out)
        assert "114 surahs, 123 ayahs ready. Nothing written" in out.getvalue()
        assert not AudioTimingVersion.objects.exists()

        call_command("import_mp3quran_timings", "idris-abkar-murattal", stdout=out)

    assert "timing version mp3quran-12 attached to 114 surahs, 123 ayahs" in out.getvalue()
    with pytest.raises(CommandError, match="No recitation"):
        call_command("import_mp3quran_timings", "missing")
