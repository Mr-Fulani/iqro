# ruff: noqa: RUF001 -- Admin-facing messages intentionally use Cyrillic characters.

"""Whole-surah MP3 files uploaded in the admin.

Each file becomes one surah track with one managed rendition. Everything the
model needs is measured here rather than typed by an editor: the duration and
bitrate by ffprobe, the size and SHA-256 from the bytes. The file is stored
create-only under an immutable key, the public URL is checked to serve it the
way the media contract requires, and only then are the rows created, so a
published listening recitation never shows a surah that does not play.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioRendition,
    AudioRenditionQuality,
    AudioTrack,
    AudioTrackScope,
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.audio.selectors import forget_recitation_summaries
from quran_backend.modules.audio.validators import validate_strong_etag
from quran_backend.modules.core.content_revalidation import enqueue_audio_content_change
from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)

# The Quran edition the apps' audio catalogs ask for.
LISTENING_QURAN_EDITION = "madani-hafs"
# The app refuses offline audio files above 512 MB, so nothing larger is accepted.
MAX_SURAH_UPLOAD_MIB = 512
MAX_SURAH_SECONDS = 8 * 60 * 60
FFPROBE_TIMEOUT_SECONDS = 60
CDN_CHECK_TIMEOUT_SECONDS = 15
MIN_IMMUTABLE_MAX_AGE = 31_536_000
_LEADING_NUMBER = re.compile(r"\s*0*(\d{1,3})(?!\d)")

PublicObjectVerifier = Callable[[str, int, str], str]


class SurahUploadError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class SurahUploadResult:
    track_id: uuid.UUID
    surah_number: int
    duration_ms: int
    bitrate_kbps: int
    size_bytes: int


@dataclass(frozen=True, slots=True)
class _Probe:
    duration_ms: int
    bitrate_kbps: int


def surah_number_from_filename(name: str) -> int | None:
    """Read the surah from names such as 001.mp3, 2.mp3 or 112 Al-Ikhlas.mp3."""
    match = _LEADING_NUMBER.match(Path(name).name)
    if match is None:
        return None
    number = int(match.group(1))
    return number if 1 <= number <= 114 else None


def accepts_new_surahs(recitation: RecitationEdition) -> bool:
    return recitation.status == RecitationPublicationStatus.DRAFT or (
        recitation.status == RecitationPublicationStatus.PUBLISHED and recitation.listening_only
    )


def surah_audio_uploader() -> ObjectUploader:
    if (
        settings.DEBUG
        and getattr(settings, "LOCAL_DEVELOPMENT", False)
        and not settings.MEDIA_OBJECT_STORAGE_ENABLED
        and not settings.MEDIA_OBJECT_STORAGE_REQUIRED
    ):
        return LocalMediaUploader()
    return configured_object_uploader()


def upload_surah_audio(  # noqa: PLR0913
    recitation_id: uuid.UUID,
    surah_number: int,
    source_path: Path,
    *,
    uploader: ObjectUploader | None = None,
    verify_public: PublicObjectVerifier | None = None,
    ffprobe: str = "ffprobe",
) -> SurahUploadResult:
    recitation = RecitationEdition.objects.filter(pk=recitation_id).first()
    if recitation is None:
        raise SurahUploadError("Запись не найдена.")
    _check_target(recitation, surah_number)

    size_bytes = source_path.stat().st_size
    if size_bytes == 0:
        raise SurahUploadError("Файл пуст.")
    if size_bytes > MAX_SURAH_UPLOAD_MIB * 1024 * 1024:
        raise SurahUploadError(f"Файл суры должен быть не больше {MAX_SURAH_UPLOAD_MIB} МБ.")
    probe = _probe(ffprobe, source_path, size_bytes)
    checksum = _sha256(source_path)
    object_key = (
        f"audio/recitations/{recitation.code}/{recitation.version}/"
        f"surah-{surah_number:03d}-{checksum[:16]}.mp3"
    )

    actual_uploader = uploader or surah_audio_uploader()
    stored = actual_uploader.upload_path(
        source_path,
        ImmutableObjectSpec(
            key=object_key,
            content_type=AudioContentType.MPEG,
            size_bytes=size_bytes,
            checksum_sha256=checksum,
        ),
    )
    public_url = f"{settings.PUBLIC_AUDIO_BASE_URL.rstrip('/')}/{object_key}"
    if verify_public is not None:
        edge_etag = verify_public(public_url, size_bytes, AudioContentType.MPEG)
    elif isinstance(actual_uploader, LocalMediaUploader):
        # Local development serves /media without a CDN; the stored file is the evidence.
        edge_etag = stored.etag
    else:
        edge_etag = verify_public_audio_object(public_url, size_bytes, AudioContentType.MPEG)

    with transaction.atomic():
        locked = RecitationEdition.objects.select_for_update().get(pk=recitation_id)
        _check_target(locked, surah_number)
        try:
            track = AudioTrack.objects.create(
                recitation_edition=locked,
                scope=AudioTrackScope.SURAH,
                surah_number=surah_number,
                duration_ms=probe.duration_ms,
            )
            AudioRendition.objects.create(
                track=track,
                quality=AudioRenditionQuality.STANDARD,
                is_default=True,
                codec=AudioCodec.MP3,
                content_type=AudioContentType.MPEG,
                bitrate_kbps=probe.bitrate_kbps,
                size_bytes=size_bytes,
                checksum_sha256=checksum,
                object_key=object_key,
                origin_etag=stored.etag,
                etag=edge_etag,
                cdn_contract_verified_at=timezone.now(),
            )
        except ValidationError as exc:
            raise SurahUploadError(" ".join(exc.messages)) from exc
        if locked.status == RecitationPublicationStatus.PUBLISHED:
            transaction.on_commit(lambda: _announce_new_surah(locked))

    return SurahUploadResult(
        track_id=track.id,
        surah_number=surah_number,
        duration_ms=probe.duration_ms,
        bitrate_kbps=probe.bitrate_kbps,
        size_bytes=size_bytes,
    )


def verify_public_audio_object(url: str, size_bytes: int, content_type: str) -> str:
    """Check that the public URL serves the stored bytes as immutable audio.

    Returns the strong ETag the CDN serves. The full contract in
    ops/media/contract.py (CORS and Range for every client origin) still gates
    offline packages; this is the per-file evidence a listening surah needs.
    """
    scheme = urlsplit(url).scheme
    if scheme != "https" and not (
        scheme == "http" and getattr(settings, "MEDIA_OBJECT_STORAGE_ALLOW_HTTP", False)
    ):
        raise SurahUploadError("Публичный адрес аудио должен быть HTTPS.")
    # The URL is PUBLIC_AUDIO_BASE_URL plus a key we generated, and its scheme is checked above.
    request = Request(url, method="HEAD", headers={"User-Agent": "IQRO-admin-media-check"})  # noqa: S310
    try:
        with urlopen(request, timeout=CDN_CHECK_TIMEOUT_SECONDS) as response:  # noqa: S310
            status = response.status
            headers = response.headers
    except HTTPError as exc:
        raise SurahUploadError(
            f"Файл сохранён, но CDN ответил {exc.code}. Повторите загрузку через минуту."
        ) from exc
    except (URLError, TimeoutError, OSError) as exc:
        raise SurahUploadError(
            "Файл сохранён, но CDN недоступен. Повторите загрузку через минуту."
        ) from exc

    problems: list[str] = []
    if status != 200:
        problems.append(f"статус {status}")
    if headers.get("Content-Length") != str(size_bytes):
        problems.append("размер")
    if (headers.get("Content-Type") or "").split(";")[0].strip().lower() != content_type:
        problems.append("тип файла")
    etag = headers.get("ETag") or ""
    try:
        validate_strong_etag(etag)
    except ValidationError:
        problems.append("ETag")
    if not _is_immutable_cache(headers.get("Cache-Control") or ""):
        problems.append("Cache-Control")
    if problems:
        raise SurahUploadError(
            "CDN отдаёт файл не так, как нужно (" + ", ".join(problems) + "). "
            "Сообщите администратору хранилища."
        )
    return etag


def _check_target(recitation: RecitationEdition, surah_number: int) -> None:
    if not accepts_new_surahs(recitation):
        raise SurahUploadError(
            "Суры можно добавлять в черновик или в опубликованную запись "
            "«только для вкладки Аудио»."
        )
    if not 1 <= surah_number <= 114:
        raise SurahUploadError("Номер суры должен быть от 1 до 114.")
    if AudioTrack.objects.filter(
        recitation_edition=recitation,
        scope=AudioTrackScope.SURAH,
        surah_number=surah_number,
    ).exists():
        raise SurahUploadError(f"Сура {surah_number} уже есть в этой записи.")


def _probe(ffprobe: str, path: Path, size_bytes: int) -> _Probe:
    try:
        completed = subprocess.run(  # noqa: S603 - fixed program, no shell, our temp path
            [
                ffprobe,
                "-v",
                "error",
                "-print_format",
                "json",
                "-show_format",
                "-show_streams",
                "-select_streams",
                "a:0",
                str(path),
            ],
            check=True,
            capture_output=True,
            timeout=FFPROBE_TIMEOUT_SECONDS,
        )
        report = json.loads(completed.stdout)
    except subprocess.TimeoutExpired as exc:
        raise SurahUploadError("Файл проверялся слишком долго.") from exc
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise SurahUploadError("Файл не читается как аудио. Загрузите MP3.") from exc

    streams = report.get("streams") or []
    file_format = report.get("format") or {}
    if (
        not streams
        or streams[0].get("codec_name") != "mp3"
        or "mp3" not in str(file_format.get("format_name", "")).split(",")
    ):
        raise SurahUploadError("Поддерживается только MP3.")
    try:
        duration_seconds = float(file_format["duration"])
    except (KeyError, TypeError, ValueError) as exc:
        raise SurahUploadError("Не удалось определить длительность файла.") from exc
    duration_ms = round(duration_seconds * 1000)
    if duration_ms <= 0 or duration_seconds > MAX_SURAH_SECONDS:
        raise SurahUploadError("Длительность суры выглядит неверной.")
    try:
        bitrate_kbps = round(int(file_format["bit_rate"]) / 1000)
    except KeyError, TypeError, ValueError:
        bitrate_kbps = round(size_bytes * 8 / duration_seconds / 1000)
    if not 1 <= bitrate_kbps <= 100_000:
        raise SurahUploadError("Не удалось определить битрейт файла.")
    return _Probe(duration_ms=duration_ms, bitrate_kbps=bitrate_kbps)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _is_immutable_cache(value: str) -> bool:
    directives = {part.strip().lower() for part in value.split(",") if part.strip()}
    max_age = next(
        (item.split("=", 1)[1] for item in directives if item.startswith("max-age=")), ""
    )
    return (
        "public" in directives
        and "immutable" in directives
        and max_age.isdigit()
        and int(max_age) >= MIN_IMMUTABLE_MAX_AGE
    )


def _announce_new_surah(recitation: RecitationEdition) -> None:
    forget_recitation_summaries()
    enqueue_audio_content_change(
        action="published",
        recitation_id=recitation.id,
        reciter_id=recitation.reciter_id,
        version=recitation.version,
    )
