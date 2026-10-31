# ruff: noqa: RUF001 -- Admin-facing messages intentionally use Cyrillic characters.

"""Ayah timings from MP3Quran for audio taken from its CDN folders.

MP3Quran publishes ayah timings (`/api/v3/ayat_timing`) for many of its
readings. A timing is only true for the very file it was measured on, so the
timings are attached only after every surah file we serve is shown to be the
MP3Quran file of that folder: the same URL for external audio, or the same
size (and the same MD5, where both sides expose it as the ETag) for files
uploaded to our storage. Any doubt stops the whole import.

MP3Quran starts ayah 1 after the basmala and leaves short pauses between
ayahs; like Quran.Foundation's timings, ours start ayah 1 at the beginning of
the file (so the basmala is heard) and run each ayah up to the next one.

Timings arrive as one immutable AudioTimingVersion for the surahs that had
none. Published audio keeps its tracks and files; only the ayah timeline is
added, and the catalog then offers the recitation in the Mushaf and
Memorization once every ayah is timed.
"""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_importer import (
    PreparedSegment,
    _riwayah_family,
    prepare_ayah_timeline,
)
from quran_backend.modules.audio.selectors import forget_recitation_summaries
from quran_backend.modules.core.content_revalidation import enqueue_audio_content_change
from quran_backend.modules.quran.models import Ayah

MP3QURAN_API_BASE = "https://www.mp3quran.net/api/v3"
MP3QURAN_AUDIO_HOST = "cdn.mp3quran.net"
TIMING_SOURCE_NAME = "MP3Quran ayat_timing"
HTTP_TIMEOUT_SECONDS = 20
# The admin page asks while it renders, so it gives up sooner.
ADMIN_LOOKUP_TIMEOUT_SECONDS = 5
PARALLEL_REQUESTS = 16
# MP3Quran sometimes ends the last ayah a little past the file's measured end.
END_TOLERANCE_MS = 2000
READS_CACHE_KEY = "audio:mp3quran:ayat-timing-reads:v1"
READS_CACHE_SECONDS = 6 * 60 * 60
_MD5 = re.compile(r'"?([0-9a-f]{32})"?\Z')
# MP3Quran names the riwayah in Arabic ("حفص عن عاصم").
_ARABIC_RIWAYAH = {
    "حفص": "hafs",
    "ورش": "warsh",
    "قالون": "qalun",
    "شعبة": "shubah",
    "الدوري": "al-douri",
    "السوسي": "al-sousi",
    # MP3Quran's "المصحف المجود" readings are Hafs 'an 'Asim recited mujawwad.
    "المجود": "hafs",
}


class Mp3QuranTimingError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class RemoteAudio:
    size_bytes: int
    md5: str | None


class Mp3QuranSource(Protocol):
    def timing_reads(self) -> list[dict[str, Any]]: ...

    def surah_timings(self, read_id: int, surah_number: int) -> list[dict[str, Any]]: ...

    def audio_head(self, url: str) -> RemoteAudio: ...


