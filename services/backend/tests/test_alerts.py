# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
from __future__ import annotations

import copy
import logging
import uuid
from collections.abc import Iterator
from io import StringIO
from typing import Any
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError

import pytest
from celery.exceptions import Retry
from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import Client

from quran_backend.modules.accounts.models import User
from quran_backend.modules.alerts import beat, services, tasks, telegram
from quran_backend.modules.alerts.logging import TelegramAlertHandler, process_role
from quran_backend.modules.courses.models import Course, CourseLesson
from quran_backend.modules.courses.services import (
    hide_course,
    prepare_release,
    publish_release,
    sign_release,
)
from quran_backend.modules.feedback.services import create_ticket
from quran_backend.modules.tajweed.course import load_course_snapshot
from quran_backend.modules.tajweed.course_publication import (
    copy_tajweed_course,
    import_tajweed_course,
    publish_tajweed_course,
    sign_tajweed_course,
)

TOKEN = "123456:test-only-token"
POST = "quran_backend.modules.alerts.telegram._post"


@pytest.fixture
def telegram_on(settings: Any) -> Iterator[None]:
    settings.TELEGRAM_BOT_TOKEN = TOKEN
    settings.TELEGRAM_ALERT_CHAT_ID = "-100500"
    cache.clear()
    yield
    cache.clear()


@pytest.fixture
def sent(telegram_on: None) -> Iterator[list[str]]:
    """Texts that reached Telegram's API, in order."""
    texts: list[str] = []

    def fake_post(payload: dict[str, Any]) -> int:
        assert payload["chat_id"] == "-100500"
        texts.append(str(payload["text"]))
        return 200

    with patch(POST, side_effect=fake_post):
        yield texts


@pytest.fixture
def scheduled() -> Iterator[dict[str, MagicMock]]:
    """Delayed summaries are captured instead of running at once in eager mode."""
    with (
        patch.object(tasks.send_overflow_summary, "apply_async") as overflow,
        patch.object(tasks.send_error_repeats, "apply_async") as repeats,
    ):
        yield {"overflow": overflow, "repeats": repeats}


# Sending -----------------------------------------------------------------------


def test_without_token_and_chat_nothing_is_sent(settings: Any) -> None:
    settings.TELEGRAM_BOT_TOKEN = ""
    settings.TELEGRAM_ALERT_CHAT_ID = "-100500"
    with patch(POST) as post:
        services.notify_now("text")
        services.report_error("fingerprint", "text", "title")
    post.assert_not_called()
    assert not telegram.is_configured()


def test_test_command_refuses_without_settings(settings: Any) -> None:
    settings.TELEGRAM_BOT_TOKEN = ""
    with pytest.raises(CommandError, match="TELEGRAM_BOT_TOKEN"):
        call_command("send_test_alert")


def test_test_command_sends_directly(sent: list[str]) -> None:
    out = StringIO()
    call_command("send_test_alert", stdout=out)
    assert "Отправлено" in out.getvalue()
    assert "Проверка уведомлений IQRO" in sent[0]


def test_test_command_explains_a_refusal_without_the_token(telegram_on: None) -> None:
    with patch(POST, return_value=403), pytest.raises(CommandError) as error:
        call_command("send_test_alert")
    assert "HTTP 403" in str(error.value)
    assert TOKEN not in str(error.value)


def test_token_is_only_in_the_request_url(telegram_on: None) -> None:
    requests: list[Any] = []

    def fake_urlopen(request: Any, timeout: float) -> Any:
        requests.append(request)
        response = MagicMock()
        response.__enter__.return_value.status = 200
        return response

    with patch("quran_backend.modules.alerts.telegram.urlopen", side_effect=fake_urlopen):
        telegram.send_message("<b>hello</b>")
    (request,) = requests
    assert request.full_url == f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    assert TOKEN not in request.data.decode()


