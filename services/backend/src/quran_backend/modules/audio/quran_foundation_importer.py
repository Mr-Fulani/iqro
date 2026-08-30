from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import urlsplit

from django.db import transaction
from django.utils import timezone
from django.utils.text import slugify

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
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.audio.quran_foundation import (
    ALLOWED_AUDIO_HOSTS,
    QuranFoundationError,
)
from quran_backend.modules.audio.reciter_profiles import RECITER_PROFILES
from quran_backend.modules.core.content_revalidation import enqueue_audio_content_change
from quran_backend.modules.quran.models import Ayah, QuranEditionVersion

DEVELOPER_TERMS_URL = "https://api-docs.quran.foundation/legal/developer-terms/"


@dataclass(frozen=True, slots=True)
class PreparedSegment:
    ayah_number: int
    start_ms: int
    end_ms: int


@dataclass(frozen=True, slots=True)
class PreparedTrack:
    surah_number: int
    duration_ms: int
    size_bytes: int
    bitrate_kbps: int
    external_url: str
    segments: tuple[PreparedSegment, ...]


@dataclass(frozen=True, slots=True)
class PreparedRecitation:
    source_id: int
    source_qirat: str
    name_ar: str
    name_en: str
    name_ru: str
    style: str
    source_checksum_sha256: str
    timing_checksum_sha256: str
    tracks: tuple[PreparedTrack, ...]


@dataclass(frozen=True, slots=True)
class ImportResult:
    recitation: RecitationEdition
    created: bool


class QuranFoundationAudioSource(Protocol):
    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]: ...

    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]: ...

    def get_external_audio_size(self, url: str) -> int: ...


def prepare_quran_foundation_recitation(
    client: QuranFoundationAudioSource,
    *,
    reciter_id: int,
    surah_numbers: list[int],
    quran_version: QuranEditionVersion,
    localized_catalogs: Mapping[str, list[dict[str, Any]]] | None = None,
) -> PreparedRecitation:
    if not surah_numbers or any(number < 1 or number > 114 for number in surah_numbers):
        raise QuranFoundationError("Surah numbers must be between 1 and 114.")
    if len(set(surah_numbers)) != len(surah_numbers):
        raise QuranFoundationError("Surah numbers must not be repeated.")

    catalogs = localized_catalogs or {
        language: client.list_chapter_reciters(language=language) for language in ("en", "ar", "ru")
    }
    try:
        localized = {
            language: _reciter_by_id(catalogs[language], reciter_id)
            for language in ("en", "ar", "ru")
        }
    except KeyError as exc:
        raise QuranFoundationError("Localized reciter catalogs are incomplete.") from exc
    english = localized["en"]
    style = _style_value(english)
    source_qirat = _nested_name(english, "qirat").strip()
    _ensure_riwayah_compatible(source_qirat, quran_version)

    ayahs = {
        (ayah.surah.number, ayah.number): ayah
        for ayah in Ayah.objects.filter(
            surah__edition_version=quran_version,
            surah__number__in=surah_numbers,
        ).select_related("surah")
    }
    tracks: list[PreparedTrack] = []
    canonical_audio: list[dict[str, Any]] = []
    canonical_timings: list[dict[str, Any]] = []
    for surah_number in sorted(surah_numbers):
        audio_file = client.get_chapter_audio(reciter_id, surah_number)
        audio_file = dict(audio_file)
        audio_file["file_size"] = client.get_external_audio_size(
            str(audio_file.get("audio_url", ""))
        )
        track, timing_payload = _prepare_track(audio_file, surah_number, ayahs)
        tracks.append(track)
        canonical_audio.append(
            {
                "surah": track.surah_number,
                "url": track.external_url,
                "bytes": track.size_bytes,
                "duration_ms": track.duration_ms,
            }
        )
        canonical_timings.append(timing_payload)

    return PreparedRecitation(
        source_id=reciter_id,
        source_qirat=source_qirat,
        name_ar=_localized_name(localized["ar"]),
        name_en=_localized_name(english),
        name_ru=_localized_name(localized["ru"]),
        style=style,
        source_checksum_sha256=_checksum(
            {
                "qirat": source_qirat,
                "style": style,
                "audio": canonical_audio,
            }
        ),
        timing_checksum_sha256=_checksum(canonical_timings),
        tracks=tuple(tracks),
    )


