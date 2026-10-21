from __future__ import annotations

import hashlib
import hmac
from typing import Any

from django.conf import settings
from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class AnnouncementEventRateThrottle(AtomicFixedWindowRateThrottle):
    """Bound anonymous counters without keeping the client address in the cache key."""

    scope = "announcement_event"

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        digest = hmac.new(
            str(settings.SECRET_KEY).encode(),
            f"announcement-event\x00{self.get_ident(request)}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return self.cache_format % {"scope": self.scope, "ident": digest}
