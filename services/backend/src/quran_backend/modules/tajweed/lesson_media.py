# Russian messages for the editor intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""Media of the tajweed course's lessons (docs/tajweed/course.md, «Медиа уроков»).

A lesson's video, slides and banners belong to the lesson of one version: the
blocks live in the draft's snapshot, the video block with its file, poster and
dubs, so «Создать черновик из этой версии» copies them with the rest. Files
are checked, joined and stored as for thematic courses (courses/video.py,
courses/lesson_media.py) under the same immutable keys.
"""

from __future__ import annotations

import copy
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from django.core.files.uploadedfile import UploadedFile
from django.db import transaction

from quran_backend.modules.courses.lesson_media import (
    MAX_BLOCKS,
    VIDEO,
    VIDEO_BLOCK_ID,
    LessonMediaError,
)
from quran_backend.modules.courses.video import (
    SPEECH_NAMES,
    CourseVideoError,
    make_poster,
    process_dub,
    process_video,
)
from quran_backend.modules.tajweed.course import TajweedCourseError, lesson_video
from quran_backend.modules.tajweed.course_publication import save_course_draft
from quran_backend.modules.tajweed.models import TajweedCourseStatus, TajweedCourseVersion

# The keys of thematic courses: the CDN already caches them as immutable files.
PREFIX = "courses"
CHANGED = "Видео урока изменили в другой вкладке. Обновите страницу."


@dataclass(frozen=True, slots=True)
class StoredVideo:
    """The video of a lesson's snapshot, as courses/video.py reads a stored video."""

    sha256: str
    object_key: str
    duration_ms: int
    width: int
    height: int
    spoken_language: str

    @classmethod
    def of(cls, video: dict[str, Any]) -> StoredVideo:
        return cls(
            sha256=video["sha256"],
            object_key=video["object_key"],
            duration_ms=video["duration_ms"],
            width=video["width"],
            height=video["height"],
            spoken_language=video["spoken_language"],
        )


def find_lesson(snapshot: dict[str, Any], slug: str) -> dict[str, Any]:
    lessons: list[dict[str, Any]] = snapshot.get("lessons", [])
    lesson = next((item for item in lessons if item["slug"] == slug), None)
    if lesson is None:
        raise LessonMediaError("Такого урока в версии нет. Обновите страницу.", status=409)
    return lesson


def change_lesson(
    version: TajweedCourseVersion, slug: str, change: Callable[[dict[str, Any]], None]
) -> TajweedCourseVersion:
    """Changes one lesson of an unsigned draft and compiles its documents again."""
    with transaction.atomic():
        locked = (
            TajweedCourseVersion.objects.select_for_update()
            .select_related("course")
            .get(pk=version.pk)
        )
        if locked.status != TajweedCourseStatus.DRAFT or locked.is_signed:
            raise LessonMediaError(
                "Медиа меняются только в неподписанном черновике. Обновите страницу.", status=409
            )
        snapshot = copy.deepcopy(locked.snapshot)
        change(find_lesson(snapshot, slug))
        try:
            save_course_draft(locked, snapshot)
        except TajweedCourseError as error:
            raise LessonMediaError("; ".join(error.problems)) from error
    return locked


def _video(lesson: dict[str, Any], video_id: Any) -> dict[str, Any]:
    """The lesson's video, if it is still the one the page showed."""
    video = lesson_video(lesson)
    if video is None or video["sha256"] != str(video_id):
        raise CourseVideoError(CHANGED, status=409)
    return video


def upload_video(  # noqa: PLR0913 - the admin passes each of them
    version: TajweedCourseVersion,
    slug: str,
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

    change_lesson(version, slug, change)
    return video


def set_spoken_language(
    version: TajweedCourseVersion, slug: str, video_id: Any, language: str
) -> None:
    if language not in SPEECH_NAMES:
        raise CourseVideoError("Выберите язык речи.")

    def change(lesson: dict[str, Any]) -> None:
        video = _video(lesson, video_id)
        if language and language in video["dubs"]:
            raise CourseVideoError(
                f"У видео есть озвучка на языке «{SPEECH_NAMES[language]}». Сначала удалите её."
            )
        video["spoken_language"] = language

    change_lesson(version, slug, change)


def set_poster(  # noqa: PLR0913 - the admin passes each of them
    version: TajweedCourseVersion,
    slug: str,
    video_id: Any,
    *,
    second: float | None = None,
    image: UploadedFile | None = None,
    ffmpeg: str | None = None,
) -> None:
    video = _video(find_lesson(version.snapshot, slug), video_id)
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

    change_lesson(version, slug, change)


def upload_dub(  # noqa: PLR0913 - the admin passes each of them
    version: TajweedCourseVersion,
    slug: str,
    video_id: Any,
    language: str,
    source: Path,
    *,
    original_name: str,
    ffmpeg: str | None = None,
    ffprobe: str = "ffprobe",
) -> dict[str, Any]:
    video = _video(find_lesson(version.snapshot, slug), video_id)
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

    change_lesson(version, slug, change)
    return dub


def delete_dub(version: TajweedCourseVersion, slug: str, video_id: Any, language: str) -> None:
    def change(lesson: dict[str, Any]) -> None:
        if _video(lesson, video_id)["dubs"].pop(language, None) is None:
            raise CourseVideoError("Этой озвучки уже нет. Обновите страницу.", status=409)

    change_lesson(version, slug, change)


def remove_video(version: TajweedCourseVersion, slug: str, video_id: Any) -> None:
    """Takes the video out of the lesson; its place stays for a new upload."""

    def change(lesson: dict[str, Any]) -> None:
        _video(lesson, video_id)
        for block in lesson.get("media", []):
            if block.get("type") == VIDEO:
                block.pop("video", None)

    change_lesson(version, slug, change)
