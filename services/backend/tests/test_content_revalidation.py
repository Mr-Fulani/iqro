from __future__ import annotations

import json
from typing import Any

import pytest
from django.test import override_settings

from quran_backend.modules.core.content_revalidation import (
    enqueue_content_revalidation,
    enqueue_dua_content_change,
    enqueue_reciter_content_change,
)
from quran_backend.modules.core.tasks import notify_web_content_change_task

TEST_SECRET = "test-content-revalidation-secret-00000001"
TEST_URL = "http://web:3000/api/internal/content-revalidation"
TEST_PURGE_URL = "http://gateway:8080/internal/cache/purge-public-api"
TEST_OPERATIONS_TOKEN = "test-operations-token-0000000000000001"


class FakeResponse:
    status = 200

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, limit: int) -> bytes:
        assert limit == 64 * 1024
        return b'{"accepted":true}'


@override_settings(
    WEB_CONTENT_REVALIDATION_URL=TEST_URL,
    WEB_CONTENT_REVALIDATION_SECRET=TEST_SECRET,
    WEB_CONTENT_REVALIDATION_TIMEOUT_SECONDS=5,
    PUBLIC_API_CACHE_PURGE_URL=TEST_PURGE_URL,
    QURAN_OPERATIONS_TOKEN=TEST_OPERATIONS_TOKEN,
)
def test_revalidation_task_posts_json_then_purges_public_api_cache(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: list[dict[str, Any]] = []

    def fake_urlopen(request: Any, *, timeout: int) -> FakeResponse:
        captured.append(
            {
                "url": request.full_url,
                "method": request.get_method(),
                "authorization": request.get_header("Authorization"),
                "content_type": request.get_header("Content-type"),
                "payload": json.loads(request.data) if request.data else None,
                "timeout": timeout,
            }
        )
        return FakeResponse()

    monkeypatch.setattr("quran_backend.modules.core.tasks.urlopen", fake_urlopen)
    event = {
        "type": "quran.edition.changed",
        "action": "activated",
        "edition": "madani-hafs",
        "version": "1.0.0",
    }

    result = notify_web_content_change_task.run(event)

    assert captured == [
        {
            "url": TEST_URL,
            "method": "POST",
            "authorization": f"Bearer {TEST_SECRET}",
            "content_type": "application/json",
            "payload": event,
            "timeout": 5,
        },
        {
            "url": TEST_PURGE_URL,
            "method": "PURGE",
            "authorization": f"Bearer {TEST_OPERATIONS_TOKEN}",
            "content_type": None,
            "payload": None,
            "timeout": 5,
        },
    ]
    assert result == {
        "accepted": True,
        "status": 200,
        "purge_status": 200,
        "type": event["type"],
    }


@pytest.mark.django_db
@override_settings(
    WEB_CONTENT_REVALIDATION_URL=TEST_URL,
    WEB_CONTENT_REVALIDATION_SECRET=TEST_SECRET,
)
def test_revalidation_event_is_enqueued_only_after_commit(
    django_capture_on_commit_callbacks: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queued: list[dict[str, str]] = []
    monkeypatch.setattr(notify_web_content_change_task, "delay", queued.append)
    event = {
        "type": "audio.recitation.changed",
        "action": "withdrawn",
        "recitation_id": "00000000-0000-7000-8000-000000000701",
        "reciter_id": "00000000-0000-7000-8000-000000000159",
        "version": "1.0.0",
    }

    with django_capture_on_commit_callbacks(execute=True):
        enqueue_content_revalidation(event)
        assert queued == []

    assert queued == [event]


@pytest.mark.django_db
@override_settings(
    WEB_CONTENT_REVALIDATION_URL=TEST_URL,
    WEB_CONTENT_REVALIDATION_SECRET=TEST_SECRET,
)
def test_reciter_change_uses_a_scoped_revalidation_event(
    django_capture_on_commit_callbacks: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queued: list[dict[str, str]] = []
    monkeypatch.setattr(notify_web_content_change_task, "delay", queued.append)

    with django_capture_on_commit_callbacks(execute=True):
        enqueue_reciter_content_change(
            action="updated",
            reciter_id="00000000-0000-7000-8000-000000000159",
        )

    assert queued == [
        {
            "type": "audio.reciter.changed",
            "action": "updated",
            "reciter_id": "00000000-0000-7000-8000-000000000159",
        }
    ]


@pytest.mark.django_db
@override_settings(
    WEB_CONTENT_REVALIDATION_URL=TEST_URL,
    WEB_CONTENT_REVALIDATION_SECRET=TEST_SECRET,
)
def test_dua_revalidation_uses_a_scoped_collection_event(
    django_capture_on_commit_callbacks: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queued: list[dict[str, str]] = []
    monkeypatch.setattr(notify_web_content_change_task, "delay", queued.append)

    with django_capture_on_commit_callbacks(execute=True):
        enqueue_dua_content_change(
            action="updated",
            collection="hisn-al-muslim",
            version="hisn-full-2026-08-28",
        )

    assert queued == [
        {
            "type": "dua.collection.changed",
            "action": "updated",
            "collection": "hisn-al-muslim",
            "version": "hisn-full-2026-08-28",
        }
    ]
