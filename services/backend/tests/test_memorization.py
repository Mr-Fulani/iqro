from __future__ import annotations

import uuid

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.memorization.models import MemorizationPlan, MemorizationSession
from quran_backend.modules.memorization.services import (
    record_memorization_session,
    set_memorization_plan,
)

pytestmark = pytest.mark.django_db


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _plan_payload(quran_dataset: dict[str, object], *, base_revision: int = 0) -> dict[str, object]:
    return {
        "start_ayah_id": str(quran_dataset["first_ayah"].id),
        "end_ayah_id": str(quran_dataset["second_ayah"].id),
        "recitation_id": None,
        "daily_repetitions": 5,
        "pause_seconds": 2,
        "timezone_name": "UTC",
        "base_revision": base_revision,
        "client_updated_at": timezone.now().isoformat(),
    }


def test_memorization_dashboard_is_private_and_no_store(quran_dataset: dict[str, object]) -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _client(user)

    empty = client.get(reverse("memorization:dashboard"), {"timezone_name": "UTC"})
    created = client.put(
        reverse("memorization:dashboard"),
        _plan_payload(quran_dataset),
        format="json",
    )
    dashboard = client.get(reverse("memorization:dashboard"))
    anonymous = APIClient().get(reverse("memorization:dashboard"))

    assert empty.status_code == 200
    assert empty.json()["plan"] is None
    assert empty.headers["Cache-Control"] == "private, no-store, max-age=0"
    assert created.status_code == 201
    assert created.json()["start_ayah"]["ayah_number"] == 1
    assert created.json()["end_ayah"]["ayah_number"] == 2
    assert created.json()["revision"] == 1
    assert dashboard.json()["today"]["target_repetitions"] == 5
    assert dashboard.json()["today"]["completed_repetitions"] == 0
    assert anonymous.status_code in {401, 403}


def test_plan_update_requires_current_revision_and_valid_range(
    quran_dataset: dict[str, object],
) -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _client(user)
    created = client.put(
        reverse("memorization:dashboard"),
        _plan_payload(quran_dataset),
        format="json",
    )
    update_payload = _plan_payload(quran_dataset, base_revision=created.json()["revision"])
    update_payload["daily_repetitions"] = 8
    updated = client.put(reverse("memorization:dashboard"), update_payload, format="json")
    stale = client.put(reverse("memorization:dashboard"), update_payload, format="json")
    reversed_range = _plan_payload(quran_dataset, base_revision=updated.json()["revision"])
    reversed_range["start_ayah_id"] = str(quran_dataset["second_ayah"].id)
    reversed_range["end_ayah_id"] = str(quran_dataset["first_ayah"].id)
    invalid = client.put(reverse("memorization:dashboard"), reversed_range, format="json")

    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert updated.json()["daily_repetitions"] == 8
    assert stale.status_code == 409
    assert invalid.status_code == 400
    assert MemorizationPlan.objects.get(user=user).daily_repetitions == 8


def test_session_is_idempotent_and_updates_today_progress(
    quran_dataset: dict[str, object],
) -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _client(user)
    plan = client.put(
        reverse("memorization:dashboard"),
        _plan_payload(quran_dataset),
        format="json",
    ).json()
    session_id = uuid.uuid7()
    session_payload = {
        "id": str(session_id),
        "plan_id": plan["id"],
        "completed_repetitions": 3,
        "assessment": "repeat",
        "duration_seconds": 90,
        "timezone_name": "UTC",
        "local_date": timezone.now().date().isoformat(),
        "client_updated_at": timezone.now().isoformat(),
    }

    created = client.post(reverse("memorization:session-create"), session_payload, format="json")
    replayed = client.post(reverse("memorization:session-create"), session_payload, format="json")
    dashboard = client.get(reverse("memorization:dashboard"))

    assert created.status_code == 201
    assert replayed.status_code == 200
    assert MemorizationSession.objects.filter(id=session_id).count() == 1
    assert dashboard.json()["today"]["completed_repetitions"] == 3
    assert dashboard.json()["today"]["remaining_repetitions"] == 2
    assert dashboard.json()["today"]["last_assessment"] == "repeat"
    assert dashboard.json()["recent_days"][0]["session_count"] == 1


def test_session_cannot_use_another_users_plan(quran_dataset: dict[str, object]) -> None:
    owner = User.objects.create_user(timezone="UTC")
    stranger = User.objects.create_user(timezone="UTC")
    plan = (
        _client(owner)
        .put(
            reverse("memorization:dashboard"),
            _plan_payload(quran_dataset),
            format="json",
        )
        .json()
    )

    response = _client(stranger).post(
        reverse("memorization:session-create"),
        {
            "id": str(uuid.uuid7()),
            "plan_id": plan["id"],
            "completed_repetitions": 1,
            "assessment": "difficult",
            "duration_seconds": 10,
            "timezone_name": "UTC",
            "local_date": timezone.now().date().isoformat(),
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )

    assert response.status_code == 404


def test_memorization_requests_reject_unknown_fields(quran_dataset: dict[str, object]) -> None:
    user = User.objects.create_user(timezone="UTC")
    payload = _plan_payload(quran_dataset)
    payload["unexpected"] = True

    response = _client(user).put(reverse("memorization:dashboard"), payload, format="json")

    assert response.status_code == 400
    assert response.json()["field_errors"]["unexpected"] == ["Unknown field."]


def test_guest_memorization_plan_and_history_merge_into_verified_account(
    quran_dataset: dict[str, object],
) -> None:
    now = timezone.now()
    guest = User.objects.create_user(timezone="UTC")
    target = User.objects.create_user(
        email="memorizer@example.com",
        status=UserStatus.ACTIVE,
        timezone="UTC",
    )
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="memorizer@example.com",
        email_at_provider="memorizer@example.com",
        email_verified=True,
    )
    plan, _created = set_memorization_plan(
        user=guest,
        start_ayah_id=quran_dataset["first_ayah"].id,
        end_ayah_id=quran_dataset["second_ayah"].id,
        recitation_id=None,
        daily_repetitions=5,
        pause_seconds=2,
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=now,
    )
    session, _created = record_memorization_session(
        user=guest,
        session_id=uuid.uuid7(),
        plan_id=plan.id,
        completed_repetitions=2,
        assessment="repeat",
        duration_seconds=60,
        timezone_name="UTC",
        local_date=now.date(),
        client_updated_at=now,
    )

    result = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=uuid.uuid4(),
    )

    plan.refresh_from_db()
    session.refresh_from_db()
    assert result.moved_counts["memorization_plans"] == 1
    assert result.moved_counts["memorization_sessions"] == 1
    assert plan.user_id == target.id
    assert session.user_id == target.id
    assert session.plan_id == plan.id
