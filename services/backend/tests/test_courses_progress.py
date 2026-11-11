# ruff: noqa: F811 - imported fixtures are used by name
from __future__ import annotations

from datetime import timedelta

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.lifecycle import _finalize_account
from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.courses.models import Course, LearnerProgress
from quran_backend.modules.salah.models import SalahCourse, SalahCourseVersion
from tests.test_courses import owner, ramadan, release_course  # noqa: F401 - fixtures by name


def _entry(status: str, step: str, at: str) -> dict[str, str]:
    return {"status": status, "step_slug": step, "content_version": "v1", "updated_at": at}


def _url(kind: str, course: str) -> str:
    return reverse("courses-progress", args=[kind, course])


def _account() -> User:
    return User.objects.create_user(
        email="learner@example.test", status=UserStatus.ACTIVE, timezone="UTC"
    )


@pytest.fixture
def live(ramadan: Course, owner: User) -> Course:
    release_course(ramadan, owner)
    ramadan.refresh_from_db()
    return ramadan


@pytest.fixture
def salah(owner: User) -> SalahCourse:
    course = SalahCourse.objects.create(slug="hanbali-umdah")
    course.active_version = SalahCourseVersion.objects.create(
        course=course,
        version="2026-11-01",
        schema_version=1,
        snapshot={"lessons": []},
        checksum_sha256="0" * 64,
        status="published",
        published_at=timezone.now(),
        reviewed_by=owner,
        reviewed_at=timezone.now(),
        methodology="hanbali",
    )
    course.save()
    return course


@pytest.mark.django_db
def test_progress_of_a_thematic_course_is_private_and_merged(
    live: Course, api_client: APIClient
) -> None:
    url = _url("courses", "ramadan")
    assert api_client.get(url).status_code in {401, 403}
    api_client.force_authenticate(_account())
    assert api_client.get(url).json() == {"kind": "courses", "course": "ramadan", "lessons": {}}

    # The lessons of a thematic course have no steps: step_slug is "".
    first = api_client.put(
        url,
        {"lessons": {"smysl-posta": _entry("completed", "", "2026-11-10T10:00:00+03:00")}},
        format="json",
    )
    assert first.status_code == 200
    assert first["Cache-Control"].startswith("private")
    assert first.json()["lessons"]["smysl-posta"]["updated_at"] == "2026-11-10T07:00:00.000Z"

    second = api_client.put(
        url,
        {
            "lessons": {
                "smysl-posta": _entry("in_progress", "", "2026-11-10T08:00:00.000Z"),
                "niyat": _entry("in_progress", "", "2026-11-10T09:00:00.000Z"),
            }
        },
        format="json",
    ).json()
    assert second["lessons"]["smysl-posta"]["status"] == "completed"
    assert second["lessons"]["niyat"]["status"] == "in_progress"
    assert api_client.get(url).json() == second
    assert LearnerProgress.objects.count() == 1

    for bad in (
        {"lessons": []},
        {"lessons": {"Bad!": _entry("completed", "", "2026-11-10T08:00:00Z")}},
        {"lessons": {"niyat": _entry("passed", "", "2026-11-10T08:00:00Z")}},
        {"lessons": {"niyat": _entry("completed", "", "2026-11-10T08:00:00")}},
    ):
        assert api_client.put(url, bad, format="json").status_code == 400


@pytest.mark.django_db
def test_progress_of_the_prayer_course_is_kept_apart(
    live: Course, salah: SalahCourse, api_client: APIClient
) -> None:
    api_client.force_authenticate(_account())
    saved = api_client.put(
        _url("salah", "hanbali-umdah"),
        {"lessons": {"fajr": _entry("in_progress", "fajr.r1.ruku", "2026-11-10T08:00:00Z")}},
        format="json",
    )
    assert saved.status_code == 200
    assert saved.json()["kind"] == "salah"
    assert saved.json()["lessons"]["fajr"]["step_slug"] == "fajr.r1.ruku"
    assert api_client.get(_url("courses", "ramadan")).json()["lessons"] == {}


@pytest.mark.django_db
def test_progress_needs_a_known_course(
    ramadan: Course, salah: SalahCourse, api_client: APIClient
) -> None:
    api_client.force_authenticate(_account())
    body = {"lessons": {"a": _entry("completed", "", "2026-11-10T08:00:00Z")}}
    # A course that was never published, an unknown one, an unknown kind,
    # and the tajweed course, which keeps its own address.
    for kind, course in (
        ("courses", "ramadan"),
        ("courses", "nope"),
        ("salah", "nope"),
        ("quiz", "ramadan"),
        ("tajweed", "tajweed"),
    ):
        assert api_client.get(_url(kind, course)).status_code == 404
        assert api_client.put(_url(kind, course), body, format="json").status_code == 404
    assert not LearnerProgress.objects.exists()


@pytest.mark.django_db
def test_a_guest_keeps_progress_on_the_device(live: Course, api_client: APIClient) -> None:
    api_client.force_authenticate(User.objects.create_user(status=UserStatus.GUEST))
    url = _url("courses", "ramadan")
    body = {"lessons": {"niyat": _entry("completed", "", "2026-11-10T08:00:00Z")}}

    assert api_client.get(url).status_code == 403
    refused = api_client.put(url, body, format="json")
    assert refused.status_code == 403
    assert "account_required" in str(refused.json())
    assert not LearnerProgress.objects.exists()


@pytest.mark.django_db
def test_progress_is_deleted_with_the_account(live: Course) -> None:
    learner = _account()
    other = User.objects.create_user(email="other@example.test", status=UserStatus.ACTIVE)
    for user in (learner, other):
        LearnerProgress.objects.create(
            user=user,
            kind="courses",
            course="ramadan",
            lessons={"niyat": _entry("completed", "", "2026-11-10T08:00:00.000Z")},
        )

    _finalize_account(user=learner, deleted_at=timezone.now() + timedelta(days=30))

    assert list(LearnerProgress.objects.values_list("user_id", flat=True)) == [other.pk]
