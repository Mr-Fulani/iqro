# Russian operator strings are asserted verbatim.
# ruff: noqa: RUF001, F811 - imported fixtures are used by name
from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.contrib.auth.models import Group, Permission
from django.core.cache import caches
from django.test import Client
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.course_feedback.analytics import course_report, dropoff, summary
from quran_backend.modules.course_feedback.models import CourseDailyStat, CourseRating
from quran_backend.modules.course_feedback.services import voter_digest
from quran_backend.modules.course_feedback.throttling import (
    CourseEventRateThrottle,
    CourseRatingRateThrottle,
)
from quran_backend.modules.courses.models import Course
from quran_backend.modules.courses.services import hide_course
from quran_backend.modules.feedback.models import FeedbackTicket
from quran_backend.modules.names.publication import import_names
from quran_backend.modules.salah.models import SalahCourse, SalahCourseVersion
from quran_backend.modules.tajweed.models import TajweedCourse, TajweedCourseVersion
from tests.test_courses import owner, ramadan, release_course  # noqa: F401 - fixtures by name
from tests.test_names import _data as names_data
from tests.test_names import _published as publish_names

EVENTS = "/api/v1/courses/events"
NAMES_LIST = "asma-al-husna"
RATING = "/api/v1/courses/ramadan/rating"


@pytest.fixture(autouse=True)
def _fresh_throttles() -> None:
    caches["throttling"].clear()


@pytest.fixture
def live(ramadan: Course, owner: User) -> Course:
    release_course(ramadan, owner)
    ramadan.refresh_from_db()
    return ramadan


def _guest_client() -> tuple[APIClient, User]:
    guest = User.objects.create_user(status=UserStatus.GUEST)
    client = APIClient()
    client.force_authenticate(user=guest)
    return client, guest


def _event(lesson: str, event: str, course: str = "ramadan") -> dict[str, str]:
    return {"course": course, "lesson": lesson, "event": event}


@pytest.fixture
def builtin(owner: User) -> None:
    """The published prayer and tajweed courses, under the slugs their clients send."""
    for course_model, version_model, slug, lessons in (
        (SalahCourse, SalahCourseVersion, "hanbali-umdah", ("wudu", "fajr")),
        (TajweedCourse, TajweedCourseVersion, "tajweed", ("izhar", "iqlab")),
    ):
        course: Any = course_model.objects.create(slug=slug)
        extra = {"methodology": "hanbali"} if course_model is SalahCourse else {}
        course.active_version = version_model.objects.create(
            course=course,
            version="2026-11-01",
            schema_version=1,
            snapshot={
                "lessons": [
                    {"slug": lesson, "title": {"ru": f"Урок {lesson}"}} for lesson in lessons
                ]
            },
            checksum_sha256="0" * 64,
            status="published",
            published_at=timezone.now(),
            reviewed_by=owner,
            reviewed_at=timezone.now(),
            **extra,
        )
        course.save()


# Events ------------------------------------------------------------------


@pytest.mark.django_db
def test_events_of_the_builtin_courses_are_counted(
    live: Course, builtin: None, api_client: APIClient
) -> None:
    response = api_client.post(
        EVENTS,
        {
            "platform": "web",
            "events": [
                _event("wudu", "lesson_opened", course="hanbali-umdah"),
                _event("wudu", "lesson_opened", course="hanbali-umdah"),
                _event("fajr", "lesson_completed", course="hanbali-umdah"),
                _event("izhar", "video_started", course="tajweed"),
                _event("no-such-lesson", "lesson_opened", course="hanbali-umdah"),
                # A lesson of the other course is not a lesson of this one.
                _event("izhar", "lesson_opened", course="hanbali-umdah"),
                _event("smysl-posta", "lesson_opened"),
            ],
        },
        format="json",
    )
    api_client.post(
        EVENTS,
        {"platform": "web", "events": [_event("wudu", "lesson_opened", course="hanbali-umdah")]},
        format="json",
    )

    assert response.json() == {"accepted": 5}
    counts = {
        (row.builtin, row.lesson, row.event): row.count
        for row in CourseDailyStat.objects.filter(course=None)
    }
    assert counts == {
        ("salah", "wudu", "lesson_opened"): 3,
        ("salah", "fajr", "lesson_completed"): 1,
        ("tajweed", "izhar", "video_started"): 1,
    }
    assert CourseDailyStat.objects.get(course=live).builtin == ""


