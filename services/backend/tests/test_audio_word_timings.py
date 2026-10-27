from __future__ import annotations

from typing import Any

import pytest

from quran_backend.modules.audio.models import AyahAudioSegment, RecitationEdition
from quran_backend.modules.audio.quran_foundation import ENVIRONMENTS, QuranFoundationError
from quran_backend.modules.audio.quran_foundation_importer import (
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)
from quran_backend.modules.audio.quran_foundation_word_timings import (
    backfill_quran_foundation_word_timings,
)
from tests.test_quran_foundation_audio import FakeQuranFoundationClient

WORDS_1 = [[1, 0, 900], [2, 900, 2_100], [3, 2_100, 3_400], [4, 3_400, 4_950]]
WORDS_2 = [[1, 5_000, 6_000], [2, 6_000, 7_000], [3, 7_000, 8_000], [4, 8_000, 9_900]]


class WordTimingClient(FakeQuranFoundationClient):
    environment = ENVIRONMENTS["prelive"]

    def __init__(self, *, words_2: object = None, end_1: int = 5_000) -> None:
        self.words_2 = WORDS_2 if words_2 is None else words_2
        self.end_1 = end_1

    def get_chapter_audio(self, reciter_id: int, chapter_number: int) -> dict[str, Any]:
        payload = super().get_chapter_audio(reciter_id, chapter_number)
        payload["timestamps"] = [
            {
                "verse_key": "1:1",
                "timestamp_from": 0,
                "timestamp_to": self.end_1,
                "segments": WORDS_1,
            },
            {
                "verse_key": "1:2",
                "timestamp_from": 5_000,
                "timestamp_to": 10_000,
                "segments": self.words_2,
            },
        ]
        return payload


def _import(client: FakeQuranFoundationClient, quran_dataset: dict[str, Any]) -> RecitationEdition:
    prepared = prepare_quran_foundation_recitation(
        client,
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )
    return import_quran_foundation_recitation(
        prepared,
        quran_version=quran_dataset["version"],
        content_version="2026.10.21-prelive",
        environment_name="prelive",
        publish=True,
    ).recitation


def _words(recitation: RecitationEdition) -> list[list[list[int]]]:
    return [
        segment.word_segments
        for segment in AyahAudioSegment.objects.filter(
            track__recitation_edition=recitation
        ).order_by("ayah__number")
    ]


def test_import_keeps_quran_foundation_word_timings(quran_dataset: dict[str, Any]) -> None:
    recitation = _import(WordTimingClient(), quran_dataset)

    assert _words(recitation) == [WORDS_1, WORDS_2]


@pytest.mark.parametrize(
    "words_2",
    [
        [[1, 5_000]],
        [[0, 5_000, 6_000]],
        [[1, 6_000, 5_000]],
        [[1, 5_000, 6_000]] * 2,
        [[1, 5_000.5, 6_000]],
        [[True, 5_000, 6_000]],
        "x",
    ],
)
def test_malformed_word_timings_are_dropped_without_failing_the_ayah(
    quran_dataset: dict[str, Any],
    words_2: object,
) -> None:
    recitation = _import(WordTimingClient(words_2=words_2), quran_dataset)

    assert _words(recitation) == [WORDS_1, []]


def test_whole_number_floats_count_as_word_timings(quran_dataset: dict[str, Any]) -> None:
    # QF sends al-Husary's Muallim timings as floats: [1, 5000.0, 6000.0].
    floats = [[float(item) for item in word] for word in WORDS_2]
    recitation = _import(WordTimingClient(words_2=floats), quran_dataset)

    words = _words(recitation)
    assert words == [WORDS_1, WORDS_2]
    assert all(type(item) is int for word in words[1] for item in word)


def test_word_timings_do_not_change_the_published_timing_checksum(
    quran_dataset: dict[str, Any],
) -> None:
    without_words = prepare_quran_foundation_recitation(
        FakeQuranFoundationClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )
    with_words = prepare_quran_foundation_recitation(
        WordTimingClient(),
        reciter_id=7,
        surah_numbers=[1],
        quran_version=quran_dataset["version"],
    )

    assert with_words.timing_checksum_sha256 == without_words.timing_checksum_sha256
    assert with_words.source_checksum_sha256 == without_words.source_checksum_sha256


def test_backfill_adds_words_only_when_the_ayah_timeline_is_unchanged(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    recitation = _import(FakeQuranFoundationClient(), quran_dataset)
    monkeypatch.setattr(
        "quran_backend.modules.audio.quran_foundation_word_timings.latest_complete_qf_recitations",
        lambda environment: [(7, recitation)] if environment == "prelive" else [],
    )
    assert _words(recitation) == [[], []]

    moved = backfill_quran_foundation_word_timings(client=WordTimingClient(end_1=4_000))
    dry = backfill_quran_foundation_word_timings(client=WordTimingClient(), dry_run=True)
    assert (moved.tracks_skipped, moved.segments_updated) == (1, 0)
    assert (dry.tracks_updated, dry.segments_updated) == (1, 2)
    assert _words(recitation) == [[], []]

    result = backfill_quran_foundation_word_timings(client=WordTimingClient())
    again = backfill_quran_foundation_word_timings(
        client=WordTimingClient(),
        recitation_codes=(recitation.code,),
    )

    assert (result.recitations, result.tracks_updated, result.segments_updated) == (1, 1, 2)
    assert _words(recitation) == [WORDS_1, WORDS_2]
    assert (again.tracks_updated, again.tracks_unchanged) == (0, 1)
    with pytest.raises(QuranFoundationError, match="Unknown or incomplete"):
        backfill_quran_foundation_word_timings(
            client=WordTimingClient(),
            recitation_codes=("qf-404-murattal",),
        )
