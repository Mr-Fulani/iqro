# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Lesson videos and their dubs (docs/courses/README.md, «Видео и озвучки»).

The server never re-encodes the picture (decision 3). A video is checked by
ffprobe and remuxed as is: the phone's metadata, GPS included, is dropped and
the index moves to the front, so playback starts at once. It gets a WebP poster
in two sizes and goes to R2 under immutable keys. A dub is the whole sound of
another language: it is encoded to AAC and joined with the video's picture,
which is copied, not re-encoded. Objects in R2 are never deleted (ADR 0001).
"""

from __future__ import annotations

import subprocess
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from shutil import disk_usage, which
from tempfile import TemporaryDirectory, gettempdir
from typing import Any

from django.core.cache import cache
from django.core.files.uploadedfile import UploadedFile
from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.audio.surah_upload import (
    SurahUploadError,
    _sha256,
    ffprobe_report,
    verify_public_audio_object,
)
from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectUploader
from quran_backend.modules.courses.document import snapshot_files
from quran_backend.modules.courses.media import CourseCoverError, _encode, _is_image, _save_upload
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    SPOKEN_LANGUAGES,
    CourseLesson,
    CourseRelease,
    CourseVideo,
    CourseVideoDub,
)

MAX_VIDEO_MIB = 480
MAX_DUB_MIB = 200
MIN_VIDEO_SECONDS = 10
MAX_VIDEO_MINUTES = 60
MAX_LONG_SIDE = 1920
MAX_SHORT_SIDE = 1080
MAX_FPS = 60
DUB_TOLERANCE_MS = 2000
DUB_AUDIO_BITRATE = "128k"
POSTER_BOX = (1280, 720)
POSTER_SMALL_BOX = (640, 360)
POSTER_BYTES = 120 * 1024
POSTER_SMALL_BYTES = 50 * 1024
POSTER_SECOND = 3.0
REMUX_TIMEOUT_SECONDS = 300
DUB_TIMEOUT_SECONDS = 420
FRAME_TIMEOUT_SECONDS = 60
UPLOAD_LOCK = "courses:video-upload"
UPLOAD_LOCK_SECONDS = 900
DISK_RESERVE_BYTES = 1024**3
VIDEO_CONTENT_TYPE = "video/mp4"
POSTER_CONTENT_TYPE = "image/webp"
VIDEO_FORMATS = frozenset({"mov", "mp4"})
AUDIO_FORMATS = frozenset({"mp3", "mov", "mp4", "m4a", "aac", "wav", "flac"})
AUDIO_CODECS = frozenset({"mp3", "aac", "flac"})
SPEECH_NAMES = dict(SPOKEN_LANGUAGES)
HANDBRAKE = "пересохраните файл в HandBrake: пресет «Fast 720p30» с галочкой «Web Optimized»"
HEVC = (
    "Видео в формате HEVC, его покажет не каждый телефон. На iPhone включите "
    "«Настройки → Камера → Форматы → Наиболее совместимые» или " + HANDBRAKE + "."
)
INSTRUCTION = f"Нужен MP4 или MOV с видео H.264: {HANDBRAKE}."


class CourseVideoError(ValueError):
    """A message for the author; `status` is the HTTP status of the admin's JSON answer."""

    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


@dataclass(frozen=True, slots=True)
class VideoProbe:
    duration_ms: int
    width: int
    height: int
    fps: float
    bitrate_kbps: int
    video_codec: str
    audio_codec: str
    # Stream numbers in the file: a phone adds data tracks, an MP4 may carry cover art.
    video_index: int
    audio_index: int | None


@dataclass(frozen=True, slots=True)
class AudioProbe:
    duration_ms: int
    codec: str


@dataclass(frozen=True, slots=True)
class Poster:
    object_key: str
    small_object_key: str
    width: int
    height: int


# One upload at a time -----------------------------------------------------


