"""Player background videos uploaded in the admin.

Whatever the editor uploads is re-encoded here: the sound is removed, the
picture is scaled to at most 720p and capped in length, and the file is laid
out to start playing at once. The first frame becomes the poster, which is
also the background's image, so a phone shows it while the video loads and
an app without video support still shows a still.
"""

from __future__ import annotations

import hashlib
import subprocess
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.player_background_upload import (
    MAX_PLAYER_BACKGROUND_BYTES,
    player_background_uploader,
)
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectUploader

MAX_VIDEO_UPLOAD_MIB = 60
MAX_VIDEO_SECONDS = 30
# A phone downloads this once and loops it behind the recitation.
MAX_VIDEO_OUTPUT_MIB = 6
VIDEO_LONG_SIDE = 1280
FFMPEG_TIMEOUT_SECONDS = 120


class PlayerBackgroundVideoError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class PlayerBackgroundVideoResult:
    video_object_key: str
    poster_object_key: str


def upload_player_background_video(
    uploaded: UploadedFile,
    *,
    uploader: ObjectUploader | None = None,
    ffmpeg: str = "ffmpeg",
) -> PlayerBackgroundVideoResult:
    with TemporaryDirectory(prefix="iqro-player-video-") as directory:
        folder = Path(directory)
        source = folder / "source"
        size_bytes = 0
        with source.open("wb") as file:
            for chunk in uploaded.chunks():
                size_bytes += len(chunk)
                if size_bytes > MAX_VIDEO_UPLOAD_MIB * 1024 * 1024:
                    raise PlayerBackgroundVideoError(
                        f"Видео должно быть не больше {MAX_VIDEO_UPLOAD_MIB} МБ."
                    )
                file.write(chunk)
        if size_bytes == 0:
            raise PlayerBackgroundVideoError("Выбранный файл пуст.")

        video = folder / "background.mp4"
        poster = folder / "poster.jpg"
        _ffmpeg(
            ffmpeg,
            "-i",
            str(source),
            "-t",
            str(MAX_VIDEO_SECONDS),
            # No sound, subtitles or data tracks, and no metadata such as location.
            "-an",
            "-sn",
            "-dn",
            "-map_metadata",
            "-1",
            "-vf",
            # Fit within 1280 by 1280, never upscaling a smaller clip.
            f"scale='min({VIDEO_LONG_SIDE},iw)':'min({VIDEO_LONG_SIDE},ih)'"
            ":force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p",
            "-fpsmax",
            "30",
            "-c:v",
            "libx264",
            "-profile:v",
            "main",
            "-preset",
            "veryfast",
            "-crf",
            "27",
            "-movflags",
            "+faststart",
            str(video),
        )
        _ffmpeg(ffmpeg, "-i", str(video), "-frames:v", "1", "-q:v", "3", str(poster))

        if video.stat().st_size > MAX_VIDEO_OUTPUT_MIB * 1024 * 1024:
            raise PlayerBackgroundVideoError(
                f"После сжатия видео больше {MAX_VIDEO_OUTPUT_MIB} МБ. "
                "Загрузите ролик короче или спокойнее по движению."
            )
        if poster.stat().st_size > MAX_PLAYER_BACKGROUND_BYTES:
            raise PlayerBackgroundVideoError("Постер нужного размера сделать не удалось.")

        actual_uploader = uploader or player_background_uploader()
        return PlayerBackgroundVideoResult(
            video_object_key=_store(actual_uploader, video, "video/mp4", "mp4"),
            poster_object_key=_store(actual_uploader, poster, "image/jpeg", "jpg"),
        )


def _ffmpeg(ffmpeg: str, *arguments: str) -> None:
    try:
        subprocess.run(  # noqa: S603 - fixed program, no shell, paths we created
            [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *arguments],
            check=True,
            capture_output=True,
            timeout=FFMPEG_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        raise PlayerBackgroundVideoError(
            "Видео обрабатывалось слишком долго. Загрузите ролик короче."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise PlayerBackgroundVideoError(
            "Файл не удалось обработать. Загрузите видео MP4, MOV или WebM."
        ) from exc


def _store(uploader: ObjectUploader, path: Path, content_type: str, extension: str) -> str:
    data = path.read_bytes()
    checksum = hashlib.sha256(data).hexdigest()
    stored = uploader.upload_path(
        path,
        ImmutableObjectSpec(
            key=f"audio/player-backgrounds/{checksum[:20]}.{extension}",
            content_type=content_type,
            size_bytes=len(data),
            checksum_sha256=checksum,
        ),
    )
    return stored.key
