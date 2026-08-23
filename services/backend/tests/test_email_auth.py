from __future__ import annotations

import re
import uuid
from datetime import time, timedelta
from decimal import Decimal
from typing import Any, cast
from unittest.mock import patch

import pytest
from django.core import mail
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Consent,
    Device,
    EmailAuthChallenge,
    GuestMergeAudit,
    IdentityProvider,
    RefreshSession,
    User,
    UserStatus,
)
from quran_backend.modules.feedback.models import FeedbackChannel, FeedbackTicket
from quran_backend.modules.reading.models import Bookmark, ReadingPosition, SyncChange
from quran_backend.modules.reminders.models import ReminderRule, ReminderType

pytestmark = pytest.mark.django_db


def _guest_payload() -> dict[str, object]:
    return {
        "installation_id": str(uuid.uuid4()),
        "installation_credential": "A" * 43,
        "platform": "web",
        "locale": "ru",
        "app_version": "1.0.0",
    }


def _bootstrap(client: APIClient) -> tuple[dict[str, Any], dict[str, object]]:
    payload = _guest_payload()
    response = client.post(reverse("accounts:guest-bootstrap"), payload, format="json")
    assert response.status_code == 200
    return cast(dict[str, Any], response.json()), payload


def _start(
    client: APIClient,
    session: dict[str, Any],
    email: str,
) -> tuple[dict[str, Any], str]:
    response = client.post(
        reverse("accounts:email-start"),
        {"email": email},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
    )
    assert response.status_code == 202, response.data
    body = cast(dict[str, Any], response.json())
    match = re.search(r"\b([0-9]{6})\b", mail.outbox[-1].body)
    assert match is not None
    return body, match.group(1)


def _verify_payload(
    challenge_id: str,
    code: str,
    installation_credential: object,
    *,
    idempotency_key: uuid.UUID | None = None,
) -> dict[str, object]:
    return {
        "challenge_id": challenge_id,
        "code": code,
        "installation_credential": installation_credential,
        "idempotency_key": str(idempotency_key or uuid.uuid4()),
    }


def test_email_start_is_authenticated_device_bound_and_does_not_store_plain_code(
    api_client: APIClient,
) -> None:
    unauthorized = api_client.post(
        reverse("accounts:email-start"),
        {"email": "reader@example.com"},
        format="json",
    )
    session, _payload = _bootstrap(api_client)
    response, code = _start(api_client, session, "Reader@Example.COM")

    challenge = EmailAuthChallenge.objects.get(id=response["challenge_id"])
    assert unauthorized.status_code == 401
    assert response["expires_in"] == 600
    assert challenge.email == "reader@example.com"
    assert challenge.code_hash != code
    assert code not in challenge.code_hash
    assert challenge.requester_id == uuid.UUID(session["user"]["id"])
    assert challenge.device_id == uuid.UUID(session["device"]["id"])
    assert mail.outbox[-1].to == ["reader@example.com"]


def test_email_verify_promotes_guest_and_is_idempotently_replayable(api_client: APIClient) -> None:
    session, guest_payload = _bootstrap(api_client)
    challenge, code = _start(api_client, session, "reader@example.com")
    verification_key = uuid.uuid4()
    payload = _verify_payload(
        challenge["challenge_id"],
        code,
        guest_payload["installation_credential"],
        idempotency_key=verification_key,
    )

    response = api_client.post(reverse("accounts:email-verify"), payload, format="json")

    assert response.status_code == 200
    result = response.json()
    assert result["user"]["status"] == UserStatus.ACTIVE
    assert result["user"]["email"] == "reader@example.com"
    assert result["merged_guest"] is False
    assert result["replayed"] is False
    identity = AuthIdentity.objects.get()
    assert identity.email_verified is True
    assert identity.provider_subject == "reader@example.com"
    assert EmailAuthChallenge.objects.get().consumed_at is not None

    me = api_client.get(
        reverse("account_user:me"),
        HTTP_AUTHORIZATION=f"Bearer {result['access_token']}",
    )
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "reader@example.com"

    replay = api_client.post(reverse("accounts:email-verify"), payload, format="json")
    assert replay.status_code == 200
    assert replay.json()["replayed"] is True
    assert replay.json()["user"]["id"] == result["user"]["id"]
    assert replay.json()["refresh_token"] != result["refresh_token"]


