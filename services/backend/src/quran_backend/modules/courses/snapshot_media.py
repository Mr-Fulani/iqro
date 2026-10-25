# Russian messages for the editor intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""Media of a lesson that lives in the snapshot of a course version.

The tajweed course and the prayer-learning course keep a lesson's video, slides
and banners in the draft's snapshot (`lessons[].media`), the video block with
its file, poster and dubs, so a draft copied from a version copies them too.
The module gives a `DraftLesson`: how to read the lesson and how to change it
under the lock of its version row. Files are checked, joined and stored as for
thematic courses (video.py, lesson_media.py), under the same immutable keys.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.courses.document import shown_files, video_payload
from quran_backend.modules.courses.lesson_media import (
    KINDS,
    MAX_BLOCKS,
    VIDEO,
    VIDEO_BLOCK_ID,
    LessonMediaError,
    media_payload,
    media_snapshot,
)
from quran_backend.modules.courses.video import (
    SPEECH_NAMES,
    CourseVideoError,
    make_poster,
    process_dub,
    process_video,
)

# The keys of thematic courses: the CDN already caches them as immutable files.
PREFIX = "courses"
CHANGED = "Видео урока изменили в другой вкладке. Обновите страницу."
MEDIA_PROBLEM = f"media — до {MAX_BLOCKS} блоков видео, слайдов и баннеров, видео одно."

LessonChange = Callable[[dict[str, Any]], None]


@dataclass(frozen=True, slots=True)
class DraftLesson:
    """A lesson of an unsigned draft, as its module reaches it."""

    # The lesson as stored now.
    read: Callable[[], Mapping[str, Any]]
    # Changes the lesson under the version's lock, saves and compiles the documents;
    # raises LessonMediaError when the draft can no longer take it.
    change: Callable[[LessonChange], object]


@dataclass(frozen=True, slots=True)
class StoredVideo:
    """The video of a lesson's snapshot, as video.py reads a stored video."""

    sha256: str
    object_key: str
    duration_ms: int
    width: int
    height: int
    spoken_language: str

    @classmethod
    def of(cls, video: Mapping[str, Any]) -> StoredVideo:
        return cls(
            sha256=video["sha256"],
            object_key=video["object_key"],
            duration_ms=video["duration_ms"],
            width=video["width"],
            height=video["height"],
            spoken_language=video["spoken_language"],
        )


# Snapshot and documents ------------------------------------------------------


def media_valid(media: Any) -> bool:
    """The shape a snapshot keeps: up to MAX_BLOCKS known blocks, one video at most."""
    return (
        isinstance(media, list)
        and len(media) <= MAX_BLOCKS
        and all(
            isinstance(block, Mapping)
            and block.get("type") in KINDS
            and (block.get("type") == VIDEO or isinstance(block.get("slides"), list))
            for block in media
        )
        and sum(1 for block in media if block.get("type") == VIDEO) <= 1
    )


def lesson_video(lesson: Mapping[str, Any]) -> dict[str, Any] | None:
    """The lesson's video with its poster and dubs, as a course release keeps one."""
    return next(
        (
            block["video"]
            for block in lesson.get("media") or []
            if block.get("type") == VIDEO and block.get("video")
        ),
        None,
    )


def lesson_media(
    lesson: Mapping[str, Any], language: str, languages: Sequence[str]
) -> list[dict[str, Any]]:
    """The media blocks of one language (docs/courses/README.md, «Медиа темы»)."""
    video = lesson_video(lesson)
    blocks = media_snapshot(
        lesson.get("media") or [], has_video=video is not None, languages=languages
    )
    return media_payload(
        blocks,
        language=language,
        video=video_payload(video, language),
        public_url=public_audio_url,
    )


def video_files(lessons: Sequence[Mapping[str, Any]], languages: Sequence[str]) -> set[str]:
    """SHA-256 of the video and dub files the course's documents give students."""
    return shown_files(
        {"lessons": [{"video": lesson_video(lesson)} for lesson in lessons]}, list(languages)
    )


# Changes of the video block ----------------------------------------------------


def _video(lesson: Mapping[str, Any], video_id: Any) -> dict[str, Any]:
    """The lesson's video, if it is still the one the page showed."""
    video = lesson_video(lesson)
    if video is None or video["sha256"] != str(video_id):
        raise CourseVideoError(CHANGED, status=409)
    return video


