"""One message to the owner's Telegram group through the Bot API.

The token is part of the request URL, so it lives only inside `_post`: no
exception, log line or Sentry frame raised from here carries it
(error_reporting.py also drops Sentry breadcrumbs of these requests).
"""

from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from django.conf import settings

API_ORIGIN = "https://api.telegram.org"
TIMEOUT_SECONDS = 10
# Telegram refuses texts over 4096 characters.
MAX_TEXT = 4000


class TelegramSendError(Exception):
    """Telegram did not take the message; worth retrying later."""


class TelegramConfigError(TelegramSendError):
    """Telegram refused the token or the chat: retrying will not help."""


def is_configured() -> bool:
    return bool(settings.TELEGRAM_BOT_TOKEN and settings.TELEGRAM_ALERT_CHAT_ID)


def send_message(text: str) -> None:
    if not is_configured():
        raise TelegramConfigError("TELEGRAM_BOT_TOKEN или TELEGRAM_ALERT_CHAT_ID не заданы")
    if len(text) > MAX_TEXT:
        text = text[: MAX_TEXT - 1] + "…"
    status = _post(
        {
            "chat_id": settings.TELEGRAM_ALERT_CHAT_ID,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
    )
    if status is None:
        raise TelegramSendError("Telegram не ответил")
    if status in {400, 401, 403, 404}:
        raise TelegramConfigError(
            f"Telegram ответил HTTP {status}: проверьте токен, chat id и что бот в группе"
        )
    if not 200 <= status < 300:
        raise TelegramSendError(f"Telegram ответил HTTP {status}")


def _post(payload: dict[str, object]) -> int | None:
    """The HTTP status, or None when Telegram could not be reached."""
    request = Request(  # noqa: S310 - a fixed https origin
        f"{API_ORIGIN}/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310
            return int(response.status)
    except HTTPError as error:
        status = int(error.code)
        error.close()
        return status
    except URLError, TimeoutError, OSError:
        return None