class Mp3QuranClient:
    """The few public MP3Quran endpoints the import reads; no key is needed."""

    def __init__(self, timeout: float = HTTP_TIMEOUT_SECONDS) -> None:
        self.timeout = timeout

    def timing_reads(self) -> list[dict[str, Any]]:
        rows = self._get_json(f"{MP3QURAN_API_BASE}/ayat_timing/reads")
        if not isinstance(rows, list):
            raise Mp3QuranTimingError("MP3Quran вернул непонятный список чтецов.")
        return [row for row in rows if isinstance(row, dict)]

    def surah_timings(self, read_id: int, surah_number: int) -> list[dict[str, Any]]:
        query = urlencode({"surah": surah_number, "read": read_id})
        rows = self._get_json(f"{MP3QURAN_API_BASE}/ayat_timing?{query}")
        if not isinstance(rows, list):
            raise Mp3QuranTimingError(f"Сура {surah_number}: MP3Quran не вернул таймкоды.")
        return rows

    def audio_head(self, url: str) -> RemoteAudio:
        _require_mp3quran_audio_url(url)
        # The URL is checked above to be an HTTPS MP3Quran CDN address.
        request = Request(url, method="HEAD", headers={"User-Agent": "IQRO-timings"})  # noqa: S310
        try:
            with urlopen(request, timeout=self.timeout) as response:  # noqa: S310
                headers = response.headers
        except HTTPError as exc:
            raise Mp3QuranTimingError(f"MP3Quran не отдаёт файл {url} (ответ {exc.code}).") from exc
        except (URLError, TimeoutError, OSError) as exc:
            raise Mp3QuranTimingError("MP3Quran сейчас недоступен. Повторите позже.") from exc
        try:
            size_bytes = int(headers.get("Content-Length") or 0)
        except ValueError:
            size_bytes = 0
        return RemoteAudio(size_bytes=size_bytes, md5=_md5_etag(headers.get("ETag")))

    def _get_json(self, url: str) -> object:
        # Fixed HTTPS API base; only the query varies.
        request = Request(url, headers={"Accept": "application/json", "User-Agent": "IQRO-timings"})  # noqa: S310
        try:
            with urlopen(request, timeout=self.timeout) as response:  # noqa: S310
                return json.loads(response.read())
        except HTTPError as exc:
            raise Mp3QuranTimingError(f"MP3Quran ответил {exc.code}. Повторите позже.") from exc
        except (URLError, TimeoutError, OSError) as exc:
            raise Mp3QuranTimingError("MP3Quran сейчас недоступен. Повторите позже.") from exc
        except ValueError as exc:
            raise Mp3QuranTimingError("MP3Quran вернул непонятный ответ.") from exc


@dataclass(frozen=True, slots=True)
class TimingRead:
    read_id: int
    rewaya: str
    folder_url: str


@dataclass(frozen=True, slots=True)
class _PreparedTrack:
    track_id: uuid.UUID
    surah_number: int
    segments: tuple[PreparedSegment, ...]
    canonical: dict[str, Any]


@dataclass(frozen=True, slots=True)
class PreparedTimings:
    recitation_id: uuid.UUID
    read: TimingRead
    checksum_sha256: str
    tracks: tuple[_PreparedTrack, ...]

    @property
    def ayah_count(self) -> int:
        return sum(len(track.segments) for track in self.tracks)


@dataclass(frozen=True, slots=True)
class ImportedTimings:
    timing_version: AudioTimingVersion
    surah_count: int
    ayah_count: int


def mp3quran_folder(recitation: RecitationEdition) -> str | None:
    """The MP3Quran CDN folder the recitation's source points at, if any."""
    url = (recitation.source_url or "").strip()
    parts = urlsplit(url)
    if parts.hostname != MP3QURAN_AUDIO_HOST or parts.username or parts.password:
        return None
    path = parts.path if parts.path.endswith("/") else f"{parts.path}/"
    return f"https://{MP3QURAN_AUDIO_HOST}{path}"


def find_timing_read(rows: list[dict[str, Any]], folder_url: str) -> TimingRead | None:
    matches: list[TimingRead] = []
    for row in rows:
        row_folder = str(row.get("folder_url") or "")
        if not row_folder.endswith("/"):
            row_folder = f"{row_folder}/"
        if row_folder.replace("http://", "https://", 1) != folder_url:
            continue
        try:
            read_id = int(row["id"])
        except KeyError, TypeError, ValueError:
            continue
        matches.append(TimingRead(read_id, str(row.get("rewaya") or ""), folder_url))
    return matches[0] if len(matches) == 1 else None


def cached_timing_read(
    recitation: RecitationEdition,
    client: Mp3QuranSource | None = None,
) -> TimingRead | None:
    """The admin's lookup; the MP3Quran list is cached for a few hours."""
    folder = mp3quran_folder(recitation)
    if folder is None:
        return None
    rows: list[dict[str, Any]] | None = cache.get(READS_CACHE_KEY)
    if rows is None:
        rows = (client or Mp3QuranClient(timeout=ADMIN_LOOKUP_TIMEOUT_SECONDS)).timing_reads()
        cache.set(READS_CACHE_KEY, rows, READS_CACHE_SECONDS)
    return find_timing_read(rows, folder)


