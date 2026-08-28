from __future__ import annotations

import re
import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

import pytest
from django.core import mail
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts import services as account_services
from quran_backend.modules.accounts.lifecycle import finalize_due_account_deletions
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Consent,
    ConsentPurpose,
    Device,
    IdentityProvider,
    RefreshSession,
    User,
    UserStatus,
)
from quran_backend.modules.reading.habit_services import record_manual_session, set_reading_goal
from quran_backend.modules.reading.models import (
    Bookmark,
    GoalProgress,
    ReadingGoal,
    ReadingGoalMetric,
    ReadingSession,
    ReadingStreak,
)

pytestmark = pytest.mark.django_db

INSTALLATION_CREDENTIAL = "A" * 43


def _active_session(
    *,
    email: str = "reader@example.com",
    installation_hash: str = "a" * 64,
) -> tuple[User, Device, dict[str, str]]:
    user = User.objects.create_user(email=email, status=UserStatus.ACTIVE, preferred_locale="ru")
    AuthIdentity.objects.create(
        user=user,
        provider=IdentityProvider.EMAIL,
        provider_subject=email,
        email_at_provider=email,
        email_verified=True,
    )
    device = Device.objects.create(
        user=user,
        platform="web",
        installation_id_hash=installation_hash,
        installation_credential_hash=account_services.hash_installation_credential(
            INSTALLATION_CREDENTIAL
        ),
        bootstrap_generation=1,
        app_version="1.0.0",
        locale="ru",
    )
    now = timezone.now()
    session = RefreshSession.objects.create(
        user=user,
        device=device,
        expires_at=now + timedelta(days=30),
    )
    credentials = account_services._issue_credentials(session=session, now=now)
    return (
        user,
        device,
        {
            "access_token": credentials.access_token,
            "refresh_token": credentials.refresh_token,
        },
    )


def _reauthenticate(
    client: APIClient,
    *,
    access_token: str,
    email: str = "reader@example.com",
) -> tuple[dict[str, Any], str]:
    started = client.post(
        reverse("accounts:email-start"),
        {"email": email},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {access_token}",
    )
    assert started.status_code == 202, started.data
    match = re.search(r"\b([0-9]{6})\b", mail.outbox[-1].body)
    assert match is not None
    challenge_id = started.json()["challenge_id"]
    verified = client.post(
        reverse("accounts:email-verify"),
        {
            "challenge_id": challenge_id,
            "code": match.group(1),
            "installation_credential": INSTALLATION_CREDENTIAL,
            "idempotency_key": str(uuid.uuid4()),
        },
        format="json",
    )
    assert verified.status_code == 200, verified.data
    return verified.json(), challenge_id


def test_device_inventory_and_selective_revoke_are_user_scoped(api_client: APIClient) -> None:
    user, current_device, current = _active_session()
    other_device = Device.objects.create(
        user=user,
        platform="ios",
        installation_id_hash="b" * 64,
        app_version="2.0.0",
        locale="en",
    )
    now = timezone.now()
    other_session = RefreshSession.objects.create(
        user=user,
        device=other_device,
        expires_at=now + timedelta(days=30),
    )
    other_credentials = account_services._issue_credentials(session=other_session, now=now)
    _other_user, foreign_device, _foreign = _active_session(
        email="other@example.com",
        installation_hash="c" * 64,
    )

    inventory = api_client.get(
        reverse("account_user:devices"),
        HTTP_AUTHORIZATION=f"Bearer {current['access_token']}",
    )

    assert inventory.status_code == 200
    assert inventory["Cache-Control"] == "private, no-store"
    by_id = {item["id"]: item for item in inventory.json()}
    assert by_id[str(current_device.id)]["is_current"] is True
    assert by_id[str(other_device.id)]["is_current"] is False
    assert by_id[str(other_device.id)]["active_session_count"] == 1
    assert "installation_id_hash" not in inventory.content.decode()
    assert "refresh_token" not in inventory.content.decode()

    foreign = api_client.delete(
        reverse("account_user:device-detail", kwargs={"device_id": foreign_device.id}),
        HTTP_AUTHORIZATION=f"Bearer {current['access_token']}",
    )
    current_conflict = api_client.delete(
        reverse("account_user:device-detail", kwargs={"device_id": current_device.id}),
        HTTP_AUTHORIZATION=f"Bearer {current['access_token']}",
    )
    revoked = api_client.delete(
        reverse("account_user:device-detail", kwargs={"device_id": other_device.id}),
        HTTP_AUTHORIZATION=f"Bearer {current['access_token']}",
    )

    assert foreign.status_code == 404
    assert foreign.json()["code"] == "device_not_found"
    assert current_conflict.status_code == 409
    assert current_conflict.json()["code"] == "current_device_revoke_conflict"
    assert revoked.status_code == 204
    other_device.refresh_from_db()
    other_session.refresh_from_db()
    assert other_device.revoked_at is not None
    assert other_session.revoked_at is not None
    rejected_refresh = api_client.post(
        reverse("accounts:token-refresh"),
        {"refresh_token": other_credentials.refresh_token},
        format="json",
    )
    assert rejected_refresh.status_code == 401


def test_current_session_locale_updates_user_and_device(api_client: APIClient) -> None:
    user, device, credentials = _active_session()

    response = api_client.patch(
        reverse("account_user:me"),
        {"locale": "tr"},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {credentials['access_token']}",
    )

    assert response.status_code == 200
    assert response["Cache-Control"] == "private, no-store"
    assert response.json()["user"]["preferred_locale"] == "tr"
    assert response.json()["device"]["locale"] == "tr"
    user.refresh_from_db()
    device.refresh_from_db()
    assert user.preferred_locale == "tr"
    assert device.locale == "tr"


