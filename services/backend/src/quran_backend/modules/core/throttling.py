from __future__ import annotations

import math
from typing import Any

from django.core.cache import caches
from rest_framework.request import Request
from rest_framework.throttling import SimpleRateThrottle


class AtomicFixedWindowRateThrottle(SimpleRateThrottle):
    """A Redis-safe atomic counter with one cache key per fixed time window.

    DRF's sliding-window throttle updates a cached list with a non-atomic read/modify/write
    sequence. This implementation uses cache ``add`` and ``incr`` operations, which are
    atomic for the production Redis backend and the test LocMem backend.
    """

    _wait_seconds: float | None = None
    cache = caches["throttling"]
    duration: int
    num_requests: int

    def allow_request(self, request: Request, view: Any) -> bool:
        if self.rate is None:
            return True

        cache_key = self.get_cache_key(request, view)
        if cache_key is None:
            return True

        now = self.timer()
        window = int(now // self.duration)
        remaining = self.duration - (now % self.duration)
        self._wait_seconds = remaining
        counter_key = f"{cache_key}:fixed:{window}"
        timeout = max(1, math.ceil(remaining) + 1)
        cost = max(1, int(self.get_request_cost(request, view)))

        if self.cache.add(counter_key, cost, timeout=timeout):
            count = cost
        else:
            count = int(self.cache.incr(counter_key, delta=cost))
        return count <= self.num_requests

    def get_request_cost(self, request: Request, view: Any) -> int:  # noqa: ARG002
        return 1

    def wait(self) -> float | None:
        return self._wait_seconds
