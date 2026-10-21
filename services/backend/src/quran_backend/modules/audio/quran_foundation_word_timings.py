"""Fill QF word timings into already published ayah segments.

The importer keeps word timings for new versions. Versions imported before it
did have only ayah boundaries; this backfill re-reads the same QF chapter
timestamps and adds the words only when the ayah timeline is unchanged, so no
published boundary ever moves.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

from quran_backend.modules.audio.models import AudioTrackScope, AyahAudioSegment
from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationEnvironment,
    QuranFoundationError,
)
from quran_backend.modules.audio.quran_foundation_importer import prepare_ayah_timeline
from quran_backend.modules.audio.quran_foundation_sync import latest_complete_qf_recitations


class QuranFoundationChapterAudioSource(Protocol):
    environment: QuranFoundationEnvironment

    def get_chapter_audio(self, reciter_id: int, chapter_number: int) -> dict[str, Any]: ...


@dataclass(frozen=True, slots=True)
class WordTimingBackfillSummary:
    recitations: int
    tracks_updated: int
    tracks_unchanged: int
    tracks_skipped: int
    segments_updated: int


def backfill_quran_foundation_word_timings(
    *,
    client: QuranFoundationChapterAudioSource | None = None,
    recitation_codes: tuple[str, ...] = (),
    dry_run: bool = False,
) -> WordTimingBackfillSummary:
    sync_client = client or QuranFoundationClient.from_environment()
    recitations = latest_complete_qf_recitations(sync_client.environment.name)
    if recitation_codes:
        recitations = [item for item in recitations if item[1].code in recitation_codes]
        missing = set(recitation_codes) - {recitation.code for _, recitation in recitations}
        if missing:
            raise QuranFoundationError(
                "Unknown or incomplete Quran.Foundation recitations: " + ", ".join(sorted(missing))
            )
    updated = unchanged = skipped = segments_updated = 0
    for source_id, recitation in recitations:
        tracks = recitation.tracks.filter(scope=AudioTrackScope.SURAH).order_by("surah_number")
        for track in tracks:
            surah_number = track.surah_number
            if surah_number is None:
                continue
            segments = sorted(
                track.segments.select_related("ayah"),
                key=lambda segment: segment.ayah.number,
            )
            audio_file = sync_client.get_chapter_audio(source_id, surah_number)
            try:
                prepared, _ = prepare_ayah_timeline(
                    audio_file.get("timestamps"),
                    surah_number,
                    [segment.ayah.number for segment in segments],
                )
            except QuranFoundationError:
                skipped += 1
                continue
            stored = [(item.ayah.number, item.start_ms, item.end_ms) for item in segments]
            fresh = [(item.ayah_number, item.start_ms, item.end_ms) for item in prepared]
            if stored != fresh:
                skipped += 1
                continue
            changed = []
            for segment, item in zip(segments, prepared, strict=True):
                words = [list(word) for word in item.words]
                if segment.word_segments != words:
                    segment.word_segments = words
                    changed.append(segment)
            if not changed:
                unchanged += 1
                continue
            if not dry_run:
                AyahAudioSegment.objects.bulk_update(changed, ["word_segments"], batch_size=500)
            updated += 1
            segments_updated += len(changed)
    return WordTimingBackfillSummary(
        recitations=len(recitations),
        tracks_updated=updated,
        tracks_unchanged=unchanged,
        tracks_skipped=skipped,
        segments_updated=segments_updated,
    )