@pytest.mark.django_db
def test_events_of_an_unpublished_builtin_course_are_dropped(
    builtin: None, api_client: APIClient
) -> None:
    SalahCourse.objects.update(active_version=None)

    response = api_client.post(
        EVENTS,
        {"platform": "ios", "events": [_event("wudu", "lesson_opened", course="hanbali-umdah")]},
        format="json",
    )

    assert response.json() == {"accepted": 0}
    assert not CourseDailyStat.objects.exists()


@pytest.mark.django_db
def test_events_of_the_names_of_allah_are_counted(
    builtin: None,
    owner: User,
    api_client: APIClient,
) -> None:
    publish_names(owner)

    response = api_client.post(
        EVENTS,
        {
            "platform": "android",
            "events": [
                _event("", "section_opened", course=NAMES_LIST),
                _event("", "section_opened", course=NAMES_LIST),
                # A name is a lesson: its card was opened, it was marked learnt.
                _event("ar-rahman", "lesson_opened", course=NAMES_LIST),
                _event("al-jamil", "lesson_completed", course=NAMES_LIST),
                _event("no-such-name", "lesson_opened", course=NAMES_LIST),
                # The section has no lesson, a card has one.
                _event("ar-rahman", "section_opened", course=NAMES_LIST),
                _event("", "lesson_opened", course=NAMES_LIST),
                # Only the names are a section.
                _event("", "section_opened", course="hanbali-umdah"),
                _event("", "section_opened"),
            ],
        },
        format="json",
    )

    assert response.status_code == 202
    assert response.json() == {"accepted": 4}
    assert {
        (row.builtin, row.lesson, row.platform, row.event): row.count
        for row in CourseDailyStat.objects.all()
    } == {
        ("names", "", "android", "section_opened"): 2,
        ("names", "ar-rahman", "android", "lesson_opened"): 1,
        ("names", "al-jamil", "android", "lesson_completed"): 1,
    }


@pytest.mark.django_db
def test_events_of_an_unpublished_list_of_names_are_dropped(
    owner: User,
    api_client: APIClient,
) -> None:
    import_names(names_data())
    events = [
        _event("", "section_opened", course=NAMES_LIST),
        _event("ar-rahman", "lesson_opened", course=NAMES_LIST),
    ]

    draft = api_client.post(EVENTS, {"platform": "web", "events": events}, format="json")
    version = publish_names(owner, "v2")
    live = api_client.post(EVENTS, {"platform": "web", "events": events}, format="json")
    version.status = "withdrawn"
    version.save(update_fields=["status"])
    withdrawn = api_client.post(EVENTS, {"platform": "web", "events": events}, format="json")

    assert [draft.json(), live.json(), withdrawn.json()] == [
        {"accepted": 0},
        {"accepted": 2},
        {"accepted": 0},
    ]


@pytest.mark.django_db
def test_events_keep_only_daily_sums_of_visible_lessons(
    live: Course, api_client: APIClient
) -> None:
    opened = _event("smysl-posta", "lesson_opened")
    response = api_client.post(
        EVENTS,
        {
            "platform": "android",
            "events": [
                opened,
                opened,
                _event("namerenie", "video_finished"),
                _event("namerenie", "lesson_helpful"),
                _event("no-such-lesson", "lesson_opened"),
                _event("smysl-posta", "lesson_opened", course="no-such-course"),
            ],
        },
        format="json",
    )
    api_client.post(EVENTS, {"platform": "web", "events": [opened]}, format="json")

    assert response.status_code == 202
    assert response.json() == {"accepted": 4}
    assert response["Cache-Control"] == "no-store"
    assert not response.cookies
    counts = {
        (row.lesson, row.platform, row.event): row.count
        for row in CourseDailyStat.objects.filter(course=live)
    }
    assert counts == {
        ("smysl-posta", "android", "lesson_opened"): 2,
        ("smysl-posta", "web", "lesson_opened"): 1,
        ("namerenie", "android", "video_finished"): 1,
        ("namerenie", "android", "lesson_helpful"): 1,
    }
    stored = {field.name for field in CourseDailyStat._meta.get_fields()}
    assert stored == {
        "id",
        "date",
        "course",
        "builtin",
        "lesson",
        "platform",
        "event",
        "count",
    }


