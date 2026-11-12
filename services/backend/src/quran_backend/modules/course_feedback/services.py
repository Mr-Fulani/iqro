from __future__ import annotations

import hashlib
import hmac
import uuid
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date
from typing import Any

from django.conf import settings
from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.db.models import F
from django.utils import timezone

from quran_backend.modules.course_feedback.models import (
    BUILTIN_STATS,
    NAMES,
    CourseDailyStat,
    CourseRating,
    CourseStatEvent,
)
from quran_backend.modules.courses.models import BuiltInCourse, Course, CourseRelease
from quran_backend.modules.names.models import DivineName, NamesCollection, NamesStatus
from quran_backend.modules.salah.models import (
    SalahCourse,
    SalahCourseVersion,
    SalahPublicationStatus,
)
from quran_backend.modules.tajweed.models import (
    TajweedCourse,
    TajweedCourseStatus,
    TajweedCourseVersion,
)

# A release never changes, so its lesson list may stay cached for long.
LESSONS_CACHE_SECONDS = 24 * 60 * 60


@dataclass(frozen=True)
class LiveCourse:
    id: uuid.UUID
    release_number: int
    lessons: tuple[str, ...]


def live_courses(slugs: Iterable[str]) -> dict[str, LiveCourse]:
    """Courses students can open now, with the lesson slugs of their live release."""
    found: dict[str, LiveCourse] = {}
    rows = Course.objects.filter(
        slug__in=set(slugs), hidden_at__isnull=True, live_release__isnull=False
    ).values_list("id", "slug", "live_release_id", "live_release__number")
    for course_id, slug, release_id, number in rows:
        key = f"course_feedback:lessons:{release_id}"
        lessons = cache.get(key)
        if lessons is None:
            snapshot = CourseRelease.objects.values_list("snapshot", flat=True).get(pk=release_id)
            lessons = tuple(lesson["slug"] for lesson in snapshot.get("lessons", []))
            cache.set(key, lessons, LESSONS_CACHE_SECONDS)
        found[slug] = LiveCourse(id=course_id, release_number=number, lessons=tuple(lessons))
    return found


@dataclass(frozen=True)
class LiveBuiltIn:
    kind: str
    lessons: tuple[str, ...]


def live_builtin_versions(kind: str) -> list[tuple[str, int]]:
    """(course slug, published version) of the prayer or the tajweed courses, or of the names."""
    if kind == BuiltInCourse.SALAH:
        courses: Any = SalahCourse.objects.filter(
            active_version__status=SalahPublicationStatus.PUBLISHED
        )
    elif kind == NAMES:
        courses = NamesCollection.objects.filter(active_version__status=NamesStatus.PUBLISHED)
    else:
        courses = TajweedCourse.objects.filter(active_version__status=TajweedCourseStatus.PUBLISHED)
    return list(courses.order_by("slug").values_list("slug", "active_version_id"))


def builtin_snapshot_lessons(kind: str, version_id: Any) -> list[dict[str, Any]]:
    if kind == NAMES:
        # A name is a lesson, in the order of the list.
        names = DivineName.objects.filter(version_id=version_id).order_by("position")
        return [
            {"slug": slug, "title": {"ru": f"{name} — {meaning}"}}
            for slug, name, meaning in names.values_list("slug", "transliteration_ru", "meaning_ru")
        ]
    model: Any = SalahCourseVersion if kind == BuiltInCourse.SALAH else TajweedCourseVersion
    snapshot = model.objects.values_list("snapshot", flat=True).get(pk=version_id)
    return list(snapshot.get("lessons", []))


def live_builtin_courses(slugs: Iterable[str]) -> dict[str, LiveBuiltIn]:
    """«Обучение намазу», «Таджвид» and «Имена Аллаха» by the slugs their clients send."""
    wanted = set(slugs)
    found: dict[str, LiveBuiltIn] = {}
    if not wanted:
        return found
    for kind in BUILTIN_STATS:
        for slug, version_id in live_builtin_versions(kind):
            if slug not in wanted or slug in found:
                continue
            # A published version never changes either.
            key = f"course_feedback:lessons:{kind}:{version_id}"
            lessons = cache.get(key)
            if lessons is None:
                lessons = tuple(
                    lesson["slug"] for lesson in builtin_snapshot_lessons(kind, version_id)
                )
                cache.set(key, lessons, LESSONS_CACHE_SECONDS)
            found[slug] = LiveBuiltIn(kind=kind, lessons=tuple(lessons))
    return found


def record_events(
    *,
    platform: str,
    events: Iterable[tuple[str, str, str]],
    today: date | None = None,
) -> int:
    """Add (course, lesson, event) to the daily sums of visible courses; return accepted.

    Events of unknown or hidden courses and of lessons outside the live release
    are dropped. The prayer and the tajweed course and the Names of Allah count like a
    course of the catalog; «Открыли раздел» is counted for the names only.
    """
    events = list(events)
    slugs = {course for course, _lesson, _event in events}
    courses = live_courses(slugs)
    builtin = live_builtin_courses(slugs - courses.keys())
    day = today or timezone.localdate()
    totals: Counter[tuple[str, object, str, str]] = Counter()
    for course, lesson, event in events:
        if event == CourseStatEvent.SECTION_OPENED:
            if not lesson and course in builtin and builtin[course].kind == NAMES:
                totals["builtin", NAMES, "", event] += 1
        elif course in courses and lesson in courses[course].lessons:
            totals["course_id", courses[course].id, lesson, event] += 1
        elif course in builtin and lesson in builtin[course].lessons:
            totals["builtin", builtin[course].kind, lesson, event] += 1
    for (field, value, lesson, event), count in totals.items():
        lookup = {
            "date": day,
            field: value,
            "lesson": lesson,
            "platform": platform,
            "event": event,
        }
        updated = CourseDailyStat.objects.filter(**lookup).update(count=F("count") + count)
        if updated:
            continue
        try:
            with transaction.atomic():
                CourseDailyStat.objects.create(**lookup, count=count)
        except IntegrityError:
            CourseDailyStat.objects.filter(**lookup).update(count=F("count") + count)
    return sum(totals.values())


def voter_digest(voter_id: object, course_id: uuid.UUID) -> str:
    """The same voter gives a different, irreversible digest for every course."""
    return hmac.new(
        str(settings.SECRET_KEY).encode(),
        f"course-rating\x00{voter_id}\x00{course_id}".encode(),
        hashlib.sha256,
    ).hexdigest()


def rate_course(  # noqa: PLR0913 - every field of the rating
    *,
    course: LiveCourse,
    voter_id: object,
    stars: int,
    comment: str,
    language: str,
    platform: str,
) -> CourseRating:
    """Save the voter's rating of the course; a repeated rating replaces the earlier one."""
    rating, _created = CourseRating.objects.update_or_create(
        course_id=course.id,
        voter_digest=voter_digest(voter_id, course.id),
        defaults={
            "stars": stars,
            "comment": comment,
            "language": language,
            "platform": platform,
            "release_number": course.release_number,
        },
    )
    return rating
