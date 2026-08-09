from __future__ import annotations

import hashlib
import hmac
from typing import Any
from uuid import UUID

from django.conf import settings
from rest_framework.request import Request
from rest_framework.throttling import BaseThrottle

from quran_backend.modules.accounts.services import refresh_token_rate_limit_identity
from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle


class _IPBurstThrottle(AtomicFixedWindowRateThrottle):
    """Emergency per-edge-IP circuit breaker, not the primary client quota."""

    def get_cache_key(self, request: Request, view: Any) -> str:  # noqa: ARG002
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class GuestBootstrapIPBurstThrottle(_IPBurstThrottle):
    scope = "guest_bootstrap_ip_burst"


class RefreshTokenIPBurstThrottle(_IPBurstThrottle):
    scope = "token_refresh_ip_burst"


class GuestBootstrapInstallationThrottle(AtomicFixedWindowRateThrottle):
    """Limit one installation proof without coupling unrelated CGNAT users."""

    scope = "guest_bootstrap_installation"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        data = request.data
        installation_id = data.get("installation_id")
        credential = data.get("installation_credential")
        if not isinstance(installation_id, str) or not isinstance(credential, str):
            return None
        try:
            installation_identity = str(UUID(installation_id))
        except ValueError:
            installation_identity = installation_id
        identity = _keyed_cache_identity(
            setting_name="QURAN_GUEST_CREDENTIAL_HASH_KEY",
            namespace="guest-bootstrap",
            value=f"{installation_identity}\x00{credential}",
        )
        return self.cache_format % {"scope": self.scope, "ident": identity}


class RefreshTokenSessionThrottle(AtomicFixedWindowRateThrottle):
    """Use a verified token family as the quota identity when one is available."""

    scope = "token_refresh_session"

    def get_cache_key(self, request: Request, view: Any) -> str | None:  # noqa: ARG002
        data = request.data
        raw_token = data.get("refresh_token")
        if not isinstance(raw_token, str) or not raw_token:
            return None
        session_id = refresh_token_rate_limit_identity(raw_token)
        namespace = "refresh-session" if session_id is not None else "invalid-refresh"
        value = str(session_id) if session_id is not None else raw_token
        identity = _keyed_cache_identity(
            setting_name="QURAN_REFRESH_TOKEN_HASH_KEY",
            namespace=namespace,
            value=value,
        )
        return self.cache_format % {"scope": self.scope, "ident": identity}


class _ShortCircuitThrottle(BaseThrottle):
    """Apply an IP breaker before any identity lookup that may touch the database."""

    throttle_classes: tuple[type[BaseThrottle], ...] = ()

    def __init__(self) -> None:
        self.throttles = tuple(throttle_class() for throttle_class in self.throttle_classes)
        self.denied_throttle: BaseThrottle | None = None

    def allow_request(self, request: Request, view: Any) -> bool:
        for throttle in self.throttles:
            if not throttle.allow_request(request, view):
                self.denied_throttle = throttle
                return False
        return True

    def wait(self) -> float | None:
        return self.denied_throttle.wait() if self.denied_throttle is not None else None


class GuestBootstrapThrottle(_ShortCircuitThrottle):
    throttle_classes = (
        GuestBootstrapIPBurstThrottle,
        GuestBootstrapInstallationThrottle,
    )


class RefreshTokenThrottle(_ShortCircuitThrottle):
    throttle_classes = (
        RefreshTokenIPBurstThrottle,
        RefreshTokenSessionThrottle,
    )


def _keyed_cache_identity(*, setting_name: str, namespace: str, value: str) -> str:
    configured_key = getattr(settings, setting_name, settings.SECRET_KEY)
    key = str(configured_key).encode("utf-8")
    material = f"{namespace}\x00{value}".encode()
    return hmac.new(key, material, hashlib.sha256).hexdigest()
