from __future__ import annotations

import uuid
from unittest.mock import patch

import pytest
from django.core import mail
from django.test import override_settings

from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.models import (
    FeedbackAuthorType,
    FeedbackMessage,
    FeedbackVisibility,
)
from quran_backend.modules.feedback.services import (
    add_reporter_message,
    create_ticket,
    register_operator_message,
)
from quran_backend.modules.feedback.tasks import (
    send_feedback_operator_notification_task,
    send_feedback_reporter_notification_task,
)


def _ticket_data() -> dict[str, object]:
    return {
        "client_request_id": uuid.uuid7(),
        "client_message_id": uuid.uuid7(),
        "category": "technical",
        "subject": "Login error",
        "message": "Unable to request a login code.",
        "locale": "ru",
        "contact_email": "reader@example.com",
        "context": {"route": "/ru/login", "client_platform": "web"},
    }


@pytest.mark.django_db(transaction=True)
def test_new_ticket_and_reporter_reply_schedule_operator_notifications() -> None:
    reporter = User.objects.create_user(email="reader@example.com", status="active")

    with patch(
        "quran_backend.modules.feedback.tasks.send_feedback_operator_notification_task.delay"
    ) as delay:
        ticket, created = create_ticket(reporter, _ticket_data(), channel="web")
        initial_message = ticket.messages.get()
        add_reporter_message(
            reporter,
            ticket.public_id,
            {"client_message_id": uuid.uuid7(), "body": "Дополнительные сведения."},
        )

    assert created is True
    assert delay.call_count == 2
    assert delay.call_args_list[0].args == (
        str(ticket.id),
        str(initial_message.id),
        "created",
    )
    assert delay.call_args_list[1].args[0] == str(ticket.id)
    assert delay.call_args_list[1].args[2] == "reporter_reply"


@pytest.mark.django_db(transaction=True)
def test_public_operator_reply_schedules_reporter_notification() -> None:
    reporter = User.objects.create_user(email="reader@example.com", status="active")
    operator = User.objects.create_user(
        email="operator@example.com", status="active", is_staff=True
    )
    with patch(
        "quran_backend.modules.feedback.tasks.send_feedback_operator_notification_task.delay"
    ):
        ticket, _created = create_ticket(reporter, _ticket_data(), channel="web")
    message = FeedbackMessage.objects.create(
        ticket=ticket,
        author=operator,
        author_type=FeedbackAuthorType.OPERATOR,
        visibility=FeedbackVisibility.PUBLIC,
        body="Мы исправили проблему.",
    )

    with patch(
        "quran_backend.modules.feedback.tasks.send_feedback_reporter_notification_task.delay"
    ) as delay:
        register_operator_message(message.id, operator)

    delay.assert_called_once_with(str(message.id))


@pytest.mark.django_db
@override_settings(
    MAILERS={"default": {"BACKEND": "django.core.mail.backends.locmem.EmailBackend"}},
    DEFAULT_FROM_EMAIL="IQRO <login@auth.iqro.forum>",
    FEEDBACK_NOTIFICATION_EMAIL="operator@example.com",
    PUBLIC_SITE_URL="https://staging.iqro.forum",
)
def test_feedback_tasks_send_operator_and_verified_reporter_emails() -> None:
    reporter = User.objects.create_user(email="reader@example.com", status="active")
    ticket, _created = create_ticket(reporter, _ticket_data(), channel="web")
    initial_message = ticket.messages.get()
    operator_message = FeedbackMessage.objects.create(
        ticket=ticket,
        author_type=FeedbackAuthorType.OPERATOR,
        visibility=FeedbackVisibility.PUBLIC,
        body="Ответ оператора.",
    )

    operator_result = send_feedback_operator_notification_task.run(
        str(ticket.id),
        str(initial_message.id),
        "created",
    )
    reporter_result = send_feedback_reporter_notification_task.run(str(operator_message.id))

    assert operator_result == "sent"
    assert reporter_result == "sent"
    assert len(mail.outbox) == 2
    assert mail.outbox[0].to == ["operator@example.com"]
    assert ticket.public_id in mail.outbox[0].subject
    assert f"/admin/feedback/feedbackticket/{ticket.id}/change/" in mail.outbox[0].body
    assert mail.outbox[1].to == ["reader@example.com"]
    assert "/ru/profile#feedback" in mail.outbox[1].body