def upload_video(  # noqa: PLR0913 - the admin passes each of them
    draft: DraftLesson,
    source: Path,
    *,
    spoken_language: str,
    original_name: str,
    ffmpeg: str | None = None,
    ffprobe: str = "ffprobe",
) -> dict[str, Any]:
    """Checks and stores the video and makes it the lesson's; a replaced video loses its dubs."""
    checksum, fields = process_video(
        source, spoken_language=spoken_language, prefix=PREFIX, ffmpeg=ffmpeg, ffprobe=ffprobe
    )
    assert fields is not None  # nothing is known in advance: every upload is stored
    poster = {
        "object_key": fields.pop("poster_object_key"),
        "small_object_key": fields.pop("poster_small_object_key"),
        "width": fields.pop("poster_width"),
        "height": fields.pop("poster_height"),
    }
    video = {
        "sha256": checksum,
        **fields,
        "poster": poster,
        "dubs": {},
        "original_name": original_name[:255],
    }

    def change(lesson: dict[str, Any]) -> None:
        media = lesson.setdefault("media", [])
        block = next((item for item in media if item.get("type") == VIDEO), None)
        if block is None:
            if len(media) >= MAX_BLOCKS:
                raise LessonMediaError(f"В уроке уже {MAX_BLOCKS} блоков медиа.")
            block = {"id": VIDEO_BLOCK_ID, "type": VIDEO}
            media.insert(0, block)
        previous = block.get("video")
        if previous and previous["sha256"] == checksum:
            # The same file again keeps its poster, language and dubs.
            return
        block["video"] = video

    draft.change(change)
    return video


def set_spoken_language(draft: DraftLesson, video_id: Any, language: str) -> None:
    if language not in SPEECH_NAMES:
        raise CourseVideoError("Выберите язык речи.")

    def change(lesson: dict[str, Any]) -> None:
        video = _video(lesson, video_id)
        if language and language in video["dubs"]:
            raise CourseVideoError(
                f"У видео есть озвучка на языке «{SPEECH_NAMES[language]}». Сначала удалите её."
            )
        video["spoken_language"] = language

    draft.change(change)


def set_poster(
    draft: DraftLesson,
    video_id: Any,
    *,
    second: float | None = None,
    image: UploadedFile | None = None,
    ffmpeg: str | None = None,
) -> None:
    video = _video(draft.read(), video_id)
    poster = make_poster(
        StoredVideo.of(video), second=second, image=image, prefix=PREFIX, ffmpeg=ffmpeg
    )

    def change(lesson: dict[str, Any]) -> None:
        _video(lesson, video_id)["poster"] = {
            "object_key": poster.object_key,
            "small_object_key": poster.small_object_key,
            "width": poster.width,
            "height": poster.height,
        }

    draft.change(change)


def upload_dub(  # noqa: PLR0913 - the admin passes each of them
    draft: DraftLesson,
    video_id: Any,
    language: str,
    source: Path,
    *,
    original_name: str,
    ffmpeg: str | None = None,
    ffprobe: str = "ffprobe",
) -> dict[str, Any]:
    video = _video(draft.read(), video_id)
    dub = {
        **process_dub(
            StoredVideo.of(video), language, source, prefix=PREFIX, ffmpeg=ffmpeg, ffprobe=ffprobe
        ),
        "audio_original_name": original_name[:255],
    }

    def change(lesson: dict[str, Any]) -> None:
        current = _video(lesson, video_id)
        if language == current["spoken_language"]:
            raise CourseVideoError(CHANGED, status=409)
        current["dubs"][language] = dub

    draft.change(change)
    return dub


def delete_dub(draft: DraftLesson, video_id: Any, language: str) -> None:
    def change(lesson: dict[str, Any]) -> None:
        if _video(lesson, video_id)["dubs"].pop(language, None) is None:
            raise CourseVideoError("Этой озвучки уже нет. Обновите страницу.", status=409)

    draft.change(change)


def remove_video(draft: DraftLesson, video_id: Any) -> None:
    """Takes the video out of the lesson; its place stays for a new upload."""

    def change(lesson: dict[str, Any]) -> None:
        _video(lesson, video_id)
        for block in lesson.get("media", []):
            if block.get("type") == VIDEO:
                block.pop("video", None)

    draft.change(change)
