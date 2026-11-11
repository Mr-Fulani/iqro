# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
from __future__ import annotations

import json
import re
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib import admin
from django.contrib.auth.models import Permission
from django.test import Client, RequestFactory

from quran_backend.admin_attention import attention_items, backup_item
from quran_backend.admin_site import SECTIONS, TILES, IqroAdminSite, placement
from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.models import FeedbackTicket
from quran_backend.modules.feedback.services import create_ticket

SECTION_TITLES = [section.title for section in SECTIONS]


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="sections-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _ticket(category: str) -> FeedbackTicket:
    ticket, _ = create_ticket(
        User.objects.create_user(),
        {
            "client_request_id": str(uuid.uuid7()),
            "client_message_id": str(uuid.uuid7()),
            "category": category,
            "subject": "Тема",
            "message": "Текст обращения.",
            "locale": "ru",
            "context": {},
        },
        channel="web",
    )
    return ticket


def test_admin_site_is_the_iqro_site() -> None:
    assert isinstance(admin.site, IqroAdminSite)


def test_every_registered_model_has_a_section() -> None:
    """A new app needs a line in admin_site.SECTIONS; a new model of a known app does not."""
    unplaced = [
        model._meta.label
        for model in admin.site._registry
        if placement(model._meta.app_label, model.__name__)[0] == "other"
    ]
    assert unplaced == []


def test_placement_rules() -> None:
    assert placement("courses", "CourseLesson") == ("learning", None)
    assert placement("tajweed", "TajweedCourseVersion") == ("learning", None)
    assert placement("tajweed", "AyahTajweed") == ("quran", "Разметка таджвида")
    assert placement("quiz", "Quiz") == ("learning", None)
    # Ratings and remarks of the parallel courses work go to feedback.
    assert placement("courses", "CourseRating") == ("feedback", "Оценки и замечания по курсам")
    assert placement("courses", "LessonRemark")[0] == "feedback"
    assert placement("courses", "CourseRelease") == ("learning", None)
    assert placement("brand_new_app", "Thing") == ("other", None)


def test_main_tables_and_tiles_point_at_registered_models() -> None:
    registered = {model._meta.label for model in admin.site._registry}
    for section in SECTIONS:
        assert section.hint
        assert set(section.main) <= registered, section.key
        for label in section.main:
            app_label, object_name = label.split(".")
            assert placement(app_label, object_name)[0] == section.key, label
    assert {label for _title, _hint, label in TILES} <= registered


def _section(body: str, key: str) -> str:
    rest = body.split(f'<div class="app-section-{key} module', maxsplit=1)[1]
    return rest.split('<div class="app-section-', maxsplit=1)[0]


def _open_and_folded(section: str) -> tuple[str, str]:
    main, _, folded = section.partition('<details class="iqro-service">')
    return main, folded


@pytest.mark.django_db
def test_home_shows_sections_with_main_tables_open_and_the_rest_folded(owner: User) -> None:
    body = _client(owner).get("/admin/").content.decode()

    captions = re.findall(
        r'<div class="app-section-[a-z]+ module">\s*<table>\s*<caption>\s*(.+?)\s*</caption>', body
    )
    assert captions == SECTION_TITLES
    for section in SECTIONS:
        assert section.hint in _section(body, section.key)

    # The main tables come first, in the order of SECTIONS, with no group headings.
    main, folded = _open_and_folded(_section(body, "feedback"))
    tables = re.findall(r'<th scope="row"[^>]*>\s*<a href="([^"]+)"', main)
    assert tables == [
        "/admin/feedback/feedbackticket/",
        "/admin/feedback/feedbackmessage/",
        "/admin/course_feedback/courseanalytics/",
    ]
    assert "iqro-group" not in main
    # Journals and technical tables are folded, under the name of their app.
    assert "Служебные таблицы — заходить редко (2)" in folded
    assert "/admin/feedback/feedbackaudit/" in folded
    assert "/admin/feedback/feedbackcontext/" in folded
    assert '<a href="/admin/feedback/">Обратная связь</a>' in folded

    main, folded = _open_and_folded(_section(body, "audio"))
    assert "/admin/audio/reciter/" in main
    assert "/admin/audio/audiotrack/" in folded
    assert '<a href="/admin/audio/">Аудио Корана</a>' in folded
    main, folded = _open_and_folded(_section(body, "learning"))
    assert "/admin/courses/courserelease/" in main
    assert "/admin/tajweed/tajweedcourseversion/" in main
    assert '<a href="/admin/salah/">Обучение намазу</a>' in folded
    assert "/admin/tajweed/ayahtajweed/" not in main + folded
    assert "Разметка таджвида" in _open_and_folded(_section(body, "quran"))[1]
    # A section whose tables are all main has nothing to fold.
    assert "iqro-service" not in _section(body, "announcements")


@pytest.mark.django_db
def test_home_has_daily_tiles_for_what_the_user_may_open(owner: User) -> None:
    body = _client(owner).get("/admin/").content.decode()
    assert "Каждый день" in body
    for title, hint, _label in TILES:
        assert f"<strong>{title}</strong><span>{hint}</span>" in body
    assert '<a href="/admin/feedback/feedbackticket/"><strong>Обращения</strong>' in body

    staff = User.objects.create_user(
        email="tiles-staff@example.test", status="active", is_staff=True
    )
    staff.user_permissions.set(
        Permission.objects.filter(
            content_type__app_label="feedback", codename="view_feedbackticket"
        )
    )
    body = _client(staff).get("/admin/").content.decode()
    assert "<strong>Обращения</strong>" in body
    assert "<strong>Чтецы</strong>" not in body


