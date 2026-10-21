# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Announcement images: the picture shown in the window and a tiny bubble thumbnail.

The bubble is about 52 px with a 34 px picture inside, so phones get a 96 px
thumbnail instead of decoding a full portrait on the home screen.
"""

from __future__ import annotations

import hashlib
import json
import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path
from tempfile import NamedTemporaryFile, TemporaryDirectory

from django.conf import settings
from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)

logger = logging.getLogger(__name__)

MAX_IMAGE_KIB = 512
MAX_IMAGE_BYTES = MAX_IMAGE_KIB * 1024
THUMB_SIDE = 96
TOOL_TIMEOUT_SECONDS = 30


class AnnouncementMediaError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class AnnouncementImage:
    object_key: str
    width: int
    height: int
    thumb_object_key: str


def announcement_uploader() -> ObjectUploader:
    """Local media in development without object storage, else the configured bucket."""
    if (
        settings.DEBUG
        and getattr(settings, "LOCAL_DEVELOPMENT", False)
        and not settings.MEDIA_OBJECT_STORAGE_ENABLED
        and not settings.MEDIA_OBJECT_STORAGE_REQUIRED
    ):
        return LocalMediaUploader()
    return configured_object_uploader()


def upload_announcement_image(
    uploaded: UploadedFile,
    *,
    uploader: ObjectUploader | None = None,
    ffmpeg: str = "ffmpeg",
    ffprobe: str = "ffprobe",
    with_thumbnail: bool = True,
) -> AnnouncementImage:
    digest = hashlib.sha256()
    size_bytes = 0
    header = bytearray()
    actual_uploader = uploader or announcement_uploader()
    with NamedTemporaryFile(prefix="iqro-announcement-", suffix=".upload") as temporary:
        for chunk in uploaded.chunks():
            size_bytes += len(chunk)
            if size_bytes > MAX_IMAGE_BYTES:
                raise AnnouncementMediaError(
                    f"Картинка должна быть не больше {MAX_IMAGE_KIB} КБ. "
                    "Сожмите её до ширины около 1080 px."
                )
            if len(header) < 16:
                header.extend(chunk[: 16 - len(header)])
            digest.update(chunk)
            temporary.write(chunk)
        if size_bytes == 0:
            raise AnnouncementMediaError("Выбранный файл пуст.")
        content_type, extension = _image_format(bytes(header))
        temporary.flush()
        source = Path(temporary.name)
        width, height = _dimensions(ffprobe, source)
        checksum = digest.hexdigest()
        stored = actual_uploader.upload_path(
            source,
            ImmutableObjectSpec(
                key=f"announcements/images/{checksum[:20]}.{extension}",
                content_type=content_type,
                size_bytes=size_bytes,
                checksum_sha256=checksum,
            ),
        )
        thumb_key = _store_thumbnail(actual_uploader, str(source), ffmpeg) if with_thumbnail else ""
    return AnnouncementImage(
        object_key=stored.key,
        width=width,
        height=height,
        thumb_object_key=thumb_key,
    )


def portrait_thumbnail(
    portrait_object_key: str,
    *,
    uploader: ObjectUploader | None = None,
    ffmpeg: str = "ffmpeg",
) -> str:
    """Thumbnail of a reciter portrait already published on the CDN."""
    return _store_thumbnail(
        uploader or announcement_uploader(),
        public_audio_url(portrait_object_key),
        ffmpeg,
    )


def _store_thumbnail(uploader: ObjectUploader, source: str, ffmpeg: str) -> str:
    with TemporaryDirectory(prefix="iqro-announcement-thumb-") as folder:
        thumb = Path(folder) / "thumb.jpg"
        _run(
            ffmpeg,
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            source,
            "-vf",
            (
                f"scale={THUMB_SIDE}:{THUMB_SIDE}:force_original_aspect_ratio=increase,"
                f"crop={THUMB_SIDE}:{THUMB_SIDE}"
            ),
            "-frames:v",
            "1",
            "-q:v",
            "3",
            str(thumb),
        )
        payload = thumb.read_bytes()
        checksum = hashlib.sha256(payload).hexdigest()
        stored = uploader.upload_path(
            thumb,
            ImmutableObjectSpec(
                key=f"announcements/thumbs/{checksum[:20]}.jpg",
                content_type="image/jpeg",
                size_bytes=len(payload),
                checksum_sha256=checksum,
            ),
        )
    return stored.key


def _dimensions(ffprobe: str, source: Path) -> tuple[int, int]:
    output = _run(
        ffprobe,
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "json",
        str(source),
    )
    try:
        stream = json.loads(output)["streams"][0]
        return int(stream["width"]), int(stream["height"])
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise AnnouncementMediaError("Не удалось прочитать размер картинки.") from exc


def _run(program: str, *arguments: str) -> str:
    try:
        completed = subprocess.run(  # noqa: S603 - fixed program, no shell, arguments we built
            [program, *arguments],
            check=True,
            capture_output=True,
            text=True,
            timeout=TOOL_TIMEOUT_SECONDS,
        )
    except FileNotFoundError as exc:
        raise AnnouncementMediaError(f"На сервере нет {program}.") from exc
    except subprocess.TimeoutExpired as exc:
        raise AnnouncementMediaError("Обработка картинки заняла слишком много времени.") from exc
    except subprocess.CalledProcessError as exc:
        logger.warning("Announcement image tool failed", extra={"stderr": exc.stderr[-500:]})
        raise AnnouncementMediaError("Не удалось обработать картинку.") from exc
    return completed.stdout


def _image_format(header: bytes) -> tuple[str, str]:
    if header.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return "image/webp", "webp"
    raise AnnouncementMediaError("Поддерживаются только изображения WebP и JPEG.")
