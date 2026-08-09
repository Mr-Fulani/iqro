from __future__ import annotations

from typing import Any

from django.utils.cache import patch_vary_headers
from rest_framework.request import Request
from rest_framework.response import Response

PRIVATE_NO_STORE_CACHE_CONTROL = "private, no-store, max-age=0"


class PrivateNoStoreResponseMixin:
    """Prevent private API responses from being retained by shared or local caches."""

    def finalize_response(
        self,
        request: Request,
        response: Response,
        *args: Any,
        **kwargs: Any,
    ) -> Response:
        response = super().finalize_response(request, response, *args, **kwargs)  # type: ignore[misc]
        response["Cache-Control"] = PRIVATE_NO_STORE_CACHE_CONTROL
        response["Pragma"] = "no-cache"
        response["Expires"] = "0"
        patch_vary_headers(response, ("Authorization",))
        return response
