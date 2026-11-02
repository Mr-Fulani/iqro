# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Reciter portraits: the uploaded original and two smaller WebP copies.

Avatars on the site are at most 112 CSS px and the app's player artwork is
about 200 dp, so the site and app lists load a 320 px copy and the player a
640 px one instead of a multi-megabyte original.
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
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import UploadedFile
from django.core.validators import validate_slug

from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)

logger = logging.getLogger(__name__)

MAX_RECITER_PORTRAIT_MIB = 50
MAX_RECITER_PORTRAIT_BYTES = MAX_RECITER_PORTRAIT_MIB * 1024 * 1024
# The shorter side of each copy; a smaller original is never enlarged.
PORTRAIT_DISPLAY_SIDE = 640
PORTRAIT_THUMBNAIL_SIDE = 320
TOOL_TIMEOUT_SECONDS = 60


class ReciterPortraitUploadError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ReciterPortraitVariants:
    display_object_key: str
    thumbnail_object_key: str


@dataclass(frozen=True, slots=True)
class ReciterPortraitUploadResult:
    object_key: str
    etag: str
    created: bool
    variants: ReciterPortraitVariants


def upload_reciter_portrait(
    uploaded: UploadedFile,
    *,
    reciter_code: str,
    uploader: ObjectUploader | None = None,
    ffmpeg: str = "ffmpeg",
    ffprobe: str = "ffprobe",
) -> ReciterPortraitUploadResult:
    try:
        validate_slug(reciter_code)
    except ValidationError as exc:
        raise ReciterPortraitUploadError("Сначала укажите корректный код чтеца латиницей.") from exc

    digest = hashlib.sha256()
    size_bytes = 0
    header = bytearray()
    with NamedTemporaryFile(prefix="iqro-reciter-portrait-", suffix=".upload") as temporary:
        for chunk in uploaded.chunks():
            size_bytes += len(chunk)
            if size_bytes > MAX_RECITER_PORTRAIT_BYTES:
                raise ReciterPortraitUploadError(
                    f"Портрет должен быть не больше {MAX_RECITER_PORTRAIT_MIB} МБ."
                )
            if len(header) < 16:
                header.extend(chunk[: 16 - len(header)])
            digest.update(chunk)
            temporary.write(chunk)

        if size_bytes == 0:
            raise ReciterPortraitUploadError("Выбранный файл пуст.")
        content_type, extension = _image_format(bytes(header))
        checksum = digest.hexdigest()
        object_key = f"audio/reciter-portraits/{reciter_code}/{checksum[:20]}.{extension}"
        temporary.flush()
        actual_uploader = uploader or portrait_uploader()
        stored = actual_uploader.upload_path(
            Path(temporary.name),
            ImmutableObjectSpec(
                key=object_key,
                content_type=content_type,
                size_bytes=size_bytes,
                checksum_sha256=checksum,
            ),
        )
        variants = store_reciter_portrait_variants(
            temporary.name,
            original_object_key=stored.key,
            reciter_code=reciter_code,
            uploader=actual_uploader,
            ffmpeg=ffmpeg,
            ffprobe=ffprobe,
        )

    return ReciterPortraitUploadResult(
        object_key=stored.key,
        etag=stored.etag,
        created=stored.created,
        variants=variants,
    )


def portrait_uploader() -> ObjectUploader:
    """Local media in development without object storage, else the configured bucket."""
    if (
        settings.DEBUG
        and getattr(settings, "LOCAL_DEVELOPMENT", False)
        and not settings.MEDIA_OBJECT_STORAGE_ENABLED
        and not settings.MEDIA_OBJECT_STORAGE_REQUIRED
    ):
        return LocalMediaUploader()
    return configured_object_uploader()


def store_reciter_portrait_variants(  # noqa: PLR0913
    source: str,
    *,
    original_object_key: str,
    reciter_code: str,
    uploader: ObjectUploader,
    ffmpeg: str = "ffmpeg",
    ffprobe: str = "ffprobe",
) -> ReciterPortraitVariants:
    """Store the 640 px and 320 px WebP copies of a portrait file or URL.

    A copy that would not be smaller than the original is not stored: its key
    is the original's, so a small portrait is served as it is.
    """
    width, height, original_bytes = _probe(ffprobe, source)
    keys = []
    with TemporaryDirectory(prefix="iqro-reciter-portrait-variant-") as folder:
        for side in (PORTRAIT_DISPLAY_SIDE, PORTRAIT_THUMBNAIL_SIDE):
            scale = min(1.0, side / min(width, height))
            target = Path(folder) / f"{side}.webp"
            _encode_webp(
                ffmpeg,
                source,
                target,
                max(1, round(width * scale)),
                max(1, round(height * scale)),
            )
            payload = target.read_bytes()
            if len(payload) >= original_bytes:
                keys.append(original_object_key)
                continue
            checksum = hashlib.sha256(payload).hexdigest()
            stored = uploader.upload_path(
                target,
                ImmutableObjectSpec(
                    key=f"audio/reciter-portraits/{reciter_code}/{checksum[:20]}.webp",
                    content_type="image/webp",
                    size_bytes=len(payload),
                    checksum_sha256=checksum,
                ),
            )
            keys.append(stored.key)
    display, thumbnail = keys
    return ReciterPortraitVariants(display_object_key=display, thumbnail_object_key=thumbnail)


def _encode_webp(ffmpeg: str, source: str, target: Path, width: int, height: int) -> None:
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
        f"scale={width}:{height}:flags=lanczos",
        "-frames:v",
        "1",
        "-c:v",
        "libwebp",
        "-quality",
        "82",
        "-compression_level",
        "6",
        str(target),
    )


def _probe(ffprobe: str, source: str) -> tuple[int, int, int]:
    output = _run(
        ffprobe,
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height:format=size",
        "-of",
        "json",
        source,
    )
    try:
        probed = json.loads(output)
        stream = probed["streams"][0]
        width, height = int(stream["width"]), int(stream["height"])
        size_bytes = int(probed["format"]["size"])
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise ReciterPortraitUploadError("Не удалось прочитать размер портрета.") from exc
    if width <= 0 or height <= 0 or size_bytes <= 0:
        raise ReciterPortraitUploadError("Не удалось прочитать размер портрета.")
    return width, height, size_bytes


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
        raise ReciterPortraitUploadError(f"На сервере нет {program}.") from exc
    except subprocess.TimeoutExpired as exc:
        raise ReciterPortraitUploadError(
            "Обработка портрета заняла слишком много времени."
        ) from exc
    except subprocess.CalledProcessError as exc:
        logger.warning("Reciter portrait tool failed", extra={"stderr": exc.stderr[-500:]})
        raise ReciterPortraitUploadError("Не удалось обработать портрет.") from exc
    return completed.stdout


def _image_format(header: bytes) -> tuple[str, str]:
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if header.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return "image/webp", "webp"
    raise ReciterPortraitUploadError("Поддерживаются только изображения WebP, JPEG и PNG.")
