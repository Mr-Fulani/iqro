# Operator-facing text is intentionally Russian.
"""Numbers for the admin pages «Аналитика» of a course and «Курсы: сводка»."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from django.db.models import Avg, Count, Sum
from django.utils import timezone

from quran_backend.modules.course_feedback.models import (
    CourseDailyStat,
    CourseRating,
    CourseStatEvent,
)
from quran_backend.modules.courses.models import COURSE_LANGUAGES, Course
from quran_backend.modules.feedback.models import FeedbackTicket

PERIODS = (7, 30, 90)
DEFAULT_PERIOD = 30
FUNNEL = (
    CourseStatEvent.LESSON_OPENED,
    CourseStatEvent.VIDEO_STARTED,
    CourseStatEvent.VIDEO_FINISHED,
    CourseStatEvent.LESSON_COMPLETED,
)
LATEST_COMMENTS = 20
PLATFORM_LABELS = {"web": "Сайт", "android": "Android", "ios": "iOS"}


def period_days(value: str | None) -> int:
    return int(value) if value in {str(days) for days in PERIODS} else DEFAULT_PERIOD


def since(days: int, today: date | None = None) -> date:
    return (today or timezone.localdate()) - timedelta(days=days - 1)


def percent(part: int, whole: int) -> int | None:
    return round(100 * part / whole) if whole else None


def _title(texts: dict[str, str]) -> str:
    return next((texts[language] for language in ("ru", *COURSE_LANGUAGES) if texts[language]), "")


def course_lessons(course: Course) -> list[dict[str, str]]:
    """Lessons in the order students see them: the live release, else the admin."""
    if course.live_release is not None:
        return [
            {"slug": lesson["slug"], "title": _title(lesson["title"]) or lesson["slug"]}
            for lesson in course.live_release.snapshot.get("lessons", [])
        ]
    return [{"slug": lesson.slug, "title": str(lesson)} for lesson in course.lessons.all()]


def course_report(course: Course, days: int, today: date | None = None) -> dict[str, Any]:
    start = since(days, today)
    stats = CourseDailyStat.objects.filter(course=course, date__gte=start)
    counts: dict[tuple[str, str], int] = {}
    platforms: dict[str, dict[str, int]] = {}
    for row in stats.values("lesson", "platform", "event").annotate(total=Sum("count")):
        key = (row["lesson"], row["event"])
        counts[key] = counts.get(key, 0) + row["total"]
        by_platform = platforms.setdefault(row["platform"], {})
        by_platform[row["event"]] = by_platform.get(row["event"], 0) + row["total"]

    lessons = course_lessons(course)
    known = {lesson["slug"] for lesson in lessons}
    removed = sorted({lesson for lesson, _event in counts} - known)
    lessons += [{"slug": slug, "title": f"{slug} (темы нет в курсе)"} for slug in removed]
    widest = max([1, *(value for value in counts.values())])
    rows: list[dict[str, Any]] = []
    for number, lesson in enumerate(lessons, start=1):
        values = {
            event.value: counts.get((lesson["slug"], event.value), 0) for event in CourseStatEvent
        }
        opened = values[CourseStatEvent.LESSON_OPENED]
        helpful = values[CourseStatEvent.LESSON_HELPFUL]
        votes = helpful + values[CourseStatEvent.LESSON_NOT_HELPFUL]
        rows.append(
            {
                **lesson,
                "number": number,
                "removed": lesson["slug"] in removed,
                "funnel": [
                    {
                        "label": event.label,
                        "value": values[event],
                        "width": round(100 * values[event] / widest),
                        "share": percent(values[event], opened),
                    }
                    for event in FUNNEL
                ],
                "opened": opened,
                "completed": values[CourseStatEvent.LESSON_COMPLETED],
                "helpful": helpful,
                "not_helpful": values[CourseStatEvent.LESSON_NOT_HELPFUL],
                "votes": votes,
                "helpful_share": percent(helpful, votes),
                "not_helpful_share": 100 - (percent(helpful, votes) or 0) if votes else 0,
            }
        )
    current = [row for row in rows if not row["removed"]]
    started: int = current[0]["opened"] if current else 0
    finished: int = current[-1]["completed"] if current else 0
    return {
        "days": days,
        "periods": PERIODS,
        "since": start,
        "totals": {
            "opened": sum(row["opened"] for row in rows),
            "started": started,
            "finished": finished,
            "finished_share": percent(finished, started),
        },
        "lessons": rows,
        "funnel_labels": [event.label for event in FUNNEL],
        "dropoff": dropoff(current),
        "platforms": [
            {
                "label": PLATFORM_LABELS.get(platform, platform),
                "values": [values.get(event, 0) for event in FUNNEL],
                "completion": percent(
                    values.get(CourseStatEvent.LESSON_COMPLETED, 0),
                    values.get(CourseStatEvent.LESSON_OPENED, 0),
                ),
            }
            for platform, values in sorted(platforms.items())
        ],
        "ratings": ratings(course, start),
        "reports": FeedbackTicket.objects.filter(
            context__course_slug=course.slug, created_at__date__gte=start
        ).count(),
    }


def dropoff(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Where students stop: opened the lesson but never opened the next one.

    For the last lesson it is those who opened it but did not mark it learnt.
    """
    places = []
    for index, row in enumerate(rows):
        if not row["opened"]:
            continue
        last = index == len(rows) - 1
        went_on = row["completed"] if last else rows[index + 1]["opened"]
        lost = max(0, row["opened"] - went_on)
        if lost:
            places.append(
                {
                    "number": row["number"],
                    "title": row["title"],
                    "lost": lost,
                    "share": percent(lost, row["opened"]),
                    "last": last,
                }
            )
    return sorted(places, key=lambda place: (-place["share"], -place["lost"]))[:3]


