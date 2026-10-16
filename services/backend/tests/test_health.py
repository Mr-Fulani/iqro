from __future__ import annotations

import pytest
from django.core.cache import cache, caches
from django.urls import reverse
from drf_spectacular.generators import SchemaGenerator
from rest_framework.test import APIClient

from quran_backend.modules.core.api import ReadyHealthView


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
        "components": {"database": True, "cache": True, "throttling": True},
    }
    assert response.headers["Cache-Control"] == "no-store"


def test_concurrent_cache_probes_do_not_clobber_each_other(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    role_cache = caches["default"]
    original_get = role_cache.get
    interleaved = False

    def get_after_concurrent_probe(*args: object, **kwargs: object) -> object:
        nonlocal interleaved
        if not interleaved:
            interleaved = True
            # Another request's probe runs (and deletes its key) between our set and get.
            assert ReadyHealthView._cache_ready("default")
        return original_get(*args, **kwargs)

    monkeypatch.setattr(role_cache, "get", get_after_concurrent_probe)

    assert ReadyHealthView._cache_ready("default")


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


@pytest.mark.django_db
def test_openapi_schema_is_generated_once_then_served_from_cache(
    api_client: APIClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    cache.clear()
    calls = 0
    original = SchemaGenerator.get_schema

    def counting_get_schema(self: SchemaGenerator, *args: object, **kwargs: object) -> object:
        nonlocal calls
        calls += 1
        return original(self, *args, **kwargs)

    monkeypatch.setattr(SchemaGenerator, "get_schema", counting_get_schema)
    first = api_client.get(reverse("openapi-schema"), headers={"Accept": "application/json"})
    second = api_client.get(reverse("openapi-schema"), headers={"Accept": "application/json"})

    assert first.status_code == second.status_code == 200
    assert second.content == first.content
    assert calls == 1
