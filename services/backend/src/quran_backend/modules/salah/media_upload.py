"""Course illustrations uploaded by the owner in the admin.

Any PNG, JPEG or WebP is cropped to the centre square, scaled to 720x720 and
re-encoded as WebP by ffmpeg, then stored like imported media. Only drafts
change: a published version is immutable.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.core.object_storage import ObjectUploader
from quran_backend.modules.salah.importer import (
    MAX_IMAGE_BYTES,
    compile_version,
    store_media,
    webp_size,
)
from quran_backend.modules.salah.models import (
    SalahCourseVersion,
    SalahMediaAsset,
    SalahPublicationStatus,
)

IMAGE_SIDE = 720
TARGET_IMAGE_BYTES = 60 * 1024
MAX_SOURCE_MIB = 20
WEBP_QUALITIES = (80, 70, 60, 50, 40)
FFMPEG_TIMEOUT_SECONDS = 60


class SalahMediaUploadError(ValueError):
    pass


def image_keys(version: SalahCourseVersion) -> list[dict[str, object]]:
    """The snapshot's illustrations, in snapshot order."""
    return [
        asset
        for asset in version.snapshot.get("media", [])
        if str(asset.get("file", "")).lower().endswith(".webp")
    ]


def upload_salah_image(
    version: SalahCourseVersion,
    key: str,
    uploaded: UploadedFile,
    *,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
) -> SalahMediaAsset:
    if version.status != SalahPublicationStatus.DRAFT:
        raise SalahMediaUploadError(
            "Иллюстрации меняются только в черновике. Для опубликованной версии импортируйте новую."
        )
    if key not in {asset["key"] for asset in image_keys(version)}:
        raise SalahMediaUploadError(f"Иллюстрации «{key}» нет в снимке курса.")
    with TemporaryDirectory(prefix="iqro-salah-image-") as directory:
        folder = Path(directory)
        source = folder / "source"
        size_bytes = 0
        with source.open("wb") as file:
            for chunk in uploaded.chunks():
                size_bytes += len(chunk)
                if size_bytes > MAX_SOURCE_MIB * 1024 * 1024:
                    raise SalahMediaUploadError(f"Файл должен быть не больше {MAX_SOURCE_MIB} МБ.")
                file.write(chunk)
        if size_bytes == 0:
            raise SalahMediaUploadError("Выбранный файл пуст.")
        image = _encode_webp(source, folder, ffmpeg or shutil.which("ffmpeg") or "ffmpeg")
        asset = store_media(version, key, image, uploader or player_background_uploader())
    compile_version(version)
    return asset


def _encode_webp(source: Path, folder: Path, ffmpeg: str) -> Path:
    """The lightest quality that still reads well: stops at the target size."""
    side = str(IMAGE_SIDE)
    image = folder / "image.webp"
    for quality in WEBP_QUALITIES:
        try:
            subprocess.run(  # noqa: S603 - fixed program, no shell, paths we created
                [
                    ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(source),
                    "-vf", f"scale={side}:{side}:force_original_aspect_ratio=increase,"
                    f"crop={side}:{side}",
                    "-frames:v", "1", "-c:v", "libwebp", "-quality", str(quality),
                    str(image),
                ],
                check=True,
                capture_output=True,
                timeout=FFMPEG_TIMEOUT_SECONDS,
            )  # fmt: skip
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            raise SalahMediaUploadError(
                "Файл не удалось обработать. Загрузите изображение PNG, JPEG или WebP."
            ) from exc
        if image.stat().st_size <= TARGET_IMAGE_BYTES:
            break
    data = image.read_bytes()
    if webp_size(data) != (IMAGE_SIDE, IMAGE_SIDE) or len(data) > MAX_IMAGE_BYTES:
        raise SalahMediaUploadError(
            "Изображение не удалось сжать до допустимого размера. Упростите картинку."
        )
    return image
