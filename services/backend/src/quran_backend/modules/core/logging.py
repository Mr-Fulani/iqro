from __future__ import annotations

import json
import logging
import re
from datetime import UTC, datetime
from typing import Any

from quran_backend.modules.core.request_context import get_request_id

_REDACTED = "[REDACTED]"
_SENSITIVE_KEYS = frozenset(
    {
        "api_key",
        "authorization",
        "body",
        "cookie",
        "cookies",
        "coordinate",
        "coordinates",
        "coords",
        "geolocation",
        "lat",
        "latitude",
        "lng",
        "location",
        "lon",
        "longitude",
        "password",
        "proxy_authorization",
        "query",
        "query_string",
        "request_body",
        "secret",
        "secrets",
        "set_cookie",
        "token",
        "tokens",
    }
)
_SENSITIVE_KEY_SUFFIXES = (
    "_api_key",
    "_authorization",
    "_body",
    "_cookie",
    "_cookies",
    "_coordinate",
    "_coordinates",
    "_lat",
    "_latitude",
    "_lng",
    "_location",
    "_lon",
    "_longitude",
    "_password",
    "_query",
    "_query_string",
    "_secret",
    "_secrets",
    "_token",
    "_tokens",
)


class RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = get_request_id()
        return True


class JsonFormatter(logging.Formatter):
    _standard_attributes = frozenset(
        {
            "args",
            "asctime",
            "created",
            "exc_info",
            "exc_text",
            "filename",
            "funcName",
            "levelname",
            "levelno",
            "lineno",
            "module",
            "msecs",
            "message",
            "msg",
            "name",
            "pathname",
            "process",
            "processName",
            "relativeCreated",
            "stack_info",
            "thread",
            "threadName",
        }
    )

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(tz=UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        for key, value in record.__dict__.items():
            if not isinstance(key, str) or key in self._standard_attributes or key == "request_id":
                continue
            redacted_value = _redact_sensitive_value(value, key=key)
            if _is_json_serializable(redacted_value):
                payload[key] = redacted_value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _redact_sensitive_value(
    value: object,
    *,
    key: object | None = None,
    active_container_ids: set[int] | None = None,
) -> object:
    """Return a log-safe copy while tolerating cycles and malformed extras."""

    try:
        if _is_sensitive_key(key):
            return _REDACTED

        if isinstance(value, (dict, list, tuple)):
            recursion_stack = active_container_ids if active_container_ids is not None else set()
            return _redact_container(value, recursion_stack)
        return value
    except Exception:
        # Logging must never break request handling; fail closed if an unusual
        # mapping/container implementation raises while being inspected.
        return _REDACTED


def _redact_container(
    value: dict[object, object] | list[object] | tuple[object, ...],
    active_container_ids: set[int],
) -> object:
    container_id = id(value)
    if container_id in active_container_ids:
        return _REDACTED
    active_container_ids.add(container_id)
    try:
        if isinstance(value, dict):
            redacted: object = {
                nested_key: _redact_sensitive_value(
                    nested_value,
                    key=nested_key,
                    active_container_ids=active_container_ids,
                )
                for nested_key, nested_value in value.items()
                if isinstance(nested_key, (str, int, float, bool, type(None)))
            }
        elif isinstance(value, list):
            redacted = [
                _redact_sensitive_value(
                    item,
                    active_container_ids=active_container_ids,
                )
                for item in value
            ]
        else:
            redacted = tuple(
                _redact_sensitive_value(
                    item,
                    active_container_ids=active_container_ids,
                )
                for item in value
            )
        return redacted
    finally:
        active_container_ids.discard(container_id)


def _is_sensitive_key(key: object | None) -> bool:
    if not isinstance(key, str):
        return False
    snake_case = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", key)
    normalized = re.sub(r"[^a-z0-9]+", "_", snake_case.casefold()).strip("_")
    return (
        normalized in _SENSITIVE_KEYS
        or normalized.endswith(_SENSITIVE_KEY_SUFFIXES)
        or normalized.endswith(("token", "tokens", "secret", "secrets"))
    )


def _is_json_serializable(value: object) -> bool:
    try:
        json.dumps(value)
    except Exception:
        return False
    return True
