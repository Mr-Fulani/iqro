from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from typing import Any

import pytest
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.audio.models import QuranFoundationSyncState
from quran_backend.modules.audio.operations import quran_foundation_operational_summary

OPERATIONS_TOKEN = "test-operations-token"


def test_operations_endpoints_are_hidden_when_not_configured(api_client: APIClient) -> None:
    assert api_client.get(reverse("core:health-operations")).status_code == 404
    assert api_client.get(reverse("core:metrics")).status_code == 404
    assert api_client.get(reverse("core:gateway-cache-purge-auth")).status_code == 404


@override_settings(QURAN_OPERATIONS_TOKEN=OPERATIONS_TOKEN)
def test_operations_endpoints_require_bearer_token(api_client: APIClient) -> None:
    response = api_client.get(
        reverse("core:health-operations"),
        headers={"Authorization": "Bearer wrong-token"},
    )

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


@override_settings(QURAN_OPERATIONS_TOKEN=OPERATIONS_TOKEN)
def test_gateway_cache_purge_auth_accepts_only_operations_token(
    api_client: APIClient,
) -> None:
    unauthorized = api_client.get(reverse("core:gateway-cache-purge-auth"))
    authorized = api_client.get(
        reverse("core:gateway-cache-purge-auth"),
        headers={"Authorization": f"Bearer {OPERATIONS_TOKEN}"},
    )

    assert unauthorized.status_code == 401
    assert authorized.status_code == 204
    assert authorized.headers["Cache-Control"] == "private, no-store"


@pytest.mark.django_db
@override_settings(
    QURAN_OPERATIONS_TOKEN=OPERATIONS_TOKEN,
    QURAN_QF_AUDIO_SYNC_ENABLED=False,
)
def test_operational_health_reports_disabled_sync(api_client: APIClient) -> None:
    response = api_client.get(
        reverse("core:health-operations"),
        headers={"Authorization": f"Bearer {OPERATIONS_TOKEN}"},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "disabled"
    assert response.json()["components"]["quran_foundation_audio"]["enabled"] is False
    assert response.headers["Cache-Control"] == "private, no-store"


@pytest.mark.django_db
@override_settings(
    QURAN_OPERATIONS_TOKEN=OPERATIONS_TOKEN,
    QURAN_QF_AUDIO_SYNC_ENABLED=True,
)
def test_operational_health_is_degraded_without_tracked_recitations(
    api_client: APIClient,
) -> None:
    response = api_client.get(
        reverse("core:health-operations"),
        headers={"Authorization": f"Bearer {OPERATIONS_TOKEN}"},
    )

    assert response.status_code == 503
    assert response.json()["status"] == "degraded"


@pytest.mark.django_db
@override_settings(
    QURAN_OPERATIONS_TOKEN=OPERATIONS_TOKEN,
    QURAN_QF_AUDIO_SYNC_ENABLED=False,
)
def test_metrics_are_prometheus_text_and_do_not_expose_token(api_client: APIClient) -> None:
    api_client.get(reverse("core:health-live"))
    response = api_client.get(
        reverse("core:metrics"),
        headers={"Authorization": f"Bearer {OPERATIONS_TOKEN}"},
    )
    body = response.content.decode()

    assert response.status_code == 200
    assert response.headers["Content-Type"].startswith("text/plain")
    assert "quran_platform_build_info" in body
    assert "quran_http_requests_total" in body
    assert 'route="api/v1/health/live"' in body
    assert "quran_foundation_audio_sync_enabled 0.0" in body
    assert OPERATIONS_TOKEN not in body
    assert response.headers["Cache-Control"] == "private, no-store"


@pytest.mark.django_db
@override_settings(
    QURAN_QF_AUDIO_SYNC_ENABLED=True,
    QURAN_QF_ENV="production",
    QURAN_QF_AUDIO_STALE_AFTER_HOURS=168,
)
def test_quran_foundation_summary_classifies_durable_sync_state(
    monkeypatch: Any,
) -> None:
    now = datetime(2026, 8, 23, 12, tzinfo=UTC)
    monkeypatch.setattr(
        "quran_backend.modules.audio.operations.latest_complete_qf_recitations",
        lambda _environment: [
            (1, SimpleNamespace()),
            (2, SimpleNamespace()),
            (3, SimpleNamespace()),
            (4, SimpleNamespace()),
        ],
    )
    QuranFoundationSyncState.objects.bulk_create(
        [
            QuranFoundationSyncState(
                environment="production",
                source_reciter_id=1,
                last_success_at=now - timedelta(hours=1),
            ),
            QuranFoundationSyncState(
                environment="production",
                source_reciter_id=2,
                last_success_at=now - timedelta(days=8),
            ),
            QuranFoundationSyncState(
                environment="production",
                source_reciter_id=3,
                last_success_at=now - timedelta(hours=1),
                consecutive_failures=2,
                last_error_code="quran_foundation_error",
            ),
        ]
    )

    summary = quran_foundation_operational_summary(now=now)

    assert summary.status == "degraded"
    assert summary.tracked_recitations == 4
    assert (summary.healthy, summary.stale, summary.failing, summary.never_synced) == (1, 1, 1, 1)
    assert summary.oldest_success_at == now - timedelta(days=8)
    assert summary.max_consecutive_failures == 2
