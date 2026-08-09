from __future__ import annotations

import json
import logging

from quran_backend.modules.core.logging import JsonFormatter, RequestIdFilter
from quran_backend.modules.core.request_context import reset_request_id, set_request_id


def test_json_logging_includes_request_id_and_structured_fields() -> None:
    token = set_request_id("request-123")
    try:
        record = logging.LogRecord(
            name="quran_backend.test",
            level=logging.INFO,
            pathname=__file__,
            lineno=10,
            msg="Health checked",
            args=(),
            exc_info=None,
        )
        record.component = "database"
        RequestIdFilter().filter(record)

        payload = json.loads(JsonFormatter().format(record))
    finally:
        reset_request_id(token)

    assert payload["level"] == "INFO"
    assert payload["message"] == "Health checked"
    assert payload["request_id"] == "request-123"
    assert payload["component"] == "database"
