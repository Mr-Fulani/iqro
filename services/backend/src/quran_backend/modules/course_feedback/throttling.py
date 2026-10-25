from __future__ import annotations

import hashlib
import hmac
from typing import Any

from django.conf import settings
from rest_framework.request import Request

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


def _digest(kind: str, ident: object) -> str:
    return hmac.new(
        str(settings.SECRET_KEY).encode(), f"{kind}\x00{ident}".encode(), hashlib.sha256
    ).hexdigest()


class CourseEventRateThrottle(AtomicFixedWindowRateThrottle):
    """Bound anonymous counters without keeping the client address in the cache key."""

    scope = "course_event"

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        ident = _digest("course-event", self.get_ident(request))
        return self.cache_format % {"scope": self.scope, "ident": ident}


class CourseRatingRateThrottle(AtomicFixedWindowRateThrottle):
    """Ratings per installation or account; the key is a digest, not the account id."""

    scope = "course_rating"

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        ident = _digest("course-rating", request.user.pk)
        return self.cache_format % {"scope": self.scope, "ident": ident}
