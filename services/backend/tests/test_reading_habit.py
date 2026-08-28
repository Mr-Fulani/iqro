from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from urllib.parse import urlencode

import pytest
from django.core.exceptions import ValidationError
from django.db.models import QuerySet
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Device,
    DevicePlatform,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.reading.habit_services import (
    record_manual_session,
    record_prayer_reading_check_in,
    set_prayer_reading_plan,
    set_reading_goal,
)
from quran_backend.modules.reading.models import (
    GoalProgress,
    PrayerReadingCheckIn,
    PrayerReadingPlan,
    ReadingGoal,
    ReadingGoalMetric,
    ReadingGoalStatus,
    ReadingSession,
    ReadingStreak,
)

pytestmark = pytest.mark.django_db


def _authenticated_client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _goal_payload(*, metric: str, amount: str, base_revision: int = 0) -> dict[str, object]:
    return {
        "metric": metric,
        "target_amount": amount,
        "timezone_name": "UTC",
        "base_revision": base_revision,
        "client_updated_at": timezone.now().isoformat(),
    }


def test_goal_model_rejects_fractional_page_target_and_invalid_timezone() -> None:
    user = User.objects.create_user()
    goal = ReadingGoal(
        user=user,
        metric=ReadingGoalMetric.PAGES,
        target_amount=Decimal("1.50"),
        timezone_name="UTC",
        started_on=timezone.now().date(),
        client_updated_at=timezone.now(),
    )

    with pytest.raises(ValidationError, match="whole numbers"):
        goal.full_clean()

    goal.metric = ReadingGoalMetric.MINUTES
    goal.target_amount = Decimal("5")
    goal.timezone_name = "Mars/Olympus"
    with pytest.raises(ValidationError, match="IANA timezone"):
        goal.full_clean()


def test_automatic_session_completes_goal_and_is_idempotent() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    goal_response = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="minutes", amount="2"),
        format="json",
    )
    goal_id = goal_response.json()["id"]
    now = timezone.now()
    session_id = uuid.uuid7()
    payload = {
        "id": str(session_id),
        "timezone_name": "UTC",
        "started_at": (now - timedelta(minutes=2)).isoformat(),
        "ended_at": now.isoformat(),
        "active_seconds": 120,
        "credited_pages": 1,
        "credited_ayahs": 2,
        "client_updated_at": now.isoformat(),
    }

    created = client.post(
        reverse("reading:reading-session-automatic"),
        payload,
        format="json",
    )
    replayed = client.post(
        reverse("reading:reading-session-automatic"),
        payload,
        format="json",
    )
    today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})

    assert goal_response.status_code == 201
    assert created.status_code == 201
    assert replayed.status_code == 200
    assert created.json()["goal_id"] == goal_id
    assert ReadingSession.objects.filter(id=session_id).count() == 1
    assert GoalProgress.objects.get(goal_id=goal_id).achieved_amount == Decimal("2.00")
    assert today.status_code == 200
    assert today.headers["Cache-Control"] == "private, no-store, max-age=0"
    assert today.json()["progress"] == {
        "goal_id": goal_id,
        "local_date": timezone.now().date().isoformat(),
        "metric": "minutes",
        "target_amount": "2.00",
        "achieved_amount": "2.00",
        "remaining_amount": "0.00",
        "is_completed": True,
        "completed_at": today.json()["progress"]["completed_at"],
    }
    assert today.json()["progress"]["completed_at"] is not None
    assert today.json()["streak"]["current_count"] == 1
    assert today.json()["streak"]["longest_count"] == 1


