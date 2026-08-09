from __future__ import annotations

import hashlib
import hmac
from typing import Any

from django.conf import settings
from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class PrayerCalculationThrottle(AtomicFixedWindowRateThrottle):
    """Bound anonymous fallback calculations without retaining plaintext IPs."""

    scope = "prayer_calculate"

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        identity = self.get_ident(request)
        key = str(settings.QURAN_PRAYER_THROTTLE_HASH_KEY).encode()
        digest = hmac.new(
            key,
            f"prayer-calculate\x00{identity}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return self.cache_format % {"scope": self.scope, "ident": digest}


class PrayerProfileMutationThrottle(AtomicFixedWindowRateThrottle):
    scope = "prayer_profile_mutation"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        device = getattr(request.auth, "device", None)
        device_id = getattr(device, "pk", None)
        identity = f"{user.pk}:{device_id or 'unbound'}"
        return self.cache_format % {"scope": self.scope, "ident": identity}