def compatible_quran_foundation_reciter_ids(
    rows: list[dict[str, Any]],
    *,
    quran_version: QuranEditionVersion,
) -> list[int]:
    compatible: list[int] = []
    seen: set[int] = set()
    for row in rows:
        try:
            source_id = int(row.get("id", 0))
        except (TypeError, ValueError) as exc:
            raise QuranFoundationError("Chapter reciter catalog has an invalid ID.") from exc
        if source_id <= 0 or source_id in seen:
            raise QuranFoundationError("Chapter reciter catalog has duplicate or invalid IDs.")
        seen.add(source_id)
        source_qirat = _nested_name(row, "qirat").strip()
        try:
            _ensure_riwayah_compatible(source_qirat, quran_version)
        except QuranFoundationError:
            continue
        compatible.append(source_id)
    return compatible


@transaction.atomic
def import_quran_foundation_recitation(
    prepared: PreparedRecitation,
    *,
    quran_version: QuranEditionVersion,
    content_version: str,
    environment_name: str,
    publish: bool,
) -> ImportResult:
    _ensure_riwayah_compatible(prepared.source_qirat, quran_version)

    reciter_code = f"qf-{prepared.source_id}-{slugify(prepared.name_en)[:48]}"
    curated_profile = RECITER_PROFILES.get(reciter_code)
    reciter_defaults = (
        dict(curated_profile)
        if curated_profile is not None
        else {
            "name_ar": prepared.name_ar,
            "name_en": prepared.name_en,
            "name_ru": prepared.name_ru,
            "name_tr": prepared.name_en,
        }
    )
    reciter, _ = Reciter.objects.get_or_create(
        code=reciter_code,
        defaults=reciter_defaults,
    )
    quran_version_key = str(quran_version.pk).replace("-", "")[:12]
    recitation_code = f"qf-{prepared.source_id}-{prepared.style}-{quran_version_key}"
    existing = RecitationEdition.objects.filter(
        code=recitation_code,
        version=content_version,
    ).first()
    if existing is not None:
        if existing.source_checksum_sha256 != prepared.source_checksum_sha256:
            raise QuranFoundationError(
                "This recitation version already exists with different source metadata."
            )
        return ImportResult(existing, False)

    recitation = RecitationEdition.objects.create(
        code=recitation_code,
        version=content_version,
        style=prepared.style,
        reciter=reciter,
        quran_edition_version=quran_version,
        source_name="Quran.Foundation Content API",
        source_url="https://api-docs.quran.foundation/docs/category/content-apis-4.0.0/",
        source_version=f"content-api-v4-{environment_name}",
        source_checksum_sha256=prepared.source_checksum_sha256,
        rights_holder="Quran.Foundation and source rights holders",
        license_name="Quran Foundation Developer Terms",
        license_url=DEVELOPER_TERMS_URL,
        license_attribution=(
            "Audio metadata and URLs supplied by Quran.Foundation; "
            f"source qira'ah: {prepared.source_qirat}."
        ),
        stream_allowed=True,
        offline_download_allowed=False,
    )
    timing_version = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version=content_version,
        source_name="Quran.Foundation chapter audio timestamps",
        source_version=f"content-api-v4-{environment_name}",
        source_checksum_sha256=prepared.timing_checksum_sha256,
        verified_at=timezone.now(),
    )
    ayah_by_key = {
        (ayah.surah.number, ayah.number): ayah
        for ayah in Ayah.objects.filter(
            surah__edition_version=quran_version,
            surah__number__in=[track.surah_number for track in prepared.tracks],
        ).select_related("surah")
    }
    for prepared_track in prepared.tracks:
        track = AudioTrack.objects.create(
            recitation_edition=recitation,
            timing_version=timing_version,
            scope=AudioTrackScope.SURAH,
            surah_number=prepared_track.surah_number,
            duration_ms=prepared_track.duration_ms,
        )
        AudioRendition.objects.create(
            track=track,
            quality=AudioRenditionQuality.STANDARD,
            is_default=True,
            codec=AudioCodec.MP3,
            content_type=AudioContentType.MPEG,
            bitrate_kbps=prepared_track.bitrate_kbps,
            size_bytes=prepared_track.size_bytes,
            checksum_sha256="",
            object_key=None,
            external_url=prepared_track.external_url,
        )
        AyahAudioSegment.objects.bulk_create(
            [
                AyahAudioSegment(
                    track=track,
                    ayah=ayah_by_key[(prepared_track.surah_number, segment.ayah_number)],
                    start_ms=segment.start_ms,
                    end_ms=segment.end_ms,
                )
                for segment in prepared_track.segments
            ]
        )
    if publish:
        recitation.publish()
        recitation.save()
        enqueue_audio_content_change(
            action="published",
            recitation_id=recitation.id,
            reciter_id=recitation.reciter_id,
            version=recitation.version,
        )
    return ImportResult(recitation, True)


