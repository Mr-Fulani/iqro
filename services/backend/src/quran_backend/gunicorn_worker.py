from __future__ import annotations

import os
from typing import Any

from uvicorn.workers import UvicornWorker


def _positive_env_int(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a positive integer") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


class BoundedUvicornWorker(UvicornWorker):
    """Uvicorn worker with explicit per-process request backpressure."""

    CONFIG_KWARGS: dict[str, Any] = {  # noqa: RUF012
        **UvicornWorker.CONFIG_KWARGS,
        "limit_concurrency": _positive_env_int("API_MAX_CONCURRENT_REQUESTS_PER_WORKER", 5),
    }
