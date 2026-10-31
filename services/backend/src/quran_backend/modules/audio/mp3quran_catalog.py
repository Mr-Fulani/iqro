# ruff: noqa: RUF001 -- Operator-facing messages intentionally use Cyrillic characters.

"""MP3Quran readings in our audio catalog, played straight from its CDN.

The files stay on cdn.mp3quran.net; a reading only gains catalog rows here:
the reciter's card, one recitation and one external rendition per surah. A
Hafs reading with ayah timings for all 114 surahs goes through the same checks
as `import_mp3quran_timings` and then works in the Mushaf and Memorization.
Any other Hafs reading is listening-only: it plays whole surahs on the Audio
tab and never maps onto ayahs.

Rules that keep this apart from what is already in the catalog:

- one person, one reciter card: a reciter already here gains a recitation only
  in a style the catalog lacks for them;
- what the catalog has wins: Quran.Foundation carries word timings, MP3Quran
  only ayah timings, so a reading of the same style is skipped;
- only Hafs: the catalog's Mushaf text is Hafs, and other riwayat number ayahs
  differently, so they wait for a text edition of their own.

Reading a file's headers fails a reading as a whole; nothing is written for it
and the next run picks it up, so the import can be repeated at any time.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Any, Protocol

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone
from django.utils.text import slugify

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioRendition,
    AudioRenditionQuality,
    AudioTrack,
    AudioTrackScope,
    RecitationEdition,
    RecitationPublicationStatus,
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.audio.mp3quran_timings import (
    MP3QURAN_API_BASE,
    PARALLEL_REQUESTS,
    Mp3QuranClient,
    Mp3QuranTimingError,
    RemoteAudio,
    _announce,
    _require_mp3quran_audio_url,
    import_mp3quran_timings,
    prepare_mp3quran_timings,
)
from quran_backend.modules.audio.surah_upload import LISTENING_QURAN_EDITION
from quran_backend.modules.quran.models import QuranEdition, QuranEditionVersion

SOURCE_NAME = "MP3Quran.net"
LICENSE_NAME = "MP3Quran.net public audio"
FFPROBE_TIMEOUT_SECONDS = 30
SURAH_COUNT = 114
_DIACRITICS = re.compile("[ً-ْـ]")
_MAX_RECITER_CODE = 48


class Mp3QuranCatalogError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class AudioFacts:
    duration_ms: int
    bitrate_kbps: int


class Mp3QuranCatalogSource(Protocol):
    def reciters(self, language: str) -> list[dict[str, Any]]: ...

    def timing_reads(self) -> list[dict[str, Any]]: ...

    def surah_timings(self, read_id: int, surah_number: int) -> list[dict[str, Any]]: ...

    def audio_head(self, url: str) -> RemoteAudio: ...

    def audio_facts(self, url: str) -> AudioFacts: ...


class Mp3QuranCatalogClient(Mp3QuranClient):
    def __init__(self, ffprobe: str = "ffprobe") -> None:
        super().__init__()
        self.ffprobe = ffprobe
        self._reads: list[dict[str, Any]] | None = None

    def timing_reads(self) -> list[dict[str, Any]]:
        # One run asks for every reading in turn; the list does not change meanwhile.
        if self._reads is None:
            self._reads = super().timing_reads()
        return self._reads

    def reciters(self, language: str) -> list[dict[str, Any]]:
        payload = self._get_json(f"{MP3QURAN_API_BASE}/reciters?language={language}")
        rows = payload.get("reciters") if isinstance(payload, dict) else None
        if not isinstance(rows, list):
            raise Mp3QuranCatalogError("MP3Quran вернул непонятный список чтецов.")
        return [row for row in rows if isinstance(row, dict)]

    def audio_facts(self, url: str) -> AudioFacts:
        _require_mp3quran_audio_url(url)
        try:
            completed = subprocess.run(  # noqa: S603 - fixed program, no shell, a checked URL
                [
                    self.ffprobe,
                    "-v",
                    "error",
                    "-print_format",
                    "json",
                    "-show_entries",
                    "format=duration,bit_rate",
                    url,
                ],
                capture_output=True,
                check=True,
                text=True,
                timeout=FFPROBE_TIMEOUT_SECONDS,
            )
            report = json.loads(completed.stdout)["format"]
            duration_ms = round(float(report["duration"]) * 1000)
            bitrate_kbps = round(float(report["bit_rate"]) / 1000)
        except (
            KeyError,
            OSError,
            TypeError,
            ValueError,
            subprocess.SubprocessError,
        ) as exc:
            raise Mp3QuranCatalogError(f"ffprobe не прочитал {url}") from exc
        if duration_ms <= 0 or bitrate_kbps <= 0:
            raise Mp3QuranCatalogError(f"ffprobe не определил длину файла {url}")
        return AudioFacts(duration_ms, bitrate_kbps)


@dataclass(frozen=True, slots=True)
class Reading:
    """One MP3Quran moshaf of one reciter."""

    reciter_key: int
    moshaf_id: int
    name_ar: str
    name_en: str
    name_ru: str
    name_tr: str
    folder_url: str
    style: str | None
    hafs: bool
    surahs: tuple[int, ...]
    timing_read_id: int | None

    @property
    def fully_timed(self) -> bool:
        return self.timing_read_id is not None and len(self.surahs) == SURAH_COUNT


@dataclass(slots=True)
class CatalogPlan:
    additions: list[tuple[Reading, Reciter | None]] = field(default_factory=list)
    skipped: list[tuple[Reading, str]] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class ImportedReading:
    recitation: RecitationEdition
    timed: bool
    note: str = ""


def name_key(name: str) -> tuple[str, ...]:
    """The words of an Arabic name, whatever spelling MP3Quran and we each use."""
    text = _DIACRITICS.sub("", name).replace("ـ", "")
    for variants, plain in (("أإآ", "ا"), ("ة", "ه"), ("ى", "ي")):
        for variant in variants:
            text = text.replace(variant, plain)
    text = text.replace("عبد ال", "عبدال")
    return tuple(word for word in text.split() if word not in {"بن", "ابن", "الشيخ"})


def _same_person(left: tuple[str, ...], right: tuple[str, ...]) -> bool:
    shorter, longer = sorted((left, right), key=len)
    return len(shorter) >= 2 and set(shorter) <= set(longer)


def _style_of(moshaf_name: str) -> str | None:
    if "معلم" in moshaf_name:
        return RecitationStyle.MUALLIM
    if "مجود" in moshaf_name:
        return RecitationStyle.MUJAWWAD
    if "مرتل" in moshaf_name:
        return RecitationStyle.MURATTAL
    return None


def _is_hafs(moshaf_name: str) -> bool:
    # MP3Quran's "المصحف المجود" and "المصحف المعلم" are Hafs 'an 'Asim.
    return "حفص" in moshaf_name or (
        "المصحف" in moshaf_name and not re.search("ورش|قالون|شعبة|الدوري|السوسي|البزي", moshaf_name)
    )


def _folder(url: str) -> str:
    url = url.strip().replace("http://", "https://", 1)
    return url if url.endswith("/") else f"{url}/"


def read_mp3quran_readings(source: Mp3QuranCatalogSource) -> list[Reading]:
    names = {
        language: {int(row["id"]): str(row.get("name") or "") for row in source.reciters(language)}
        for language in ("eng", "ru", "tr")
    }
    timing_reads = {
        _folder(str(row.get("folder_url") or "")): int(row["id"]) for row in source.timing_reads()
    }
    readings: list[Reading] = []
    for row in source.reciters("ar"):
        reciter_key = int(row["id"])
        name_en = names["eng"].get(reciter_key) or str(row.get("name") or "")
        for moshaf in row.get("moshaf") or []:
            folder_url = _folder(str(moshaf.get("server") or ""))
            surahs = tuple(
                sorted(
                    int(number)
                    for number in str(moshaf.get("surah_list") or "").split(",")
                    if number.strip().isdigit()
                )
            )
            moshaf_name = str(moshaf.get("name") or "")
            readings.append(
                Reading(
                    reciter_key=reciter_key,
                    moshaf_id=int(moshaf["id"]),
                    name_ar=str(row.get("name") or ""),
                    name_en=name_en,
                    name_ru=names["ru"].get(reciter_key) or name_en,
                    name_tr=names["tr"].get(reciter_key) or name_en,
                    folder_url=folder_url,
                    style=_style_of(moshaf_name),
                    hafs=_is_hafs(moshaf_name),
                    surahs=surahs,
                    timing_read_id=timing_reads.get(folder_url),
                )
            )
    return readings


def plan_catalog(readings: Iterable[Reading], *, include_untimed: bool) -> CatalogPlan:
    """Decide what to add; reads our catalog and writes nothing."""
    catalog = list(
        RecitationEdition.objects.exclude(status=RecitationPublicationStatus.WITHDRAWN).values_list(
            "source_url", "style", "reciter_id"
        )
    )
    folders = {_folder(url) for url, _, _ in catalog if url}
    styles_by_reciter: dict[Any, set[str]] = {}
    for _, style, reciter_id in catalog:
        styles_by_reciter.setdefault(reciter_id, set()).add(style)
    reciters = [(name_key(reciter.name_ar), reciter) for reciter in Reciter.objects.all()]

    def existing_reciters(reading: Reading) -> list[Reciter]:
        # Quran.Foundation gives one person a card per style, so there may be several.
        key = name_key(reading.name_ar)
        return [found for known, found in reciters if _same_person(key, known)]

    plan = CatalogPlan()
    candidates: dict[tuple[int, str], Reading] = {}
    # Fully timed readings first, then the most surahs: a reciter keeps the best one per style.
    for reading in sorted(
        readings,
        key=lambda item: (not item.fully_timed, -len(item.surahs), item.moshaf_id),
    ):
        known = existing_reciters(reading)
        known_styles = {
            style for reciter in known for style in styles_by_reciter.get(reciter.id, set())
        }
        if reading.folder_url in folders:
            reason = "уже в каталоге"
        elif not reading.hafs:
            reason = "не Хафс: нужен свой текст Мусхафа"
        elif reading.style is None:
            reason = "стиль записи не определён"
        elif not reading.surahs:
            reason = "нет сур"
        elif reading.style in known_styles:
            reason = "у чтеца уже есть запись этого стиля"
        elif (reading.reciter_key, reading.style) in candidates:
            reason = "у чтеца есть запись этого стиля получше"
        elif not include_untimed and not reading.fully_timed:
            reason = "без полной разметки: следующий этап"
        else:
            candidates[(reading.reciter_key, reading.style)] = reading
            plan.additions.append((reading, known[0] if known else None))
            continue
        plan.skipped.append((reading, reason))
    return plan


def _active_quran_version() -> QuranEditionVersion:
    edition = QuranEdition.objects.get(code=LISTENING_QURAN_EDITION)
    if edition.active_version is None:
        raise Mp3QuranCatalogError("У издания Корана нет активной версии.")
    return edition.active_version


def _reciter_code(reading: Reading) -> str:
    base = slugify(reading.name_en)[:_MAX_RECITER_CODE].strip("-")
    code = base or f"mp3quran-{reading.reciter_key}"
    if Reciter.objects.filter(code=code).exists():
        code = f"{code}-mp3quran-{reading.reciter_key}"
    return code


def _measure(
    source: Mp3QuranCatalogSource, reading: Reading
) -> list[tuple[int, str, RemoteAudio, AudioFacts]]:
    def measure(surah_number: int) -> tuple[int, str, RemoteAudio, AudioFacts]:
        url = f"{reading.folder_url}{surah_number:03d}.mp3"
        return surah_number, url, source.audio_head(url), source.audio_facts(url)

    with ThreadPoolExecutor(max_workers=PARALLEL_REQUESTS) as pool:
        files = list(pool.map(measure, reading.surahs))
    empty = [surah for surah, _, head, _ in files if head.size_bytes <= 0]
    if empty:
        raise Mp3QuranCatalogError(f"MP3Quran не сообщил размер файлов сур {empty[:5]}")
    return files


def _manifest_checksum(reading: Reading, files: list[Any]) -> str:
    manifest = {
        "folder_url": reading.folder_url,
        "files": [[surah, head.size_bytes, head.md5] for surah, _, head, _ in files],
    }
    canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def _create_draft(
    reading: Reading,
    reciter: Reciter | None,
    files: list[Any],
) -> RecitationEdition:
    if reciter is None:
        reciter = Reciter.objects.create(
            code=_reciter_code(reading),
            name_ar=reading.name_ar,
            name_en=reading.name_en,
            name_ru=reading.name_ru,
            name_tr=reading.name_tr,
        )
    assert reading.style is not None
    recitation = RecitationEdition.objects.create(
        code=f"{reciter.code}-{reading.style}",
        version="1",
        style=reading.style,
        reciter=reciter,
        quran_edition_version=_active_quran_version(),
        listening_only=not reading.fully_timed,
        source_name=SOURCE_NAME,
        source_url=reading.folder_url,
        source_version=str(reading.moshaf_id),
        source_checksum_sha256=_manifest_checksum(reading, files),
        rights_holder=f"{reading.name_en}; distributed by {SOURCE_NAME}",
        license_name=LICENSE_NAME,
        license_attribution=f"Recitation by {reading.name_en}. Audio source: {SOURCE_NAME}.",
        stream_allowed=True,
        offline_download_allowed=False,
    )
    for surah_number, url, head, facts in files:
        track = AudioTrack.objects.create(
            recitation_edition=recitation,
            scope=AudioTrackScope.SURAH,
            surah_number=surah_number,
            duration_ms=facts.duration_ms,
        )
        AudioRendition.objects.create(
            track=track,
            quality=AudioRenditionQuality.STANDARD,
            is_default=True,
            codec=AudioCodec.MP3,
            content_type=AudioContentType.MPEG,
            bitrate_kbps=facts.bitrate_kbps,
            size_bytes=head.size_bytes,
            external_url=url,
        )
    return recitation


def import_reading(
    reading: Reading,
    reciter: Reciter | None,
    source: Mp3QuranCatalogSource,
) -> ImportedReading:
    """Add one reading; on any failure nothing of it stays in the catalog."""
    files = _measure(source, reading)
    note = ""
    try:
        with transaction.atomic():
            recitation = _create_draft(reading, reciter, files)
            timed = False
            if reading.fully_timed:
                try:
                    import_mp3quran_timings(prepare_mp3quran_timings(recitation, source))
                    timed = True
                except Mp3QuranTimingError as exc:
                    # Timings MP3Quran measured on another file must not reach the
                    # Mushaf; the reading itself still plays on the Audio tab.
                    recitation = _without_timings(recitation)
                    note = str(exc)
            recitation.status = RecitationPublicationStatus.PUBLISHED
            recitation.published_at = timezone.now()
            recitation.save()
            transaction.on_commit(lambda: _announce(recitation))
    except ValidationError as exc:
        raise Mp3QuranCatalogError(" ".join(exc.messages)) from exc
    return ImportedReading(recitation, timed, note)


def timing_recovery_candidates() -> list[RecitationEdition]:
    """Readings this import left on the Audio tab although they have all 114 surahs.

    A source checksum marks them as ours: recitations an editor uploaded have
    none and keep the provenance rules of their own.
    """
    return [
        recitation
        for recitation in RecitationEdition.objects.filter(
            status=RecitationPublicationStatus.PUBLISHED,
            listening_only=True,
            source_name=SOURCE_NAME,
        ).exclude(source_checksum_sha256="")
        if recitation.tracks.filter(
            scope=AudioTrackScope.SURAH, timing_version__isnull=True
        ).count()
        == SURAH_COUNT
    ]


def recover_timings(recitation: RecitationEdition, source: Mp3QuranCatalogSource) -> None:
    """Add the timings and open the reading to the Mushaf and Memorization, or change nothing."""
    prepared = prepare_mp3quran_timings(recitation, source)
    try:
        with transaction.atomic():
            import_mp3quran_timings(prepared)
            recitation.refresh_from_db()
            recitation.listening_only = False
            recitation.save()
            transaction.on_commit(lambda: _announce(recitation))
    except ValidationError as exc:
        raise Mp3QuranCatalogError(" ".join(exc.messages)) from exc


def _without_timings(recitation: RecitationEdition) -> RecitationEdition:
    recitation.listening_only = True
    recitation.save(update_fields=["listening_only", "updated_at"])
    return recitation
