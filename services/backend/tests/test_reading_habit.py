from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from urllib.parse import urlencode

import pytest
from django.core.exceptions import ValidationError
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
    set_reading_goal,
)
from quran_backend.modules.reading.models import (
    GoalProgress,
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
    progress = GoalProgress.objects.get(goal=guest_goal)
    streak = ReadingStreak.objects.get(user=target)
    assert result.replayed is False
    assert replay.replayed is True
    assert result.moved_counts["reading_goals"] == 1
    assert result.moved_counts["reading_sessions"] == 1
    assert result.moved_counts["goal_progress"] == 1
    assert guest_goal.user_id == target.id
    assert guest_goal.status == ReadingGoalStatus.ACTIVE
    assert target_goal.status == ReadingGoalStatus.ARCHIVED
    assert guest_session.user_id == target.id
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