@contextmanager
def upload_slot() -> Iterator[None]:
    """A second upload is told to wait instead of filling the disk next to the first."""
    token = uuid.uuid4().hex
    if not cache.add(UPLOAD_LOCK, token, UPLOAD_LOCK_SECONDS):
        raise CourseVideoError(
            "Сейчас загружается другое видео или озвучка. Подождите и повторите.", status=409
        )
    try:
        yield
    finally:
        if cache.get(UPLOAD_LOCK) == token:
            cache.delete(UPLOAD_LOCK)


def check_disk_space(size_bytes: int) -> None:
    """The request body, Django's copy of the file and the result: three sizes plus 1 GiB."""
    if disk_usage(gettempdir()).free < 3 * size_bytes + DISK_RESERVE_BYTES:
        raise CourseVideoError("На сервере мало места для этого файла. Сообщите администратору.")


# Checks ------------------------------------------------------------------


def probe_video(path: Path, *, ffprobe: str = "ffprobe") -> VideoProbe:
    """The picture and sound of a lesson video, or what the author should fix."""
    report = _report(ffprobe, path, f"Файл не читается как видео. {INSTRUCTION}")
    file_format = report.get("format") or {}
    formats = set(str(file_format.get("format_name", "")).split(","))
    if not formats & VIDEO_FORMATS:
        if formats & {"webm", "matroska"}:
            raise CourseVideoError(f"WebM не подходит. {INSTRUCTION}")
        raise CourseVideoError(INSTRUCTION)
    streams = report.get("streams") or []
    video = _video_stream(streams)
    width, height = _display_size(video)
    if max(width, height) > MAX_LONG_SIDE or min(width, height) > MAX_SHORT_SIDE:
        raise CourseVideoError(
            f"Кадр {width}×{height}, допустимо до 1920×1080. {HANDBRAKE.capitalize()}."
        )
    fps = _fps(video)
    if fps > MAX_FPS + 0.5:
        raise CourseVideoError(
            f"{round(fps)} кадров в секунду, допустимо до {MAX_FPS}. {HANDBRAKE.capitalize()}."
        )
    audio = _audio_stream(streams)
    duration_ms = _duration_ms(file_format, "Не удалось определить длительность видео.")
    if duration_ms < MIN_VIDEO_SECONDS * 1000:
        raise CourseVideoError(f"Видео короче {MIN_VIDEO_SECONDS} секунд.")
    if duration_ms > MAX_VIDEO_MINUTES * 60_000:
        raise CourseVideoError(
            f"Видео длится {_length(duration_ms)}, допустимо до {MAX_VIDEO_MINUTES} минут. "
            "Разделите тему на части."
        )
    try:
        bitrate_kbps = round(int(file_format["bit_rate"]) / 1000)
    except KeyError, TypeError, ValueError:
        bitrate_kbps = round(path.stat().st_size * 8 / duration_ms)
    return VideoProbe(
        duration_ms=duration_ms,
        width=width,
        height=height,
        fps=fps,
        bitrate_kbps=bitrate_kbps,
        video_codec=str(video["codec_name"]),
        audio_codec=str(audio["codec_name"]) if audio is not None else "",
        video_index=int(video["index"]),
        audio_index=int(audio["index"]) if audio is not None else None,
    )


def _video_stream(streams: list[dict[str, Any]]) -> dict[str, Any]:
    video = next(
        (
            stream
            for stream in streams
            if stream.get("codec_type") == "video"
            and not (stream.get("disposition") or {}).get("attached_pic")
        ),
        None,
    )
    if video is None:
        raise CourseVideoError("В файле нет видео.")
    codec = str(video.get("codec_name") or "")
    if codec == "hevc":
        raise CourseVideoError(HEVC)
    if codec != "h264":
        raise CourseVideoError(f"Видео в формате {codec.upper() or 'неизвестном'}. {INSTRUCTION}")
    if video.get("pix_fmt") not in {"yuv420p", "yuvj420p"}:
        raise CourseVideoError(
            "Видео с 10-битным цветом или в 4:2:2: его покажет не каждый телефон. "
            f"{HANDBRAKE.capitalize()}."
        )
    return video