def test_telegram_errors_never_carry_the_token(telegram_on: None) -> None:
    def refuse(request: Any, timeout: float) -> Any:
        raise HTTPError(request.full_url, 502, "Bad gateway", {}, None)  # type: ignore[arg-type]

    with (
        patch("quran_backend.modules.alerts.telegram.urlopen", side_effect=refuse),
        pytest.raises(telegram.TelegramSendError) as error,
    ):
        telegram.send_message("text")
    assert str(error.value) == "Telegram ответил HTTP 502"
    assert error.value.__context__ is None
    assert error.value.__cause__ is None


def test_task_retries_a_busy_telegram_and_gives_up_on_a_refusal(telegram_on: None) -> None:
    for status in (None, 429, 502):
        with (
            patch(POST, return_value=status),
            patch.object(tasks.send_alert, "retry", side_effect=Retry()) as retry,
            pytest.raises(Retry),
        ):
            tasks.send_alert("text")
        retry.assert_called_once_with(countdown=30)
    with (
        patch.object(tasks.logger, "warning") as warning,
        patch(POST, return_value=400) as post,
        patch.object(tasks.send_alert, "retry") as retry,
    ):
        tasks.send_alert("text")
    post.assert_called_once()
    retry.assert_not_called()
    logged = warning.call_args.args[0] % warning.call_args.args[1:]
    assert logged.startswith("Telegram alert refused: Telegram ответил HTTP 400")
    assert TOKEN not in logged


def test_task_backs_off_and_drops_the_message_after_its_retries(telegram_on: None) -> None:
    tasks.send_alert.push_request(retries=3)
    try:
        with (
            patch(POST, return_value=None),
            patch.object(tasks.send_alert, "retry", side_effect=Retry()) as retry,
            pytest.raises(Retry),
        ):
            tasks.send_alert.run("text")
        retry.assert_called_once_with(countdown=240)
        tasks.send_alert.request.retries = tasks.MAX_RETRIES
        with patch.object(tasks.logger, "warning") as warning, patch(POST, return_value=None):
            tasks.send_alert.run("text")
    finally:
        tasks.send_alert.pop_request()
    logged = warning.call_args.args[0] % warning.call_args.args[1:]
    assert logged == "Telegram alert dropped after retries: Telegram не ответил"


# Flood protection --------------------------------------------------------------


def test_twenty_messages_in_ten_minutes_then_one_summary(
    sent: list[str], scheduled: dict[str, MagicMock]
) -> None:
    # The cache reads the same clock, so the whole window stays inside the patch.
    with patch("quran_backend.modules.alerts.services.time.time", return_value=6000.0):
        for number in range(25):
            services.notify_now(f"message {number}")
        assert sent == [f"message {number}" for number in range(20)]
        scheduled["overflow"].assert_called_once_with(args=[10], countdown=601)

        tasks.send_overflow_summary(10)
    assert "И ещё 5 уведомлений" in sent[-1]
    with patch("quran_backend.modules.alerts.services.time.time", return_value=6600.0):
        services.notify_now("next window")
    assert sent[-1] == "next window"


def test_no_summary_when_nothing_was_held_back(sent: list[str]) -> None:
    tasks.send_overflow_summary(99)
    assert sent == []


# Server errors -------------------------------------------------------------------


def _log_error(logger: logging.Logger, value: int) -> None:
    try:
        raise ValueError(f"broken value {value}")
    except ValueError:
        logger.exception("Import of %s failed", value)


@pytest.fixture
def alert_logger() -> Iterator[logging.Logger]:
    logger = logging.getLogger("quran_backend.tests.alert_probe")
    handler = TelegramAlertHandler()
    logger.addHandler(handler)
    logger.propagate = False
    yield logger
    logger.removeHandler(handler)
    logger.propagate = True


