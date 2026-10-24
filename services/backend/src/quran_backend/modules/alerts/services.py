# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Alerts to the owner's Telegram group (docs/alerts.md).

`notify` never raises and never blocks the request: the message goes after
commit to a Celery task with retries. Without TELEGRAM_BOT_TOKEN and
TELEGRAM_ALERT_CHAT_ID nothing is sent and nothing else changes.

Against a flood: at most RATE_LIMIT messages in a RATE_WINDOW_SECONDS window,
then one summary «и ещё N» when the window ends. A server error is sent once
per ERROR_REPEAT_SECONDS; how often it came back follows in one more message.
"""

from __future__ import annotations

import logging
import time
from html import escape
from typing import Any

from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.urls import reverse
from django.utils import translation

from quran_backend.modules.alerts import telegram

logger = logging.getLogger(__name__)

RATE_LIMIT = 20
RATE_WINDOW_SECONDS = 10 * 60
ERROR_REPEAT_SECONDS = 30 * 60
TEXT_PREVIEW = 300


def notify(text: str) -> None:
    """Sends `text` (Telegram HTML) once the current transaction commits."""
    if not telegram.is_configured():
        return
    transaction.on_commit(lambda: _enqueue(text))


def notify_now(text: str) -> None:
    """Sends `text` without waiting for a commit, and without opening a database connection."""
    if telegram.is_configured():
        _enqueue(text)


def _window_key(window: int) -> str:
    return f"alerts:window:{window}"


def _take_slot(now: float) -> int:
    """This message's number in the current window, counting from 1."""
    key = _window_key(int(now // RATE_WINDOW_SECONDS))
    cache.add(key, 0, timeout=RATE_WINDOW_SECONDS * 2)
    return int(cache.incr(key))


def _enqueue(text: str) -> None:
    from quran_backend.modules.alerts.tasks import (  # noqa: PLC0415
        send_alert,
        send_overflow_summary,
    )

    try:
        now = time.time()
        number = _take_slot(now)
        if number <= RATE_LIMIT:
            send_alert.delay(text)
        elif number == RATE_LIMIT + 1:
            window = int(now // RATE_WINDOW_SECONDS)
            ends_in = (window + 1) * RATE_WINDOW_SECONDS - now
            send_overflow_summary.apply_async(args=[window], countdown=int(ends_in) + 1)
    except Exception:
        logger.warning("Telegram alert was not queued", exc_info=True)


def overflow_text(window: int) -> str | None:
    """The «и ещё N» summary of a window, or None when nothing was held back."""
    held_back = int(cache.get(_window_key(window)) or 0) - RATE_LIMIT
    if held_back <= 0:
        return None
    return (
        f"⚠️ <b>И ещё {held_back} уведомлений</b> за 10 минут не отправлены, "
        f"чтобы не засыпать чат (лимит {RATE_LIMIT}). Подробности — в Sentry и в админке."
    )


def report_error(fingerprint: str, text: str, title: str) -> None:
    """A server error: the first in ERROR_REPEAT_SECONDS goes out, the rest are counted."""
    if not telegram.is_configured():
        return
    gate = f"alerts:error:{fingerprint}"
    if cache.add(gate, 1, timeout=ERROR_REPEAT_SECONDS):
        from quran_backend.modules.alerts.tasks import send_error_repeats  # noqa: PLC0415

        cache.set(_repeats_key(fingerprint), 0, timeout=ERROR_REPEAT_SECONDS * 2)
        # Not after commit: the transaction around an error is usually rolled back.
        _enqueue(text)
        send_error_repeats.apply_async(args=[fingerprint, title], countdown=ERROR_REPEAT_SECONDS)
        return
    try:
        cache.incr(_repeats_key(fingerprint))
    except ValueError:
        cache.set(_repeats_key(fingerprint), 1, timeout=ERROR_REPEAT_SECONDS * 2)


def _repeats_key(fingerprint: str) -> str:
    return f"alerts:error-repeats:{fingerprint}"


def error_repeats_text(fingerprint: str, title: str) -> str | None:
    repeats = int(cache.get(_repeats_key(fingerprint)) or 0)
    cache.delete(_repeats_key(fingerprint))
    if repeats <= 0:
        return None
    return (
        f"🔁 <b>Ошибка повторилась ещё {repeats} раз</b> за 30 минут\n{escape(title)}\n"
        "Следующее появление снова придёт отдельным сообщением."
    )


# Events -----------------------------------------------------------------------


def admin_url(viewname: str, *args: Any) -> str:
    return f"{settings.PUBLIC_SITE_URL}{reverse(viewname, args=args)}"


def _preview(value: str) -> str:
    value = " ".join(value.split())
    if len(value) > TEXT_PREVIEW:
        value = value[: TEXT_PREVIEW - 1] + "…"
    return escape(value)


def _message(headline: str, *lines: str, link: str = "") -> str:
    parts = [f"<b>{escape(headline)}</b>", *[line for line in lines if line]]
    if link:
        parts.append(escape(link))
    return "\n".join(parts)


def feedback_ticket_created(ticket: Any, body: str) -> None:
    from quran_backend.modules.feedback.models import FeedbackCategory  # noqa: PLC0415

    with translation.override("ru"):
        category = translation.gettext(FeedbackCategory(ticket.category).label)
    religious = ticket.category == FeedbackCategory.RELIGIOUS_CONTENT
    notify(
        _message(
            "🕌 Новое обращение · Религиозное содержание" if religious else "📩 Новое обращение",
            f"Категория: {escape(category)}",
            f"{escape(ticket.public_id)}: {_preview(ticket.subject)}",
            _preview(body),
            link=admin_url("admin:feedback_feedbackticket_change", ticket.pk),
        )
    )


def _who(user: Any) -> str:
    return f"Кто: {escape(str(user))}" if user is not None else ""


def course_release_event(release: Any, event: str, user: Any = None, note: str = "") -> None:
    """A course release: «in_review» waits for a signature, «published», «hidden»."""
    headlines = {
        "in_review": "🟡 Выпуск курса ждёт подписи",
        "published": "🟢 Курс опубликован",
        "hidden": "⚪️ Курс скрыт с сайта",
        "shown": "🟢 Курс снова на сайте",
        "rolled_back": "↩️ Курс возвращён к прежнему выпуску",
    }
    notify(
        _message(
            headlines[event],
            f"«{escape(str(release.course))}», выпуск {release.number}",
            _preview(note) if note else "",
            _who(user),
            link=admin_url("admin:courses_courserelease_change", release.pk),
        )
    )


def course_version_event(version: Any, event: str, user: Any = None) -> None:
    """A tajweed or salah course version: «draft» waits for a signature, «published»."""
    course = "Таджвид" if version._meta.app_label == "tajweed" else "Обучение намазу"
    headlines = {
        "draft": f"🟡 {course}: новая версия ждёт подписи",
        "published": f"🟢 {course}: версия опубликована",
    }
    notify(
        _message(
            headlines[event],
            f"Версия {escape(str(version))}",
            _who(user),
            link=admin_url(
                f"admin:{version._meta.app_label}_{version._meta.model_name}_change", version.pk
            ),
        )
    )


def video_upload_failed(lesson: Any, what: str, reason: str, user: Any = None) -> None:
    notify(
        _message(
            f"🎬 Не удалось загрузить {what}",
            f"Тема «{escape(str(lesson))}» курса «{escape(str(lesson.course))}»",
            f"Причина: {_preview(reason)}",
            _who(user),
            link=admin_url("admin:courses_courselesson_change", lesson.pk),
        )
    )
