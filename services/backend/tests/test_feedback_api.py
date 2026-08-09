from __future__ import annotations

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from threading import Barrier
from typing import Any

import pytest
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import close_old_connections, connection
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.models import (
    FeedbackAudit,
    FeedbackAuditAction,
    FeedbackAuthorType,
    FeedbackMessage,
    FeedbackPriority,
    FeedbackStatus,
    FeedbackVisibility,
)
from quran_backend.modules.feedback.services import (
    create_ticket,
    operator_update_ticket,
    register_operator_message,
)
from quran_backend.modules.feedback.throttling import FeedbackWriteRateThrottle


def _authenticated_client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _ticket_payload(
    *,
    request_id: uuid.UUID | None = None,
    message_id: uuid.UUID | None = None,
    category: str = "religious_content",
) -> dict[str, Any]:
    return {
        "client_request_id": str(request_id or uuid.uuid7()),
        "client_message_id": str(message_id or uuid.uuid7()),
        "category": category,
        "subject": "Possible ayah page mismatch",
        "message": "Please verify the highlighted ayah on this page.",
        "locale": "en",
        "contact_email": "Reporter@Example.com",
        "context": {
            "edition_code": "madani-hafs",
            "content_version": "1.0.0",
            "surah_number": 1,
            "ayah_number": 1,
            "page_number": 1,
            "reciter_id": "alafasy",
            "recitation_id": "hafs-complete",
            "audio_track_id": "001-001",
            "playback_ms": 1234,
            "ad_campaign_id": "campaign-42",
            "ad_creative_id": "creative-7",
            "route": "/quran/madani-hafs/pages/1",
            "app_version": "1.0.0",
            "app_build": "100",
            "client_platform": "android",
            "os_version": "Android 16",
        },
    }


@pytest.mark.django_db
def test_religious_ticket_has_accelerated_sla_context_and_audit() -> None:
    user = User.objects.create_user(preferred_locale="ru")
    client = _authenticated_client(user)
    before = timezone.now()

    response = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(),
        format="json",
    )

    assert response.status_code == 201
    assert response.headers["Cache-Control"] == "private, no-store, max-age=0"
    assert "Authorization" in response.headers["Vary"]
    body = response.json()
    assert body["public_id"].startswith("FB-")
    assert len(body["public_id"]) == 27
    assert body["priority"] == "high"
    assert body["team"] == "religious_editorial"
    assert body["channel"] == "web"
    assert body["contact_email"] == "reporter@example.com"
    assert body["context"]["ayah_number"] == 1
    assert body["context"]["audio_track_id"] == "001-001"
    assert body["context"]["ad_campaign_id"] == "campaign-42"
    assert body["context"]["app_build"] == "100"
    due_at = datetime.fromisoformat(body["sla_response_due_at"])
    assert before + timedelta(hours=23, minutes=59) < due_at
    assert due_at < before + timedelta(hours=24, minutes=1)
    audit = FeedbackAudit.objects.get(ticket__public_id=body["public_id"])
    assert audit.action == FeedbackAuditAction.CREATED
    assert audit.new_values["priority"] == "high"
    assert "body" not in audit.new_values


@pytest.mark.django_db
def test_ticket_create_retry_is_idempotent_and_changed_reuse_conflicts() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    request_id = uuid.uuid7()
    payload = _ticket_payload(request_id=request_id)
    url = reverse("feedback:ticket-list")

    first = client.post(url, payload, format="json")
    retry = client.post(url, payload, format="json")
    conflict = client.post(url, {**payload, "subject": "Changed"}, format="json")

    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json() == first.json()
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "feedback_conflict"
    assert user.feedback_tickets.count() == 1
    assert FeedbackMessage.objects.count() == 1
    assert FeedbackAudit.objects.count() == 1