def untimed_surah_tracks(recitation: RecitationEdition) -> list[AudioTrack]:
    return list(
        AudioTrack.objects.filter(
            recitation_edition=recitation,
            scope=AudioTrackScope.SURAH,
            timing_version__isnull=True,
        ).order_by("surah_number")
    )


def prepare_mp3quran_timings(
    recitation: RecitationEdition,
    client: Mp3QuranSource | None = None,
) -> PreparedTimings:
    """Check the files and read the timings; nothing is written here."""
    source = client or Mp3QuranClient()
    _check_recitation(recitation)
    folder = mp3quran_folder(recitation)
    if folder is None:
        raise Mp3QuranTimingError(
            "Источник записи не MP3Quran: в «Адресе источника» должна быть папка "
            f"https://{MP3QURAN_AUDIO_HOST}/audio/…/"
        )
    read = find_timing_read(source.timing_reads(), folder)
    if read is None:
        raise Mp3QuranTimingError(f"У MP3Quran нет таймкодов аятов для папки {folder}")
    _check_riwayah(read, recitation)

    tracks = untimed_surah_tracks(recitation)
    if not tracks:
        raise Mp3QuranTimingError("У всех сур этой записи уже есть таймкоды.")
    renditions = {
        rendition.track_id: rendition
        for rendition in AudioRendition.objects.filter(
            track__in=tracks,
            is_default=True,
        )
    }
    ayah_numbers: dict[int, list[int]] = {}
    for surah_number, ayah_number in (
        Ayah.objects.filter(
            surah__edition_version_id=recitation.quran_edition_version_id,
            surah__number__in=[track.surah_number for track in tracks],
        )
        .order_by("surah__number", "number")
        .values_list("surah__number", "number")
    ):
        ayah_numbers.setdefault(surah_number, []).append(ayah_number)

    def prepare(track: AudioTrack) -> _PreparedTrack | str:
        try:
            return _prepare_track(source, read, track, renditions.get(track.id), ayah_numbers)
        except Mp3QuranTimingError as exc:
            return str(exc)

    with ThreadPoolExecutor(max_workers=PARALLEL_REQUESTS) as pool:
        outcomes = list(pool.map(prepare, tracks))
    problems = [outcome for outcome in outcomes if isinstance(outcome, str)]
    if problems:
        shown = "; ".join(problems[:5])
        more = f" И ещё {len(problems) - 5}." if len(problems) > 5 else ""
        raise Mp3QuranTimingError(
            "Таймкоды не добавлены, запись не изменилась. Таймкоды MP3Quran верны только "
            f"для его же файлов, а здесь есть расхождения: {shown}.{more}"
        )
    prepared = tuple(outcome for outcome in outcomes if not isinstance(outcome, str))
    return PreparedTimings(
        recitation_id=recitation.id,
        read=read,
        checksum_sha256=_checksum(
            {
                "source": TIMING_SOURCE_NAME,
                "read": read.read_id,
                "folder_url": read.folder_url,
                "surahs": [track.canonical for track in prepared],
            }
        ),
        tracks=prepared,
    )