def test_same_error_is_sent_once_in_thirty_minutes_with_a_repeat_count(
    sent: list[str], scheduled: dict[str, MagicMock], alert_logger: logging.Logger
) -> None:
    for value in range(5):
        _log_error(alert_logger, value)

    assert len(sent) == 1
    assert "Ошибка сервера · backend" in sent[0]
    assert "ValueError: broken value 0" in sent[0]
    assert "Где: test_alerts.py:" in sent[0]
    fingerprint, title = scheduled["repeats"].call_args.kwargs["args"]
    assert scheduled["repeats"].call_args.kwargs["countdown"] == services.ERROR_REPEAT_SECONDS

    tasks.send_error_repeats(fingerprint, title)
    assert "повторилась ещё 4 раз" in sent[1]
    assert "Import of 0 failed" in sent[1]
    tasks.send_error_repeats(fingerprint, title)
    assert len(sent) == 2


def test_a_different_error_is_sent_separately(
    sent: list[str], scheduled: dict[str, MagicMock], alert_logger: logging.Logger
) -> None:
    _log_error(alert_logger, 1)
    try:
        raise KeyError("other")
    except KeyError:
        alert_logger.exception("Lookup failed")
    assert len(sent) == 2


def test_noise_and_the_alerts_own_logs_are_not_alerts(
    sent: list[str], scheduled: dict[str, MagicMock]
) -> None:
    handler = TelegramAlertHandler()
    for name in ("django.security.DisallowedHost", "quran_backend.modules.alerts.tasks"):
        handler.handle(logging.LogRecord(name, logging.ERROR, __file__, 1, "noise", None, None))
    celery = logging.LogRecord(
        "celery.app.trace", logging.ERROR, __file__, 1, "Task %s failed", ("alerts.send",), None
    )
    handler.handle(celery)
    assert sent == []


def test_process_role_names_backend_worker_and_beat() -> None:
    assert process_role(["/app/.venv/bin/gunicorn", "quran_backend.wsgi"]) == "backend"
    assert process_role(["/app/.venv/bin/celery", "-A", "quran_backend.celery", "worker"]) == (
        "worker"
    )
    assert process_role(["/app/.venv/bin/celery", "-A", "quran_backend.celery", "beat"]) == "beat"


# Events ----------------------------------------------------------------------------


@pytest.mark.django_db
def test_new_religious_ticket_is_sent_after_commit(
    sent: list[str], django_capture_on_commit_callbacks: Any
) -> None:
    reporter = User.objects.create_user(preferred_locale="ru")
    body = "Проверьте перевод аята. " * 30
    with django_capture_on_commit_callbacks(execute=True):
        ticket, _ = create_ticket(
            reporter,
            {
                "client_request_id": str(uuid.uuid7()),
                "client_message_id": str(uuid.uuid7()),
                "category": "religious_content",
                "subject": "Перевод 2:255",
                "message": body,
                "locale": "ru",
                "context": {},
            },
            channel="web",
        )
    (text,) = sent
    assert "Новое обращение · Религиозное содержание" in text
    assert "Категория: Замечание к религиозному содержанию" in text
    assert f"{ticket.public_id}: Перевод 2:255" in text
    preview = text.split("\n")[3]
    assert len(preview) == services.TEXT_PREVIEW
    assert preview.endswith("…")
    assert text.endswith(f"/admin/feedback/feedbackticket/{ticket.pk}/change/")


@pytest.mark.django_db
def test_ordinary_ticket_has_no_religious_mark(
    sent: list[str], django_capture_on_commit_callbacks: Any
) -> None:
    reporter = User.objects.create_user()
    with django_capture_on_commit_callbacks(execute=True):
        create_ticket(
            reporter,
            {
                "client_request_id": str(uuid.uuid7()),
                "client_message_id": str(uuid.uuid7()),
                "category": "technical",
                "subject": "Не играет звук",
                "message": "После обновления.",
                "locale": "ru",
                "context": {},
            },
            channel="android",
        )
    assert sent[0].startswith("<b>📩 Новое обращение</b>")
    assert "Религиозное" not in sent[0]


@pytest.mark.django_db
def test_ticket_is_not_sent_when_the_transaction_rolls_back(
    sent: list[str], django_capture_on_commit_callbacks: Any
) -> None:
    with django_capture_on_commit_callbacks(execute=False) as callbacks:
        services.notify("rolled back")
    assert len(callbacks) == 1
    assert sent == []