@pytest.mark.django_db
def test_ticket_list_detail_and_public_messages_are_user_isolated() -> None:
    owner = User.objects.create_user()
    stranger = User.objects.create_user()
    owner_client = _authenticated_client(owner)
    created = owner_client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="technical"),
        format="json",
    )
    ticket = owner.feedback_tickets.get()
    FeedbackMessage.objects.create(
        ticket=ticket,
        author_type=FeedbackAuthorType.OPERATOR,
        visibility=FeedbackVisibility.INTERNAL,
        body="Internal triage note",
    )
    detail_url = reverse(
        "feedback:ticket-detail",
        kwargs={"public_id": created.json()["public_id"]},
    )

    owner_list = owner_client.get(reverse("feedback:ticket-list"))
    owner_detail = owner_client.get(detail_url)
    stranger_list = _authenticated_client(stranger).get(reverse("feedback:ticket-list"))
    stranger_detail = _authenticated_client(stranger).get(detail_url)

    assert owner_list.status_code == 200
    assert len(owner_list.json()["results"]) == 1
    assert len(owner_detail.json()["messages"]) == 1
    assert owner_detail.json()["messages"][0]["body"] != "Internal triage note"
    assert stranger_list.json()["results"] == []
    assert stranger_detail.status_code == 404
    assert stranger_detail.content_type == "application/problem+json"
    assert stranger_detail.json()["code"] == "feedback_ticket_not_found"


@pytest.mark.django_db
def test_close_is_idempotent_and_new_message_reopens_once() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    created = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(),
        format="json",
    )
    public_id = created.json()["public_id"]
    close_url = reverse("feedback:ticket-close", kwargs={"public_id": public_id})

    first_close = client.post(close_url, {"reason": "Solved locally"}, format="json")
    retry_close = client.post(close_url, {"reason": "Retry"}, format="json")
    message_id = uuid.uuid7()
    message_payload = {"client_message_id": str(message_id), "body": "The issue returned."}
    message_url = reverse("feedback:message-create", kwargs={"public_id": public_id})
    reply = client.post(message_url, message_payload, format="json")
    reply_retry = client.post(message_url, message_payload, format="json")

    assert first_close.status_code == 200
    assert retry_close.status_code == 200
    assert first_close.json()["status"] == FeedbackStatus.CLOSED
    assert reply.status_code == 201
    assert reply.json()["status"] == FeedbackStatus.NEW
    assert reply.json()["reopen_count"] == 1
    assert len(reply.json()["messages"]) == 2
    assert reply_retry.status_code == 200
    assert reply_retry.json()["reopen_count"] == 1
    assert len(reply_retry.json()["messages"]) == 2
    actions = list(
        FeedbackAudit.objects.filter(ticket__public_id=public_id).values_list(
            "action",
            flat=True,
        )
    )
    assert actions.count(FeedbackAuditAction.STATUS_CHANGED) == 1
    assert actions.count(FeedbackAuditAction.REOPENED) == 1
    assert actions.count(FeedbackAuditAction.MESSAGE_ADDED) == 1


@pytest.mark.django_db
def test_explicit_reopen_is_retry_safe_and_rejects_active_ticket() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    created = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )
    public_id = created.json()["public_id"]
    reopen_url = reverse("feedback:ticket-reopen", kwargs={"public_id": public_id})

    invalid = client.post(reopen_url, {}, format="json")
    client.post(
        reverse("feedback:ticket-close", kwargs={"public_id": public_id}),
        {},
        format="json",
    )
    reopened = client.post(reopen_url, {"reason": "More evidence"}, format="json")
    retry = client.post(reopen_url, {"reason": "Retry"}, format="json")

    assert invalid.status_code == 409
    assert reopened.status_code == 200
    assert retry.status_code == 200
    assert retry.json()["reopen_count"] == 1


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("payload_update", "field"),
    [
        ({"subject": "<b>Markup</b>"}, "subject"),
        ({"message": "<script>alert(1)</script>"}, "message"),
        ({"message": "Contains\x00null"}, "message"),
        (
            {"context": {"surah_number": 1, "ayah_number": 1, "page_number": 1}},
            "context",
        ),
        (
            {
                "context": {
                    "edition_code": "madani-hafs",
                    "content_version": "1.0.0",
                    "route": "https://evil.example/path?token=secret",
                }
            },
            "context",
        ),
    ],
)
def test_feedback_rejects_markup_controls_and_unsafe_context(
    payload_update: dict[str, Any],
    field: str,
) -> None:
    user = User.objects.create_user()
    payload = _ticket_payload()
    payload.update(payload_update)

    response = _authenticated_client(user).post(
        reverse("feedback:ticket-list"),
        payload,
        format="json",
    )

    assert response.status_code == 400
    assert field in response.json()["field_errors"]
    assert user.feedback_tickets.count() == 0