def test_current_session_locale_rejects_unknown_locale(api_client: APIClient) -> None:
    user, device, credentials = _active_session()

    response = api_client.patch(
        reverse("account_user:me"),
        {"locale": "de"},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {credentials['access_token']}",
    )

    assert response.status_code == 400
    user.refresh_from_db()
    device.refresh_from_db()
    assert user.preferred_locale == "ru"
    assert device.locale == "ru"


def test_deletion_request_blocks_product_apis_but_can_be_cancelled_after_reauth(
    api_client: APIClient,
) -> None:
    user, _device, credentials = _active_session()
    verified, request_challenge_id = _reauthenticate(
        api_client,
        access_token=credentials["access_token"],
    )

    requested = api_client.post(
        reverse("account_user:deletion-request"),
        {"reauth_challenge_id": request_challenge_id},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {verified['access_token']}",
    )

    assert requested.status_code == 202
    assert requested.json()["user"]["status"] == UserStatus.PENDING_DELETION
    assert requested.json()["user"]["deletion_scheduled_for"] is not None
    user.refresh_from_db()
    assert user.deletion_scheduled_for is not None
    assert timedelta(days=6, hours=23) < user.deletion_scheduled_for - timezone.now()

    product_api = api_client.get(
        reverse("account_user:devices"),
        HTTP_AUTHORIZATION=f"Bearer {verified['access_token']}",
    )
    assert product_api.status_code == 401
    refreshed = api_client.post(
        reverse("accounts:token-refresh"),
        {"refresh_token": verified["refresh_token"]},
        format="json",
    )
    assert refreshed.status_code == 200
    pending_me = api_client.get(
        reverse("account_user:me"),
        HTTP_AUTHORIZATION=f"Bearer {refreshed.json()['access_token']}",
    )
    assert pending_me.status_code == 200
    assert pending_me.json()["user"]["status"] == UserStatus.PENDING_DELETION

    reused_proof = api_client.post(
        reverse("account_user:deletion-cancel"),
        {"reauth_challenge_id": request_challenge_id},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {refreshed.json()['access_token']}",
    )
    assert reused_proof.status_code == 403
    assert reused_proof.json()["code"] == "account_reauthentication_required"

    cancellation_verified, cancel_challenge_id = _reauthenticate(
        api_client,
        access_token=refreshed.json()["access_token"],
    )
    cancelled = api_client.post(
        reverse("account_user:deletion-cancel"),
        {"reauth_challenge_id": cancel_challenge_id},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {cancellation_verified['access_token']}",
    )

    assert cancelled.status_code == 200
    assert cancelled.json()["user"]["status"] == UserStatus.ACTIVE
    assert cancelled.json()["user"]["deletion_scheduled_for"] is None
    user.refresh_from_db()
    assert user.status == UserStatus.ACTIVE
    assert user.deletion_requested_at is None
    assert user.deletion_scheduled_for is None


def test_deletion_request_requires_recent_same_device_email_verification(
    api_client: APIClient,
) -> None:
    _user, _device, credentials = _active_session()

    missing = api_client.post(
        reverse("account_user:deletion-request"),
        {"reauth_challenge_id": str(uuid.uuid4())},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {credentials['access_token']}",
    )

    assert missing.status_code == 403
    assert missing.json()["code"] == "account_reauthentication_required"


def test_due_deletion_anonymizes_account_and_removes_synced_data(
    quran_dataset: dict[str, Any],
) -> None:
    user, device, _credentials = _active_session()
    Consent.objects.create(
        user=user,
        purpose=ConsentPurpose.NOTIFICATIONS,
        policy_version="1",
        granted_at=timezone.now(),
    )
    bookmark = Bookmark.objects.create(
        user=user,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        label="private",
        note="private note",
        client_updated_at=timezone.now(),
        device=device,
    )
    goal, _created = set_reading_goal(
        user=user,
        metric=ReadingGoalMetric.MINUTES,
        target_amount=Decimal("1"),
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=timezone.now(),
        device_id=device.id,
    )
    reading_session, _created = record_manual_session(
        user=user,
        session_id=uuid.uuid7(),
        timezone_name="UTC",
        local_date=timezone.now().date(),
        metric=ReadingGoalMetric.MINUTES,
        amount=Decimal("1"),
        client_updated_at=timezone.now(),
        device_id=device.id,
    )
    requested_at = timezone.now() - timedelta(days=8)
    User.objects.filter(id=user.id).update(
        status=UserStatus.PENDING_DELETION,
        deletion_requested_at=requested_at,
        deletion_scheduled_for=requested_at + timedelta(days=7),
    )

    result = finalize_due_account_deletions(now=timezone.now())

    assert result["finalized"] == 1
    user.refresh_from_db()
    identity = AuthIdentity.objects.get(user=user)
    assert user.status == UserStatus.DELETED
    assert user.is_active is False
    assert user.email is None
    assert user.deleted_at is not None
    assert identity.provider_subject == f"deleted:{identity.id}"
    assert identity.email_at_provider is None
    assert identity.email_verified is False
    assert not Device.objects.filter(user=user).exists()
    assert not Consent.objects.filter(user=user).exists()
    assert not Bookmark.objects.filter(id=bookmark.id).exists()
    assert not ReadingSession.objects.filter(id=reading_session.id).exists()
    assert not GoalProgress.objects.filter(goal_id=goal.id).exists()
    assert not ReadingGoal.objects.filter(id=goal.id).exists()
    assert not ReadingStreak.objects.filter(user=user).exists()
