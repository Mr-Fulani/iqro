# ruff: noqa: RUF001 -- Reciter names and operator messages are intentionally Cyrillic.

from __future__ import annotations

import re
from typing import Any

import pytest

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTrack,
    AudioTrackScope,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)
from quran_backend.modules.audio.mp3quran_catalog import (
    AudioFacts,
    Mp3QuranCatalogError,
    Reading,
    apply_reciter_profiles,
    import_reading,
    name_key,
    plan_catalog,
    read_mp3quran_readings,
    recover_timings,
    timing_recovery_candidates,
)
from quran_backend.modules.audio.mp3quran_reciter_profiles import (
    MP3QURAN_RECITER_BIOGRAPHIES,
    MP3QURAN_RECITER_NAMES,
)
from quran_backend.modules.audio.mp3quran_timings import Mp3QuranTimingError, RemoteAudio
from quran_backend.modules.audio.selectors import public_recitations
from quran_backend.modules.quran.models import Ayah, RevelationType, Surah

FOLDER = "https://cdn.mp3quran.net/audio/nasser-qatami/r1/"
ALL_SURAHS = tuple(range(1, 115))


def _reading(**overrides: Any) -> Reading:
    values: dict[str, Any] = {
        "reciter_key": 7,
        "moshaf_id": 70,
        "name_ar": "ناصر القطامي",
        "name_en": "Nasser Alqatami",
        "name_ru": "Насер Аль Катами",
        "name_tr": "Nasser Alqatami",
        "folder_url": FOLDER,
        "style": "murattal",
        "hafs": True,
        "surahs": ALL_SURAHS,
        "timing_read_id": 70,
    }
    return Reading(**{**values, **overrides})


class FakeSource:
    def __init__(self, **overrides: Any) -> None:
        self.duration_ms: int = overrides.get("duration_ms", 60_000)
        self.broken: set[int] = overrides.get("broken", set())
        self.basmala_row: bool = overrides.get("basmala_row", False)
        self.rejected_timings: bool = overrides.get("rejected_timings", False)

    def reciters(self, language: str) -> list[dict[str, Any]]:
        names = {
            "ar": "ناصر القطامي",
            "eng": "Nasser Alqatami",
            "ru": "Насер Аль Катами",
            "tr": "",
        }
        return [
            {
                "id": 7,
                "name": names[language],
                "moshaf": [
                    {
                        "id": 70,
                        "name": "حفص عن عاصم - مرتل",
                        "server": FOLDER,
                        "surah_list": "1,2,114",
                    },
                    {
                        "id": 71,
                        "name": "ورش عن نافع - مرتل",
                        "server": "https://cdn.mp3quran.net/audio/nasser-qatami/warsh/",
                        "surah_list": "1,2",
                    },
                ],
            }
        ]

    def timing_reads(self) -> list[dict[str, Any]]:
        return [{"id": 70, "rewaya": "حفص عن عاصم", "folder_url": FOLDER}]

    def surah_timings(self, read_id: int, surah_number: int) -> list[dict[str, Any]]:  # noqa: ARG002
        ayahs = 1 if self.rejected_timings else 7 if surah_number == 1 else 1
        basmala = [{"ayah": 0, "start_time": 0, "end_time": 900}] if self.basmala_row else []
        return basmala + [
            {
                "ayah": ayah,
                "start_time": 1000 + (ayah - 1) * 7000,
                "end_time": 1000 + ayah * 7000 - 20,
            }
            for ayah in range(1, ayahs + 1)
        ]

    def audio_head(self, url: str) -> RemoteAudio:  # noqa: ARG002
        return RemoteAudio(size_bytes=1_000_000, md5="a" * 32)

    def audio_facts(self, url: str) -> AudioFacts:
        surah = int(url.rsplit("/", 1)[1].removesuffix(".mp3"))
        if surah in self.broken:
            raise Mp3QuranCatalogError(f"ffprobe не прочитал {url}")
        return AudioFacts(self.duration_ms, 128)