def _audio_stream(streams: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The first sound track: AAC in mono or stereo, or none at all."""
    audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), None)
    if audio is None:
        return None
    codec = str(audio.get("codec_name") or "")
    if codec != "aac":
        raise CourseVideoError(
            f"Звук в формате {codec.upper() or 'неизвестном'}, нужен AAC. {HANDBRAKE.capitalize()}."
        )
    if int(audio.get("channels") or 0) > 2:
        raise CourseVideoError(
            f"Звук многоканальный, нужен моно или стерео. {HANDBRAKE.capitalize()}."
        )
    return audio


def probe_audio(path: Path, *, ffprobe: str = "ffprobe") -> AudioProbe:
    report = _report(
        ffprobe, path, "Файл не читается как звук. Нужен MP3, M4A (AAC), WAV или FLAC.", "a:0"
    )
    file_format = report.get("format") or {}
    formats = set(str(file_format.get("format_name", "")).split(","))
    streams = report.get("streams") or []
    codec = str(streams[0].get("codec_name") or "") if streams else ""
    if not formats & AUDIO_FORMATS or not (codec in AUDIO_CODECS or codec.startswith("pcm_")):
        raise CourseVideoError("Нужен звук MP3, M4A (AAC), WAV или FLAC.")
    return AudioProbe(
        duration_ms=_duration_ms(file_format, "Не удалось определить длительность звука."),
        codec=codec,
    )


def _report(ffprobe: str, path: Path, unreadable: str, streams: str = "") -> dict[str, Any]:
    options = ("-select_streams", streams) if streams else ()
    try:
        return ffprobe_report(ffprobe, path, *options, unreadable=unreadable)
    except SurahUploadError as exc:
        raise CourseVideoError(str(exc)) from exc


def _display_size(stream: dict[str, Any]) -> tuple[int, int]:
    """The frame as it is shown: a phone held upright stores it turned by 90°."""
    width, height = int(stream.get("width") or 0), int(stream.get("height") or 0)
    rotation = next(
        (
            item.get("rotation")
            for item in stream.get("side_data_list") or []
            if item.get("rotation") is not None
        ),
        (stream.get("tags") or {}).get("rotate", 0),
    )
    try:
        quarter_turn = round(float(rotation)) % 180 == 90
    except TypeError, ValueError:
        quarter_turn = False
    if width <= 0 or height <= 0:
        raise CourseVideoError("Не удалось определить размер кадра.")
    return (height, width) if quarter_turn else (width, height)


def _fps(stream: dict[str, Any]) -> float:
    for field in ("avg_frame_rate", "r_frame_rate"):
        try:
            rate = Fraction(str(stream.get(field) or ""))
        except ValueError, ZeroDivisionError:
            continue
        if rate > 0:
            return round(float(rate), 3)
    raise CourseVideoError("Не удалось определить число кадров в секунду.")


def _duration_ms(file_format: dict[str, Any], message: str) -> int:
    try:
        duration_ms = round(float(file_format["duration"]) * 1000)
    except (KeyError, TypeError, ValueError) as exc:
        raise CourseVideoError(message) from exc
    if duration_ms <= 0:
        raise CourseVideoError(message)
    return duration_ms


def _length(milliseconds: int) -> str:
    """Under 10 seconds with a decimal, else whole seconds, or minutes and seconds."""
    seconds = milliseconds / 1000
    if seconds < 10:
        return f"{seconds:.1f}".removesuffix(".0").replace(".", ",") + " с"
    minutes, rest = divmod(round(seconds), 60)
    if not minutes:
        return f"{rest} с"
    return f"{minutes} мин {rest} с" if rest else f"{minutes} мин"


# Lesson video ------------------------------------------------------------


def upload_lesson_video(  # noqa: PLR0913 - the admin passes each of them
    lesson: CourseLesson,
    source: Path,
    *,
    user: Any,
    original_name: str,
    spoken_language: str,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
    ffprobe: str = "ffprobe",
) -> CourseVideo:
    """Checks, remuxes and stores the video, then makes it the lesson's video."""
    if spoken_language not in SPEECH_NAMES:
        raise CourseVideoError("Выберите язык речи.")
    _check_size(source, MAX_VIDEO_MIB, "Видео должно быть")
    program = ffmpeg or which("ffmpeg") or "ffmpeg"
    probe = probe_video(source, ffprobe=ffprobe)
    created: dict[str, Any] | None = None
    with TemporaryDirectory(prefix="iqro-course-video-") as directory:
        folder = Path(directory)
        remuxed = folder / "video.mp4"
        maps = ["-map", f"0:{probe.video_index}"]
        if probe.audio_index is not None:
            maps += ["-map", f"0:{probe.audio_index}"]
        _ffmpeg(
            program,
            ["-i", str(source), *maps, "-c", "copy", *_CLEAN_MP4, str(remuxed)],
            timeout=REMUX_TIMEOUT_SECONDS,
            failure=f"Видео не удалось переупаковать. {HANDBRAKE.capitalize()}.",
        )
        stored = probe_video(remuxed, ffprobe=ffprobe)
        checksum = _sha256(remuxed)
        if not CourseVideo.objects.filter(course_id=lesson.course_id, sha256=checksum).exists():
            actual_uploader = uploader or player_background_uploader()
            object_key = f"courses/videos/{checksum[:20]}.mp4"
            _store(actual_uploader, remuxed, object_key, VIDEO_CONTENT_TYPE, checksum)
            frame = _frame(
                program, str(remuxed), min(POSTER_SECOND, stored.duration_ms / 10_000), folder
            )
            poster = _posters(
                program,
                frame,
                video_checksum=checksum,
                width=stored.width,
                height=stored.height,
                folder=folder,
                uploader=actual_uploader,
            )
            created = {
                "object_key": object_key,
                "bytes": remuxed.stat().st_size,
                "duration_ms": stored.duration_ms,
                "width": stored.width,
                "height": stored.height,
                "fps": stored.fps,
                "bitrate_kbps": stored.bitrate_kbps,
                "video_codec": stored.video_codec,
                "audio_codec": stored.audio_codec,
                "has_audio": bool(stored.audio_codec),
                "spoken_language": spoken_language,
                **_poster_fields(poster),
                "original_name": original_name[:255],
                "uploaded_by": user,
            }
    with transaction.atomic():
        locked = CourseLesson.objects.select_for_update().get(pk=lesson.pk)
        video, _ = CourseVideo.objects.get_or_create(
            course_id=locked.course_id, sha256=checksum, defaults=created
        )
        previous = locked.video_id
        locked.video = video
        locked.updated_by = user
        locked.save(update_fields=["video", "updated_by", "updated_at"])
        if previous is not None and previous != video.pk:
            _forget_video(previous)
    return video


def remove_lesson_video(lesson: CourseLesson, video_id: Any, *, user: Any) -> None:
    with transaction.atomic():
        locked = _locked_lesson(lesson, video_id)
        locked.video = None
        locked.updated_by = user
        locked.save(update_fields=["video", "updated_by", "updated_at"])
        _forget_video(video_id)


def set_spoken_language(lesson: CourseLesson, video_id: Any, language: str, *, user: Any) -> None:
    if language not in SPEECH_NAMES:
        raise CourseVideoError("Выберите язык речи.")
    with transaction.atomic():
        locked = _locked_lesson(lesson, video_id)
        video = CourseVideo.objects.select_for_update().get(pk=video_id)
        if language and video.dubs.filter(language=language, retired_at__isnull=True).exists():
            raise CourseVideoError(
                f"У видео есть озвучка на языке «{SPEECH_NAMES[language]}». Сначала удалите её."
            )
        video.spoken_language = language
        video.save(update_fields=["spoken_language", "updated_at"])
        _touch(locked, user)


def set_video_poster(  # noqa: PLR0913 - the admin passes each of them
    lesson: CourseLesson,
    video_id: Any,
    *,
    user: Any,
    second: float | None = None,
    image: UploadedFile | None = None,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
) -> CourseVideo:
    """A frame at `second` of the video, or the author's picture cropped to the frame's shape."""
    video = _video_of(lesson, video_id)
    program = ffmpeg or which("ffmpeg") or "ffmpeg"
    with TemporaryDirectory(prefix="iqro-course-poster-") as directory:
        folder = Path(directory)
        if image is not None:
            picture = folder / "picture"
            try:
                _save_upload(image, picture)
            except CourseCoverError as exc:
                raise CourseVideoError(str(exc)) from exc
            if not _is_image(picture):
                raise CourseVideoError("Нужна картинка JPEG, PNG или WebP.")
        else:
            if second is None or not 0 <= second < video.duration_ms / 1000:
                raise CourseVideoError(f"Укажите секунду от 0 до {video.duration_ms // 1000 - 1}.")
            picture = _frame(program, video_source(video), second, folder)
        poster = _posters(
            program,
            picture,
            video_checksum=video.sha256,
            width=video.width,
            height=video.height,
            folder=folder,
            uploader=uploader or player_background_uploader(),
        )
    with transaction.atomic():
        locked = _locked_lesson(lesson, video_id)
        CourseVideo.objects.filter(pk=video_id).update(
            **_poster_fields(poster), updated_at=timezone.now()
        )
        _touch(locked, user)
    video.refresh_from_db()
    return video


def video_source(video: CourseVideo) -> str:
    """Where ffmpeg reads a stored video: the public URL, which answers Range requests."""
    return public_audio_url(video.object_key)


# Dubs --------------------------------------------------------------------


def upload_video_dub(  # noqa: PLR0913 - the admin passes each of them
    lesson: CourseLesson,
    video_id: Any,
    language: str,
    source: Path,
    *,
    user: Any,
    original_name: str,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
    ffprobe: str = "ffprobe",
) -> CourseVideoDub:
    """Joins the picture of the lesson's video with the whole sound of another language."""
    video = _video_of(lesson, video_id)
    _check_dub_language(video, language)
    _check_size(source, MAX_DUB_MIB, "Файл озвучки должен быть")
    audio = probe_audio(source, ffprobe=ffprobe)
    difference = audio.duration_ms - video.duration_ms
    if abs(difference) > DUB_TOLERANCE_MS:
        raise CourseVideoError(
            f"Озвучка {'короче' if difference < 0 else 'длиннее'} видео на "
            f"{_length(abs(difference))}. Длительность должна совпадать с видео "
            f"({_length(video.duration_ms)}) с точностью до 2 секунд."
        )
    audio_checksum = _sha256(source)
    program = ffmpeg or which("ffmpeg") or "ffmpeg"
    with TemporaryDirectory(prefix="iqro-course-dub-") as directory:
        joined = Path(directory) / "dub.mp4"
        _ffmpeg(
            program,
            [
                "-i", video_source(video), "-i", str(source),
                "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy", "-c:a", "aac", "-b:a", DUB_AUDIO_BITRATE,
                "-shortest", *_CLEAN_MP4, str(joined),
            ],
            timeout=DUB_TIMEOUT_SECONDS,
            failure="Озвучку не удалось соединить с видео. Проверьте файл и повторите.",
        )  # fmt: skip
        stored = probe_video(joined, ffprobe=ffprobe)
        checksum = _sha256(joined)
        object_key = f"courses/videos/{video.sha256[:20]}-{language}-{checksum[:12]}.mp4"
        _store(
            uploader or player_background_uploader(),
            joined,
            object_key,
            VIDEO_CONTENT_TYPE,
            checksum,
        )
        size_bytes = joined.stat().st_size
    with transaction.atomic():
        locked = _locked_lesson(lesson, video_id)
        locked_video = CourseVideo.objects.select_for_update().get(pk=video_id)
        _check_dub_language(locked_video, language)
        current = locked_video.dubs.filter(language=language, retired_at__isnull=True).first()
        if current is not None:
            _drop_dub(current)
        dub = CourseVideoDub.objects.create(
            video=locked_video,
            language=language,
            audio_original_name=original_name[:255],
            audio_sha256=audio_checksum,
            audio_bytes=source.stat().st_size,
            audio_codec=audio.codec,
            audio_duration_ms=audio.duration_ms,
            object_key=object_key,
            sha256=checksum,
            bytes=size_bytes,
            duration_ms=stored.duration_ms,
            uploaded_by=user,
        )
        _touch(locked, user)
    return dub


def delete_video_dub(lesson: CourseLesson, video_id: Any, language: str, *, user: Any) -> None:
    with transaction.atomic():
        locked = _locked_lesson(lesson, video_id)
        dub = CourseVideoDub.objects.filter(
            video_id=video_id, language=language, retired_at__isnull=True
        ).first()
        if dub is None:
            raise CourseVideoError("Этой озвучки уже нет. Обновите страницу.", status=409)
        _drop_dub(dub)
        _touch(locked, user)


def current_dubs(video: CourseVideo) -> list[CourseVideoDub]:
    return list(video.dubs.filter(retired_at__isnull=True).order_by("language"))


def _check_dub_language(video: CourseVideo, language: str) -> None:
    if language not in COURSE_LANGUAGES:
        raise CourseVideoError("Неизвестный язык озвучки.")
    if language == video.spoken_language:
        raise CourseVideoError(
            f"Основной звук видео уже на языке «{SPEECH_NAMES[language]}»: озвучка на нём не нужна."
        )


# Rows nothing uses ---------------------------------------------------------


def released_files(course_id: Any) -> set[str]:
    """SHA-256 of every video and dub file any release of the course mentions."""
    found: set[str] = set()
    for snapshot in CourseRelease.objects.filter(course_id=course_id).values_list(
        "snapshot", flat=True
    ):
        found |= snapshot_files(snapshot)
    return found


def _forget_video(video_id: Any) -> None:
    """Deletes a video row no lesson and no release uses; its files stay in R2."""
    video = CourseVideo.objects.filter(pk=video_id).first()
    if video is None or CourseLesson.objects.filter(video_id=video_id).exists():
        return
    if video.sha256 not in released_files(video.course_id):
        # A video that never went into a release has no released dubs either.
        video.delete()


def _drop_dub(dub: CourseVideoDub) -> None:
    if dub.sha256 in released_files(dub.video.course_id):
        dub.retired_at = timezone.now()
        dub.save(update_fields=["retired_at", "updated_at"])
    else:
        dub.delete()


def _locked_lesson(lesson: CourseLesson, video_id: Any) -> CourseLesson:
    """The lesson row, if its video is still the one the page showed."""
    locked = CourseLesson.objects.select_for_update().get(pk=lesson.pk)
    if locked.video_id is None or str(locked.video_id) != str(video_id):
        raise CourseVideoError(
            "Видео темы изменили в другой вкладке. Обновите страницу.", status=409
        )
    return locked


def _video_of(lesson: CourseLesson, video_id: Any) -> CourseVideo:
    current = CourseLesson.objects.filter(pk=lesson.pk).values_list("video_id", flat=True).first()
    if current is None or str(current) != str(video_id):
        raise CourseVideoError(
            "Видео темы изменили в другой вкладке. Обновите страницу.", status=409
        )
    return CourseVideo.objects.get(pk=current)


def _touch(lesson: CourseLesson, user: Any) -> None:
    lesson.updated_by = user
    lesson.save(update_fields=["updated_by", "updated_at"])


# ffmpeg and storage --------------------------------------------------------

# No metadata of the phone (GPS, model, dates) and the index first, so playback starts at once.
# bitexact keeps the bytes the same for the same input: an uploaded file again reuses its row.
_CLEAN_MP4 = (
    "-map_metadata", "-1", "-map_chapters", "-1", "-fflags", "+bitexact",
    "-movflags", "+faststart", "-f", "mp4",
)  # fmt: skip


def _check_size(source: Path, limit_mib: int, limit: str) -> None:
    size_bytes = source.stat().st_size
    if size_bytes == 0:
        raise CourseVideoError("Выбранный файл пуст.")
    if size_bytes > limit_mib * 1024 * 1024:
        raise CourseVideoError(f"{limit} не больше {limit_mib} МБ.")


def _ffmpeg(ffmpeg: str, arguments: list[str], *, timeout: int, failure: str) -> None:
    try:
        subprocess.run(  # noqa: S603 - fixed program, no shell, paths and URLs we built
            [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *arguments],
            check=True,
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise CourseVideoError(f"На сервере нет {ffmpeg}.", status=502) from exc
    except subprocess.TimeoutExpired as exc:
        raise CourseVideoError("Файл обрабатывался слишком долго. Повторите позже.") from exc
    except subprocess.CalledProcessError as exc:
        raise CourseVideoError(failure) from exc


def _frame(ffmpeg: str, source: str, second: float, folder: Path) -> Path:
    frame = folder / "frame.png"
    _ffmpeg(
        ffmpeg,
        ["-ss", f"{second:.3f}", "-i", source, "-frames:v", "1", "-update", "1", str(frame)],
        timeout=FRAME_TIMEOUT_SECONDS,
        failure="Кадр взять не удалось. Укажите другую секунду.",
    )
    if not frame.exists() or frame.stat().st_size == 0:
        raise CourseVideoError("Кадр взять не удалось. Укажите другую секунду.")
    return frame


def poster_size(width: int, height: int, box: tuple[int, int]) -> tuple[int, int]:
    """The frame's shape fitted into the box, even sides: 1920x1080 gives 1280x720."""
    box_width, box_height = box
    if width * box_height >= height * box_width:
        return box_width, max(2, round(box_width * height / width / 2) * 2)
    return max(2, round(box_height * width / height / 2) * 2), box_height


def _posters(  # noqa: PLR0913 - the picture, the video and where to put the result
    ffmpeg: str,
    picture: Path,
    *,
    video_checksum: str,
    width: int,
    height: int,
    folder: Path,
    uploader: ObjectUploader,
) -> Poster:
    big_size = poster_size(width, height, POSTER_BOX)
    try:
        big = _encode(ffmpeg, picture, folder / "poster.webp", big_size, POSTER_BYTES)
        small = _encode(
            ffmpeg,
            picture,
            folder / "poster-small.webp",
            poster_size(width, height, POSTER_SMALL_BOX),
            POSTER_SMALL_BYTES,
        )
    except CourseCoverError as exc:
        raise CourseVideoError(str(exc)) from exc
    stem = f"courses/posters/{video_checksum[:20]}-{_sha256(big)[:12]}"
    big_key = f"{stem}-{POSTER_BOX[0]}.webp"
    small_key = f"{stem}-{POSTER_SMALL_BOX[0]}.webp"
    _store(uploader, big, big_key, POSTER_CONTENT_TYPE)
    _store(uploader, small, small_key, POSTER_CONTENT_TYPE)
    return Poster(big_key, small_key, *big_size)


def _poster_fields(poster: Poster) -> dict[str, Any]:
    return {
        "poster_object_key": poster.object_key,
        "poster_small_object_key": poster.small_object_key,
        "poster_width": poster.width,
        "poster_height": poster.height,
    }


def _store(
    uploader: ObjectUploader,
    path: Path,
    key: str,
    content_type: str,
    checksum: str | None = None,
) -> None:
    """Create-only upload to R2, then the public URL must serve the same bytes."""
    size_bytes = path.stat().st_size
    uploader.upload_path(
        path,
        ImmutableObjectSpec(
            key=key,
            content_type=content_type,
            size_bytes=size_bytes,
            checksum_sha256=checksum or _sha256(path),
        ),
    )
    if isinstance(uploader, LocalMediaUploader):
        # Local development serves /media without a CDN; the stored file is the evidence.
        return
    try:
        verify_public_audio_object(public_audio_url(key), size_bytes, content_type)
    except SurahUploadError as exc:
        raise CourseVideoError(str(exc), status=502) from exc