def test_manual_session_update_and_delete_recalculate_progress_and_streak() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    goal = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="pages", amount="2"),
        format="json",
    ).json()
    session_id = uuid.uuid7()
    today = timezone.now().date().isoformat()
    created = client.post(
        reverse("reading:reading-session-manual"),
        {
            "id": str(session_id),
            "timezone_name": "UTC",
            "local_date": today,
            "metric": "pages",
            "amount": "1",
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    partial_today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})
    updated = client.patch(
        reverse("reading:reading-session-detail", kwargs={"session_id": session_id}),
        {
            "base_revision": 1,
            "timezone_name": "UTC",
            "local_date": today,
            "metric": "pages",
            "amount": "2",
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    completed_today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})
    delete_url = reverse(
        "reading:reading-session-detail",
        kwargs={"session_id": session_id},
    )
    deleted = client.delete(
        f"{delete_url}?{
            urlencode(
                {
                    'base_revision': 2,
                    'client_updated_at': timezone.now().isoformat(),
                }
            )
        }"
    )
    recalculated_today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})
    history = client.get(reverse("reading:reading-session-list"))

    assert created.status_code == 201
    assert partial_today.json()["progress"]["is_completed"] is False
    assert partial_today.json()["streak"]["current_count"] == 1
    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert completed_today.json()["progress"]["is_completed"] is True
    assert completed_today.json()["progress"]["achieved_amount"] == "2.00"
    assert deleted.status_code == 200
    assert deleted.json()["status"] == "discarded"
    assert recalculated_today.json()["progress"]["is_completed"] is False
    assert recalculated_today.json()["progress"]["achieved_amount"] == "0.00"
    assert recalculated_today.json()["streak"]["current_count"] == 0
    assert recalculated_today.json()["streak"]["longest_count"] == 0
    assert history.json()["results"] == []
    assert GoalProgress.objects.filter(goal_id=goal["id"]).exists() is False


