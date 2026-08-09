from __future__ import annotations

import hashlib
import json
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any

from django.core.serializers.json import DjangoJSONEncoder
from django.utils.http import parse_etags
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response

if TYPE_CHECKING:
    from rest_framework.permissions import _PermissionClass


class PublicReadOnlyViewMixin:
    """Disable authentication and attach validators suitable for public catalog APIs."""

    authentication_classes: Sequence[type[BaseAuthentication]] = ()
    permission_classes: Sequence[_PermissionClass] = (AllowAny,)

    def finalize_response(
        self,
        request: Request,
        response: Response,
        *args: Any,
        **kwargs: Any,
    ) -> Response:
        if response.status_code == 200 and response.data is not None:
            payload = json.dumps(
                response.data,
                cls=DjangoJSONEncoder,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
            etag = f'W/"{hashlib.sha256(payload).hexdigest()}"'
            request_etags = parse_etags(request.headers.get("If-None-Match", ""))
            comparable_etag = self._weak_etag_value(etag)
            if "*" in request_etags or any(
                self._weak_etag_value(candidate) == comparable_etag for candidate in request_etags
            ):
                response = Response(status=304)
            response["ETag"] = etag
            response["Cache-Control"] = "public, max-age=300, stale-while-revalidate=86400"
        return super().finalize_response(request, response, *args, **kwargs)  # type: ignore[misc,no-any-return]

    @staticmethod
    def _weak_etag_value(etag: str) -> str:
        return etag[2:] if etag.startswith("W/") else etag