@pytest.fixture
def course(db: None) -> Course:
    course = Course.objects.create(slug="ramadan", title_ru="Рамадан", summary_ru="Пост.")
    CourseLesson.objects.create(
        course=course, slug="smysl-posta", title_ru="Смысл поста", notes_ru="Пост."
    )
    return course


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="alerts-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


@pytest.mark.django_db
def test_course_release_waits_is_published_and_hidden(
    sent: list[str], course: Course, owner: User, django_capture_on_commit_callbacks: Any
) -> None:
    with django_capture_on_commit_callbacks(execute=True):
        release = prepare_release(course, owner, languages=["ru"], change_note="Первый выпуск")
        sign_release(release, owner)
        publish_release(release, owner)
        hide_course(course, owner, reason="Ошибка в теме")
    assert [text.split("\n")[0] for text in sent] == [
        "<b>🟡 Выпуск курса ждёт подписи</b>",
        "<b>🟢 Курс опубликован</b>",
        "<b>⚪️ Курс скрыт с сайта</b>",
    ]
    assert "«Рамадан», выпуск 1" in sent[0]
    assert "Первый выпуск" in sent[0]
    assert "Ошибка в теме" in sent[2]
    assert sent[1].endswith(f"/admin/courses/courserelease/{release.pk}/change/")


@pytest.mark.django_db
def test_tajweed_draft_waits_for_signature_and_is_published(
    sent: list[str], owner: User, django_capture_on_commit_callbacks: Any
) -> None:
    first = import_tajweed_course(copy.deepcopy(load_course_snapshot()))
    sign_tajweed_course(first, owner)
    with django_capture_on_commit_callbacks(execute=True):
        publish_tajweed_course(first)
        draft = copy_tajweed_course(first, "2026-11-01")
    assert [text.split("\n")[0] for text in sent] == [
        "<b>🟢 Таджвид: версия опубликована</b>",
        "<b>🟡 Таджвид: новая версия ждёт подписи</b>",
    ]
    assert sent[1].endswith(f"/admin/tajweed/tajweedcourseversion/{draft.pk}/change/")


@pytest.mark.django_db
def test_failed_video_upload_is_an_alert(
    sent: list[str], course: Course, owner: User, django_capture_on_commit_callbacks: Any
) -> None:
    client = Client()
    client.force_login(owner)
    lesson = course.lessons.get()
    with django_capture_on_commit_callbacks(execute=True):
        response = client.post(f"/admin/courses/courselesson/{lesson.pk}/video/upload/")
    assert response.status_code == 400
    (text,) = sent
    assert "Не удалось загрузить видео" in text
    assert "Причина: Файл не получен." in text
    assert "Смысл поста" in text


# Celery beat -----------------------------------------------------------------------


def test_beat_silence_is_sent_once_after_five_minutes_and_its_return_once(
    sent: list[str],
) -> None:
    with patch.object(beat, "beat_alive", return_value=False):
        beat.check_beat(now=1000.0)
        beat.check_beat(now=1200.0)
        assert sent == []
        beat.check_beat(now=1300.0)
        beat.check_beat(now=1900.0)
    assert len(sent) == 1
    assert "Celery beat не отвечает 5 мин" in sent[0]
    with patch.object(beat, "beat_alive", return_value=True):
        beat.check_beat(now=2000.0)
        beat.check_beat(now=2060.0)
    assert len(sent) == 2
    assert "снова работает" in sent[1]


def test_beat_check_is_quiet_when_redis_cannot_be_asked(sent: list[str]) -> None:
    with patch.object(beat, "beat_alive", return_value=None):
        beat.check_beat(now=1000.0)
        beat.check_beat(now=5000.0)
    assert sent == []


def test_beat_alive_reads_the_singleton_lease(settings: Any) -> None:
    client = MagicMock()
    client.exists.return_value = 1
    with patch("quran_backend.modules.alerts.beat.Redis.from_url", return_value=client):
        assert beat.beat_alive() is True
    client.exists.assert_called_once_with(settings.CELERY_BEAT_LOCK_KEY)
    client.close.assert_called_once()
