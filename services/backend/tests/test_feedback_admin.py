from __future__ import annotations

import uuid

import pytest
from django.contrib import admin
from django.contrib.admin.sites import AdminSite
from django.test import RequestFactory
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.admin import (
    FeedbackAuditAdmin,
    FeedbackContextAdmin,
    FeedbackMessageAdmin,
    FeedbackMessageAdminForm,
    FeedbackTicketAdmin,
    FeedbackTicketAdminForm,
)
from quran_backend.modules.feedback.models import (
    FeedbackAudit,
    FeedbackContext,
    FeedbackMessage,
    FeedbackPriority,
    FeedbackStatus,
    FeedbackTicket,
    FeedbackVisibility,
)


def _create_ticket(reporter: User) -> FeedbackTicket:
    client = APIClient()
    client.force_authenticate(user=reporter)
    response = client.post(
        reverse("feedback:ticket-list"),
        {
            "client_request_id": str(uuid.uuid7()),
            "client_message_id": str(uuid.uuid7()),
            "category": "religious_content",
            "subject": "Review requested",
            "message": "Please review this content.",
        },
        format="json",
    )
    return reporter.feedback_tickets.get(public_id=response.json()["public_id"])


@pytest.mark.django_db
def test_ticket_admin_form_requires_reason_and_valid_transition() -> None:
    reporter = User.objects.create_user()
    ticket = _create_ticket(reporter)
    base = {
        "priority": ticket.priority,
        "team": ticket.team,
        "assignee": "",
    }

    missing_reason = FeedbackTicketAdminForm(
        data={**base, "status": FeedbackStatus.TRIAGED},
        instance=ticket,
    )
    invalid_transition = FeedbackTicketAdminForm(
        data={
            **base,
            "status": FeedbackStatus.WAITING_FOR_USER,
            "transition_reason": "Not yet contacted",
        },
        instance=ticket,
    )
    valid = FeedbackTicketAdminForm(
        data={
            **base,
            "status": FeedbackStatus.TRIAGED,
            "transition_reason": "Initial editorial triage",
        },
        instance=ticket,
    )

    assert not missing_reason.is_valid()
    assert "transition_reason" in missing_reason.errors
    assert not invalid_transition.is_valid()
    assert "status" in invalid_transition.errors
    assert valid.is_valid(), valid.errors


@pytest.mark.django_db
def test_ticket_admin_save_and_critical_action_are_audited() -> None:
    reporter = User.objects.create_user()
    operator = User.objects.create_user(
        email="admin@example.com",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    ticket = _create_ticket(reporter)
    form = FeedbackTicketAdminForm(
        data={
            "status": FeedbackStatus.TRIAGED,
            "priority": ticket.priority,
            "team": ticket.team,
            "assignee": str(operator.id),
            "transition_reason": "Assigned to an editor",
        },
        instance=ticket,
    )
    assert form.is_valid(), form.errors
    obj = form.save(commit=False)
    request = RequestFactory().post("/admin/feedback/feedbackticket/")
    request.user = operator
    model_admin = FeedbackTicketAdmin(FeedbackTicket, AdminSite())

    model_admin.save_model(request, obj, form, change=True)
    ticket.refresh_from_db()
    model_admin.escalate_to_critical(
        request,
        FeedbackTicket.objects.filter(pk=ticket.pk),
    )
    ticket.refresh_from_db()

    assert ticket.status == FeedbackStatus.TRIAGED
    assert ticket.assignee == operator
    assert ticket.priority == FeedbackPriority.CRITICAL
    assert ticket.sla_response_due_at is not None
    assert ticket.audit_events.count() == 3


@pytest.mark.django_db
def test_operator_message_admin_enforces_plain_text_and_registers_response() -> None:
    reporter = User.objects.create_user()
    operator = User.objects.create_user(
        email="admin@example.com",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    ticket = _create_ticket(reporter)
    invalid = FeedbackMessageAdminForm(
        data={
            "ticket": str(ticket.id),
            "visibility": FeedbackVisibility.PUBLIC,
            "body": "<b>Unsafe operator markup</b>",
        }
    )
    valid = FeedbackMessageAdminForm(
        data={
            "ticket": str(ticket.id),
            "visibility": FeedbackVisibility.PUBLIC,
            "body": "We are reviewing this report.",
        }
    )
    assert not invalid.is_valid()
    assert valid.is_valid(), valid.errors
    message = valid.save(commit=False)
    request = RequestFactory().post("/admin/feedback/feedbackmessage/add/")
    request.user = operator
    model_admin = FeedbackMessageAdmin(FeedbackMessage, AdminSite())

    model_admin.save_model(request, message, valid, change=False)
    ticket.refresh_from_db()

    assert message.author == operator
    assert message.author_type == "operator"
    assert ticket.first_response_at is not None
    assert ticket.audit_events.filter(action="message_added").count() == 1
    assert model_admin.has_change_permission(request, message) is False
    assert model_admin.has_delete_permission(request, message) is False


@pytest.mark.django_db
def test_immutable_admin_models_cannot_be_mutated() -> None:
    reporter = User.objects.create_user()
    operator = User.objects.create_user(
        email="admin@example.com",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    _create_ticket(reporter)
    request = RequestFactory().get("/admin/")
    request.user = operator

    for model, model_admin_class in (
        (FeedbackAudit, FeedbackAuditAdmin),
        (FeedbackContext, FeedbackContextAdmin),
    ):
        model_admin = model_admin_class(model, admin.site)
        assert model_admin.has_add_permission(request) is False
        assert model_admin.has_change_permission(request, model.objects.first()) is False
        assert model_admin.has_delete_permission(request, model.objects.first()) is False
