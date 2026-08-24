from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from typing import Any

from django.core.cache import caches
from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class _TestAtomicThrottle(AtomicFixedWindowRateThrottle):
    scope = "test_atomic"

    def get_rate(self) -> str:
        return "10/minute"

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        return self.cache_format % {"scope": self.scope, "ident": "shared-client"}


def test_atomic_throttle_caps_a_concurrent_burst() -> None:
    throttle_cache = caches["throttling"]
    throttle_cache.clear()

    def attempt(_index: int) -> bool:
        return _TestAtomicThrottle().allow_request(None, None)  # type: ignore[arg-type]

    with ThreadPoolExecutor(max_workers=20) as executor:
        accepted = list(executor.map(attempt, range(100)))

    throttle_cache.clear()
    assert sum(accepted) == 10
