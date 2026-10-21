from __future__ import annotations

# Turkish copy intentionally contains the dotless i.
# ruff: noqa: RUF001
import re
import uuid
from typing import Any, cast

import pytest
from django.core import mail
from django.core.mail import EmailMultiAlternatives
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts.emails import _minutes, send_login_code_email
from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.emails import email_locale
from quran_backend.modules.feedback.emails import (
    send_operator_notification_email,
    send_reporter_notification_email,
)
from quran_backend.modules.feedback.models import FeedbackMessage, FeedbackTicket

LOCALES = ("ru", "en", "ar", "tr")

pytestmark = pytest.mark.usefixtures("email_settings")


@pytest.fixture
def email_settings() -> Any:
    with override_settings(
        MAILERS={"default": {"BACKEND": "django.core.mail.backends.locmem.EmailBackend"}},
        DEFAULT_FROM_EMAIL="IQRO <login@auth.iqro.forum>",
        PUBLIC_SITE_URL="https://iqro.forum",
        LEGAL_CONTACT_EMAIL="support@iqro.forum",
    ):
        yield


def _sent() -> tuple[EmailMultiAlternatives, str]:
    message = cast(EmailMultiAlternatives, mail.outbox[-1])
    assert len(message.alternatives) == 1
    html, mimetype = message.alternatives[0]
    assert mimetype == "text/html"
    return message, str(html)


def _assert_layout(message: EmailMultiAlternatives, html: str, locale: str) -> None:
    direction = "rtl" if locale == "ar" else "ltr"
    assert message.from_email == "IQRO <login@auth.iqro.forum>"
    assert f'<html lang="{locale}" dir="{direction}">' in html
    assert 'src="https://iqro.forum/iqro-email-seal.png"' in html
    assert 'alt="' in html
    assert f'href="https://iqro.forum/{locale}/privacy"' in html
    assert 'href="mailto:support@iqro.forum"' in html
    assert "<link" not in html
    assert "<script" not in html
    assert "@import" not in html
    assert "fonts.googleapis" not in html
    assert f"https://iqro.forum/{locale}/privacy" in message.body
    assert "support@iqro.forum" in message.body
    # The text part is unescaped and carries no markup from the templates.
    assert not re.search(r"<(?:p|a|br|table|td|span|div)\b", message.body)
    assert "&lt;" not in message.body
    assert "&amp;" not in message.body


@pytest.mark.parametrize(
    ("locale", "subject", "expires"),
    [
        ("ru", "Ваш код входа в IQRO", "Код действует 10 минут."),
        ("en", "Your IQRO sign-in code", "The code is valid for 10 minutes."),
        ("ar", "رمز الدخول إلى IQRO", "الرمز صالح لمدة 10 دقائق."),
        ("tr", "IQRO giriş kodunuz", "Kod 10 dakika geçerlidir."),
    ],
)
def test_login_code_email_renders_in_each_locale(locale: str, subject: str, expires: str) -> None:
    delivered = send_login_code_email(
        email="reader@example.com",
        code="482913",
        ttl_seconds=600,
        locale=locale,
    )

    message, html = _sent()
    assert delivered == 1
    assert message.to == ["reader@example.com"]
    assert message.subject == subject
    assert "482913" not in message.subject
    _assert_layout(message, html, locale)
    for body in (message.body, html):
        assert expires in body
        assert "reader@example.com" in body
    assert re.search(r"\b([0-9]{6})\b", message.body).group(1) == "482913"  # type: ignore[union-attr]
    assert '<span class="iq-code" dir="ltr"' in html
    assert ">482913</span>" in html
    # The code email offers no action beyond the code: no buttons, no code in any link.
    hrefs = re.findall(r'href="([^"]+)"', html)
    assert all("482913" not in href for href in hrefs)
    assert all("/login" not in href and "/profile" not in href for href in hrefs)
    assert '<span dir="ltr">reader@example.com</span>' in html


def test_login_code_email_falls_back_to_russian_and_pluralizes() -> None:
    send_login_code_email(email="reader@example.com", code="000123", ttl_seconds=60, locale="de")

    message, html = _sent()
    assert message.subject == "Ваш код входа в IQRO"
    assert "Код действует 1 минуту." in message.body
    assert '<html lang="ru" dir="ltr">' in html
    assert email_locale(None, "", "xx") == "ru"
    assert email_locale(None, "tr", "en") == "tr"
    assert [_minutes("ru", n) for n in (1, 2, 5, 11, 21, 22, 112)] == [
        "1 минуту",
        "2 минуты",
        "5 минут",
        "11 минут",
        "21 минуту",
        "22 минуты",
        "112 минут",
    ]
    assert [_minutes("ar", n) for n in (1, 2, 10, 15)] == [
        "دقيقة واحدة",
        "دقيقتين",
        "10 دقائق",
        "15 دقيقة",
    ]
    assert [_minutes("en", n) for n in (1, 10)] == ["1 minute", "10 minutes"]


