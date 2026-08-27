from __future__ import annotations

import uuid

from celery import shared_task
from django.conf import settings
from django.core.mail import send_mail

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

    event_label = "Новое обращение" if event == "created" else "Новое сообщение пользователя"
    admin_url = f"{settings.PUBLIC_SITE_URL}/admin/feedback/feedbackticket/{ticket.id}/change/"
    delivered = send_mail(
        subject=f"[IQRO] {event_label}: {ticket.public_id}",
        message=(
            f"{event_label}\n\n"
            f"Номер: {ticket.public_id}\n"
            f"Категория: {ticket.get_category_display()}\n"
            f"Тема: {ticket.subject}\n"
            f"Команда: {ticket.team or 'не назначена'}\n"
            f"Email пользователя: {ticket.reporter.email or 'не подтверждён'}\n\n"
            f"Сообщение:\n{message.body}\n\n"
            f"Открыть в административной панели:\n{admin_url}"
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[recipient],
        fail_silently=False,
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

    profile_url = f"{settings.PUBLIC_SITE_URL}/{ticket.locale}/profile#feedback"
    delivered = send_mail(
        subject=f"Ответ по обращению {ticket.public_id}",
        message=(
            f"По вашему обращению «{ticket.subject}» появился ответ команды IQRO.\n\n"
            f"Откройте личный кабинет, чтобы прочитать сообщение и ответить:\n{profile_url}"
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[recipient],
        fail_silently=False,
    )
    if delivered != 1:
        raise RuntimeError("Feedback reporter notification was not accepted by the email backend.")
    return "sent"
