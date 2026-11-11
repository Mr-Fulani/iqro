# Russian operator strings are asserted verbatim.
# ruff: noqa: F811 - imported fixtures are used by name
from __future__ import annotations

from typing import Any

import pytest
from django.contrib.auth.models import Group, Permission
from django.test import Client
from django.utils import timezone

from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.courses.learners import learners, user_learning
from quran_backend.modules.courses.models import Course, LearnerProgress
from quran_backend.modules.tajweed.models import (
    TajweedCourse,
    TajweedCourseProgress,
    TajweedCourseVersion,
    TajweedPracticeSession,
)
from tests.test_courses import owner, ramadan, release_course  # noqa: F401 - fixtures by name

LEARNERS = "/admin/courses/learnerprogress/"


def _entry(status: str, at: str) -> dict[str, str]:
    return {"status": status, "step_slug": "", "content_version": "1", "updated_at": at}


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


@pytest.fixture
def studied(ramadan: Course, owner: User) -> dict[str, User]:
    """Aisha studies «Рамадан» and tajweed, Bilal only tajweed; a guest has tajweed too."""
    release_course(ramadan, owner)
    course = TajweedCourse.objects.create(slug="tajweed")
    course.active_version = TajweedCourseVersion.objects.create(
        course=course,
        version="2026-11-01",
        schema_version=1,
        snapshot={
            "lessons": [
                {"slug": slug, "title": {"ru": f"Урок {slug}"}} for slug in ("izhar", "iqlab")
            ]
        },
        checksum_sha256="0" * 64,
        status="published",
        published_at=timezone.now(),
        reviewed_by=owner,
        reviewed_at=timezone.now(),
    )
    course.save()
    aisha = User.objects.create_user(email="aisha@example.test", status=UserStatus.ACTIVE)
    bilal = User.objects.create_user(email="bilal@example.test", status=UserStatus.ACTIVE)
    guest = User.objects.create_user(status=UserStatus.GUEST)
    LearnerProgress.objects.create(
        user=aisha,
        kind="courses",
        course="ramadan",
        lessons={
            "smysl-posta": _entry("completed", "2026-11-10T08:00:00.000Z"),
            "namerenie": _entry("in_progress", "2026-11-11T09:30:00.000Z"),
            # A lesson gone from the course is not counted.
            "old-lesson": _entry("completed", "2026-11-01T08:00:00.000Z"),
        },
    )
    for user, lessons in (
        (aisha, {"izhar": _entry("completed", "2026-11-09T08:00:00.000Z")}),
        (bilal, {"izhar": _entry("completed", "2026-11-12T08:00:00.000Z")}),
        (guest, {"izhar": _entry("completed", "2026-11-12T10:00:00.000Z")}),
    ):
        TajweedCourseProgress.objects.create(user=user, course="tajweed", lessons=lessons)
    TajweedPracticeSession.objects.create(
        user=aisha,
        course="tajweed",
        local_date="2026-11-11",
        finished_at=timezone.now(),
        answers=[
            {
                "key": f"izhar:{index}",
                "target": "izhar",
                "type": "find",
                "correct": index < 3,
                "at": "2026-11-11T09:00:00.000Z",
            }
            for index in range(4)
        ],
    )
    return {"aisha": aisha, "bilal": bilal, "guest": guest}


def _summary(rows: list[dict[str, Any]]) -> list[tuple[str, str, int, int, int]]:
    return [
        (row["user"].email, row["title"], row["completed"], row["started"], row["total"])
        for row in rows
    ]