@pytest.fixture
def one_ayah_quran(quran_dataset: dict[str, Any]) -> dict[str, Any]:
    """Al-Fatihah with its 7 ayahs, every other surah with one: enough for a full timeline."""
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
            ayah_count=1,
        )
        _ayah(surah, 1)
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


def _existing_recitation(dataset: dict[str, Any], name_ar: str, style: str) -> RecitationEdition:
    reciter = Reciter.objects.create(
        code="known", name_ar=name_ar, name_en="Known", name_ru="Известный"
    )
    return RecitationEdition.objects.create(
        code=f"known-{style}",
        version="1",
        style=style,
        reciter=reciter,
        quran_edition_version=dataset["version"],
        listening_only=True,
        source_name="Quran.Foundation Content API",
        source_url="https://api-docs.quran.foundation/",
        source_version="1",
    )


def test_readings_join_names_timings_and_riwayah() -> None:
    hafs, warsh = read_mp3quran_readings(FakeSource())
    assert hafs.name_ru == "Насер Аль Катами"
    assert hafs.name_tr == "Nasser Alqatami", "a missing translation falls back to English"
    assert hafs.style == "murattal"
    assert hafs.hafs
    assert hafs.surahs == (1, 2, 114)
    assert hafs.timing_read_id == 70
    assert not warsh.hafs
    assert warsh.timing_read_id is None


def test_name_key_ignores_spelling_differences() -> None:
    assert name_key("عبد الباسط عبد الصمد") == name_key("عبدالباسط عبدالصمد")
    assert name_key("سعود إبراهيم بن محمد") == name_key("سعود ابراهيم محمد")
    assert name_key("سعود الشريم") != name_key("سعد الغامدي")


@pytest.mark.django_db
def test_plan_adds_new_timed_hafs_only() -> None:
    plan = plan_catalog(
        [
            _reading(),
            _reading(reciter_key=8, moshaf_id=80, folder_url="x/", hafs=False),
            _reading(reciter_key=9, moshaf_id=90, folder_url="y/", style=None),
            _reading(reciter_key=10, moshaf_id=100, folder_url="z/", timing_read_id=None),
        ],
        include_untimed=False,
    )
    assert [reading.moshaf_id for reading, _ in plan.additions] == [70]
    assert {reading.moshaf_id: reason for reading, reason in plan.skipped} == {
        80: "не Хафс: нужен свой текст Мусхафа",
        90: "стиль записи не определён",
        100: "без полной разметки: следующий этап",
    }


@pytest.mark.django_db
def test_plan_keeps_untimed_for_the_second_stage() -> None:
    plan = plan_catalog([_reading(timing_read_id=None)], include_untimed=True)
    assert len(plan.additions) == 1


@pytest.mark.django_db
def test_partial_timings_stay_listening_only() -> None:
    reading = _reading(surahs=(1, 2, 3))
    assert not reading.fully_timed
    assert plan_catalog([reading], include_untimed=False).additions == []


@pytest.mark.django_db
def test_what_the_catalog_has_wins(quran_dataset: dict[str, Any]) -> None:
    _existing_recitation(quran_dataset, "ناصر بن علي القطامي", "murattal")
    plan = plan_catalog([_reading()], include_untimed=True)
    assert plan.additions == []
    assert plan.skipped[0][1] == "у чтеца уже есть запись этого стиля"


@pytest.mark.django_db
def test_a_known_reciter_gains_only_a_new_style(quran_dataset: dict[str, Any]) -> None:
    known = _existing_recitation(quran_dataset, "ناصر القطامي", "murattal").reciter
    plan = plan_catalog([_reading(style="mujawwad")], include_untimed=True)
    assert plan.additions == [(_reading(style="mujawwad"), known)]


