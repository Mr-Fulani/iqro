from __future__ import annotations

import logging
import re
import time
import uuid
from collections.abc import Callable

from django.http import HttpRequest, HttpResponse

from quran_backend.modules.core.request_context import reset_request_id, set_request_id
from quran_backend.modules.core.runtime_metrics import observe_http_request

REQUEST_ID_HEADER = "X-Request-ID"
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
logger = logging.getLogger(__name__)


class RequestIdMiddleware:
    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        incoming_request_id = request.headers.get(REQUEST_ID_HEADER, "")
        request_id = (
            incoming_request_id
            if REQUEST_ID_PATTERN.fullmatch(incoming_request_id)
            else str(uuid.uuid4())
        )
        request.request_id = request_id  # type: ignore[attr-defined]
        token = set_request_id(request_id)
        try:
            response = self.get_response(request)
            response[REQUEST_ID_HEADER] = request_id
            return response
        finally:
            reset_request_id(token)


class RequestMetricsMiddleware:
    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response
        self.observation_failure_reported = False

    def __call__(self, request: HttpRequest) -> HttpResponse:
        started_at = time.perf_counter()
        status_code = 500
        try:
            response = self.get_response(request)
            status_code = response.status_code
            return response
        finally:
            resolver_match = getattr(request, "resolver_match", None)
            route = getattr(resolver_match, "route", None)
            try:
                observe_http_request(
                    method=request.method or "OTHER",
                    route=route if isinstance(route, str) else None,
                    status=status_code,
                    duration=time.perf_counter() - started_at,
                )
            except Exception:
                if not self.observation_failure_reported:
                    logger.exception("request_metrics_observation_failed")
                    self.observation_failure_reported = True
