from __future__ import annotations

from typing import Any

from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class ShareEventRateThrottle(AtomicFixedWindowRateThrottle):
    scope = "share_event"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        return self.cache_format % {"scope": self.scope, "ident": str(user.pk)}


class ReferralLinkRateThrottle(AtomicFixedWindowRateThrottle):
    scope = "referral_link"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        return self.cache_format % {"scope": self.scope, "ident": str(user.pk)}


class ReferralRedirectRateThrottle(AtomicFixedWindowRateThrottle):
    scope = "referral_redirect"

    def get_cache_key(self, request: Request, _view: Any) -> str:
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}