@pytest.mark.django_db
@override_settings(FEEDBACK_MAX_OPEN_TICKETS_PER_USER=1)
def test_open_ticket_limit_is_enforced_but_retry_still_works() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    original = _ticket_payload(category="general")

    first = client.post(reverse("feedback:ticket-list"), original, format="json")
    retry = client.post(reverse("feedback:ticket-list"), original, format="json")
    over_limit = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )

    assert first.status_code == 201
    assert retry.status_code == 200
    assert over_limit.status_code == 409
    assert over_limit.json()["code"] == "feedback_limit_reached"


@pytest.mark.django_db
@override_settings(FEEDBACK_MAX_MESSAGES_PER_TICKET=1)
def test_message_limit_and_client_message_id_conflict() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    created = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )
    message_url = reverse(
        "feedback:message-create",
        kwargs={"public_id": created.json()["public_id"]},
    )
    message_id = uuid.uuid7()

    limited = client.post(
        message_url,
        {"client_message_id": str(message_id), "body": "Second message"},
        format="json",
    )

    assert limited.status_code == 409
    assert limited.json()["code"] == "feedback_limit_reached"


@pytest.mark.django_db
def test_operator_workflow_critical_sla_and_public_response() -> None:
    reporter = User.objects.create_user()
    operator = User.objects.create_user(
        email="operator@example.com",
        status="active",
        is_staff=True,
    )
    client = _authenticated_client(reporter)
    created = client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(),
        format="json",
    )
    ticket = reporter.feedback_tickets.get(public_id=created.json()["public_id"])
    before = timezone.now()

    updated = operator_update_ticket(
        ticket.id,
        operator,
        changes={
            "status": FeedbackStatus.TRIAGED,
            "priority": FeedbackPriority.CRITICAL,
            "assignee": operator,
        },
        reason="Canonical page report confirmed for immediate review.",
    )
    message = FeedbackMessage.objects.create(
        ticket=ticket,
        author=operator,
        author_type=FeedbackAuthorType.OPERATOR,
        visibility=FeedbackVisibility.PUBLIC,
        body="We are reviewing this report.",
    )
    register_operator_message(message.id, operator)
    detail = client.get(reverse("feedback:ticket-detail", kwargs={"public_id": ticket.public_id}))

    assert updated.status == FeedbackStatus.TRIAGED
    assert updated.priority == FeedbackPriority.CRITICAL
    assert updated.assignee == operator
    assert updated.sla_response_due_at is not None
    assert before + timedelta(hours=3, minutes=59) < updated.sla_response_due_at
    assert updated.sla_response_due_at < before + timedelta(hours=4, minutes=1)
    assert detail.json()["first_response_at"] is not None
    assert detail.json()["messages"][-1]["author_type"] == "operator"
    assert detail.json()["messages"][-1]["body"] == "We are reviewing this report."
    audit_actions = set(ticket.audit_events.values_list("action", flat=True))
    assert FeedbackAuditAction.STATUS_CHANGED in audit_actions
    assert FeedbackAuditAction.MESSAGE_ADDED in audit_actions


