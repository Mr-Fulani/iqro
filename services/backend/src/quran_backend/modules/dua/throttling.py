from __future__ import annotations

import hashlib
import hmac
from typing import Any

from django.conf import settings
from rest_framework.exceptions import Throttled
from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class DuaSearchRateLimitExceeded(Throttled):
    default_detail = "Dua search rate limit exceeded. Retry later."
    default_code = "dua_search_rate_limited"


class DuaSearchRateThrottle(AtomicFixedWindowRateThrottle):
    """Bound public text search without retaining its IP or query as cache data."""

    scope = "dua_search"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        query = request.query_params.get("q")
        if not isinstance(query, str) or not query.strip():
            return None
        identity = self.get_ident(request)
        digest = hmac.new(
            str(settings.SECRET_KEY).encode(),
            f"dua-search\x00{identity}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return self.cache_format % {"scope": self.scope, "ident": digest}
