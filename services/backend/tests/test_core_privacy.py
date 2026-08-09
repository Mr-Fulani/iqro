from __future__ import annotations

import json
import logging

import pytest
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

from quran_backend.modules.core.logging import JsonFormatter
from quran_backend.modules.core.privacy import (
    PRIVATE_NO_STORE_CACHE_CONTROL,
    PrivateNoStoreResponseMixin,
)


class _PrivateResponseProbeView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = ()
    permission_classes = ()

    def get(self, request: Request) -> Response:
        if request.query_params.get("invalid"):
            raise ValidationError({"field": "Invalid value."})
        return Response({"status": "ok"})


@pytest.mark.parametrize(
    ("path", "expected_status"),
    [
        ("/private-probe", 200),
        ("/private-probe?invalid=1", 400),
    ],
)
def test_private_no_store_headers_cover_success_and_handled_errors(
    path: str,
    expected_status: int,
) -> None:
    response = _PrivateResponseProbeView.as_view()(APIRequestFactory().get(path))

    assert response.status_code == expected_status
    assert response["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    assert response["Pragma"] == "no-cache"
    assert response["Expires"] == "0"
    assert "Authorization" in {value.strip() for value in response["Vary"].split(",")}


def test_json_logging_recursively_redacts_sensitive_structured_values() -> None:
    record = logging.LogRecord(
        name="quran_backend.privacy",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="Prayer calculation requested",
        args=(),
        exc_info=None,
    )
    record.authorization = "Bearer access-token"
    record.context = {
        "safe": "preserved",
        "token_count": 2,
        "nested": [
            {
                "latitude": 41.0082,
                "longitude": 28.9784,
                "coordinates": [41.0082, 28.9784],
                "location": "Istanbul",
                "safe_list_value": 7,
            },
            (
                {
                    "body": {"safe-looking": "still private"},
                    "requestBody": "private request payload",
                    "query": "latitude=41.0082",
                    "QUERY_STRING": "longitude=28.9784",
                },
                {
                    "Authorization": "Basic credentials",
                    "Cookie": "session=secret",
                    "Set-Cookie": "session=secret",
                    "access_token": "access-token",
                    "refreshToken": "refresh-token",
                    "client_secret": "client-secret",
                    "tokens": ["one", "two"],
                    "secrets": {"value": "private"},
                },
            ),
        ],
    }

    payload = json.loads(JsonFormatter().format(record))

    assert payload["authorization"] == "[REDACTED]"
    assert payload["context"]["safe"] == "preserved"
    assert payload["context"]["token_count"] == 2
    first_nested = payload["context"]["nested"][0]
    for key in ("latitude", "longitude", "coordinates", "location"):
        assert first_nested[key] == "[REDACTED]"
    assert first_nested["safe_list_value"] == 7
    request_values = payload["context"]["nested"][1][0]
    for key in ("body", "requestBody", "query", "QUERY_STRING"):
        assert request_values[key] == "[REDACTED]"
    credential_values = payload["context"]["nested"][1][1]
    for key in (
        "Authorization",
        "Cookie",
        "Set-Cookie",
        "access_token",
        "refreshToken",
        "client_secret",
        "tokens",
        "secrets",
    ):
        assert credential_values[key] == "[REDACTED]"


def test_json_logging_tolerates_cycles_and_odd_extras() -> None:
    record = logging.LogRecord(
        name="quran_backend.privacy",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="Structured event",
        args=(),
        exc_info=None,
    )
    cyclic: dict[str, object] = {"safe": "preserved"}
    cyclic["self"] = cyclic
    record.cyclic = cyclic
    record.unserializable = object()
    record.__dict__[object()] = "ignored odd key"

    payload = json.loads(JsonFormatter().format(record))

    assert payload["cyclic"] == {"safe": "preserved", "self": "[REDACTED]"}
    assert "unserializable" not in payload
