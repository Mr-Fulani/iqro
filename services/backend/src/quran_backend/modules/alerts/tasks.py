from __future__ import annotations

import logging
from typing import Any

from celery import shared_task

from quran_backend.modules.alerts import telegram
from quran_backend.modules.alerts.services import error_repeats_text, overflow_text

logger = logging.getLogger(__name__)

MAX_RETRIES = 5


@shared_task(  # type: ignore[untyped-decorator]
    name="alerts.send", bind=True, ignore_result=True, max_retries=MAX_RETRIES
)
def send_alert(self: Any, text: str) -> None:
    """Sends one alert; a busy or unreachable Telegram is retried for about half an hour."""
    try:
        telegram.send_message(text)
    except telegram.TelegramConfigError as error:
        # A warning, not an error: an error would be one more alert to the same broken chat.
        logger.warning("Telegram alert refused: %s", error)
    except telegram.TelegramSendError as error:
        if self.request.retries >= MAX_RETRIES:
            logger.warning("Telegram alert dropped after retries: %s", error)
            return
        raise self.retry(countdown=min(600, 30 * 2**self.request.retries)) from None


@shared_task(name="alerts.send_overflow_summary", ignore_result=True)  # type: ignore[untyped-decorator]
def send_overflow_summary(window: int) -> None:
    text = overflow_text(window)
    if text is not None:
        send_alert.delay(text)


@shared_task(name="alerts.send_error_repeats", ignore_result=True)  # type: ignore[untyped-decorator]
def send_error_repeats(fingerprint: str, title: str) -> None:
    text = error_repeats_text(fingerprint, title)
    if text is not None:
        send_alert.delay(text)