def test_email_verify_decrements_attempts_without_consuming_challenge(
    api_client: APIClient,
) -> None:
    session, guest_payload = _bootstrap(api_client)
    challenge, _code = _start(api_client, session, "reader@example.com")

    response = api_client.post(
        reverse("accounts:email-verify"),
        _verify_payload(
            challenge["challenge_id"],
            "000000",
            guest_payload["installation_credential"],
        ),
        format="json",
    )

    assert response.status_code == 400
    assert response.json()["code"] == "email_challenge_invalid"
    stored = EmailAuthChallenge.objects.get(id=challenge["challenge_id"])
    assert stored.attempts_remaining == 4
    assert stored.consumed_at is None


def test_email_verify_rejects_expired_challenge(api_client: APIClient) -> None:
    session, guest_payload = _bootstrap(api_client)
    challenge, code = _start(api_client, session, "reader@example.com")
    EmailAuthChallenge.objects.filter(id=challenge["challenge_id"]).update(
        expires_at=timezone.now() - timedelta(seconds=1)
    )

    response = api_client.post(
        reverse("accounts:email-verify"),
        _verify_payload(
            challenge["challenge_id"],
            code,
            guest_payload["installation_credential"],
        ),
        format="json",
    )

    assert response.status_code == 410
    assert response.json()["code"] == "email_challenge_expired"
    assert EmailAuthChallenge.objects.get(id=challenge["challenge_id"]).consumed_at is None


def test_email_verify_is_bound_to_installation_credential(api_client: APIClient) -> None:
    session, _guest_payload = _bootstrap(api_client)
    challenge, code = _start(api_client, session, "reader@example.com")

    response = api_client.post(
        reverse("accounts:email-verify"),
        _verify_payload(challenge["challenge_id"], code, "B" * 43),
        format="json",
    )

    assert response.status_code == 400
    assert response.json()["code"] == "email_challenge_invalid"
    stored = EmailAuthChallenge.objects.get(id=challenge["challenge_id"])
    assert stored.attempts_remaining == 5
    assert stored.consumed_at is None


def test_email_start_invalidates_challenge_when_delivery_fails(api_client: APIClient) -> None:
    session, _guest_payload = _bootstrap(api_client)

    with patch(
        "quran_backend.modules.accounts.email_auth.send_mail",
        return_value=0,
    ):
        response = api_client.post(
            reverse("accounts:email-start"),
            {"email": "reader@example.com"},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
        )

    assert response.status_code == 503
    assert response.json()["code"] == "email_delivery_failed"
    challenge = EmailAuthChallenge.objects.get(email="reader@example.com")
    assert challenge.invalidated_at is not None
    assert challenge.consumed_at is None


def test_email_verify_does_not_claim_address_from_suspended_account(
    api_client: APIClient,
) -> None:
    owner = User.objects.create_user(
        email="reader@example.com",
        status=UserStatus.SUSPENDED,
        is_active=False,
    )
    session, guest_payload = _bootstrap(api_client)
    guest_id = uuid.UUID(session["user"]["id"])
    challenge, code = _start(api_client, session, "reader@example.com")

    response = api_client.post(
        reverse("accounts:email-verify"),
        _verify_payload(
            challenge["challenge_id"],
            code,
            guest_payload["installation_credential"],
        ),
        format="json",
    )

    assert response.status_code == 403
    assert response.json()["code"] == "account_link_unavailable"
    assert not AuthIdentity.objects.filter(provider_subject="reader@example.com").exists()
    assert User.objects.get(id=guest_id).status == UserStatus.GUEST
    assert User.objects.get(id=owner.id).status == UserStatus.SUSPENDED
    assert EmailAuthChallenge.objects.get(id=challenge["challenge_id"]).consumed_at is None


