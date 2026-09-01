from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from tempfile import NamedTemporaryFile

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import UploadedFile
from django.core.validators import validate_slug

from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)

MAX_RECITER_PORTRAIT_MIB = 50
MAX_RECITER_PORTRAIT_BYTES = MAX_RECITER_PORTRAIT_MIB * 1024 * 1024


class ReciterPortraitUploadError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ReciterPortraitUploadResult:
    object_key: str
    etag: str
    created: bool


def upload_reciter_portrait(
    uploaded: UploadedFile,
    *,
    reciter_code: str,
    uploader: ObjectUploader | None = None,
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
        actual_uploader = uploader or configured_object_uploader()
        stored = actual_uploader.upload_path(
            Path(temporary.name),
            ImmutableObjectSpec(
                key=object_key,
                content_type=content_type,
                size_bytes=size_bytes,
                checksum_sha256=checksum,
            ),
        )

    return ReciterPortraitUploadResult(
        object_key=stored.key,
        etag=stored.etag,
        created=stored.created,
    )


def _image_format(header: bytes) -> tuple[str, str]:
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if header.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return "image/webp", "webp"
    raise ReciterPortraitUploadError("Поддерживаются только изображения WebP, JPEG и PNG.")
