from __future__ import annotations

from typing import Any

from rest_framework.exceptions import Throttled
from rest_framework.request import Request
from rest_framework.throttling import BaseThrottle

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class ReadingRateLimitExceeded(Throttled):
    default_detail = "Too many reading-state mutations. Retry later."
    default_code = "reading_rate_limited"


class _UserDeviceRateThrottle(AtomicFixedWindowRateThrottle):
    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        device = getattr(request.auth, "device", None)
        device_id = getattr(device, "pk", None)
        ident = f"{user.pk}:{device_id or 'unbound'}"
        return self.cache_format % {"scope": self.scope, "ident": ident}


class ReadingMutationRateThrottle(_UserDeviceRateThrottle):
    scope = "reading_mutation"


class SyncPushRateThrottle(_UserDeviceRateThrottle):
    scope = "sync_push"

    def get_request_cost(self, request: Request, view: Any) -> int:  # noqa: ARG002
        data = request.data
        operations = data.get("operations") if isinstance(data, dict) else None
        return len(operations) if isinstance(operations, list) and operations else 1


class SyncPushDailyRateThrottle(SyncPushRateThrottle):
    scope = "sync_push_daily"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        return self.cache_format % {"scope": self.scope, "ident": str(user.pk)}


class SyncPushThrottle(BaseThrottle):
    """Short-circuit burst quota before charging the per-user daily operation budget."""

    def __init__(self) -> None:
        self.throttles: tuple[BaseThrottle, ...] = (
            SyncPushRateThrottle(),
            SyncPushDailyRateThrottle(),
        )
        self.denied_throttle: BaseThrottle | None = None

    def allow_request(self, request: Request, view: Any) -> bool:
        for throttle in self.throttles:
            if not throttle.allow_request(request, view):
                self.denied_throttle = throttle
                return False
        return True

    def wait(self) -> float | None:
        return self.denied_throttle.wait() if self.denied_throttle is not None else None
