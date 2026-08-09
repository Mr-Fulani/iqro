from __future__ import annotations

import pytest
from django.urls import reverse
from rest_framework.test import APIClient


def test_live_health_is_public_and_not_cacheable(api_client: APIClient) -> None:
    response = api_client.get(reverse("core:health-live"))

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "quran-platform-backend",
        "version": "0.1.0",
    }
    assert response.headers["Cache-Control"] == "no-store"


@pytest.mark.django_db
def test_ready_health_checks_database_and_cache(api_client: APIClient) -> None:
    response = api_client.get(reverse("core:health-ready"))

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "components": {"database": True, "cache": True},
    }
    assert response.headers["Cache-Control"] == "no-store"


def test_request_id_is_preserved_when_valid(api_client: APIClient) -> None:
    response = api_client.get(reverse("core:health-live"), headers={"X-Request-ID": "client-123"})

    assert response.headers["X-Request-ID"] == "client-123"


def test_invalid_request_id_is_replaced(api_client: APIClient) -> None:
    response = api_client.get(
        reverse("core:health-live"),
        headers={"X-Request-ID": "invalid request id with spaces"},
    )

    assert response.headers["X-Request-ID"] != "invalid request id with spaces"
    assert len(response.headers["X-Request-ID"]) == 36