@pytest.mark.django_db
def test_events_of_hidden_or_unpublished_courses_are_dropped(
    live: Course, owner: User, api_client: APIClient
) -> None:
    Course.objects.create(slug="draft", title_ru="Черновик")
    hide_course(live, owner, reason="Проверка")

    response = api_client.post(
        EVENTS,
        {
            "platform": "web",
            "events": [
                _event("smysl-posta", "lesson_opened"),
                _event("smysl-posta", "lesson_opened", course="draft"),
            ],
        },
        format="json",
    )

    assert response.json() == {"accepted": 0}
    assert not CourseDailyStat.objects.exists()


@pytest.mark.django_db
@pytest.mark.parametrize(
    "body",
    [
        {"platform": "web", "events": []},
        {"platform": "tv", "events": [_event("smysl-posta", "lesson_opened")]},
        {"platform": "web", "events": [_event("smysl-posta", "lesson_liked")]},
        {"platform": "web", "events": [_event("smysl-posta", "lesson_opened")] * 51},
    ],
)
def test_events_reject_bad_batches(api_client: APIClient, body: dict[str, Any]) -> None:
    assert api_client.post(EVENTS, body, format="json").status_code == 400


@pytest.mark.django_db
def test_events_are_throttled(
    live: Course, api_client: APIClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(CourseEventRateThrottle, "get_rate", lambda _self: "2/minute")
    body = {"platform": "web", "events": [_event("smysl-posta", "lesson_opened")]}
    statuses = [api_client.post(EVENTS, body, format="json").status_code for _ in range(3)]

    assert statuses == [202, 202, 429]


# Ratings -----------------------------------------------------------------


@pytest.mark.django_db
def test_rating_needs_a_session(live: Course, api_client: APIClient) -> None:
    response = api_client.put(
        RATING, {"stars": 5, "language": "ru", "platform": "web"}, format="json"
    )

    assert response.status_code == 401


@pytest.mark.django_db
def test_a_guest_rates_once_and_a_new_rating_replaces_it(live: Course) -> None:
    client, guest = _guest_client()

    first = client.put(RATING, {"stars": 2, "language": "ru", "platform": "android"}, format="json")
    second = client.put(
        RATING,
        {"stars": 4, "comment": "  Спасибо, понятно!  ", "language": "ru", "platform": "android"},
        format="json",
    )
    other, _ = _guest_client()
    other.put(RATING, {"stars": 5, "language": "ru", "platform": "web"}, format="json")

    assert first.status_code == 200
    assert second.json()["stars"] == 4
    assert second.json()["comment"] == "Спасибо, понятно!"
    assert "no-store" in second["Cache-Control"]
    assert CourseRating.objects.count() == 2
    rating = CourseRating.objects.get(voter_digest=voter_digest(guest.pk, live.pk))
    assert (rating.stars, rating.comment, rating.release_number) == (4, "Спасибо, понятно!", 1)
    # Nothing in the row points at the guest.
    stored = {field.name for field in CourseRating._meta.get_fields()}
    assert stored == {
        "id",
        "created_at",
        "updated_at",
        "course",
        "voter_digest",
        "stars",
        "comment",
        "language",
        "platform",
        "release_number",
    }
    assert str(guest.pk) not in rating.voter_digest


@pytest.mark.django_db
def test_voter_digest_differs_between_courses() -> None:
    voter = uuid.uuid7()

    assert voter_digest(voter, uuid.uuid7()) != voter_digest(voter, uuid.uuid7())


@pytest.mark.django_db
@pytest.mark.parametrize(
    "body",
    [
        {"stars": 0, "language": "ru", "platform": "web"},
        {"stars": 6, "language": "ru", "platform": "web"},
        {"stars": 5, "language": "fr", "platform": "web"},
        {"stars": 5, "comment": "x" * 1001, "language": "ru", "platform": "web"},
        {"stars": 5, "comment": "<b>жирно</b>", "language": "ru", "platform": "web"},
    ],
)
def test_rating_rejects_bad_input(live: Course, body: dict[str, Any]) -> None:
    client, _ = _guest_client()

    assert client.put(RATING, body, format="json").status_code == 400


@pytest.mark.django_db
def test_hidden_course_can_not_be_rated(live: Course, owner: User) -> None:
    hide_course(live, owner, reason="Проверка")
    client, _ = _guest_client()

    response = client.put(RATING, {"stars": 5, "language": "ru", "platform": "web"}, format="json")

    assert response.status_code == 404
    assert response.json()["detail"] == "Такого курса нет."


@pytest.mark.django_db
def test_ratings_are_throttled_per_voter(live: Course, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(CourseRatingRateThrottle, "get_rate", lambda _self: "2/hour")
    client, _ = _guest_client()
    body = {"stars": 5, "language": "ru", "platform": "web"}

    statuses = [client.put(RATING, body, format="json").status_code for _ in range(3)]
    other, _ = _guest_client()

    assert statuses == [200, 200, 429]
    assert other.put(RATING, body, format="json").status_code == 200


# Reports -----------------------------------------------------------------


def _report(client: APIClient, **context: Any) -> Any:
    return client.post(
        "/api/v1/feedback/tickets",
        {
            "client_request_id": str(uuid.uuid7()),
            "client_message_id": str(uuid.uuid7()),
            "category": "religious_content",
            "subject": "Рамадан · 2. Намерение (ният)",
            "message": "В цитате, кажется, неверный аят.",
            "locale": "ru",
            "context": {"route": "/courses/ramadan/namerenie", **context},
        },
        format="json",
    )


@pytest.mark.django_db
def test_lesson_report_keeps_the_course_context(live: Course) -> None:
    client, _ = _guest_client()

    response = _report(
        client,
        course_slug="ramadan",
        lesson_slug="namerenie",
        content_version="1",
        playback_ms=252_000,
        slide_number=3,
        client_platform="android",
    )

    assert response.status_code == 201
    context = response.json()["context"]
    assert (context["course_slug"], context["lesson_slug"]) == ("ramadan", "namerenie")
    assert (context["content_version"], context["playback_ms"], context["slide_number"]) == (
        "1",
        252_000,
        3,
    )


@pytest.mark.django_db
@pytest.mark.parametrize(
    "context",
    [
        {"lesson_slug": "namerenie"},
        {"course_slug": "ramadan", "slide_number": 2},
        {"playback_ms": 1000},
        {"course_slug": "Рамадан!"},
    ],
)
def test_lesson_report_context_must_be_consistent(live: Course, context: dict[str, Any]) -> None:
    client, _ = _guest_client()

    assert _report(client, **context).status_code == 400


@pytest.mark.django_db
def test_admin_ticket_links_to_the_lesson_and_filters_by_course(live: Course, owner: User) -> None:
    client, _ = _guest_client()
    _report(client, course_slug="ramadan", lesson_slug="namerenie", playback_ms=252_000)
    _report(client)
    ticket = FeedbackTicket.objects.get(context__course_slug="ramadan")
    lesson = live.lessons.get(slug="namerenie")
    admin = Client()
    admin.force_login(owner)

    page = admin.get(f"/admin/feedback/feedbackticket/{ticket.pk}/change/").content.decode()
    listing = admin.get("/admin/feedback/feedbackticket/?course=ramadan").content.decode()

    assert f"/admin/courses/courselesson/{lesson.pk}/change/" in page
    assert "/ru/courses/ramadan/namerenie" in page
    assert "видео 4:12" in page
    assert listing.count(ticket.public_id) >= 1
    assert FeedbackTicket.objects.exclude(pk=ticket.pk).get().public_id not in listing


# Admin analytics ---------------------------------------------------------


def _stat(
    course: Course, lesson: str, event: str, count: int, days_ago: int = 0, **extra: Any
) -> None:
    CourseDailyStat.objects.create(
        date=timezone.localdate() - timedelta(days=days_ago),
        course=course,
        lesson=lesson,
        platform=extra.get("platform", "web"),
        event=event,
        count=count,
    )


@pytest.mark.django_db
def test_course_report_builds_the_funnel_dropoff_and_ratings(live: Course) -> None:
    _stat(live, "smysl-posta", "lesson_opened", 10)
    _stat(live, "smysl-posta", "lesson_completed", 8)
    _stat(live, "namerenie", "lesson_opened", 4, platform="android")
    _stat(live, "namerenie", "video_started", 3, platform="android")
    _stat(live, "namerenie", "video_finished", 2, platform="android")
    _stat(live, "namerenie", "lesson_completed", 2, platform="android")
    _stat(live, "namerenie", "lesson_helpful", 3)
    _stat(live, "namerenie", "lesson_not_helpful", 1)
    _stat(live, "taraviikh", "lesson_opened", 3)
    _stat(live, "taraviikh", "lesson_opened", 50, days_ago=40)
    _stat(live, "old-lesson", "lesson_opened", 1)
    for stars, comment in ((5, "Отлично"), (3, ""), (4, "Хорошо")):
        CourseRating.objects.create(
            course=live,
            voter_digest=uuid.uuid4().hex,
            stars=stars,
            comment=comment,
            language="ru",
            platform="web",
            release_number=1,
        )

    report = course_report(live, 30)

    lessons = {row["slug"]: row for row in report["lessons"]}
    assert [row["slug"] for row in report["lessons"]] == [
        "smysl-posta",
        "namerenie",
        "taraviikh",
        "old-lesson",
    ]
    assert lessons["old-lesson"]["removed"]
    assert [step["value"] for step in lessons["namerenie"]["funnel"]] == [4, 3, 2, 2]
    assert lessons["namerenie"]["helpful_share"] == 75
    assert lessons["taraviikh"]["opened"] == 3
    assert [(place["number"], place["share"], place["last"]) for place in report["dropoff"]] == [
        (3, 100, True),
        (1, 60, False),
        (2, 25, False),
    ]
    assert report["ratings"]["count"] == 3
    assert report["ratings"]["average"] == pytest.approx(4)
    assert [item["count"] for item in report["ratings"]["stars"]] == [1, 1, 1, 0, 0]
    assert [rating.comment for rating in report["ratings"]["comments"]] == ["Хорошо", "Отлично"]
    assert {row["label"] for row in report["platforms"]} == {"Сайт", "Android"}
    assert course_report(live, 90)["lessons"][2]["opened"] == 53


def test_dropoff_of_the_last_lesson_counts_those_who_did_not_finish() -> None:
    rows = [
        {"number": 1, "title": "A", "opened": 10, "completed": 9},
        {"number": 2, "title": "B", "opened": 10, "completed": 4},
    ]

    assert dropoff(rows) == [{"number": 2, "title": "B", "lost": 6, "share": 60, "last": True}]


@pytest.mark.django_db
def test_summary_shows_how_far_students_get(live: Course) -> None:
    _stat(live, "smysl-posta", "lesson_opened", 10)
    _stat(live, "taraviikh", "lesson_completed", 4)
    Course.objects.create(slug="draft", title_ru="Черновик")

    rows = {row["course"].slug: row for row in summary(30)["rows"] if row["course"]}

    assert (rows["ramadan"]["started"], rows["ramadan"]["finished"]) == (10, 4)
    assert rows["ramadan"]["finished_share"] == 40
    assert rows["draft"]["opened"] == 0


@pytest.mark.django_db
def test_admin_pages_show_analytics_to_permitted_staff(live: Course, owner: User) -> None:
    _stat(live, "smysl-posta", "lesson_opened", 7)
    CourseRating.objects.create(
        course=live,
        voter_digest="a" * 64,
        stars=5,
        comment="Спасибо за курс",
        language="ru",
        platform="android",
        release_number=1,
    )
    client = Client()
    client.force_login(owner)

    course_form = client.get(f"/admin/courses/course/{live.pk}/change/").content.decode()
    overview = client.get("/admin/course_feedback/courseanalytics/?days=7")
    page = client.get(f"/admin/course_feedback/courseanalytics/{live.pk}/change/?days=90")

    assert f"/admin/course_feedback/courseanalytics/{live.pk}/change/" in course_form
    assert overview.status_code == 200
    assert "Статистика и оценки курсов" in overview.content.decode()
    assert page.status_code == 200
    body = page.content.decode()
    assert "Аналитика: Рамадан" in body
    assert "Спасибо за курс" in body
    assert "Где чаще бросают" in body


def _builtin_stat(kind: str, lesson: str, event: str, count: int) -> None:
    CourseDailyStat.objects.create(
        date=timezone.localdate(),
        builtin=kind,
        lesson=lesson,
        platform="android",
        event=event,
        count=count,
    )


@pytest.mark.django_db
def test_summary_and_report_include_the_builtin_courses(live: Course, builtin: None) -> None:
    _stat(live, "smysl-posta", "lesson_opened", 10)
    _builtin_stat("salah", "wudu", "lesson_opened", 6)
    _builtin_stat("salah", "fajr", "lesson_completed", 3)
    _builtin_stat("tajweed", "izhar", "lesson_opened", 2)

    rows = summary(30)["rows"]
    report = course_report("salah", 30)

    assert [row["title"] for row in rows] == [
        "Обучение намазу",
        "Таджвид",
        "Имена Аллаха",
        "Рамадан",
    ]
    assert (rows[0]["opened"], rows[0]["started"], rows[0]["finished"]) == (6, 6, 3)
    assert rows[0]["finished_share"] == 50
    assert (rows[1]["opened"], rows[1]["completed"]) == (2, 0)
    assert rows[3]["opened"] == 10
    # Only the names have «Открыли раздел».
    assert [row["visits"] for row in rows] == [None, None, 0, None]
    assert [(row["slug"], row["title"]) for row in report["lessons"]] == [
        ("wudu", "Урок wudu"),
        ("fajr", "Урок fajr"),
    ]
    assert report["totals"] == {"opened": 6, "started": 6, "finished": 3, "finished_share": 50}
    assert report["ratings"] is None
    assert report["visits"] is None
    assert [row["label"] for row in report["platforms"]] == ["Android"]


@pytest.mark.django_db
def test_summary_and_report_include_the_names_of_allah(
    owner: User,
) -> None:
    publish_names(owner)
    _builtin_stat("names", "", "section_opened", 9)
    _builtin_stat("names", "ar-rahman", "lesson_opened", 5)
    _builtin_stat("names", "al-jamil", "lesson_opened", 2)
    _builtin_stat("names", "al-jamil", "lesson_completed", 1)

    row = summary(30)["rows"][2]
    report = course_report("names", 30)

    assert (row["key"], row["title"], row["course"]) == ("names", "Имена Аллаха", None)
    assert (row["opened"], row["completed"], row["visits"]) == (7, 1, 9)
    assert (row["started"], row["finished"], row["rating_count"]) == (5, 1, 0)
    # A name is a lesson, in the order of the list; the section itself is not one.
    assert [(item["slug"], item["title"], item["opened"]) for item in report["lessons"]] == [
        ("ar-rahman", "Ар-Рахман [ru] — Милостивый [ru]", 5),
        ("al-jamil", "Аль-Джамиль [ru] — Прекрасный [ru]", 2),
    ]
    assert report["visits"] == 9
    assert report["totals"]["opened"] == 7
    assert report["ratings"] is None
    assert [(item["label"], item["values"]) for item in report["platforms"]] == [
        ("Android", [7, 0, 0, 1])
    ]


@pytest.mark.django_db
def test_admin_pages_show_the_names_of_allah(
    owner: User,
) -> None:
    publish_names(owner)
    _builtin_stat("names", "", "section_opened", 9)
    _builtin_stat("names", "ar-rahman", "lesson_opened", 5)
    client = Client()
    client.force_login(owner)

    overview = client.get("/admin/course_feedback/courseanalytics/").content.decode()
    page = client.get("/admin/course_feedback/courseanalytics/names/change/?days=7")
    courses = client.get("/admin/courses/course/").content.decode()

    assert '<a href="/admin/course_feedback/courseanalytics/names/change/?days=30">' in overview
    assert "(раздел открывали: 9)" in overview
    assert page.status_code == 200
    body = page.content.decode()
    assert "Аналитика: Имена Аллаха" in body
    assert "<span>Открыли раздел</span><strong>9</strong>" in body
    assert "Ар-Рахман [ru] — Милостивый [ru]" in body
    assert "Тема здесь — одно имя" in body
    # The learners of the names, by the filter of «Ученики курсов».
    assert '<a href="/admin/courses/learnerprogress/?course=names">' in body
    assert "Открыть курс в редакторе" not in body
    assert "Оценки и комментарии" not in body
    assert "(темы нет в курсе)" not in body
    # The block above the catalog: the statistics and the editor of the list.
    assert 'Имена Аллаха</strong> <span class="ca-quiet">(отдельный раздел)</span>' in courses
    assert "/admin/course_feedback/courseanalytics/names/change/" in courses
    assert '<a href="/admin/names/namesversion/">Править</a>' in courses


@pytest.mark.django_db
def test_admin_pages_show_the_builtin_courses(builtin: None, owner: User) -> None:
    _builtin_stat("salah", "wudu", "lesson_opened", 6)
    _builtin_stat("tajweed", "iqlab", "lesson_completed", 4)
    client = Client()
    client.force_login(owner)

    overview = client.get("/admin/course_feedback/courseanalytics/").content.decode()
    salah = client.get("/admin/course_feedback/courseanalytics/salah/change/")
    tajweed = client.get("/admin/course_feedback/courseanalytics/tajweed/change/?days=7")

    assert "/admin/course_feedback/courseanalytics/salah/change/" in overview
    assert "Обучение намазу" in overview
    assert "Таджвид" in overview
    assert salah.status_code == 200
    body = salah.content.decode()
    assert "Аналитика: Обучение намазу" in body
    assert "Урок wudu" in body
    assert "?course=hanbali-umdah" in body
    assert "Открыть курс в редакторе" not in body
    assert "Оценки и комментарии" not in body
    # «Открыли раздел» is of the names only.
    assert "Открыли раздел" not in body
    assert "Урок iqlab" in tajweed.content.decode()
    assert client.get("/admin/course_feedback/courseanalytics/nope/change/").status_code in {
        302,
        404,
    }


@pytest.mark.django_db
def test_analytics_needs_its_permission(live: Course) -> None:
    staff = User.objects.create_user(email="editor@example.test", status="active", is_staff=True)
    client = Client()
    client.force_login(staff)

    assert client.get("/admin/course_feedback/courseanalytics/").status_code == 403

    staff.user_permissions.add(Permission.objects.get(codename="view_courseanalytics"))
    assert client.get("/admin/course_feedback/courseanalytics/").status_code == 200


@pytest.mark.django_db
def test_course_editors_and_publishers_may_view_analytics() -> None:
    for name in ("Редактор курсов", "Публикатор"):
        group = Group.objects.get(name=name)
        assert group.permissions.filter(codename="view_courseanalytics").exists()


@pytest.mark.django_db
def test_courses_list_shows_every_course_with_its_numbers(
    live: Course, builtin: None, owner: User
) -> None:
    _stat(live, "smysl-posta", "lesson_opened", 7)
    _builtin_stat("salah", "wudu", "lesson_opened", 6)
    _builtin_stat("tajweed", "iqlab", "lesson_completed", 4)
    client = Client()
    client.force_login(owner)

    page = client.get("/admin/courses/course/")

    assert page.status_code == 200
    rows = page.context["all_courses"]["rows"]
    assert [row["title"] for row in rows] == [
        "Обучение намазу",
        "Таджвид",
        "Имена Аллаха",
        "Рамадан",
    ]
    assert [(row["opened"], row["completed"]) for row in rows] == [(6, 0), (0, 4), (0, 0), (7, 0)]
    body = page.content.decode()
    assert "Все курсы и их статистика за 30 дней" in body
    assert "встроенный курс" in body
    assert "/admin/course_feedback/courseanalytics/salah/change/" in body
    assert "/admin/course_feedback/courseanalytics/tajweed/change/" in body
    assert f"/admin/course_feedback/courseanalytics/{live.pk}/change/" in body
    assert '<a href="/admin/salah/salahcourseversion/">Править</a>' in body
    assert '<a href="/admin/tajweed/tajweedcourseversion/">Править</a>' in body
    assert f'<a href="/admin/courses/course/{live.pk}/change/">Править</a>' in body
    assert '<a href="/admin/course_feedback/courseanalytics/">Полная сводка' in body
    # The usual list of the catalog stays below, with its search.
    assert 'id="changelist-search"' in body
    assert client.get("/admin/courses/course/?q=ramadan").status_code == 200


@pytest.mark.django_db
def test_courses_list_hides_the_numbers_without_the_analytics_permission(
    live: Course, builtin: None
) -> None:
    _builtin_stat("salah", "wudu", "lesson_opened", 6)
    staff = User.objects.create_user(email="editor@example.test", status="active", is_staff=True)
    staff.user_permissions.set(Permission.objects.filter(codename="view_course"))
    client = Client()
    client.force_login(staff)

    page = client.get("/admin/courses/course/")

    assert page.status_code == 200
    body = page.content.decode()
    assert "Обучение намазу" in body
    assert "Таджвид" in body
    assert "Открыли темы" not in body
    assert "courseanalytics" not in body
    # No link to the editors of the built-in courses this user may not open.
    assert "/admin/salah/" not in body
    assert "/admin/tajweed/" not in body
    assert "Имена Аллаха" in body
    assert "/admin/names/" not in body
    assert all("opened" not in row for row in page.context["all_courses"]["rows"])
