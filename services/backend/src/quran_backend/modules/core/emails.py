from __future__ import annotations

# Turkish copy intentionally contains the dotless i.
# ruff: noqa: RUF001
import re
from collections.abc import Mapping
from urllib.parse import urlsplit

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils.safestring import mark_safe

EMAIL_LOCALES = ("ru", "en", "ar", "tr")
DEFAULT_EMAIL_LOCALE = "ru"
# Served by the website from services/web/public. Mail clients handle PNG far
# better than WebP, and the 192 px file stays sharp at the 96 px it is shown.
EMAIL_LOGO_PATH = "/iqro-email-seal.png"

_LAYOUT_COPY = {
    "ru": {
        "logo_alt": "IQRO — печать",
        "privacy_label": "Политика конфиденциальности",
        "support_label": "Поддержка",
        "button_fallback": "Если кнопка не открывается, скопируйте ссылку в браузер:",
        "tagline": "IQRO — Коран, намаз и знания",
    },
    "en": {
        "logo_alt": "IQRO seal",
        "privacy_label": "Privacy Policy",
        "support_label": "Support",
        "button_fallback": "If the button does not open, copy this link into your browser:",
        "tagline": "IQRO — Quran, prayer and knowledge",
    },
    "ar": {
        "logo_alt": "ختم IQRO",
        "privacy_label": "سياسة الخصوصية",
        "support_label": "الدعم",
        "button_fallback": "إذا لم يفتح الزر، فانسخ هذا الرابط إلى المتصفح:",
        "tagline": "IQRO — القرآن والصلاة والعلم",
    },
    "tr": {
        "logo_alt": "IQRO mührü",
        "privacy_label": "Gizlilik Politikası",
        "support_label": "Destek",
        "button_fallback": "Düğme açılmazsa bu bağlantıyı tarayıcınıza kopyalayın:",
        "tagline": "IQRO — Kur'an, namaz ve ilim",
    },
}
# Unquoted family names keep the stacks safe inside style="" attributes.
_LATIN_FONTS = mark_safe(
    "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"
)
_ARABIC_FONTS = mark_safe(
    "Segoe UI, Tahoma, Geeza Pro, Noto Naskh Arabic, Noto Sans Arabic, Arial, sans-serif"
)


def email_locale(*candidates: str | None) -> str:
    """Return the first supported candidate; Russian is the house default."""
    for candidate in candidates:
        if candidate in EMAIL_LOCALES:
            return candidate
    return DEFAULT_EMAIL_LOCALE


def render_email(
    template: str,
    *,
    locale: str,
    subject: str,
    context: Mapping[str, object],
) -> tuple[str, str]:
    """Render the plain-text and HTML bodies of emails/<template>.{txt,html}.

    The context also fills the layout: ``preheader`` (inbox preview line) and
    ``reason`` (why the recipient got the email) are expected in every email.
    """
    site_url = settings.PUBLIC_SITE_URL
    support_email = settings.LEGAL_CONTACT_EMAIL
    rtl = locale == "ar"
    full_context = {
        **_LAYOUT_COPY[locale],
        "lang": locale,
        "dir": "rtl" if rtl else "ltr",
        "align": "right" if rtl else "left",
        "font_stack": _ARABIC_FONTS if rtl else _LATIN_FONTS,
        "subject": subject,
        "logo_url": f"{site_url}{EMAIL_LOGO_PATH}",
        "site_label": urlsplit(site_url).netloc,
        "home_url": f"{site_url}/{locale}",
        "privacy_url": f"{site_url}/{locale}/privacy",
        "support_email": support_email,
        "support_url": (
            f"mailto:{support_email}" if support_email else f"{site_url}/{locale}/contacts"
        ),
        **context,
    }
    text = render_to_string(f"emails/{template}.txt", full_context)
    html = render_to_string(f"emails/{template}.html", full_context)
    return _tidy_text(text), html


def send_email(
    *,
    to: str,
    template: str,
    locale: str,
    subject: str,
    context: Mapping[str, object],
) -> int:
    text, html = render_email(template, locale=locale, subject=subject, context=context)
    message = EmailMultiAlternatives(
        subject=subject,
        body=text,
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[to],
    )
    message.attach_alternative(html, "text/html")
    return message.send()


def _tidy_text(text: str) -> str:
    # Template tags leave trailing spaces and runs of blank lines behind.
    lines = [line.rstrip() for line in text.strip().splitlines()]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)) + "\n"
