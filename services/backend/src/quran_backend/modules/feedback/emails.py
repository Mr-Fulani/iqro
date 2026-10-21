from __future__ import annotations

# Russian and Turkish copy intentionally contains letters that resemble Latin glyphs.
# ruff: noqa: RUF001
from django.conf import settings
from django.utils import translation

from quran_backend.modules.core.emails import email_locale, send_email
from quran_backend.modules.feedback.models import FeedbackMessage, FeedbackTicket

_REPLY_COPY = {
    "ru": {
        "subject": "Ответ по обращению {public_id} — IQRO",
        "title": "Команда IQRO ответила на ваше обращение",
        "intro": (
            "В обращении появился новый ответ. Прочитайте его и продолжите переписку "
            "в личном кабинете."
        ),
        "number_label": "Номер обращения",
        "subject_label": "Тема",
        "button": "Открыть обращение",
        "reason": "Вы получили это письмо, потому что отправили обращение в поддержку IQRO.",
    },
    "en": {
        "subject": "Reply to your request {public_id} — IQRO",
        "title": "The IQRO team has replied to your request",
        "intro": (
            "There is a new reply in your support request. Read it and continue "
            "the conversation in your profile."
        ),
        "number_label": "Request number",
        "subject_label": "Subject",
        "button": "Open request",
        "reason": "You received this email because you contacted IQRO support.",
    },
    "ar": {
        "subject": "رد على طلبك {public_id} — IQRO",
        "title": "ردّ فريق IQRO على طلبك",
        "intro": "وصل رد جديد على طلب الدعم الخاص بك. اقرأه وتابع المحادثة من صفحتك الشخصية.",
        "number_label": "رقم الطلب",
        "subject_label": "الموضوع",
        "button": "فتح الطلب",
        "reason": "وصلتك هذه الرسالة لأنك راسلت دعم IQRO.",
    },
    "tr": {
        "subject": "{public_id} numaralı talebinize yanıt — IQRO",
        "title": "IQRO ekibi talebinizi yanıtladı",
        "intro": (
            "Destek talebinize yeni bir yanıt geldi. Yanıtı okumak ve yazışmaya "
            "devam etmek için profilinizi açın."
        ),
        "number_label": "Talep numarası",
        "subject_label": "Konu",
        "button": "Talebi aç",
        "reason": "Bu e-postayı IQRO destek ekibine yazdığınız için aldınız.",
    },
}


def send_operator_notification_email(
    *,
    recipient: str,
    ticket: FeedbackTicket,
    message: FeedbackMessage,
    event: str,
) -> int:
    """Notify the support inbox. Operators read Russian, like the admin panel."""
    event_label = "Новое обращение" if event == "created" else "Новое сообщение пользователя"
    admin_url = f"{settings.PUBLIC_SITE_URL}/admin/feedback/feedbackticket/{ticket.id}/change/"
    # Workers run in English and never load the admin; its catalogue has the Russian names.
    with translation.override("ru"):
        category = translation.gettext(ticket.get_category_display())
    return send_email(
        to=recipient,
        template="feedback_operator",
        locale="ru",
        subject=f"[IQRO] {event_label}: {ticket.public_id}",
        context={
            "preheader": f"{ticket.public_id} · {ticket.subject}",
            "reason": (
                "Вы получили это письмо, потому что ваш адрес указан получателем "
                "уведомлений об обращениях в поддержку IQRO."
            ),
            "title": event_label,
            "details": [
                ("Номер", ticket.public_id),
                ("Категория", category),
                ("Тема", ticket.subject),
                ("Команда", ticket.team or "не назначена"),
                ("Email пользователя", ticket.reporter.email or "не подтверждён"),
            ],
            "message_label": "Сообщение",
            "message_body": message.body,
            "button_label": "Открыть в административной панели",
            "button_url": admin_url,
        },
    )


def send_reporter_notification_email(*, recipient: str, ticket: FeedbackTicket) -> int:
    locale = email_locale(ticket.locale)
    copy = _REPLY_COPY[locale]
    return send_email(
        to=recipient,
        template="feedback_reply",
        locale=locale,
        subject=copy["subject"].format(public_id=ticket.public_id),
        context={
            "preheader": copy["intro"],
            "reason": copy["reason"],
            "title": copy["title"],
            "intro": copy["intro"],
            "details": [
                (copy["number_label"], ticket.public_id),
                (copy["subject_label"], ticket.subject),
            ],
            "button_label": copy["button"],
            "button_url": f"{settings.PUBLIC_SITE_URL}/{locale}/profile#feedback",
        },
    )