def ratings(course: Course, start: date) -> dict[str, Any]:
    period = CourseRating.objects.filter(course=course, updated_at__date__gte=start)
    summary = period.aggregate(count=Count("id"), average=Avg("stars"))
    overall = CourseRating.objects.filter(course=course).aggregate(
        count=Count("id"), average=Avg("stars")
    )
    by_stars = dict(
        period.values_list("stars").annotate(total=Count("id")).values_list("stars", "total")
    )
    count = summary["count"]
    return {
        "count": count,
        "average": summary["average"],
        "overall_count": overall["count"],
        "overall_average": overall["average"],
        "stars": [
            {
                "stars": stars,
                "count": by_stars.get(stars, 0),
                "width": percent(by_stars.get(stars, 0), count) or 0,
            }
            for stars in range(5, 0, -1)
        ],
        "comments": list(period.exclude(comment="")[:LATEST_COMMENTS]),
    }


def summary(days: int, today: date | None = None) -> dict[str, Any]:
    """Every course in one table: how far students get, how they rate it, what they report."""
    start = since(days, today)
    courses = list(Course.objects.select_related("live_release").prefetch_related("lessons"))
    lessons = {course.pk: course_lessons(course) for course in courses}
    events: dict[Any, dict[str, int]] = {}
    first_last: dict[Any, dict[str, int]] = {}
    for row in (
        CourseDailyStat.objects.filter(date__gte=start)
        .values("course_id", "lesson", "event")
        .annotate(total=Sum("count"))
    ):
        totals = events.setdefault(row["course_id"], {})
        totals[row["event"]] = totals.get(row["event"], 0) + row["total"]
        slugs = [lesson["slug"] for lesson in lessons.get(row["course_id"], [])]
        if not slugs:
            continue
        edges = first_last.setdefault(row["course_id"], {"started": 0, "finished": 0})
        if row["lesson"] == slugs[0] and row["event"] == CourseStatEvent.LESSON_OPENED:
            edges["started"] += row["total"]
        if row["lesson"] == slugs[-1] and row["event"] == CourseStatEvent.LESSON_COMPLETED:
            edges["finished"] += row["total"]
    rated = {
        row["course_id"]: row
        for row in CourseRating.objects.filter(updated_at__date__gte=start)
        .values("course_id")
        .annotate(count=Count("id"), average=Avg("stars"))
    }
    reported = dict(
        FeedbackTicket.objects.filter(created_at__date__gte=start)
        .exclude(context__course_slug="")
        .values_list("context__course_slug")
        .annotate(total=Count("id"))
        .values_list("context__course_slug", "total")
    )
    rows = []
    for course in courses:
        values = events.get(course.pk, {})
        edges = first_last.get(course.pk, {"started": 0, "finished": 0})
        helpful = values.get(CourseStatEvent.LESSON_HELPFUL, 0)
        votes = helpful + values.get(CourseStatEvent.LESSON_NOT_HELPFUL, 0)
        rating = rated.get(course.pk, {"count": 0, "average": None})
        rows.append(
            {
                "course": course,
                "opened": values.get(CourseStatEvent.LESSON_OPENED, 0),
                "completed": values.get(CourseStatEvent.LESSON_COMPLETED, 0),
                "started": edges["started"],
                "finished": edges["finished"],
                "finished_share": percent(edges["finished"], edges["started"]),
                "helpful_share": percent(helpful, votes),
                "votes": votes,
                "rating_count": rating["count"],
                "rating_average": rating["average"],
                "reports": reported.get(course.slug, 0),
            }
        )
    return {"days": days, "periods": PERIODS, "since": start, "rows": rows}