def test_existing_account_login_transactionally_merges_guest_state(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    target = User.objects.create_user(
        email="reader@example.com",
        status=UserStatus.ACTIVE,
        preferred_locale="ru",
    )
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="reader@example.com",
        email_at_provider="reader@example.com",
        email_verified=True,
    )
    session, guest_payload = _bootstrap(api_client)
    guest = User.objects.get(id=session["user"]["id"])
    guest_device = Device.objects.get(id=session["device"]["id"])
    now = timezone.now()
    old_target_position = ReadingPosition.objects.create(
        user=target,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        ayah=quran_dataset["first_ayah"],
        progress_percent=Decimal("10.00"),
        last_read_at=now - timedelta(days=1),
        client_updated_at=now - timedelta(days=1),
        revision=2,
    )
    ReadingPosition.objects.create(
        user=guest,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        ayah=quran_dataset["second_ayah"],
        progress_percent=Decimal("90.00"),
        last_read_at=now,
        client_updated_at=now,
        revision=3,
        device=guest_device,
    )
    bookmark = Bookmark.objects.create(
        user=guest,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        ayah=quran_dataset["second_ayah"],
        label="Гостевая закладка",
        client_updated_at=now,
        device=guest_device,
    )
    reminder = ReminderRule.objects.create(
        user=guest,
        device=guest_device,
        reminder_type=ReminderType.QURAN_READING,
        local_time=time(8, 30),
        client_updated_at=now,
    )
    Consent.objects.create(
        user=guest,
        purpose="diagnostics",
        policy_version="2026-08",
        granted_at=now,
    )
    ticket = FeedbackTicket.objects.create(
        reporter=guest,
        client_request_id=uuid.uuid4(),
        request_fingerprint="f" * 64,
        category="other",
        subject="Гостевое обращение",
        locale="ru",
        channel=FeedbackChannel.WEB,
    )
    challenge, code = _start(api_client, session, "reader@example.com")

    response = api_client.post(
        reverse("accounts:email-verify"),
        _verify_payload(
            challenge["challenge_id"],
            code,
            guest_payload["installation_credential"],
        ),
        format="json",
    )

    assert response.status_code == 200, response.data
    result = response.json()
    assert result["user"]["id"] == str(target.id)
    assert result["merged_guest"] is True
    guest.refresh_from_db()
    guest_device.refresh_from_db()
    old_target_position.refresh_from_db()
    bookmark.refresh_from_db()
    reminder.refresh_from_db()
    ticket.refresh_from_db()
    assert guest.status == UserStatus.DELETED
    assert guest.is_active is False
    assert guest_device.user_id == target.id
    assert old_target_position.ayah_id == quran_dataset["second_ayah"].id
    assert old_target_position.progress_percent == Decimal("90.00")
    assert old_target_position.revision == 4
    assert bookmark.user_id == target.id
    assert reminder.user_id == target.id
    assert reminder.device_id == guest_device.id
    assert ticket.reporter_id == target.id
    assert Consent.objects.filter(user=target, purpose="diagnostics").exists()
    audit = GuestMergeAudit.objects.get(source_user=guest)
    assert audit.target_user_id == target.id
    assert audit.trigger_identity_id == identity.id
    assert audit.moved_counts["bookmarks"] == 1
    assert SyncChange.objects.filter(user=target).count() == 3
    assert RefreshSession.objects.filter(user=target, revoked_at__isnull=True).count() == 1


def test_consumed_challenge_rejects_a_different_idempotency_key(api_client: APIClient) -> None:
    session, guest_payload = _bootstrap(api_client)
    challenge, code = _start(api_client, session, "reader@example.com")
    first_payload = _verify_payload(
        challenge["challenge_id"],
        code,
        guest_payload["installation_credential"],
    )
    first = api_client.post(reverse("accounts:email-verify"), first_payload, format="json")
    second_payload = {**first_payload, "idempotency_key": str(uuid.uuid4())}

    second = api_client.post(reverse("accounts:email-verify"), second_payload, format="json")

    assert first.status_code == 200
    assert second.status_code == 400
    assert second.json()["code"] == "email_challenge_invalid"