@pytest.mark.django_db
def test_one_person_with_two_cards_counts_as_one(quran_dataset: dict[str, Any]) -> None:
    mujawwad = _existing_recitation(quran_dataset, "ناصر القطامي", "mujawwad")
    other_card = Reciter.objects.create(
        code="known-2", name_ar="ناصر القطامي", name_en="Known", name_ru="Известный"
    )
    RecitationEdition.objects.create(
        code="known-2-murattal",
        version="1",
        style="murattal",
        reciter=other_card,
        quran_edition_version=quran_dataset["version"],
        listening_only=True,
        source_name="Quran.Foundation Content API",
        source_url="https://api-docs.quran.foundation/x",
        source_version="1",
    )
    assert mujawwad.reciter != other_card
    assert plan_catalog([_reading()], include_untimed=True).additions == []


@pytest.mark.django_db
def test_a_folder_already_in_the_catalog_is_skipped(quran_dataset: dict[str, Any]) -> None:
    recitation = _existing_recitation(quran_dataset, "شخص آخر تماما", "muallim")
    recitation.source_url = FOLDER
    recitation.save(update_fields=["source_url"])
    plan = plan_catalog([_reading()], include_untimed=True)
    assert plan.skipped[0][1] == "уже в каталоге"


@pytest.mark.django_db
def test_a_reciter_keeps_the_best_reading_of_a_style() -> None:
    untimed = _reading(moshaf_id=71, folder_url="x/", timing_read_id=None)
    plan = plan_catalog([untimed, _reading()], include_untimed=True)
    assert [reading.moshaf_id for reading, _ in plan.additions] == [70]


@pytest.mark.django_db
def test_timed_reading_reaches_the_mushaf(one_ayah_quran: dict[str, Any]) -> None:
    imported = import_reading(_reading(), None, FakeSource())

    recitation = imported.recitation
    assert imported.timed
    assert recitation.status == RecitationPublicationStatus.PUBLISHED
    assert not recitation.listening_only
    assert not recitation.offline_download_allowed
    assert recitation.reciter.name_ru == "Насер аль-Катами", "our spelling, not MP3Quran's"
    assert (
        AudioTrack.objects.filter(
            recitation_edition=recitation, scope=AudioTrackScope.SURAH
        ).count()
        == 114
    )
    rendition = AudioRendition.objects.get(track__surah_number=1)
    assert rendition.external_url == f"{FOLDER}001.mp3"
    assert not rendition.object_key
    listed = public_recitations().get(pk=recitation.pk)
    assert int(listed.timed_ayah_count) == int(listed.expected_ayah_count)


@pytest.mark.django_db
def test_second_run_adds_nothing(one_ayah_quran: dict[str, Any]) -> None:
    import_reading(_reading(), None, FakeSource())
    plan = plan_catalog([_reading()], include_untimed=True)
    assert plan.additions == []


@pytest.mark.django_db
def test_timings_of_another_recording_stay_out_of_the_mushaf(
    one_ayah_quran: dict[str, Any],
) -> None:
    # The last ayah ends after the file does: the Idris Abkar surah 36 case.
    imported = import_reading(_reading(), None, FakeSource(duration_ms=20_000))

    assert not imported.timed
    assert "не подходят к файлу" in imported.note
    assert imported.recitation.listening_only
    assert imported.recitation.status == RecitationPublicationStatus.PUBLISHED
    assert not imported.recitation.timing_versions.exists()


@pytest.mark.django_db
def test_listening_reading_may_be_partial(one_ayah_quran: dict[str, Any]) -> None:
    reading = _reading(surahs=(1, 2, 3), timing_read_id=None)
    imported = import_reading(reading, None, FakeSource())

    assert imported.recitation.listening_only
    assert not imported.timed
    assert public_recitations().filter(pk=imported.recitation.pk).exists()


@pytest.mark.django_db
def test_an_unreadable_file_leaves_nothing_behind(
    one_ayah_quran: dict[str, Any],
) -> None:
    with pytest.raises(Mp3QuranCatalogError):
        import_reading(_reading(), None, FakeSource(broken={36}))

    assert not Reciter.objects.filter(name_en="Nasser Alqatami").exists()
    assert not RecitationEdition.objects.filter(source_url=FOLDER).exists()


