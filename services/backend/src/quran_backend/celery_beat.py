from __future__ import annotations

import logging
import secrets
import time
from collections.abc import Callable
from typing import Any, Protocol, cast

from celery.beat import Scheduler
from django.conf import settings
from redis import Redis
from redis.exceptions import RedisError

logger = logging.getLogger(__name__)

_RENEW_SCRIPT = """
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("expire", KEYS[1], tonumber(ARGV[2]))
end
return 0
"""

_RELEASE_SCRIPT = """
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
end
return 0
"""


class RedisClient(Protocol):
    def set(self, key: str, value: str, *, ex: int, nx: bool) -> object: ...

    def eval(self, script: str, key_count: int, *args: object) -> object: ...

    def close(self) -> None: ...


class BeatLeaseUnavailableError(RuntimeError):
    """Raised when another Celery Beat process owns the singleton lease."""


class BeatLeaseLostError(RuntimeError):
    """Raised when the active Celery Beat process can no longer renew its lease."""


class RedisLease:
    def __init__(
        self,
        *,
        client: RedisClient,
        key: str,
        ttl_seconds: int,
        token: str | None = None,
    ) -> None:
        self.client = client
        self.key = key
        self.ttl_seconds = ttl_seconds
        self.token = token or secrets.token_hex(32)

    @classmethod
    def from_url(cls, *, url: str, key: str, ttl_seconds: int) -> RedisLease:
        client = Redis.from_url(
            url,
            socket_connect_timeout=5,
            socket_timeout=5,
            decode_responses=True,
        )
        return cls(
            client=cast(RedisClient, client),
            key=key,
            ttl_seconds=ttl_seconds,
        )

    def acquire(self) -> bool:
        result = self.client.set(
            self.key,
            self.token,
            ex=self.ttl_seconds,
            nx=True,
        )
        return bool(result)

    def renew(self) -> bool:
        result = self.client.eval(
            _RENEW_SCRIPT,
            1,
            self.key,
            self.token,
            self.ttl_seconds,
        )
        return bool(result)

    def release(self) -> bool:
        result = self.client.eval(_RELEASE_SCRIPT, 1, self.key, self.token)
        return bool(result)

    def close(self) -> None:
        self.client.close()


class SingletonRedisScheduler(Scheduler):  # type: ignore[misc]
    """In-memory Celery scheduler protected by a renewable Redis singleton lease."""

    def __init__(
        self,
        *args: Any,
        monotonic: Callable[[], float] = time.monotonic,
        **kwargs: Any,
    ) -> None:
        lazy = bool(kwargs.get("lazy", False))
        super().__init__(*args, **kwargs)
        self._monotonic = monotonic
        self._lease: RedisLease | None = None
        self._renew_interval_seconds = settings.CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS
        self._next_renew_at: float | None = None

        # Celery creates a lazy scheduler while rendering CLI help/introspection. It must not
        # claim the production lease before the service actually starts.
        if lazy:
            return

        lease = RedisLease.from_url(
            url=settings.CELERY_BROKER_URL,
            key=settings.CELERY_BEAT_LOCK_KEY,
            ttl_seconds=settings.CELERY_BEAT_LOCK_TTL_SECONDS,
        )
        try:
            acquired = lease.acquire()
        except RedisError:
            lease.close()
            raise
        if not acquired:
            lease.close()
            raise BeatLeaseUnavailableError(
                "Celery Beat singleton lease is already owned by another process"
            )

        self._lease = lease
        self._next_renew_at = self._monotonic() + self._renew_interval_seconds
        logger.info("Acquired Celery Beat singleton lease", extra={"lease_key": lease.key})

    def tick(self, *args: Any, **kwargs: Any) -> float:
        lease = self._lease
        next_renew_at = self._next_renew_at
        if lease is None or next_renew_at is None:
            return cast(float, super().tick(*args, **kwargs))

        now = self._monotonic()
        if now >= next_renew_at:
            try:
                renewed = lease.renew()
            except RedisError as exc:
                raise BeatLeaseLostError("Celery Beat lease renewal failed") from exc
            if not renewed:
                raise BeatLeaseLostError("Celery Beat singleton lease was lost")
            now = self._monotonic()
            next_renew_at = now + self._renew_interval_seconds
            self._next_renew_at = next_renew_at

        delay = cast(float, super().tick(*args, **kwargs))
        return min(delay, max(0.0, next_renew_at - self._monotonic()))

    def close(self) -> None:
        lease = self._lease
        self._lease = None
        self._next_renew_at = None
        if lease is not None:
            try:
                released = lease.release()
                if not released:
                    logger.warning(
                        "Celery Beat lease was not owned during shutdown",
                        extra={"lease_key": lease.key},
                    )
            except RedisError:
                logger.warning(
                    "Could not release Celery Beat lease; waiting for TTL expiry",
                    extra={"lease_key": lease.key},
                    exc_info=True,
                )
            finally:
                lease.close()
        super().close()
