from __future__ import annotations

# Russian and Turkish copy intentionally contains letters that resemble Latin glyphs.
# ruff: noqa: RUF001
from django.utils.html import format_html
from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.core.emails import email_locale, send_email

_LOGIN_CODE_COPY = {
    "ru": {
        "subject": "Ваш код входа в IQRO",
        "title": "Код для входа в IQRO",
        "intro": (
            "Введите этот код на сайте или в приложении IQRO, чтобы подтвердить адрес {email}."
        ),
        "expires": "Код действует {duration}.",
        "ignore": (
            "Если вы не запрашивали код, просто проигнорируйте это письмо: "
            "без кода никто не войдёт в аккаунт с вашим адресом."
        ),
        "security": "Никому не сообщайте код. Команда IQRO никогда его не спрашивает.",
        "reason": (
            "Вы получили это письмо, потому что на сайте или в приложении IQRO "
            "запросили код для адреса {email}."
        ),
    },
    "en": {
        "subject": "Your IQRO sign-in code",
        "title": "Your IQRO sign-in code",
        "intro": "Enter this code on the IQRO website or app to confirm {email}.",
        "expires": "The code is valid for {duration}.",
        "ignore": (
            "If you did not request a code, simply ignore this email: "
            "nobody can sign in with your address without it."
        ),
        "security": "Never share this code. The IQRO team will never ask you for it.",
        "reason": (
            "You received this email because a code for {email} was requested "
            "on the IQRO website or app."
        ),
    },
    "ar": {
        "subject": "رمز الدخول إلى IQRO",
        "title": "رمز الدخول إلى IQRO",
        "intro": "أدخل هذا الرمز في موقع IQRO أو تطبيقه لتأكيد العنوان {email}.",
        "expires": "الرمز صالح لمدة {duration}.",
        "ignore": ("إذا لم تطلب الرمز فتجاهل هذه الرسالة، فلا يمكن لأحد الدخول بعنوانك من دونه."),
        "security": "لا تشارك هذا الرمز مع أحد، ففريق IQRO لن يطلبه منك أبدًا.",
        "reason": "وصلتك هذه الرسالة لأن رمزًا طُلب للعنوان {email} عبر موقع IQRO أو تطبيقه.",
    },
    "tr": {
        "subject": "IQRO giriş kodunuz",
        "title": "IQRO giriş kodunuz",
        "intro": (
            "{email} adresini doğrulamak için bu kodu IQRO web sitesine veya uygulamasına girin."
        ),
        "expires": "Kod {duration} geçerlidir.",
        "ignore": (
            "Kodu siz istemediyseniz bu e-postayı dikkate almayın: "
            "kod olmadan kimse adresinizle giriş yapamaz."
        ),
        "security": "Bu kodu kimseyle paylaşmayın. IQRO ekibi kodu asla sormaz.",
        "reason": (
            "Bu e-postayı, IQRO web sitesinde veya uygulamasında {email} adresi için "
            "kod istendiği için aldınız."
        ),
    },
}


@sensitive_variables("code")
def send_login_code_email(*, email: str, code: str, ttl_seconds: int, locale: str | None) -> int:
    """Send the one-time code. No sign-in button or link: typing the code is the only action."""
    locale = email_locale(locale)
    copy = _LOGIN_CODE_COPY[locale]
    expires = copy["expires"].format(duration=_minutes(locale, max(1, ttl_seconds // 60)))
    # The address sits inside right-to-left text in Arabic; isolate it.
    email_html = format_html('<span dir="ltr">{}</span>', email)
    return send_email(
        to=email,
        template="login_code",
        locale=locale,
        subject=copy["subject"],
        context={
            "preheader": expires,
            "reason": copy["reason"].format(email=email),
            "title": copy["title"],
            "intro": copy["intro"].format(email=email),
            "intro_html": format_html(copy["intro"], email=email_html),
            "reason_html": format_html(copy["reason"], email=email_html),
            "code": code,
            "expires": expires,
            "ignore": copy["ignore"],
            "security": copy["security"],
        },
    )


def _minutes(locale: str, count: int) -> str:
    if locale == "ar":
        return _arabic_minutes(count)
    if locale == "ru":
        if count % 10 == 1 and count % 100 != 11:
            word = "минуту"
        elif 2 <= count % 10 <= 4 and not 12 <= count % 100 <= 14:
            word = "минуты"
        else:
            word = "минут"
    elif locale == "tr":
        word = "dakika"
    else:
        word = "minute" if count == 1 else "minutes"
    return f"{count} {word}"


def _arabic_minutes(count: int) -> str:
    # One and two are spelled out; 3-10 take the plural, everything else the singular.
    if count == 1:
        return "دقيقة واحدة"
    if count == 2:
        return "دقيقتين"
    return f"{count} {'دقائق' if 3 <= count % 100 <= 10 else 'دقيقة'}"
