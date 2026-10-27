"""Course illustrations and recordings uploaded by the owner in the admin.

Any PNG, JPEG, WebP or SVG (drawn by rsvg-convert first) is cropped to the
centre square, scaled to 720x720 and re-encoded as WebP by ffmpeg, then stored
like imported media. A recording is an m4a or mp3 stored as it is, once
ffprobe has read it as one. Only drafts change: a published version is
immutable.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.core.object_storage import ObjectUploader
from quran_backend.modules.core.webp import webp_size
from quran_backend.modules.salah.importer import (
    MAX_AUDIO_BYTES,
    MAX_IMAGE_BYTES,
    compile_version,
    store_media,
)
from quran_backend.modules.salah.models import (
    SalahCourseVersion,
    SalahMediaAsset,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.snapshot import snapshot_checksum

IMAGE_SIDE = 720
TARGET_IMAGE_BYTES = 60 * 1024
MAX_SOURCE_MIB = 20
WEBP_QUALITIES = (80, 70, 60, 50, 40)
FFMPEG_TIMEOUT_SECONDS = 60
# A step's explanation or a formula, not a lecture.
MAX_AUDIO_SECONDS = 180
# What ffprobe calls the container of each accepted file type.
AUDIO_FORMATS = {".mp3": {"mp3"}, ".m4a": {"mp4", "m4a", "mov"}}
# An SVG is drawn this large before the crop, so a wide drawing still fills the square.
SVG_RENDER_SIDE = IMAGE_SIDE * 2
IMAGE_FORMATS_HELP = "PNG, JPEG, WebP или SVG"


class SalahMediaUploadError(ValueError):
    pass


def image_keys(version: SalahCourseVersion) -> list[dict[str, object]]:
    """The snapshot's illustrations, in snapshot order."""
    return [
        asset
        for asset in version.snapshot.get("media", [])
        if str(asset.get("file", "")).lower().endswith(".webp")
    ]


def upload_salah_image(  # noqa: PLR0913 - the file and how it replaces the old one
    version: SalahCourseVersion,
    key: str,
    uploaded: UploadedFile,
    *,
    keep_scene: bool = False,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
) -> SalahMediaAsset:
    """Replaces the picture of `key` everywhere it is shown.

    The owner's own picture is no longer a still of the 3D scene: unless
    `keep_scene`, the scene stops playing over it, so the learner sees it.
    """
    if version.status != SalahPublicationStatus.DRAFT or version.is_signed:
        raise SalahMediaUploadError(
            "Иллюстрации меняются только в черновике до подписи. "
            "Создайте из этой версии новый черновик."
        )
    if key not in {asset["key"] for asset in image_keys(version)}:
        raise SalahMediaUploadError(f"Иллюстрации «{key}» нет в снимке курса.")
    with checked_image(uploaded, ffmpeg=ffmpeg) as image:
        asset = store_media(version, key, image, uploader or player_background_uploader())
    if not keep_scene and drop_scene(version.snapshot, key):
        version.checksum_sha256 = snapshot_checksum(version.snapshot)
        version.save(update_fields=["snapshot", "checksum_sha256", "updated_at"])
    compile_version(version)
    return asset


def drop_scene(snapshot: dict[str, Any], key: str) -> bool:
    """The picture stops being a still of the 3D scene; True when it was one."""
    for asset in snapshot.get("media", []):
        if asset.get("key") == key and "scene" in asset:
            del asset["scene"]
            return True
    return False


@contextmanager
def checked_image(
    uploaded: UploadedFile, *, ffmpeg: str | None = None, rsvg: str | None = None
) -> Iterator[Path]:
    """An uploaded picture as a 720x720 WebP in a temporary file.

    The file's own bytes decide what it is, not its name or the browser's type.
    """
    with TemporaryDirectory(prefix="iqro-salah-image-") as directory:
        folder = Path(directory)
        source = folder / "source"
        _save_upload(uploaded, source, max_mib=MAX_SOURCE_MIB)
        with source.open("rb") as file:
            kind = image_kind(file.read(4096))
        if kind is None:
            raise SalahMediaUploadError(
                f"Файл не похож на картинку. Загрузите {IMAGE_FORMATS_HELP}."
            )
        if kind == "svg":
            source = _draw_svg(source, folder, rsvg or shutil.which("rsvg-convert"))
        yield _encode_webp(source, folder, ffmpeg or shutil.which("ffmpeg") or "ffmpeg")


def image_kind(head: bytes) -> str | None:
    """png, jpeg, webp or svg by the first bytes of a file, otherwise None."""
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if head.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    text = head.decode("utf-8", errors="ignore").lstrip("\ufeff \t\r\n").lower()
    if text.startswith(("<svg", "<?xml", "<!--", "<!doctype svg")) and "<svg" in text:
        return "svg"
    return None


