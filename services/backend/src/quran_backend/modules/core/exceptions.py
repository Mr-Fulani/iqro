from __future__ import annotations

from typing import Any

from django.core.exceptions import RequestDataTooBig
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler


def problem_details_handler(
    exc: Exception,
    context: dict[str, Any],
) -> Response | None:
    response: Response | None
    if isinstance(exc, RequestDataTooBig):
        response = Response(
            {"detail": "Request body exceeds the configured size limit."},
            status=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
        )
        code = "request_body_too_large"
    else:
        response = exception_handler(exc, context)
        code = getattr(exc, "default_code", "request_error")
    if response is None:
        return None

    request = context.get("request")
    request_id = _request_id(request)
    detail, field_errors = _extract_details(response.data)

    response.data = {
        "type": f"https://api.quran.example/problems/{code}",
        "title": _title_for_status(response.status_code),
        "status": response.status_code,
        "code": str(code),
        "detail": detail,
        "instance": str(getattr(request, "path", "")),
        "request_id": request_id,
    }
    if field_errors:
        response.data["field_errors"] = field_errors
    response.content_type = "application/problem+json"
    return response


def _request_id(request: object) -> str:
    return str(getattr(request, "request_id", "-"))


def _extract_details(data: Any) -> tuple[str, dict[str, Any] | None]:
    if isinstance(data, dict):
        detail = data.get("detail")
        if detail is not None:
            return str(detail), None
        return "Request validation failed.", data
    if isinstance(data, list):
        return "Request validation failed.", {"non_field_errors": data}
    return str(data), None


def _title_for_status(status_code: int) -> str:
    return {
        status.HTTP_400_BAD_REQUEST: "Bad Request",
        status.HTTP_401_UNAUTHORIZED: "Unauthorized",
        status.HTTP_403_FORBIDDEN: "Forbidden",
        status.HTTP_404_NOT_FOUND: "Not Found",
        status.HTTP_405_METHOD_NOT_ALLOWED: "Method Not Allowed",
        status.HTTP_409_CONFLICT: "Conflict",
        status.HTTP_413_REQUEST_ENTITY_TOO_LARGE: "Content Too Large",
        status.HTTP_429_TOO_MANY_REQUESTS: "Too Many Requests",
    }.get(status_code, "Request Error")
