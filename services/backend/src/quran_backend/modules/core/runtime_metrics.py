from __future__ import annotations

import os
from typing import Final

from prometheus_client import CollectorRegistry, Counter, Histogram, multiprocess

HTTP_METHODS: Final = frozenset(
    {"CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "TRACE"}
)
UNMATCHED_ROUTE: Final = "__unmatched__"

HTTP_REQUESTS = Counter(
    "quran_http_requests_total",
    "Completed backend HTTP requests grouped by bounded route labels.",
    labelnames=("method", "route", "status_class"),
    registry=None,
)
HTTP_REQUEST_DURATION = Histogram(
    "quran_http_request_duration_seconds",
    "Backend HTTP request duration grouped by bounded route labels.",
    labelnames=("method", "route"),
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
    registry=None,
)


def observe_http_request(*, method: str, route: str | None, status: int, duration: float) -> None:
    """Record one request without using raw URLs or other unbounded labels."""

    method_label = method.upper() if method.upper() in HTTP_METHODS else "OTHER"
    route_label = route or UNMATCHED_ROUTE
    status_class = f"{status // 100}xx" if 100 <= status <= 599 else "unknown"
    HTTP_REQUESTS.labels(
        method=method_label,
        route=route_label,
        status_class=status_class,
    ).inc()
    HTTP_REQUEST_DURATION.labels(method=method_label, route=route_label).observe(max(duration, 0))


def register_runtime_collectors(registry: CollectorRegistry) -> None:
    """Attach either local collectors or Gunicorn multiprocess files to a scrape registry."""

    if os.getenv("PROMETHEUS_MULTIPROC_DIR"):
        multiprocess.MultiProcessCollector(registry)  # type: ignore[no-untyped-call]
        return
    registry.register(HTTP_REQUESTS)
    registry.register(HTTP_REQUEST_DURATION)