def import_mp3quran_timings(prepared: PreparedTimings) -> ImportedTimings:
    """Attach the prepared timings as one new immutable timing version."""
    try:
        with transaction.atomic():
            recitation = RecitationEdition.objects.select_for_update().get(
                pk=prepared.recitation_id
            )
            _check_recitation(recitation)
            tracks = {track.id: track for track in untimed_surah_tracks(recitation)}
            if set(tracks) != {track.track_id for track in prepared.tracks}:
                raise Mp3QuranTimingError("Суры записи изменились во время проверки. Повторите.")
            timing_version = AudioTimingVersion.objects.create(
                recitation_edition=recitation,
                version=_next_version(recitation, prepared.read.read_id),
                source_name=TIMING_SOURCE_NAME,
                source_version=f"api-v3-read-{prepared.read.read_id}",
                source_checksum_sha256=prepared.checksum_sha256,
                verified_at=timezone.now(),
            )
            ayah_ids = {
                (surah_number, number): ayah_id
                for ayah_id, surah_number, number in Ayah.objects.filter(
                    surah__edition_version_id=recitation.quran_edition_version_id,
                    surah__number__in=[track.surah_number for track in prepared.tracks],
                ).values_list("id", "surah__number", "number")
            }
            segments: list[AyahAudioSegment] = []
            for prepared_track in prepared.tracks:
                track = tracks[prepared_track.track_id]
                track.timing_version = timing_version
                track.save(update_fields=["timing_version", "updated_at"])
                segments.extend(
                    AyahAudioSegment(
                        track=track,
                        ayah_id=ayah_ids[(prepared_track.surah_number, segment.ayah_number)],
                        start_ms=segment.start_ms,
                        end_ms=segment.end_ms,
                    )
                    for segment in prepared_track.segments
                )
            AyahAudioSegment.objects.bulk_create(segments, batch_size=2000)
            # The publication checks re-read every timeline, now with the new segments.
            recitation.full_clean()
            if recitation.status == RecitationPublicationStatus.PUBLISHED:
                transaction.on_commit(lambda: _announce(recitation))
    except ValidationError as exc:
        raise Mp3QuranTimingError(" ".join(exc.messages)) from exc
    return ImportedTimings(
        timing_version=timing_version,
        surah_count=len(prepared.tracks),
        ayah_count=prepared.ayah_count,
    )


def _check_recitation(recitation: RecitationEdition) -> None:
    if recitation.status == RecitationPublicationStatus.WITHDRAWN:
        raise Mp3QuranTimingError("Запись отозвана; таймкоды ей не добавить.")


def _check_riwayah(read: TimingRead, recitation: RecitationEdition) -> None:
    source_family = next(
        (family for word, family in _ARABIC_RIWAYAH.items() if word in read.rewaya), None
    )
    edition_family = _riwayah_family(recitation.quran_edition_version.edition.riwayah.strip())
    if source_family != edition_family:
        raise Mp3QuranTimingError(
            f"Риваят MP3Quran «{read.rewaya}» не совпадает с риваятом издания Корана записи."
        )


