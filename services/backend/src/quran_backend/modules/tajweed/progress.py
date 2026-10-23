"""Lesson progress of the tajweed course, merged lesson by lesson.

The format is the clients' local one (docs/tajweed/course.md, «Прогресс»):
`{lesson: {status, step_slug, content_version, updated_at}}`. A merge keeps a
passed lesson passed and otherwise takes the later record, so it is the same
whatever order a phone and a browser send their copies in.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

from django.db import transaction

from quran_backend.modules.tajweed.models import TajweedCourseProgress

STATUSES = ("in_progress", "completed")
MAX_LESSONS = 200
LESSON_SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
STEP_SLUG = re.compile(r"^[a-z0-9][a-z0-9.-]{0,63}$")
VERSION = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$")


class TajweedProgressError(ValueError):
    pass


def iso_millis(moment: datetime) -> str:
    """The clients' `toISOString()` form: UTC, milliseconds, «Z»."""
    moment = moment.astimezone(UTC)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"


def _moment(value: object, where: str) -> datetime:
    if not isinstance(value, str):
        raise TajweedProgressError(f"{where}: updated_at must be an ISO date and time.")
    try:
        moment = datetime.fromisoformat(value)
    except ValueError as error:
        raise TajweedProgressError(f"{where}: updated_at must be an ISO date and time.") from error
    if moment.tzinfo is None:
        raise TajweedProgressError(f"{where}: updated_at needs a time zone.")
    return moment


def clean_lessons(value: object) -> dict[str, dict[str, str]]:
    """The lessons of a request in the stored form, or TajweedProgressError."""
    if not isinstance(value, Mapping):
        raise TajweedProgressError("lessons must be an object.")
    if len(value) > MAX_LESSONS:
        raise TajweedProgressError(f"At most {MAX_LESSONS} lessons.")
    cleaned: dict[str, dict[str, str]] = {}
    for slug, entry in value.items():
        where = f"lessons.{slug}"
        if not isinstance(slug, str) or not LESSON_SLUG.match(slug) or len(slug) > 64:
            raise TajweedProgressError(f"{where}: invalid lesson slug.")
        if not isinstance(entry, Mapping):
            raise TajweedProgressError(f"{where}: must be an object.")
        status = entry.get("status")
        step = entry.get("step_slug")
        version = entry.get("content_version")
        if status not in STATUSES:
            raise TajweedProgressError(f"{where}: status is in_progress or completed.")
        if not isinstance(step, str) or not STEP_SLUG.match(step):
            raise TajweedProgressError(f"{where}: invalid step_slug.")
        if not isinstance(version, str) or not VERSION.match(version):
            raise TajweedProgressError(f"{where}: invalid content_version.")
        cleaned[slug] = {
            "status": status,
            "step_slug": step,
            "content_version": version,
            "updated_at": iso_millis(_moment(entry.get("updated_at"), where)),
        }
    return cleaned


def merge_lessons(
    stored: Mapping[str, Mapping[str, str]], incoming: Mapping[str, Mapping[str, str]]
) -> dict[str, dict[str, str]]:
    merged = {slug: dict(entry) for slug, entry in stored.items()}
    for slug, entry in incoming.items():
        current = merged.get(slug)
        if current is None:
            merged[slug] = dict(entry)
            continue
        later = entry if entry["updated_at"] > current["updated_at"] else current
        completed = "completed" in {entry["status"], current["status"]}
        merged[slug] = {**later, "status": "completed" if completed else later["status"]}
    return dict(sorted(merged.items()))


@transaction.atomic
def merge_user_progress(user: Any, course: str, lessons: object) -> dict[str, Any]:
    incoming = clean_lessons(lessons)
    progress, _ = TajweedCourseProgress.objects.select_for_update().get_or_create(
        user=user, course=course
    )
    merged = merge_lessons(progress.lessons, incoming)
    if merged != progress.lessons:
        progress.lessons = merged
        progress.save(update_fields=["lessons", "updated_at"])
    return {"course": course, "lessons": merged}


def user_progress(user: Any, course: str) -> dict[str, Any]:
    progress = TajweedCourseProgress.objects.filter(user=user, course=course).first()
    return {"course": course, "lessons": progress.lessons if progress else {}}