def _prepare_track(
    audio_file: dict[str, Any],
    surah_number: int,
    ayahs: dict[tuple[int, int], Ayah],
) -> tuple[PreparedTrack, dict[str, Any]]:
    if int(audio_file.get("chapter_id", 0)) != surah_number:
        raise QuranFoundationError(f"Audio metadata does not match surah {surah_number}.")
    external_url = str(audio_file.get("audio_url", ""))
    parsed_url = urlsplit(external_url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname not in ALLOWED_AUDIO_HOSTS
        or parsed_url.username is not None
        or parsed_url.password is not None
    ):
        raise QuranFoundationError("Quran.Foundation returned an unapproved audio origin.")
    audio_formats = {
        value.strip().lower()
        for value in str(audio_file.get("format", "")).split(",")
        if value.strip()
    }
    if (audio_formats and "mp3" not in audio_formats) or not parsed_url.path.lower().endswith(
        ".mp3"
    ):
        raise QuranFoundationError("Only MP3 chapter audio is supported by this importer.")
    try:
        size_bytes = int(float(audio_file.get("file_size", 0)))
    except (TypeError, ValueError) as exc:
        raise QuranFoundationError("Audio metadata contains an invalid file size.") from exc
    if size_bytes <= 0:
        raise QuranFoundationError("Audio metadata contains an invalid file size.")

    timestamps = audio_file.get("timestamps")
    if not isinstance(timestamps, list) or not timestamps:
        raise QuranFoundationError(f"Surah {surah_number} has no ayah timestamps.")
    expected_ayah_numbers = sorted(
        ayah_number for surah, ayah_number in ayahs if surah == surah_number
    )
    segments: list[PreparedSegment] = []
    canonical: list[dict[str, int | str]] = []
    previous_start = -1
    previous_end = 0
    for timestamp in timestamps:
        if not isinstance(timestamp, dict):
            raise QuranFoundationError("Audio timestamps contain an invalid row.")
        verse_key = str(timestamp.get("verse_key", ""))
        try:
            verse_surah, verse_ayah = (int(part) for part in verse_key.split(":"))
            start_ms = int(timestamp["timestamp_from"])
            end_ms = int(timestamp["timestamp_to"])
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationError("Audio timestamps contain invalid values.") from exc
        if (
            verse_surah != surah_number
            or start_ms < 0
            or start_ms <= previous_start
            or end_ms <= start_ms
            or end_ms <= previous_end
        ):
            raise QuranFoundationError(
                f"Surah {surah_number} has an invalid timeline at {verse_key}: "
                f"previous_start={previous_start}, previous_end={previous_end}, "
                f"start={start_ms}, end={end_ms}."
            )
        if segments and start_ms < segments[-1].end_ms:
            previous = segments[-1]
            segments[-1] = PreparedSegment(
                ayah_number=previous.ayah_number,
                start_ms=previous.start_ms,
                end_ms=start_ms,
            )
            canonical[-1]["end_ms"] = start_ms
        previous_start = start_ms
        previous_end = end_ms
        segments.append(PreparedSegment(verse_ayah, start_ms, end_ms))
        canonical.append({"verse_key": verse_key, "start_ms": start_ms, "end_ms": end_ms})
    if [segment.ayah_number for segment in segments] != expected_ayah_numbers:
        raise QuranFoundationError(f"Surah {surah_number} does not cover every canonical ayah.")

    duration_ms = segments[-1].end_ms
    bitrate_kbps = max(1, round(size_bytes * 8 / duration_ms))
    return (
        PreparedTrack(
            surah_number=surah_number,
            duration_ms=duration_ms,
            size_bytes=size_bytes,
            bitrate_kbps=bitrate_kbps,
            external_url=external_url,
            segments=tuple(segments),
        ),
        {"surah": surah_number, "segments": canonical},
    )


