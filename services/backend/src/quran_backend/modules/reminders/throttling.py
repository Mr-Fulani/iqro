from __future__ import annotations

from typing import Any

from rest_framework.request import Request

from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class ReminderMutationThrottle(AtomicFixedWindowRateThrottle):
    scope = "reminder_mutation"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return None
        device_id = (
            request.auth.device.pk if isinstance(request.auth, AccessAuthContext) else "unbound"
        )
        ident = f"{user.pk}:{device_id}"
        return self.cache_format % {"scope": self.scope, "ident": ident}
