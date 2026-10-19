from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from tempfile import NamedTemporaryFile

from django.conf import settings
from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)

# Backgrounds are decoded on phones behind a playing recitation; keep them small.
MAX_PLAYER_BACKGROUND_KIB = 512
MAX_PLAYER_BACKGROUND_BYTES = MAX_PLAYER_BACKGROUND_KIB * 1024


class PlayerBackgroundUploadError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class PlayerBackgroundUploadResult:
    object_key: str
    etag: str
    created: bool


def upload_player_background(
    uploaded: UploadedFile,
    *,
    uploader: ObjectUploader | None = None,
) -> PlayerBackgroundUploadResult:
    digest = hashlib.sha256()
    size_bytes = 0
    header = bytearray()
    with NamedTemporaryFile(prefix="iqro-player-background-", suffix=".upload") as temporary:
        for chunk in uploaded.chunks():
            size_bytes += len(chunk)
            if size_bytes > MAX_PLAYER_BACKGROUND_BYTES:
                raise PlayerBackgroundUploadError(
                    f"Фон должен быть не больше {MAX_PLAYER_BACKGROUND_KIB} КБ. "
                    "Сожмите изображение до разрешения телефона (около 1080x1920)."
                )
            if len(header) < 16:
                header.extend(chunk[: 16 - len(header)])
            digest.update(chunk)
            temporary.write(chunk)

        if size_bytes == 0:
            raise PlayerBackgroundUploadError("Выбранный файл пуст.")
        content_type, extension = _image_format(bytes(header))
        checksum = digest.hexdigest()
        object_key = f"audio/player-backgrounds/{checksum[:20]}.{extension}"
        temporary.flush()
        actual_uploader = uploader or player_background_uploader()
        stored = actual_uploader.upload_path(
            Path(temporary.name),
            ImmutableObjectSpec(
                key=object_key,
                content_type=content_type,
                size_bytes=size_bytes,
                checksum_sha256=checksum,
            ),
        )

    return PlayerBackgroundUploadResult(
        object_key=stored.key,
        etag=stored.etag,
        created=stored.created,
    )


def player_background_uploader() -> ObjectUploader:
    """Local media in development without object storage, else the configured bucket."""
    if (
        settings.DEBUG
        and getattr(settings, "LOCAL_DEVELOPMENT", False)
        and not settings.MEDIA_OBJECT_STORAGE_ENABLED
        and not settings.MEDIA_OBJECT_STORAGE_REQUIRED
    ):
        return LocalMediaUploader()
    return configured_object_uploader()


def _image_format(header: bytes) -> tuple[str, str]:
    if header.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return "image/webp", "webp"
    raise PlayerBackgroundUploadError("Поддерживаются только изображения WebP и JPEG.")
