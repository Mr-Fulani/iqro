from __future__ import annotations

import hashlib
import hmac
import uuid
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date

from django.conf import settings
from django.core.cache import cache
from django.db import IntegrityError, transaction
from django.db.models import F
from django.utils import timezone

from quran_backend.modules.course_feedback.models import CourseDailyStat, CourseRating
from quran_backend.modules.courses.models import Course, CourseRelease

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


def record_events(
    *,
    platform: str,
    events: Iterable[tuple[str, str, str]],
    today: date | None = None,
) -> int:
    """Add (course, lesson, event) to the daily sums of visible courses; return accepted.

    Events of unknown or hidden courses and of lessons outside the live release
    are dropped.
    """
    events = list(events)
    courses = live_courses(course for course, _lesson, _event in events)
    day = today or timezone.localdate()
    totals = Counter(
        (courses[course].id, lesson, event)
        for course, lesson, event in events
        if course in courses and lesson in courses[course].lessons
    )
    for (course_id, lesson, event), count in totals.items():
        lookup = {
            "date": day,
            "course_id": course_id,
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
