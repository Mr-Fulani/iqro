from __future__ import annotations

from typing import Any

PUBLIC_CACHE_TAGS = {"audio", "prayer", "quran"}
PUBLIC_CACHE_HEADERS = {
    "ETag": {
        "description": "Weak validator for the semantic JSON representation.",
        "schema": {"type": "string"},
    },
    "Cache-Control": {
        "description": "Public catalog cache policy.",
        "schema": {"type": "string"},
    },
}


def add_public_cache_contract(
    result: dict[str, Any],
    generator: Any,
    request: Any,
    public: bool,
) -> dict[str, Any]:
    """Document response headers and conditional GET shared by public catalog APIs."""

    _ = generator, request, public
    for path_item in result.get("paths", {}).values():
        operation = path_item.get("get")
        if not operation or not PUBLIC_CACHE_TAGS.intersection(operation.get("tags", [])):
            continue
        responses = operation.setdefault("responses", {})
        ok_response = responses.get("200")
        if ok_response is not None:
            ok_response.setdefault("headers", {}).update(PUBLIC_CACHE_HEADERS)
        responses.setdefault(
            "304",
            {
                "description": "Not modified; the current representation matches If-None-Match.",
                "headers": PUBLIC_CACHE_HEADERS,
            },
        )
    return result
