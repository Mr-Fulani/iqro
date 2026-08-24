from __future__ import annotations

from typing import Any

from django.http import HttpRequest, HttpResponse
from django.test import RequestFactory

from quran_backend.modules.core.middleware import RequestMetricsMiddleware


def test_metrics_failure_does_not_break_request(
    monkeypatch: Any,
) -> None:
    def fail_observation(**_kwargs: object) -> None:
        raise OSError("metrics directory unavailable")

    monkeypatch.setattr(
        "quran_backend.modules.core.middleware.observe_http_request",
        fail_observation,
    )

    def response(_request: HttpRequest) -> HttpResponse:
        return HttpResponse(status=204)

    middleware = RequestMetricsMiddleware(response)
    request = RequestFactory().get("/api/v1/health/live")
    messages: list[str] = []
    monkeypatch.setattr(
        "quran_backend.modules.core.middleware.logger.exception",
        messages.append,
    )

    assert middleware(request).status_code == 204
    assert middleware(request).status_code == 204

    assert messages == ["request_metrics_observation_failed"]
