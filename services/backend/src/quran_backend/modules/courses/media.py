# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Course covers: any JPEG, PNG or WebP becomes two WebP pictures in 16:9.

The centre is cropped to 16:9 and scaled to 1280x720 for the course page and
640x360 for catalog cards (Lighthouse: a card cover stays under 50 KiB). Both
are stored under immutable keys like the salah illustrations; objects in R2 are
never deleted automatically (ADR 0001).
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectUploader
from quran_backend.modules.core.webp import webp_size

COVER_SIZE = (1280, 720)
THUMB_SIZE = (640, 360)
TARGET_COVER_BYTES = 150 * 1024
TARGET_THUMB_BYTES = 50 * 1024
MAX_SOURCE_MIB = 20
WEBP_QUALITIES = (80, 70, 60, 50, 40)
FFMPEG_TIMEOUT_SECONDS = 60


class CourseCoverError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class CourseCover:
    object_key: str
    thumb_object_key: str
    width: int
    height: int


def upload_course_cover(
    uploaded: UploadedFile,
    *,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
) -> CourseCover:
    program = ffmpeg or shutil.which("ffmpeg") or "ffmpeg"
    with TemporaryDirectory(prefix="iqro-course-cover-") as directory:
        folder = Path(directory)
        source = folder / "source"
        _save_upload(uploaded, source)
        if not _is_image(source):
            raise CourseCoverError("Нужна картинка JPEG, PNG или WebP.")
        cover = _encode(program, source, folder / "cover.webp", COVER_SIZE, TARGET_COVER_BYTES)
        thumb = _encode(program, source, folder / "thumb.webp", THUMB_SIZE, TARGET_THUMB_BYTES)
        digest = hashlib.sha256(cover.read_bytes()).hexdigest()
        stem = f"courses/covers/{digest[:20]}"
        actual_uploader = uploader or player_background_uploader()
        cover_key = _store(actual_uploader, cover, f"{stem}.webp")
        thumb_key = _store(actual_uploader, thumb, f"{stem}-{THUMB_SIZE[0]}.webp")
    return CourseCover(
        object_key=cover_key,
        thumb_object_key=thumb_key,
        width=COVER_SIZE[0],
        height=COVER_SIZE[1],
    )


def _save_upload(uploaded: UploadedFile, path: Path) -> None:
    size_bytes = 0
    with path.open("wb") as file:
        for chunk in uploaded.chunks():
            size_bytes += len(chunk)
            if size_bytes > MAX_SOURCE_MIB * 1024 * 1024:
                raise CourseCoverError(f"Картинка должна быть не больше {MAX_SOURCE_MIB} МБ.")
            file.write(chunk)
    if size_bytes == 0:
        raise CourseCoverError("Выбранный файл пуст.")


def _is_image(path: Path) -> bool:
    with path.open("rb") as file:
        head = file.read(12)
    return head.startswith((b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n")) or (
        head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    )


def _encode(ffmpeg: str, source: Path, target: Path, size: tuple[int, int], limit: int) -> Path:
    """The lightest quality that still reads well: stops once under the limit."""
    width, height = size
    for quality in WEBP_QUALITIES:
        try:
            subprocess.run(  # noqa: S603 - fixed program, no shell, paths we created
                [
                    ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(source),
                    "-vf", f"scale={width}:{height}:force_original_aspect_ratio=increase,"
                    f"crop={width}:{height}",
                    "-frames:v", "1", "-c:v", "libwebp", "-quality", str(quality),
                    str(target),
                ],
                check=True,
                capture_output=True,
                timeout=FFMPEG_TIMEOUT_SECONDS,
            )  # fmt: skip
        except FileNotFoundError as exc:
            raise CourseCoverError(f"На сервере нет {ffmpeg}.") from exc
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            raise CourseCoverError(
                "Картинку не удалось обработать. Загрузите JPEG, PNG или WebP."
            ) from exc
        if target.stat().st_size <= limit:
            break
    if webp_size(target.read_bytes()) != size:
        raise CourseCoverError("Картинку не удалось обработать. Загрузите JPEG, PNG или WebP.")
    return target


def _store(uploader: ObjectUploader, path: Path, key: str) -> str:
    data = path.read_bytes()
    stored = uploader.upload_path(
        path,
        ImmutableObjectSpec(
            key=key,
            content_type="image/webp",
            size_bytes=len(data),
            checksum_sha256=hashlib.sha256(data).hexdigest(),
        ),
    )
    return stored.key
