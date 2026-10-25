"""Media of the prayer-learning course's lessons (docs/salah/lesson-media.md).

A lesson's video, slides and banners belong to the lesson of one version: the
blocks live in the draft's snapshot, as in the tajweed course, so «Создать
черновик из этой версии» copies them with the rest. The changes themselves are
shared (courses/snapshot_media.py); this module locks the version around them,
checks the snapshot and compiles the documents, as a save of the editor does.
"""

from __future__ import annotations

import copy
from collections.abc import Callable
from typing import Any

from django.db import transaction

from quran_backend.modules.courses.lesson_media import LessonMediaError
from quran_backend.modules.courses.snapshot_media import DraftLesson
from quran_backend.modules.salah.importer import compile_version
from quran_backend.modules.salah.models import SalahCourseVersion, SalahPublicationStatus
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import integrity_problems, snapshot_checksum


def find_lesson(snapshot: dict[str, Any], slug: str) -> dict[str, Any]:
    lessons: list[dict[str, Any]] = snapshot.get("lessons", [])
    lesson = next((item for item in lessons if item.get("slug") == slug), None)
    if lesson is None:
        raise LessonMediaError("Такого урока в версии нет. Обновите страницу.", status=409)
    return lesson


def change_lesson(
    version: SalahCourseVersion, slug: str, change: Callable[[dict[str, Any]], None]
) -> SalahCourseVersion:
    """Changes one lesson of an unsigned draft and compiles its documents again."""
    with transaction.atomic():
        locked = (
            SalahCourseVersion.objects.select_for_update()
            .select_related("course")
            .get(pk=version.pk)
        )
        if locked.status != SalahPublicationStatus.DRAFT or locked.is_signed:
            raise LessonMediaError(
                "Медиа меняются только в неподписанном черновике. Обновите страницу.", status=409
            )
        snapshot = copy.deepcopy(locked.snapshot)
        change(find_lesson(snapshot, slug))
        problems = integrity_problems(snapshot)
        if problems:
            raise LessonMediaError("Изменение сломало бы курс: " + "; ".join(problems))
        locked.snapshot = snapshot
        locked.checksum_sha256 = snapshot_checksum(snapshot)
        locked.save(update_fields=["snapshot", "checksum_sha256", "updated_at"])
        try:
            compile_version(locked)
        except SalahFormulaError as error:
            # Nothing is saved: the documents must show what the draft holds.
            raise LessonMediaError(f"Документы курса не собрались: {error}", status=502) from error
    return locked


def draft_lesson(version: SalahCourseVersion, slug: str) -> DraftLesson:
    return DraftLesson(
        read=lambda: find_lesson(version.snapshot, slug),
        change=lambda change: change_lesson(version, slug, change),
    )