def test_planner_history_distinguishes_missed_partial_and_completed_days() -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _authenticated_client(user)
    local_today = timezone.now().date()
    goal_response = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="minutes", amount="2"),
        format="json",
    )
    goal_id = goal_response.json()["id"]
    ReadingGoal.objects.filter(id=goal_id).update(started_on=local_today - timedelta(days=2))

    for local_date, amount in (
        (local_today - timedelta(days=3), "1"),
        (local_today - timedelta(days=1), "1"),
        (local_today, "3"),
    ):
        response = client.post(
            reverse("reading:reading-session-manual"),
            {
                "id": str(uuid.uuid7()),
                "timezone_name": "UTC",
                "local_date": local_date.isoformat(),
                "metric": "minutes",
                "amount": amount,
                "client_updated_at": timezone.now().isoformat(),
            },
            format="json",
        )
        assert response.status_code == 201

    plan, _created = set_prayer_reading_plan(
        user=user,
        pages_per_prayer=2,
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=timezone.now(),
    )
    check_in, _created = record_prayer_reading_check_in(
        user=user,
        check_in_id=uuid.uuid7(),
        session_id=uuid.uuid7(),
        prayer="fajr",
        pages=3,
        local_date=local_today - timedelta(days=1),
        timezone_name="UTC",
        client_updated_at=timezone.now(),
    )

    planner = client.get(
        reverse("reading:reading-planner"),
        {"days": 3, "timezone_name": "UTC"},
    )

    assert planner.status_code == 400
    assert planner.json()["field_errors"]["days"] == [
        "Ensure this value is greater than or equal to 7."
    ]

    planner = client.get(
        reverse("reading:reading-planner"),
        {"days": 7, "timezone_name": "UTC"},
    )
    days_by_date = {day["local_date"]: day for day in planner.json()["days"]}
    without_goal = days_by_date[(local_today - timedelta(days=3)).isoformat()]
    missed = days_by_date[(local_today - timedelta(days=2)).isoformat()]
    partial = days_by_date[(local_today - timedelta(days=1)).isoformat()]
    completed = days_by_date[local_today.isoformat()]

    assert planner.status_code == 200
    assert planner.headers["Cache-Control"] == "private, no-store, max-age=0"
    assert planner.json()["timezone_name"] == "UTC"
    assert len(planner.json()["days"]) == 7
    assert without_goal["state"] == "no_goal"
    assert without_goal["has_reading"] is True
    assert without_goal["goal"] is None
    assert missed["state"] == "missed"
    assert missed["has_reading"] is False
    assert missed["goal"]["achieved_amount"] == "0.00"
    assert partial["state"] == "partial"
    assert partial["has_reading"] is True
    assert partial["goal"]["achieved_amount"] == "1.00"
    assert partial["prayer_pages"] == 3
    assert partial["prayer_count"] == 1
    assert partial["prayer_check_ins"][0]["id"] == str(check_in.id)
    assert partial["automatic_sessions"] == 0
    assert partial["automatic_active_seconds"] == 0
    assert completed["state"] == "completed"
    assert completed["has_reading"] is True
    assert completed["goal"]["achieved_amount"] == "3.00"
    assert completed["goal"]["remaining_amount"] == "0.00"
    assert PrayerReadingPlan.objects.get(id=plan.id).pages_per_prayer == 2

    linked_session_update = client.patch(
        reverse(
            "reading:reading-session-detail",
            kwargs={"session_id": check_in.reading_session_id},
        ),
        {
            "timezone_name": "UTC",
            "local_date": (local_today - timedelta(days=1)).isoformat(),
            "metric": "pages",
            "amount": 4,
            "base_revision": check_in.reading_session.revision,
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    assert linked_session_update.status_code == 409
    assert linked_session_update.json()["code"] == "reading_session_immutable"

    linked_session_delete = client.delete(
        f"{
            reverse(
                'reading:reading-session-detail',
                kwargs={'session_id': check_in.reading_session_id},
            )
        }?{
            urlencode(
                {
                    'base_revision': check_in.reading_session.revision,
                    'client_updated_at': timezone.now().isoformat(),
                }
            )
        }"
    )
    assert linked_session_delete.status_code == 409
    assert linked_session_delete.json()["code"] == "reading_session_immutable"


def test_manual_session_idempotency_lookup_locks_only_the_session_table(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """PostgreSQL rejects FOR UPDATE on nullable LEFT JOIN relations."""
    user = User.objects.create_user()
    client = _authenticated_client(user)
    select_for_update = QuerySet.select_for_update
    reading_session_locks: list[dict[str, object]] = []

    def capture_lock(
        queryset: QuerySet[object],
        *args: object,
        **kwargs: object,
    ) -> QuerySet[object]:
        if queryset.model is ReadingSession:
            reading_session_locks.append(dict(kwargs))
        return select_for_update(queryset, *args, **kwargs)

    monkeypatch.setattr(QuerySet, "select_for_update", capture_lock)
    response = client.post(
        reverse("reading:reading-session-manual"),
        {
            "id": str(uuid.uuid7()),
            "timezone_name": "UTC",
            "local_date": timezone.now().date().isoformat(),
            "metric": "pages",
            "amount": "1",
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )

    assert response.status_code == 201
    assert {"of": ("self",)} in reading_session_locks


def test_goal_revision_and_manual_date_validation_are_fail_closed() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    created = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="ayahs", amount="3"),
        format="json",
    )
    stale = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="ayahs", amount="4", base_revision=0),
        format="json",
    )
    future = client.post(
        reverse("reading:reading-session-manual"),
        {
            "id": str(uuid.uuid7()),
            "timezone_name": "UTC",
            "local_date": (timezone.now().date() + timedelta(days=1)).isoformat(),
            "metric": "ayahs",
            "amount": "1",
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )

    assert created.status_code == 201
    assert stale.status_code == 409
    assert stale.json()["code"] == "reading_goal_revision_conflict"
    assert future.status_code == 400
    assert future.json()["field_errors"]["local_date"] == "Future reading cannot be recorded."


def test_prayer_reading_plan_check_ins_are_flexible_idempotent_and_reversible() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    today = timezone.now().date().isoformat()
    goal = client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric="pages", amount="10"),
        format="json",
    )
    empty = client.get(
        reverse("reading:prayer-reading-plan"),
        {"timezone_name": "UTC"},
    )
    plan = client.put(
        reverse("reading:prayer-reading-plan"),
        {
            "pages_per_prayer": 2,
            "notifications_enabled": False,
            "timezone_name": "UTC",
            "base_revision": 0,
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    check_in_id = uuid.uuid7()
    session_id = uuid.uuid7()
    payload = {
        "id": str(check_in_id),
        "session_id": str(session_id),
        "prayer": "fajr",
        "pages": 1,
        "local_date": today,
        "timezone_name": "UTC",
        "client_updated_at": timezone.now().isoformat(),
    }
    checked = client.post(
        reverse("reading:prayer-reading-check-in-create"),
        payload,
        format="json",
    )
    duplicate_slot = client.post(
        reverse("reading:prayer-reading-check-in-create"),
        {**payload, "id": str(uuid.uuid7()), "session_id": str(uuid.uuid7())},
        format="json",
    )
    detail_url = reverse(
        "reading:prayer-reading-check-in-detail",
        kwargs={"check_in_id": check_in_id},
    )
    updated = client.patch(
        detail_url,
        {
            "pages": 3,
            "base_revision": 1,
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    day = client.get(reverse("reading:prayer-reading-plan"))
    reading_today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})
    removed = client.delete(
        f"{detail_url}?{
            urlencode(
                {
                    'base_revision': 2,
                    'client_updated_at': timezone.now().isoformat(),
                }
            )
        }"
    )
    after_delete = client.get(reverse("reading:prayer-reading-plan"))

    assert goal.status_code == 201
    assert empty.status_code == 200
    assert empty.json()["plan"] is None
    assert plan.status_code == 201
    assert plan.json()["pages_per_prayer"] == 2
    assert plan.json()["notifications_enabled"] is False
    assert checked.status_code == 201
    assert checked.json()["pages"] == 1
    assert duplicate_slot.status_code == 200
    assert duplicate_slot.json()["id"] == str(check_in_id)
    assert updated.status_code == 200
    assert updated.json()["pages"] == 3
    assert updated.json()["revision"] == 2
    assert ReadingSession.objects.filter(id=session_id).count() == 1
    assert day.json()["achieved_pages"] == 3
    assert day.json()["target_pages"] == 10
    assert day.json()["remaining_pages"] == 7
    assert [item["prayer"] for item in day.json()["check_ins"]] == ["fajr"]
    assert reading_today.json()["progress"]["achieved_amount"] == "3.00"
    assert removed.status_code == 204
    assert after_delete.json()["achieved_pages"] == 0
    assert after_delete.json()["check_ins"] == []
    assert PrayerReadingCheckIn.objects.filter(id=check_in_id).exists() is False
    assert ReadingSession.objects.get(id=session_id).status == "discarded"


@pytest.mark.parametrize(
    ("metric", "expected_amount"),
    [
        (ReadingGoalMetric.PAGES, "3.00"),
        (ReadingGoalMetric.MINUTES, "2.00"),
    ],
)
def test_guided_prayer_reading_keeps_page_and_time_progress_independent(
    metric: str,
    expected_amount: str,
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    now = timezone.now()
    client.put(
        reverse("reading:reading-goal"),
        _goal_payload(metric=metric, amount="10"),
        format="json",
    )
    client.put(
        reverse("reading:prayer-reading-plan"),
        {
            "pages_per_prayer": 4,
            "timezone_name": "UTC",
            "base_revision": 0,
            "client_updated_at": now.isoformat(),
        },
        format="json",
    )
    check_in = client.post(
        reverse("reading:prayer-reading-check-in-create"),
        {
            "id": str(uuid.uuid7()),
            "session_id": str(uuid.uuid7()),
            "prayer": "fajr",
            "pages": 3,
            "local_date": now.date().isoformat(),
            "timezone_name": "UTC",
            "client_updated_at": now.isoformat(),
        },
        format="json",
    )
    timed_session = client.post(
        reverse("reading:reading-session-automatic"),
        {
            "id": str(uuid.uuid7()),
            "timezone_name": "UTC",
            "started_at": (now - timedelta(minutes=2)).isoformat(),
            "ended_at": now.isoformat(),
            "active_seconds": 120,
            "credited_pages": 0,
            "credited_ayahs": 0,
            "client_updated_at": now.isoformat(),
        },
        format="json",
    )
    reading_today = client.get(reverse("reading:today"), {"timezone_name": "UTC"})

    assert check_in.status_code == 201
    assert timed_session.status_code == 201
    assert reading_today.status_code == 200
    assert reading_today.json()["progress"]["achieved_amount"] == expected_amount


def test_prayer_reading_plan_rejects_invalid_pages_and_mismatched_timezone() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    invalid = client.put(
        reverse("reading:prayer-reading-plan"),
        {
            "pages_per_prayer": 21,
            "timezone_name": "UTC",
            "base_revision": 0,
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )
    plan, _created = set_prayer_reading_plan(
        user=user,
        pages_per_prayer=2,
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=timezone.now(),
    )
    mismatch = client.post(
        reverse("reading:prayer-reading-check-in-create"),
        {
            "id": str(uuid.uuid7()),
            "session_id": str(uuid.uuid7()),
            "prayer": "isha",
            "local_date": timezone.now().date().isoformat(),
            "timezone_name": "Europe/Istanbul",
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )

    assert invalid.status_code == 400
    assert plan.pages_per_prayer == 2
    assert mismatch.status_code == 400
    assert mismatch.json()["field_errors"]["timezone_name"] == (
        "Timezone must match the active prayer reading plan."
    )


def test_guest_merge_keeps_newer_goal_sessions_progress_and_is_idempotent() -> None:
    now = timezone.now()
    guest = User.objects.create_user()
    target = User.objects.create_user(
        email="reader@example.com",
        status=UserStatus.ACTIVE,
    )
    guest_device = Device.objects.create(
        user=guest,
        platform=DevicePlatform.WEB,
        installation_id_hash="a" * 64,
    )
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="reader@example.com",
        email_at_provider="reader@example.com",
        email_verified=True,
    )
    target_goal, _created = set_reading_goal(
        user=target,
        metric=ReadingGoalMetric.MINUTES,
        target_amount=Decimal("10"),
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=now - timedelta(hours=1),
        device_id=None,
    )
    guest_goal, _created = set_reading_goal(
        user=guest,
        metric=ReadingGoalMetric.MINUTES,
        target_amount=Decimal("5"),
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=now,
        device_id=guest_device.id,
    )
    guest_session, _created = record_manual_session(
        user=guest,
        session_id=uuid.uuid7(),
        timezone_name="UTC",
        local_date=now.date(),
        metric=ReadingGoalMetric.MINUTES,
        amount=Decimal("5"),
        client_updated_at=now,
        device_id=guest_device.id,
    )
    guest_prayer_plan, _created = set_prayer_reading_plan(
        user=guest,
        pages_per_prayer=2,
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=now,
        device_id=guest_device.id,
    )
    guest_prayer_check_in, _created = record_prayer_reading_check_in(
        user=guest,
        check_in_id=uuid.uuid7(),
        session_id=uuid.uuid7(),
        prayer="fajr",
        local_date=now.date(),
        timezone_name="UTC",
        client_updated_at=now,
        device_id=guest_device.id,
    )
    idempotency_key = uuid.uuid4()

    result = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=idempotency_key,
    )
    replay = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=idempotency_key,
    )

    guest_goal.refresh_from_db()
    target_goal.refresh_from_db()
    guest_session.refresh_from_db()
    guest_prayer_plan.refresh_from_db()
    guest_prayer_check_in.refresh_from_db()
    progress = GoalProgress.objects.get(goal=guest_goal)
    streak = ReadingStreak.objects.get(user=target)
    assert result.replayed is False
    assert replay.replayed is True
    assert result.moved_counts["reading_goals"] == 1
    assert result.moved_counts["reading_sessions"] == 2
    assert result.moved_counts["prayer_reading_plans"] == 1
    assert result.moved_counts["prayer_reading_check_ins"] == 1
    assert result.moved_counts["goal_progress"] == 1
    assert guest_goal.user_id == target.id
    assert guest_goal.status == ReadingGoalStatus.ACTIVE
    assert target_goal.status == ReadingGoalStatus.ARCHIVED
    assert guest_session.user_id == target.id
    assert guest_prayer_plan.user_id == target.id
    assert guest_prayer_check_in.user_id == target.id
    assert PrayerReadingPlan.objects.filter(user=target).count() == 1
    assert guest_session.device_id == guest_device.id
    assert progress.user_id == target.id
    assert progress.completed_at is not None
    assert streak.current_count == 1
    assert (
        ReadingGoal.objects.filter(
            user=target,
            status=ReadingGoalStatus.ACTIVE,
        ).count()
        == 1
    )
