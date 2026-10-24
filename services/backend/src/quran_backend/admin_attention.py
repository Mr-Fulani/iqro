# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""«Требует внимания» on the admin home: each row links to the filtered list.

A row is shown only to someone who may view that list. To add a row, add a
line to QUEUES: the title, the model and the changelist filter.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from django.apps import apps
from django.conf import settings
from django.contrib import admin
from django.http import HttpRequest
from django.urls import reverse
from django.utils import timezone

# A heartbeat runs every 5 minutes; three missed runs mean the check itself stopped.
MONITOR_STALE_SECONDS = 20 * 60

QUEUES: tuple[tuple[str, str, dict[str, str]], ...] = (
    ("Выпуски курсов на проверке", "courses.CourseRelease", {"status__exact": "in_review"}),
    (
        "Выпуски курсов подписаны, не опубликованы",
        "courses.CourseRelease",
        {"status__exact": "signed"},
    ),
    (
        "Таджвид: черновики ждут подписи",
        "tajweed.TajweedCourseVersion",
        {"status__exact": "draft", "reviewed_at__isnull": "True"},
    ),
    (
        "Таджвид: подписано, не опубликовано",
        "tajweed.TajweedCourseVersion",
        {"status__exact": "draft", "reviewed_at__isnull": "False"},
    ),
    (
        "Намаз: черновики ждут подписи",
        "salah.SalahCourseVersion",
        {"status__exact": "draft", "reviewed_at__isnull": "True"},
    ),
    (
        "Намаз: подписано, не опубликовано",
        "salah.SalahCourseVersion",
        {"status__exact": "draft", "reviewed_at__isnull": "False"},
    ),
    ("Новые обращения", "feedback.FeedbackTicket", {"status__exact": "new"}),
    (
        "Новые обращения: религиозное содержание",
        "feedback.FeedbackTicket",
        {"status__exact": "new", "category__exact": "religious_content"},
    ),
    ("Объявления ждут проверки", "announcements.Announcement", {"status__exact": "in_review"}),
)


@dataclass(frozen=True)
class AttentionItem:
    title: str
    detail: str
    url: str = ""
    # "ok" — nothing to do, "warn" — waits for someone, "error" — something broke.
    level: str = "ok"


def attention_items(request: HttpRequest) -> list[AttentionItem]:
    items = [
        item
        for title, label, filters in QUEUES
        if (item := _queue_item(request, title, label, filters)) is not None
    ]
    if request.user.is_superuser:
        items += [backup_item(), beat_item()]
    return items


def _queue_item(
    request: HttpRequest, title: str, label: str, filters: dict[str, str]
) -> AttentionItem | None:
    try:
        model = apps.get_model(label)
    except LookupError:
        return None
    model_admin = admin.site._registry.get(model)
    if model_admin is None or not model_admin.has_view_permission(request):
        return None
    lookups: dict[str, Any] = {
        key.removesuffix("__exact"): (value == "True" if key.endswith("__isnull") else value)
        for key, value in filters.items()
    }
    count = model._default_manager.filter(**lookups).count()
    url = reverse(f"admin:{model._meta.app_label}_{model._meta.model_name}_changelist")
    return AttentionItem(
        title=title,
        detail=str(count) if count else "нет",
        url=f"{url}?{urlencode(filters)}",
        level="warn" if count else "ok",
    )


def read_monitor_status(path: str) -> dict[str, Any] | None:
    """The secret-free summary the server heartbeat writes (ops/monitoring/heartbeat.py)."""
    if not path:
        return None
    try:
        payload = json.loads(Path(path).read_text())
    except OSError, ValueError:
        return None
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        return None
    return payload


def _parse_time(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.utcoffset() is not None else parsed.replace(tzinfo=UTC)


def _local(moment: datetime) -> str:
    return timezone.localtime(moment).strftime("%d.%m %H:%M")


def backup_item(now: datetime | None = None) -> AttentionItem:
    title = "Бэкап базы"
    status = read_monitor_status(getattr(settings, "MONITOR_STATUS_FILE", ""))
    if status is None:
        return AttentionItem(
            title, "нет данных: проверка на сервере не записала статус", level="warn"
        )
    current = now or timezone.now()
    checked_at = _parse_time(status.get("checked_at"))
    backup_at = _parse_time(status.get("last_backup_at"))
    backup_text = f"последний бэкап {_local(backup_at)}" if backup_at else "бэкапа нет"
    if checked_at is None or (current - checked_at).total_seconds() > MONITOR_STALE_SECONDS:
        return AttentionItem(title, f"проверка давно не запускалась; {backup_text}", level="error")
    if not status.get("ok"):
        problem = str(status.get("problem") or "проверка не прошла")[:200]
        return AttentionItem(title, f"{problem}; {backup_text}", level="error")
    return AttentionItem(title, f"в порядке, {backup_text}")


def beat_item() -> AttentionItem:
    from quran_backend.modules.alerts.beat import beat_alive  # noqa: PLC0415

    alive = beat_alive()
    if alive is None:
        return AttentionItem("Фоновые задачи (Celery beat)", "нет связи с Redis", level="error")
    if not alive:
        return AttentionItem("Фоновые задачи (Celery beat)", "не отвечает", level="error")
    return AttentionItem("Фоновые задачи (Celery beat)", "работает")
