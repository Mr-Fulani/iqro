# Operator-facing text is intentionally Russian.
"""Who studies what, for the admin: «Ученики курсов» and «Обучение» in a user's card.

The prayer course and the thematic courses come from `LearnerProgress`, the tajweed
course from its own `tajweed.TajweedCourseProgress`.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime
from typing import Any

from django.db.models import F
from django.utils.dateparse import parse_datetime

from quran_backend.modules.accounts.models import UserStatus
from quran_backend.modules.course_feedback.analytics import builtin_lessons, course_lessons
from quran_backend.modules.courses.models import (
    BuiltInCourse,
    Course,
    LearnerProgress,
    LearnerProgressKind,
)
from quran_backend.modules.names.models import DivineName
from quran_backend.modules.tajweed.models import TajweedCourseProgress, TajweedPracticeSession
from quran_backend.modules.tajweed.practice import user_practice_state

LIST_LIMIT = 300


class _Catalog:
    """Titles and lessons of the courses, read once for a page."""

    def __init__(self) -> None:
        self._courses = {
            course.slug: course
            for course in Course.objects.select_related("live_release").prefetch_related("lessons")
        }
        self._lessons: dict[str, list[str]] = {}

    def options(self) -> list[tuple[str, str]]:
        """(filter value, title): the prayer, the tajweed course and the names, then the catalog."""
        return [
            *BuiltInCourse.choices,
            *((slug, str(course)) for slug, course in self._courses.items()),
        ]

    def describe(self, kind: str, slug: str) -> tuple[str, str, list[str]]:
        """(filter value, title, lesson slugs) of the course a progress row belongs to."""
        if kind == LearnerProgressKind.COURSES:
            course = self._courses.get(slug)
            if course is None:
                return slug, f"{slug} (курса нет)", []
            if slug not in self._lessons:
                self._lessons[slug] = [lesson["slug"] for lesson in course_lessons(course)]
            return slug, str(course), self._lessons[slug]
        if kind == LearnerProgressKind.NAMES:
            # A name is a lesson: the names of the published list.
            key = f"names:{slug}"
            if key not in self._lessons:
                self._lessons[key] = list(
                    DivineName.objects.filter(
                        version__collection__slug=slug,
                        version__collection__active_version=F("version"),
                    ).values_list("slug", flat=True)
                )
            return kind, str(LearnerProgressKind.NAMES.label), self._lessons[key]
        if kind not in self._lessons:
            self._lessons[kind] = [lesson["slug"] for lesson in builtin_lessons(kind)]
        return kind, str(BuiltInCourse(kind).label), self._lessons[kind]


def _row(catalog: _Catalog, user: Any, kind: str, slug: str, lessons: Any) -> dict[str, Any]:
    key, title, known = catalog.describe(kind, slug)
    entries = lessons if isinstance(lessons, dict) else {}
    last = max((str(entry.get("updated_at", "")) for entry in entries.values()), default="")
    return {
        "user": user,
        "key": key,
        "title": title,
        "completed": sum(
            1 for lesson in known if entries.get(lesson, {}).get("status") == "completed"
        ),
        "started": sum(1 for lesson in known if lesson in entries),
        "total": len(known),
        "last": parse_datetime(last) if last else None,
    }


def _sorted(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    oldest = datetime.min.replace(tzinfo=UTC)
    return sorted(rows, key=lambda row: row["last"] or oldest, reverse=True)


def learners(course: str = "", query: str = "") -> dict[str, Any]:
    """Registered learners and how far they got; guests are not listed.

    `course` is a value of `options`: "salah", "tajweed", "names" or the slug of a thematic
    course.
    """
    catalog = _Catalog()
    account: dict[str, Any] = {"user__status": UserStatus.ACTIVE}
    if query:
        account["user__email__icontains"] = query
    stored = LearnerProgress.objects.filter(**account).select_related("user")
    tajweed = TajweedCourseProgress.objects.filter(**account).select_related("user")
    if course == BuiltInCourse.TAJWEED:
        stored = stored.none()
    elif course:
        tajweed = tajweed.none()
        stored = (
            stored.filter(kind=course)
            if course in (LearnerProgressKind.SALAH, LearnerProgressKind.NAMES)
            else stored.filter(kind=LearnerProgressKind.COURSES, course=course)
        )
    total = stored.count() + tajweed.count()
    rows = [
        _row(catalog, item.user, item.kind, item.course, item.lessons)
        for item in stored.order_by("-updated_at")[:LIST_LIMIT]
    ]
    rows += [
        _row(catalog, item.user, BuiltInCourse.TAJWEED, item.course, item.lessons)
        for item in tajweed.order_by("-updated_at")[:LIST_LIMIT]
    ]
    return {
        "rows": _sorted(rows)[:LIST_LIMIT],
        "total": total,
        "limit": LIST_LIMIT,
        "options": catalog.options(),
    }


def user_learning(user: Any) -> dict[str, Any]:
    """The courses of one user and the results of their tajweed practice."""
    catalog = _Catalog()
    rows = [
        _row(catalog, user, item.kind, item.course, item.lessons)
        for item in LearnerProgress.objects.filter(user=user)
    ]
    rows += [
        _row(catalog, user, BuiltInCourse.TAJWEED, item.course, item.lessons)
        for item in TajweedCourseProgress.objects.filter(user=user)
    ]
    practised = (
        TajweedPracticeSession.objects.filter(user=user)
        .values_list("course", flat=True)
        .distinct()
        .order_by("course")
    )
    return {
        "rows": _sorted(rows),
        "practice": [user_practice_state(user, course) for course in practised],
    }
