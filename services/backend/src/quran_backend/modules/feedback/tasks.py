from __future__ import annotations

import uuid

from celery import shared_task
from django.conf import settings

from quran_backend.modules.feedback.emails import (
    send_operator_notification_email,
    send_reporter_notification_email,
)
from quran_backend.modules.feedback.models import (
    FeedbackMessage,
    FeedbackTicket,
    FeedbackVisibility,
)


@shared_task(  # type: ignore[untyped-decorator]
    name="feedback.notify_operator",
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_kwargs={"max_retries": 3},
)
def send_feedback_operator_notification_task(
    ticket_id: str,
    message_id: str,
    event: str,
) -> str:
    recipient = str(getattr(settings, "FEEDBACK_NOTIFICATION_EMAIL", "")).strip()
    if not recipient:
        return "disabled"
    try:
        ticket = FeedbackTicket.objects.select_related("reporter").get(pk=uuid.UUID(ticket_id))
        message = FeedbackMessage.objects.get(
            pk=uuid.UUID(message_id),
            ticket=ticket,
            visibility=FeedbackVisibility.PUBLIC,
        )
    except ValueError, FeedbackTicket.DoesNotExist, FeedbackMessage.DoesNotExist:
        return "missing"

    delivered = send_operator_notification_email(
        recipient=recipient,
        ticket=ticket,
        message=message,
        event=event,
    )
    if delivered != 1:
        raise RuntimeError("Feedback operator notification was not accepted by the email backend.")
    return "sent"


@shared_task(  # type: ignore[untyped-decorator]
    name="feedback.notify_reporter",
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_kwargs={"max_retries": 3},
)
def send_feedback_reporter_notification_task(message_id: str) -> str:
    try:
        message = FeedbackMessage.objects.select_related("ticket__reporter").get(
            pk=uuid.UUID(message_id),
            visibility=FeedbackVisibility.PUBLIC,
        )
    except ValueError, FeedbackMessage.DoesNotExist:
        return "missing"
    ticket = message.ticket
    recipient = (ticket.reporter.email or "").strip()
    if not recipient:
        return "disabled"

    delivered = send_reporter_notification_email(recipient=recipient, ticket=ticket)
    if delivered != 1:
        raise RuntimeError("Feedback reporter notification was not accepted by the email backend.")
    return "sent"
