"""Lesson progress of the prayer course, the thematic courses and the Names, kept with the account.

The format and the merge are those of the tajweed course (`tajweed.progress`): the
later record of a lesson wins, so a phone and a browser may send their copies in
any order. In the prayer course a passed lesson also stays passed; in a thematic
course the app lets the learner take «studied» back, so there the later record
wins as it is. The Names of Allah are kept the same way: a name is a lesson, «in_progress» is
a name the needle stopped on, «completed» a name marked as learned, and the mark can be
taken back.
"""

from __future__ import annotations

from typing import Any

from django.db import transaction

from quran_backend.modules.courses.models import Course, LearnerProgress, LearnerProgressKind
from quran_backend.modules.names.models import NamesCollection
from quran_backend.modules.salah.models import SalahCourse
from quran_backend.modules.tajweed.progress import clean_lessons, merge_lessons


def course_exists(kind: str, course: str) -> bool:
    """Whether learners have ever been shown this course."""
    if kind == LearnerProgressKind.SALAH:
        return SalahCourse.objects.filter(slug=course, active_version__isnull=False).exists()
    if kind == LearnerProgressKind.NAMES:
        return NamesCollection.objects.filter(slug=course, active_version__isnull=False).exists()
    return Course.objects.filter(slug=course, live_release__isnull=False).exists()


@transaction.atomic
def merge_user_progress(user: Any, kind: str, course: str, lessons: object) -> dict[str, Any]:
    incoming = clean_lessons(lessons, empty_step=True)
    progress, _ = LearnerProgress.objects.select_for_update().get_or_create(
        user=user, kind=kind, course=course
    )
    merged = merge_lessons(
        progress.lessons, incoming, keep_completed=kind == LearnerProgressKind.SALAH
    )
    if merged != progress.lessons:
        progress.lessons = merged
        progress.save(update_fields=["lessons", "updated_at"])
    return {"kind": kind, "course": course, "lessons": merged}


def user_progress(user: Any, kind: str, course: str) -> dict[str, Any]:
    progress = LearnerProgress.objects.filter(user=user, kind=kind, course=course).first()
    return {"kind": kind, "course": course, "lessons": progress.lessons if progress else {}}