@pytest.mark.django_db
def test_learners_lists_registered_accounts_latest_first(studied: dict[str, User]) -> None:
    report = learners()

    # The guest is not listed; the latest lesson comes first.
    assert _summary(report["rows"]) == [
        ("bilal@example.test", "Таджвид", 1, 1, 2),
        ("aisha@example.test", "Рамадан", 1, 2, 3),
        ("aisha@example.test", "Таджвид", 1, 1, 2),
    ]
    assert report["total"] == 3
    assert report["options"] == [
        ("salah", "Обучение намазу"),
        ("tajweed", "Таджвид"),
        ("ramadan", "Рамадан"),
    ]
    assert [row["user"].email for row in learners("tajweed")["rows"]] == [
        "bilal@example.test",
        "aisha@example.test",
    ]
    assert _summary(learners("ramadan")["rows"]) == [("aisha@example.test", "Рамадан", 1, 2, 3)]
    assert learners("salah")["rows"] == []
    assert _summary(learners(query="BILAL")["rows"]) == [("bilal@example.test", "Таджвид", 1, 1, 2)]


@pytest.mark.django_db
def test_user_learning_has_courses_and_tajweed_practice(studied: dict[str, User]) -> None:
    learning = user_learning(studied["aisha"])

    assert [(row["title"], row["completed"], row["total"]) for row in learning["rows"]] == [
        ("Рамадан", 1, 3),
        ("Таджвид", 1, 2),
    ]
    assert [
        (item["sessions"], item["correct"], item["answers"]) for item in learning["practice"]
    ] == [(1, 3, 4)]
    assert user_learning(studied["bilal"])["practice"] == []


@pytest.mark.django_db
def test_admin_shows_learners_and_the_users_learning(studied: dict[str, User], owner: User) -> None:
    client = _client(owner)

    page = client.get(LEARNERS)
    assert page.status_code == 200
    body = page.content.decode()
    assert "Ученики курсов" in body
    assert "aisha@example.test" in body
    assert "1 из 3" in body
    assert f'href="/admin/accounts/user/{studied["aisha"].pk}/change/"' in body
    assert client.get(f"{LEARNERS}?course=tajweed&q=bilal").status_code == 200
    assert "Пока никого" in client.get(f"{LEARNERS}?course=salah").content.decode()

    card = client.get(f"/admin/accounts/user/{studied['aisha'].pk}/change/").content.decode()
    assert "Обучение" in card
    assert "Рамадан" in card
    assert "Тренировки таджвида: занятий — 1, верных ответов — 3 из 4" in card
    guest_card = client.get(f"/admin/accounts/user/{studied['guest'].pk}/change/")
    assert "Таджвид" in guest_card.content.decode()

    # The home page lists it next to the courses, and a course's statistics link to it.
    assert LEARNERS in client.get("/admin/").content.decode()
    analytics = client.get("/admin/course_feedback/courseanalytics/tajweed/change/")
    assert f'href="{LEARNERS}?course=tajweed"' in analytics.content.decode()


@pytest.mark.django_db
def test_learners_need_their_own_permission(studied: dict[str, User]) -> None:
    staff = User.objects.create_user(email="staff@example.test", status="active", is_staff=True)
    staff.user_permissions.set(
        Permission.objects.filter(codename__in=("view_user", "view_course", "view_courseanalytics"))
    )
    client = _client(staff)

    assert client.get(LEARNERS).status_code == 403
    card = client.get(f"/admin/accounts/user/{studied['aisha'].pk}/change/")
    assert card.status_code == 200
    assert "Тренировки таджвида" not in card.content.decode()
    analytics = client.get("/admin/course_feedback/courseanalytics/tajweed/change/")
    assert "learnerprogress" not in analytics.content.decode()
    assert "learnerprogress" not in client.get("/admin/").content.decode()

    staff.user_permissions.add(Permission.objects.get(codename="view_learnerprogress"))
    client = _client(User.objects.get(pk=staff.pk))
    assert client.get(LEARNERS).status_code == 200
    card = client.get(f"/admin/accounts/user/{studied['aisha'].pk}/change/")
    assert "Тренировки таджвида" in card.content.decode()
    # Read only: nothing to add, change or delete.
    assert client.get(f"{LEARNERS}add/").status_code == 403


@pytest.mark.django_db
def test_course_editors_do_not_see_learners_by_default() -> None:
    for name in ("Редактор курсов", "Публикатор"):
        group = Group.objects.get(name=name)
        assert not group.permissions.filter(codename="view_learnerprogress").exists()
