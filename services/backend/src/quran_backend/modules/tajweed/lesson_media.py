"""Media of the tajweed course's lessons (docs/tajweed/course.md, «Медиа уроков»).

A lesson's video, slides and banners belong to the lesson of one version: the
blocks live in the draft's snapshot, the video block with its file, poster and
dubs, so «Создать черновик из этой версии» copies them with the rest. The
changes themselves are shared with the prayer-learning course
(courses/snapshot_media.py); this module locks the tajweed version around them.
"""

from __future__ import annotations

import copy
from collections.abc import Callable
from pathlib import Path
from typing import Any

from django.core.files.uploadedfile import UploadedFile
from django.db import transaction

from quran_backend.modules.courses import snapshot_media
from quran_backend.modules.courses.lesson_media import LessonMediaError
from quran_backend.modules.tajweed.course import TajweedCourseError
from quran_backend.modules.tajweed.course_publication import save_course_draft
from quran_backend.modules.tajweed.models import TajweedCourseStatus, TajweedCourseVersion


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


def draft_lesson(version: TajweedCourseVersion, slug: str) -> snapshot_media.DraftLesson:
    return snapshot_media.DraftLesson(
        read=lambda: find_lesson(version.snapshot, slug),
        change=lambda change: change_lesson(version, slug, change),
    )


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
    return snapshot_media.upload_video(
        draft_lesson(version, slug),
        source,
        spoken_language=spoken_language,
        original_name=original_name,
        ffmpeg=ffmpeg,
        ffprobe=ffprobe,
    )


def set_spoken_language(
    version: TajweedCourseVersion, slug: str, video_id: Any, language: str
) -> None:
    snapshot_media.set_spoken_language(draft_lesson(version, slug), video_id, language)


def set_poster(  # noqa: PLR0913 - the admin passes each of them
    version: TajweedCourseVersion,
    slug: str,
    video_id: Any,
    *,
    second: float | None = None,
    image: UploadedFile | None = None,
    ffmpeg: str | None = None,
) -> None:
    snapshot_media.set_poster(
        draft_lesson(version, slug), video_id, second=second, image=image, ffmpeg=ffmpeg
    )


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
    return snapshot_media.upload_dub(
        draft_lesson(version, slug),
        video_id,
        language,
        source,
        original_name=original_name,
        ffmpeg=ffmpeg,
        ffprobe=ffprobe,
    )


def delete_dub(version: TajweedCourseVersion, slug: str, video_id: Any, language: str) -> None:
    snapshot_media.delete_dub(draft_lesson(version, slug), video_id, language)


def remove_video(version: TajweedCourseVersion, slug: str, video_id: Any) -> None:
    """Takes the video out of the lesson; its place stays for a new upload."""
    snapshot_media.remove_video(draft_lesson(version, slug), video_id)
