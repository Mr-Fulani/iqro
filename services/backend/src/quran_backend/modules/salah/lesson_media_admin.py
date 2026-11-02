"""The «Медиа» block of a lesson in the course editor and the videos to watch.

What the editor page draws (docs/salah/lesson-media.md): the block shared with
the tajweed course and thematic courses on a lesson of the draft, and the new
videos and dubs the owner marks «Просмотрено» before signing. The views that
answer the block's buttons are in editor_admin.py.
"""

from __future__ import annotations

from typing import Any

from django.http import HttpRequest
from django.urls import reverse

from quran_backend.modules.courses.lesson_media_admin import MediaPage, media_hint
from quran_backend.modules.courses.snapshot_media import lesson_video
from quran_backend.modules.courses.snapshot_media_admin import (
    render_video,
    video_block,
)
from quran_backend.modules.courses.snapshot_media_admin import (
    review_videos as snapshot_review_videos,
)
from quran_backend.modules.salah import editor
from quran_backend.modules.salah.importer import new_videos
from quran_backend.modules.salah.lesson_media import find_lesson
from quran_backend.modules.salah.models import SALAH_LANGUAGES, SalahCourseVersion


def draft_url(request: HttpRequest, version: SalahCourseVersion, *, editable: bool) -> str:
    """Where to copy a version that can't be edited; empty without the right to."""
    if editable or not request.user.has_perm("salah.add_salahcourseversion"):
        return ""
    return reverse("admin:salah_salahcourseversion_new_draft", args=[version.pk])


def media_page(
    request: HttpRequest, version: SalahCourseVersion, lesson: str, *, editable: bool
) -> MediaPage:
    item = find_lesson(version.snapshot, lesson)
    copy_url = draft_url(request, version, editable=editable)
    return MediaPage(
        media=item.get("media") or [],
        has_video=lesson_video(item) is not None,
        languages=editor.editor_languages(SALAH_LANGUAGES),
        action_url=reverse(
            "admin:salah_salahcourseversion_lesson_media", args=[version.pk, lesson]
        ),
        can_edit=editable,
        video_html=render_video(lesson_video_block(version, lesson, editable=editable), request),
        prefix="courses",
        hint=media_hint(on_lesson=True, editable=editable, draft_url=copy_url),
        draft_url=copy_url,
    )


def lesson_video_block(
    version: SalahCourseVersion, lesson: str, *, editable: bool
) -> dict[str, Any]:
    return video_block(
        find_lesson(version.snapshot, lesson),
        editable=editable,
        languages=editor.editor_languages(SALAH_LANGUAGES),
        video_url=lambda operation: reverse(
            "admin:salah_salahcourseversion_lesson_video", args=[version.pk, lesson, operation]
        ),
        dub_url=lambda code, operation: reverse(
            "admin:salah_salahcourseversion_lesson_dub",
            args=[version.pk, lesson, code, operation],
        ),
    )


def review_videos(version: SalahCourseVersion, node_id: str) -> list[dict[str, Any]]:
    """Every new video and dub of the draft, each with its own «Просмотрено»."""
    return snapshot_review_videos(
        (
            (f"Урок «{editor.localized_title(lesson.get('title'), lesson['slug'])}»", lesson)
            for lesson in version.snapshot.get("lessons", [])
        ),
        new=new_videos(version),
        watched=set(version.watched_videos),
        mark_url=lambda sha256: reverse(
            "admin:salah_salahcourseversion_watched", args=[version.pk, sha256]
        ),
        node=node_id,
    )