@pytest.mark.django_db
def test_feedback_messages_context_and_audit_are_immutable() -> None:
    user = User.objects.create_user()
    created = _authenticated_client(user).post(
        reverse("feedback:ticket-list"),
        _ticket_payload(),
        format="json",
    )
    ticket = user.feedback_tickets.get(public_id=created.json()["public_id"])
    message = ticket.messages.first()
    audit = ticket.audit_events.first()
    context = ticket.context
    assert message is not None
    assert audit is not None

    message.body = "Rewritten history"
    context.route = "/rewritten"
    audit.reason = "Rewritten audit"

    with pytest.raises(DjangoValidationError, match="immutable"):
        message.save()
    with pytest.raises(DjangoValidationError, match="immutable"):
        context.save()
    with pytest.raises(DjangoValidationError, match="immutable"):
        audit.save()
    with pytest.raises(DjangoValidationError, match="immutable"):
        message.delete()
    with pytest.raises(DjangoValidationError, match="immutable"):
        context.delete()
    with pytest.raises(DjangoValidationError, match="immutable"):
        audit.delete()


@pytest.mark.django_db
def test_feedback_requires_authentication_and_filters_status() -> None:
    anonymous = APIClient().get(reverse("feedback:ticket-list"))
    user = User.objects.create_user()
    client = _authenticated_client(user)
    client.post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )

    filtered = client.get(reverse("feedback:ticket-list"), {"status": "closed"})
    invalid = client.get(reverse("feedback:ticket-list"), {"status": "unknown"})

    assert anonymous.status_code == 401
    assert filtered.status_code == 200
    assert filtered.json()["results"] == []
    assert invalid.status_code == 400
    assert invalid.json()["code"] == "invalid"


@pytest.mark.django_db
def test_feedback_write_rate_limit_is_keyed_by_authenticated_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        FeedbackWriteRateThrottle,
        "THROTTLE_RATES",
        {"feedback_write": "1/hour"},
    )
    first_user = User.objects.create_user()
    second_user = User.objects.create_user()

    accepted = _authenticated_client(first_user).post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )
    limited = _authenticated_client(first_user).post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )
    independent = _authenticated_client(second_user).post(
        reverse("feedback:ticket-list"),
        _ticket_payload(category="general"),
        format="json",
    )

    assert accepted.status_code == 201
    assert limited.status_code == 429
    assert limited.json()["code"] == "throttled"
    assert "Retry-After" in limited.headers
    assert independent.status_code == 201


@pytest.mark.django_db
def test_feedback_openapi_is_explicit_and_has_no_unsafe_attachment_routes() -> None:
    user = User.objects.create_user()
    response = _authenticated_client(user).get(
        reverse("openapi-schema"),
        headers={"Accept": "application/json"},
    )

    assert response.status_code == 200
    paths = response.json()["paths"]
    assert "/api/v1/feedback/tickets" in paths
    assert "/api/v1/feedback/tickets/{public_id}/messages" in paths
    assert "/api/v1/feedback/tickets/{public_id}/close" in paths
    assert "/api/v1/feedback/tickets/{public_id}/reopen" in paths
    assert not any("attachment" in path for path in paths)
    create_request = response.json()["components"]["schemas"]["FeedbackTicketCreateRequest"]
    assert {"client_request_id", "client_message_id", "category", "subject", "message"} <= set(
        create_request["required"]
    )


@pytest.mark.django_db(transaction=True)
def test_concurrent_ticket_create_is_idempotent_on_postgresql() -> None:
    if connection.vendor != "postgresql":
        pytest.skip("Row-lock concurrency semantics require PostgreSQL.")
    user = User.objects.create_user()
    payload = _ticket_payload(category="general")
    payload["client_request_id"] = uuid.UUID(payload["client_request_id"])
    payload["client_message_id"] = uuid.UUID(payload["client_message_id"])
    barrier = Barrier(2)

    def create_from_worker() -> tuple[uuid.UUID, bool]:
        close_old_connections()
        try:
            worker_user = User.objects.get(pk=user.pk)
            barrier.wait(timeout=5)
            ticket, created = create_ticket(worker_user, dict(payload), channel="web")
            return ticket.id, created
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _index: create_from_worker(), range(2)))

    assert len({ticket_id for ticket_id, _created in results}) == 1
    assert sorted(created for _ticket_id, created in results) == [False, True]
    assert FeedbackMessage.objects.count() == 1
    assert FeedbackAudit.objects.count() == 1
