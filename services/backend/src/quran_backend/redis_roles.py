from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import unquote, urlsplit, urlunsplit


class RedisRoleConfigError(ValueError):
    """Raised when a Redis role URL cannot be used safely by the application."""


def _validated_url(name: str, raw_value: str) -> str:
    value = raw_value.strip()
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise RedisRoleConfigError(f"{name} must be a valid Redis URL") from exc
    if parsed.scheme not in {"redis", "rediss"} or parsed.hostname is None:
        raise RedisRoleConfigError(f"{name} must use redis:// or rediss:// with a hostname")
    if parsed.fragment:
        raise RedisRoleConfigError(f"{name} must not contain a URL fragment")
    database_path = unquote(parsed.path.removeprefix("/"))
    if database_path and (not database_path.isdecimal() or "/" in database_path):
        raise RedisRoleConfigError(f"{name} database path must be a non-negative integer")
    if port is not None and port <= 0:
        raise RedisRoleConfigError(f"{name} must use a positive port")
    return value


def _redacted_url(value: str) -> str:
    parsed = urlsplit(value)
    hostname = parsed.hostname or "invalid"
    display_host = f"[{hostname}]" if ":" in hostname else hostname
    display_port = f":{parsed.port}" if parsed.port is not None else ""
    return urlunsplit((parsed.scheme, f"{display_host}{display_port}", parsed.path, "", ""))


def _instance_key(value: str) -> tuple[str, str, int]:
    parsed = urlsplit(value)
    default_port = 6379
    return parsed.scheme, (parsed.hostname or "").casefold(), parsed.port or default_port


@dataclass(frozen=True, slots=True)
class RedisRoleConfig:
    legacy_url: str
    cache_url: str
    throttle_url: str
    broker_url: str
    result_url: str

    @classmethod
    def from_environ(cls, environ: Mapping[str, str]) -> RedisRoleConfig:
        legacy_url = _validated_url(
            "REDIS_URL",
            environ.get("REDIS_URL") or "redis://localhost:6379/0",
        )

        def role_url(name: str) -> str:
            return _validated_url(name, environ.get(name) or legacy_url)

        return cls(
            legacy_url=legacy_url,
            cache_url=role_url("REDIS_CACHE_URL"),
            throttle_url=role_url("REDIS_THROTTLE_URL"),
            broker_url=role_url("CELERY_BROKER_URL"),
            result_url=role_url("CELERY_RESULT_BACKEND"),
        )

    def role_urls(self) -> dict[str, str]:
        return {
            "cache": self.cache_url,
            "throttling": self.throttle_url,
            "celery_broker": self.broker_url,
            "celery_results": self.result_url,
        }

    def report(self) -> dict[str, object]:
        role_urls = self.role_urls()
        return {
            "roles": {role: _redacted_url(url) for role, url in role_urls.items()},
            "unique_role_urls": len(set(role_urls.values())),
            "unique_redis_instances": len({_instance_key(url) for url in role_urls.values()}),
            "single_redis_instance": len({_instance_key(url) for url in role_urls.values()}) == 1,
        }