@pytest.mark.django_db
def test_a_basmala_row_is_not_an_ayah(one_ayah_quran: dict[str, Any]) -> None:
    imported = import_reading(_reading(), None, FakeSource(basmala_row=True))

    assert imported.timed
    assert not imported.recitation.listening_only
    first = AudioTrack.objects.get(recitation_edition=imported.recitation, surah_number=1)
    assert first.segments.order_by("start_ms").first().start_ms == 0


@pytest.mark.django_db
def test_recovery_opens_a_listening_reading_to_the_mushaf(
    one_ayah_quran: dict[str, Any],
) -> None:
    listening = import_reading(_reading(), None, FakeSource(rejected_timings=True)).recitation
    assert timing_recovery_candidates() == [listening]

    recover_timings(listening, FakeSource())

    listening.refresh_from_db()
    assert not listening.listening_only
    assert listening.status == RecitationPublicationStatus.PUBLISHED
    assert listening.timing_versions.count() == 1
    assert timing_recovery_candidates() == []
    listed = public_recitations().get(pk=listening.pk)
    assert int(listed.timed_ayah_count) == int(listed.expected_ayah_count)


@pytest.mark.django_db
def test_failed_recovery_changes_nothing(one_ayah_quran: dict[str, Any]) -> None:
    listening = import_reading(_reading(), None, FakeSource(duration_ms=20_000)).recitation

    with pytest.raises(Mp3QuranTimingError):
        recover_timings(listening, FakeSource(duration_ms=20_000))

    listening.refresh_from_db()
    assert listening.listening_only
    assert not listening.timing_versions.exists()


@pytest.mark.django_db
def test_recovery_leaves_editor_uploads_alone(quran_dataset: dict[str, Any]) -> None:
    upload = _existing_recitation(quran_dataset, "شخص آخر تماما", "murattal")
    assert upload.source_checksum_sha256 == ""
    assert timing_recovery_candidates() == []


def test_keyword_names_fall_back_to_english() -> None:
    source = FakeSource()
    original = source.reciters

    def keyword_names(language: str) -> list[dict[str, Any]]:
        rows = original(language)
        if language == "ru":
            rows[0]["name"] = "Коран,Аудио,Библиотека,MP3,Коран"
        return rows

    source.reciters = keyword_names  # type: ignore[method-assign]
    assert read_mp3quran_readings(source)[0].name_ru == "Nasser Alqatami"


@pytest.mark.django_db
def test_curated_names_replace_the_imported_ones(quran_dataset: dict[str, Any]) -> None:
    reciter = Reciter.objects.create(
        code="dawood-hamza", name_ar="داود حمزة", name_en="Dawood Hamza", name_ru="Дэвид Хамза"
    )

    assert apply_reciter_profiles() == ["dawood-hamza"]
    reciter.refresh_from_db()
    assert reciter.name_ru == "Дауд Хамза"
    assert reciter.name_tr == "Davud Hamza"
    assert apply_reciter_profiles() == []


def test_every_curated_name_is_cyrillic_and_clean() -> None:
    for code, (name_ru, name_tr) in MP3QURAN_RECITER_NAMES.items():
        assert re.fullmatch(r"[А-Яа-яЁё -]+", name_ru), code
        assert name_tr.strip() == name_tr, code
        assert "  " not in name_tr, code


@pytest.mark.django_db
def test_every_biography_fits_the_reciter_model() -> None:
    for code in MP3QURAN_RECITER_BIOGRAPHIES:
        Reciter.objects.create(code=code, name_ar=code, name_en=code, name_ru=code)

    assert sorted(apply_reciter_profiles()) == sorted(MP3QURAN_RECITER_BIOGRAPHIES)

    for code, profile in MP3QURAN_RECITER_BIOGRAPHIES.items():
        reciter = Reciter.objects.get(code=code)
        assert reciter.name_ru == MP3QURAN_RECITER_NAMES[code][0]
        assert reciter.profile_source_url == profile["profile_source_url"]
        for language in ("ar", "en", "ru", "tr"):
            assert getattr(reciter, f"biography_{language}"), (code, language)
