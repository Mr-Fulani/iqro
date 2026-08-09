from __future__ import annotations

from django.test import RequestFactory, override_settings
from rest_framework.exceptions import ValidationError
from rest_framework.test import APIClient

from quran_backend.modules.core.exceptions import problem_details_handler


def test_validation_error_uses_problem_details_contract() -> None:
    request = RequestFactory().post("/api/v1/example")
    request.request_id = "request-123"  # type: ignore[attr-defined]

    response = problem_details_handler(
        ValidationError({"locale": ["Unsupported locale."]}),
        {"request": request},
    )

    assert response is not None
    assert response.status_code == 400
    assert response.content_type == "application/problem+json"
    assert response.data == {
        "type": "https://api.quran.example/problems/invalid",
        "title": "Bad Request",
        "status": 400,
        "code": "invalid",
        "detail": "Request validation failed.",
        "instance": "/api/v1/example",
        "request_id": "request-123",
        "field_errors": {"locale": ["Unsupported locale."]},
    }


@override_settings(DATA_UPLOAD_MAX_MEMORY_SIZE=64)
def test_oversized_api_body_uses_problem_details_contract() -> None:
    response = APIClient().post(
        "/api/v1/auth/guest",
        {"padding": "x" * 256},
        format="json",
    )

    assert response.status_code == 413
    assert response.content_type == "application/problem+json"
    assert response.json()["code"] == "request_body_too_large"
    assert response.json()["title"] == "Content Too Large"
    assert response.json()["instance"] == "/api/v1/auth/guest"