@override_settings(LEGAL_CONTACT_EMAIL="")
def test_footer_links_to_contacts_page_without_support_address() -> None:
    send_login_code_email(email="reader@example.com", code="482913", ttl_seconds=600, locale="en")

    message, html = _sent()
    assert 'href="https://iqro.forum/en/contacts"' in html
    assert "mailto:" not in html
    assert "https://iqro.forum/en/contacts" in message.body


def _ticket(locale: str, subject: str = "Код <b>не</b> приходит & всё") -> FeedbackTicket:
    return FeedbackTicket(
        public_id="FB-7K2Q9M",
        subject=subject,
        locale=locale,
        category="technical",
        reporter=User(email="reader@example.com"),
    )


@pytest.mark.parametrize(
    ("locale", "subject", "button"),
    [
        ("ru", "Ответ по обращению FB-7K2Q9M — IQRO", "Открыть обращение"),
        ("en", "Reply to your request FB-7K2Q9M — IQRO", "Open request"),
        ("ar", "رد على طلبك FB-7K2Q9M — IQRO", "فتح الطلب"),
        ("tr", "FB-7K2Q9M numaralı talebinize yanıt — IQRO", "Talebi aç"),
    ],
)
def test_feedback_reply_email_renders_in_each_locale(
    locale: str,
    subject: str,
    button: str,
) -> None:
    delivered = send_reporter_notification_email(
        recipient="reader@example.com",
        ticket=_ticket(locale),
    )

    message, html = _sent()
    profile_url = f"https://iqro.forum/{locale}/profile#feedback"
    assert delivered == 1
    assert message.subject == subject
    _assert_layout(message, html, locale)
    assert f'href="{profile_url}"' in html
    assert f">{button}</a>" in html
    assert profile_url in message.body
    assert "FB-7K2Q9M" in message.body
    assert "Код &lt;b&gt;не&lt;/b&gt; приходит &amp; всё" in html
    assert "Код <b>не</b> приходит" not in html
    assert "Код <b>не</b> приходит & всё" in message.body


def test_feedback_operator_email_is_russian_and_escapes_user_text() -> None:
    ticket = _ticket("ar", subject="Ошибка <img src=x>")
    message_body = "Первая строка\n<script>alert(1)</script>"

    delivered = send_operator_notification_email(
        recipient="operator@example.com",
        ticket=ticket,
        message=FeedbackMessage(body=message_body),
        event="created",
    )

    message, html = _sent()
    admin_url = f"https://iqro.forum/admin/feedback/feedbackticket/{ticket.id}/change/"
    assert delivered == 1
    assert message.to == ["operator@example.com"]
    assert message.subject == "[IQRO] Новое обращение: FB-7K2Q9M"
    _assert_layout(message, html, "ru")
    assert "Категория: Техническая проблема" in message.body
    assert "Команда: не назначена" in message.body
    assert message_body in message.body
    assert admin_url in message.body
    assert f'href="{admin_url}"' in html
    assert "Первая строка<br>&lt;script&gt;alert(1)&lt;/script&gt;" in html
    assert "Ошибка &lt;img src=x&gt;" in html


def _bootstrap(client: APIClient, locale: str) -> dict[str, Any]:
    response = client.post(
        reverse("accounts:guest-bootstrap"),
        {
            "installation_id": str(uuid.uuid4()),
            "installation_credential": "A" * 43,
            "platform": "web",
            "locale": locale,
            "app_version": "1.0.0",
        },
        format="json",
    )
    assert response.status_code == 200
    return cast(dict[str, Any], response.json())


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("installation_locale", "requested", "subject", "direction"),
    [
        ("ru", "ar", "رمز الدخول إلى IQRO", "rtl"),
        ("ar", "en", "Your IQRO sign-in code", "ltr"),
        ("tr", None, "IQRO giriş kodunuz", "ltr"),
    ],
)
def test_email_start_sends_code_in_requested_or_installation_locale(
    api_client: APIClient,
    installation_locale: str,
    requested: str | None,
    subject: str,
    direction: str,
) -> None:
    session = _bootstrap(api_client, installation_locale)
    payload = {"email": "reader@example.com"}
    if requested is not None:
        payload["locale"] = requested

    response = api_client.post(
        reverse("accounts:email-start"),
        payload,
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
    )

    assert response.status_code == 202, response.data
    message, html = _sent()
    assert message.subject == subject
    assert f'dir="{direction}"' in html


@pytest.mark.django_db
def test_email_start_rejects_unsupported_locale(api_client: APIClient) -> None:
    session = _bootstrap(api_client, "ru")

    response = api_client.post(
        reverse("accounts:email-start"),
        {"email": "reader@example.com", "locale": "de"},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
    )

    assert response.status_code == 400
    assert mail.outbox == []