@pytest.mark.django_db
def test_app_pages_and_model_urls_are_unchanged(owner: User) -> None:
    client = _client(owner)
    page = client.get("/admin/courses/")
    assert page.status_code == 200
    assert "Тематические курсы" in page.content.decode()
    assert client.get("/admin/feedback/feedbackticket/").status_code == 200
    assert client.get("/admin/feedback/feedbackaudit/").status_code == 200
    # The sidebar of every page uses the same sections, without the hints and tiles.
    sidebar = client.get("/admin/feedback/feedbackticket/").content.decode()
    assert "Обращения и отзывы" in sidebar
    assert "Ду’а и календарь" in sidebar
    assert "Служебные таблицы (2)" in sidebar
    assert SECTIONS[0].hint not in sidebar
    assert "Каждый день" not in sidebar


@pytest.mark.django_db
def test_attention_counts_and_links_to_filtered_lists(owner: User) -> None:
    _ticket("religious_content")
    _ticket("technical")
    client = _client(owner)

    with patch("quran_backend.modules.alerts.beat.beat_alive", return_value=True):
        body = client.get("/admin/").content.decode()
        items = {item.title: item for item in attention_items(_request(owner))}

    assert "Требует внимания" in body
    assert items["Новые обращения"].detail == "2"
    assert items["Новые обращения"].level == "warn"
    religious = items["Новые обращения: религиозное содержание"]
    assert religious.detail == "1"
    assert religious.url == (
        "/admin/feedback/feedbackticket/?status__exact=new&category__exact=religious_content"
    )
    assert items["Выпуски курсов на проверке"].detail == "нет"
    assert items["Выпуски курсов на проверке"].level == "ok"
    assert items["Фоновые задачи (Celery beat)"].detail == "работает"
    assert set(items) >= {
        "Выпуски курсов подписаны, не опубликованы",
        "Таджвид: черновики ждут подписи",
        "Намаз: черновики ждут подписи",
        "Объявления ждут проверки",
        "Бэкап базы",
    }
    # Every link opens its list with the filter applied (an unknown filter redirects to ?e=1).
    for item in items.values():
        if item.url:
            assert client.get(item.url).status_code == 200, item.url
    filtered = client.get(religious.url).content.decode()
    assert "1 обращение" in filtered or "1 из" in filtered or "(1)" in filtered


def _request(user: User) -> Any:
    request = RequestFactory().get("/admin/")
    request.user = user
    return request


@pytest.mark.django_db
def test_staff_sees_only_what_they_may_view() -> None:
    staff = User.objects.create_user(
        email="feedback-staff@example.test", status="active", is_staff=True
    )
    staff.user_permissions.set(
        Permission.objects.filter(
            content_type__app_label="feedback", codename="view_feedbackticket"
        )
    )
    items = [item.title for item in attention_items(_request(staff))]
    assert items == ["Новые обращения", "Новые обращения: религиозное содержание"]

    body = _client(staff).get("/admin/").content.decode()
    assert "Обращения и отзывы" in body
    assert "Чтецы и аудио" not in body
    assert "Бэкап базы" not in body


def _status(tmp_path: Path, **values: Any) -> str:
    path = tmp_path / "status.json"
    path.write_text(json.dumps({"schema_version": 1, **values}))
    return str(path)


def test_backup_row_reads_the_heartbeat_summary(settings: Any, tmp_path: Path) -> None:
    now = datetime(2026, 10, 24, 12, tzinfo=UTC)
    settings.MONITOR_STATUS_FILE = ""
    assert backup_item(now).level == "warn"

    settings.MONITOR_STATUS_FILE = _status(
        tmp_path,
        checked_at=(now - timedelta(minutes=4)).isoformat(),
        ok=True,
        problem=None,
        last_backup_at="2026-10-24T01:00:00+00:00",
    )
    item = backup_item(now)
    assert item.level == "ok"
    assert item.detail.startswith("в порядке, последний бэкап 24.10")

    settings.MONITOR_STATUS_FILE = _status(
        tmp_path,
        checked_at=(now - timedelta(minutes=4)).isoformat(),
        ok=False,
        problem="Бэкап базы не прошёл или устарел",
        last_backup_at=None,
    )
    item = backup_item(now)
    assert item.level == "error"
    assert item.detail == "Бэкап базы не прошёл или устарел; бэкапа нет"

    settings.MONITOR_STATUS_FILE = _status(
        tmp_path, checked_at=(now - timedelta(hours=2)).isoformat(), ok=True
    )
    assert backup_item(now).detail.startswith("проверка давно не запускалась")

    Path(settings.MONITOR_STATUS_FILE).write_text("not json")
    assert backup_item(now).level == "warn"


@pytest.mark.django_db
def test_beat_row_reports_a_silent_beat(owner: User) -> None:
    with patch("quran_backend.modules.alerts.beat.beat_alive", return_value=False):
        items = {item.title: item for item in attention_items(_request(owner))}
    assert items["Фоновые задачи (Celery beat)"].level == "error"
    with patch("quran_backend.modules.alerts.beat.beat_alive", return_value=None):
        items = {item.title: item for item in attention_items(_request(owner))}
    assert items["Фоновые задачи (Celery beat)"].detail == "нет связи с Redis"