def _draw_svg(source: Path, folder: Path, rsvg: str | None) -> Path:
    if rsvg is None:
        raise SalahMediaUploadError(
            "SVG на этом сервере не обрабатывается. Сохраните картинку как PNG и загрузите её."
        )
    drawn = folder / "drawn.png"
    side = str(SVG_RENDER_SIDE)
    try:
        # rsvg-convert reads no network resources; it gets only the uploaded file.
        subprocess.run(  # noqa: S603 - fixed program, no shell, paths we created
            [rsvg, "--keep-aspect-ratio", "-w", side, "-h", side, "-f", "png",
             "-o", str(drawn), str(source)],
            check=True,
            capture_output=True,
            timeout=FFMPEG_TIMEOUT_SECONDS,
        )  # fmt: skip
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        raise SalahMediaUploadError(
            "SVG не удалось нарисовать. Проверьте файл или сохраните картинку как PNG."
        ) from exc
    return drawn


def _save_upload(uploaded: UploadedFile, path: Path, *, max_mib: float) -> None:
    size_bytes = 0
    with path.open("wb") as file:
        for chunk in uploaded.chunks():
            size_bytes += len(chunk)
            if size_bytes > max_mib * 1024 * 1024:
                raise SalahMediaUploadError(f"Файл должен быть не больше {max_mib:g} МБ.")
            file.write(chunk)
    if size_bytes == 0:
        raise SalahMediaUploadError("Выбранный файл пуст.")


@dataclass(frozen=True)
class CheckedAudio:
    path: Path
    duration_ms: int | None


@contextmanager
def checked_audio(uploaded: UploadedFile, *, ffprobe: str | None = None) -> Iterator[CheckedAudio]:
    """An uploaded recording in a temporary file, once it proved to be an m4a or mp3.

    The browser's content type is not trusted: the file's own header and
    ffprobe decide. Without ffprobe (a developer machine) the length is unchecked.
    """
    suffix = Path(uploaded.name or "").suffix.lower()
    if suffix not in AUDIO_FORMATS:
        raise SalahMediaUploadError("Нужна запись в формате .m4a или .mp3.")
    with TemporaryDirectory(prefix="iqro-salah-audio-") as directory:
        path = Path(directory) / f"audio{suffix}"
        _save_upload(uploaded, path, max_mib=MAX_AUDIO_BYTES / 1024 / 1024)
        with path.open("rb") as file:
            head = file.read(12)
        if not _audio_header_matches(suffix, head):
            raise SalahMediaUploadError(
                f"Файл не похож на запись {suffix[1:].upper()}. "
                "Сохраните её заново как m4a или mp3."
            )
        prober = ffprobe or shutil.which("ffprobe")
        duration_ms = _audio_duration_ms(path, suffix, prober) if prober else None
        yield CheckedAudio(path=path, duration_ms=duration_ms)


def _audio_header_matches(suffix: str, head: bytes) -> bool:
    if suffix == ".m4a":
        return head[4:8] == b"ftyp"
    # An ID3 tag or an MPEG audio frame sync.
    return head.startswith(b"ID3") or (len(head) > 1 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0)


def _audio_duration_ms(path: Path, suffix: str, ffprobe: str) -> int:
    try:
        result = subprocess.run(  # noqa: S603 - fixed program, no shell, a path we created
            [
                ffprobe, "-v", "error", "-of", "json",
                "-show_entries", "format=format_name,duration:stream=codec_type",
                str(path),
            ],
            check=True,
            capture_output=True,
            timeout=FFMPEG_TIMEOUT_SECONDS,
        )  # fmt: skip
        info = json.loads(result.stdout or b"{}")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError) as exc:
        raise SalahMediaUploadError(
            "Запись не удалось прочитать. Загрузите файл m4a или mp3."
        ) from exc
    file_format = info.get("format") or {}
    if not AUDIO_FORMATS[suffix] & set(str(file_format.get("format_name", "")).split(",")):
        raise SalahMediaUploadError(
            f"Внутри файла не {suffix[1:].upper()}. Сохраните запись заново как m4a или mp3."
        )
    if not any(stream.get("codec_type") == "audio" for stream in info.get("streams", [])):
        raise SalahMediaUploadError("Звуковой дорожки в файле нет.")
    try:
        seconds = float(file_format.get("duration") or 0)
    except ValueError:
        seconds = 0
    if seconds <= 0:
        raise SalahMediaUploadError("Длительность записи узнать не удалось.")
    if seconds > MAX_AUDIO_SECONDS:
        raise SalahMediaUploadError(
            f"Запись длится {int(seconds) // 60}:{int(seconds) % 60:02d}, "
            f"допустимо до {MAX_AUDIO_SECONDS // 60} минут."
        )
    return round(seconds * 1000)


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
                f"Файл не удалось обработать. Загрузите изображение {IMAGE_FORMATS_HELP}."
            ) from exc
        if image.stat().st_size <= TARGET_IMAGE_BYTES:
            break
    data = image.read_bytes()
    if webp_size(data) != (IMAGE_SIDE, IMAGE_SIDE) or len(data) > MAX_IMAGE_BYTES:
        raise SalahMediaUploadError(
            "Изображение не удалось сжать до допустимого размера. Упростите картинку."
        )
    return image