def _reciter_by_id(rows: list[dict[str, Any]], reciter_id: int) -> dict[str, Any]:
    for row in rows:
        if int(row.get("id", 0)) == reciter_id:
            return row
    raise QuranFoundationError(f"Chapter reciter {reciter_id} is not available.")


def _localized_name(row: dict[str, Any]) -> str:
    translated = row.get("translated_name")
    if isinstance(translated, dict) and translated.get("name"):
        return str(translated["name"])
    name = row.get("name")
    if not name:
        raise QuranFoundationError("A reciter is missing a display name.")
    return str(name)


def _nested_name(row: dict[str, Any], field: str) -> str:
    value = row.get(field)
    return str(value.get("name", "")) if isinstance(value, dict) else ""


def _style_value(row: dict[str, Any]) -> str:
    value = slugify(_nested_name(row, "style"))
    styles = {
        "murattal": RecitationStyle.MURATTAL,
        "mujawwad": RecitationStyle.MUJAWWAD,
        "muallim": RecitationStyle.MUALLIM,
        "kids-repeat": RecitationStyle.KIDS_REPEAT,
    }
    try:
        return styles[value]
    except KeyError as exc:
        raise QuranFoundationError(f"Unsupported recitation style: {value or 'unknown'}.") from exc


_RIWAYAH_ALIASES: dict[str, tuple[str, ...]] = {
    "hafs": ("hafs",),
    "warsh": ("warsh",),
    "shubah": ("shubah", "shuba"),
    "qalun": ("qalun", "qaloun"),
    "al-douri": ("al douri", "al duri", "aldouri", "alduri"),
    "al-sousi": ("al sousi", "al susi", "alsousi", "alsusi"),
}


def _ensure_riwayah_compatible(
    source_qirat: str,
    quran_version: QuranEditionVersion,
) -> None:
    if not source_qirat:
        raise QuranFoundationError(
            "The selected recitation has no qira'ah metadata and cannot be matched safely."
        )
    edition_riwayah = quran_version.edition.riwayah.strip()
    source_family = _riwayah_family(source_qirat)
    edition_family = _riwayah_family(edition_riwayah)
    if source_family != edition_family:
        raise QuranFoundationError(
            f"Quran.Foundation qira'ah '{source_qirat}' is incompatible with "
            f"Quran edition riwayah '{edition_riwayah}'."
        )


def _riwayah_family(value: str) -> str:
    normalized = " ".join(slugify(value).replace("-", " ").split())
    compact = normalized.replace(" ", "")
    for family, aliases in _RIWAYAH_ALIASES.items():
        for alias in aliases:
            normalized_alias = alias.replace("-", " ")
            compact_alias = normalized_alias.replace(" ", "")
            if normalized == normalized_alias or normalized.startswith(f"{normalized_alias} "):
                return family
            if compact == compact_alias or compact.startswith(f"{compact_alias}an"):
                return family
    return normalized


def _checksum(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()