def _prepare_track(
    source: Mp3QuranSource,
    read: TimingRead,
    track: AudioTrack,
    rendition: AudioRendition | None,
    ayah_numbers: dict[int, list[int]],
) -> _PreparedTrack:
    surah_number = int(track.surah_number or 0)
    if rendition is None:
        raise Mp3QuranTimingError(f"сура {surah_number}: у дорожки нет основного файла")
    _check_same_file(source, read, surah_number, rendition)

    rows = source.surah_timings(read.read_id, surah_number)
    timestamps: list[dict[str, Any]] = []
    for row in rows:
        # Many readings give the basmala its own row, "ayah 0". It is not an ayah
        # of the text: ayah 1 below starts the file, so it still plays with ayah 1.
        if row.get("ayah") in (0, "0"):
            continue
        try:
            timestamps.append(
                {
                    "verse_key": f"{surah_number}:{int(row['ayah'])}",
                    "timestamp_from": round(float(row["start_time"])),
                    "timestamp_to": round(float(row["end_time"])),
                }
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise Mp3QuranTimingError(
                f"сура {surah_number}: MP3Quran вернул неверную строку таймкодов"
            ) from exc
    try:
        segments, canonical = prepare_ayah_timeline(
            timestamps, surah_number, ayah_numbers.get(surah_number, [])
        )
    except QuranFoundationError as exc:
        raise Mp3QuranTimingError(
            f"сура {surah_number}: таймкоды MP3Quran не ложатся на аяты нашего издания ({exc})"
        ) from exc

    # Like Quran.Foundation's, the timeline has no holes: the first ayah starts
    # the file, so the basmala (or isti'adha) before it plays with ayah 1, and
    # each ayah lasts until the next begins (MP3Quran leaves ~20 ms between).
    # prepare_ayah_timeline already trimmed overlaps, so the next start is never earlier.
    for index, segment in enumerate(segments):
        start_ms = 0 if index == 0 else segment.start_ms
        end_ms = segments[index + 1].start_ms if index + 1 < len(segments) else segment.end_ms
        segments[index] = PreparedSegment(segment.ayah_number, start_ms, end_ms)
        canonical[index]["start_ms"] = segments[index].start_ms
        canonical[index]["end_ms"] = segments[index].end_ms
    last = segments[-1]
    if last.end_ms > track.duration_ms + END_TOLERANCE_MS:
        raise Mp3QuranTimingError(
            f"сура {surah_number}: таймкоды MP3Quran не подходят к файлу — последний аят "
            f"кончается на {last.end_ms // 1000} с, а файл длится {track.duration_ms // 1000} с "
            "(MP3Quran, видимо, размечал другую запись этой суры)"
        )
    if last.end_ms > track.duration_ms:
        if last.start_ms >= track.duration_ms:
            raise Mp3QuranTimingError(
                f"сура {surah_number}: последний аят начинается после конца нашего файла"
            )
        segments[-1] = PreparedSegment(last.ayah_number, last.start_ms, track.duration_ms)
        canonical[-1]["end_ms"] = track.duration_ms
    return _PreparedTrack(
        track_id=track.id,
        surah_number=surah_number,
        segments=tuple(segments),
        canonical={"surah": surah_number, "segments": canonical},
    )


def _check_same_file(
    source: Mp3QuranSource,
    read: TimingRead,
    surah_number: int,
    rendition: AudioRendition,
) -> None:
    expected_url = f"{read.folder_url}{surah_number:03d}.mp3"
    if rendition.external_url:
        if rendition.external_url != expected_url:
            raise Mp3QuranTimingError(
                f"сура {surah_number}: файл берётся не из папки MP3Quran ({rendition.external_url})"
            )
        return
    remote = source.audio_head(expected_url)
    if remote.size_bytes != rendition.size_bytes:
        raise Mp3QuranTimingError(
            f"сура {surah_number}: наш файл не тот, что у MP3Quran (размер у нас "
            f"{rendition.size_bytes} байт, у MP3Quran {remote.size_bytes} байт)"
        )
    ours = _md5_etag(rendition.origin_etag) or _md5_etag(rendition.etag)
    if ours is not None and remote.md5 is not None and ours != remote.md5:
        raise Mp3QuranTimingError(
            f"сура {surah_number}: наш файл не тот, что у MP3Quran (размер тот же, "
            "но содержимое другое по MD5)"
        )


def _require_mp3quran_audio_url(url: str) -> None:
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.hostname != MP3QURAN_AUDIO_HOST:
        raise Mp3QuranTimingError("Ожидался адрес файла на cdn.mp3quran.net.")


def _md5_etag(value: str | None) -> str | None:
    """Single-part S3/R2 objects and the MP3Quran CDN use the content MD5 as ETag."""
    match = _MD5.match((value or "").strip().lower())
    return match.group(1) if match else None


def _next_version(recitation: RecitationEdition, read_id: int) -> str:
    base = f"mp3quran-{read_id}"
    existing = set(recitation.timing_versions.values_list("version", flat=True))
    if base not in existing:
        return base
    number = 2
    while f"{base}-{number}" in existing:
        number += 1
    return f"{base}-{number}"


def _checksum(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def _announce(recitation: RecitationEdition) -> None:
    forget_recitation_summaries()
    enqueue_audio_content_change(
        action="published",
        recitation_id=recitation.id,
        reciter_id=recitation.reciter_id,
        version=recitation.version,
    )
