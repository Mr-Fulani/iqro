from __future__ import annotations

from typing import Any

from drf_spectacular.extensions import OpenApiAuthenticationExtension
from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.request import Request

from quran_backend.modules.accounts.exceptions import AccessTokenInvalid
from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.services import AccessAuthContext, authenticate_access_token


class SignedAccessTokenAuthentication(BaseAuthentication):
    """Authenticate a short-lived signed access token and its live token family."""

    keyword = "Bearer"

    def authenticate(self, request: Request) -> tuple[User, AccessAuthContext] | None:
        header = get_authorization_header(request).split()
        if not header:
            return None
        if header[0].lower() != self.keyword.lower().encode("ascii"):
            return None
        if len(header) != 2:
            raise AccessTokenInvalid
        try:
            raw_token = header[1].decode("ascii")
        except UnicodeDecodeError as exc:
            raise AccessTokenInvalid from exc
        return authenticate_access_token(raw_token)

    def authenticate_header(self, _request: Request) -> str:
        return self.keyword


class SignedAccessTokenAuthenticationScheme(  # type: ignore[no-untyped-call]
    OpenApiAuthenticationExtension
):
    target_class = SignedAccessTokenAuthentication
    name = "bearerAuth"

    def get_security_definition(self, _auto_schema: Any) -> dict[str, str]:
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "QAT1",
            "description": "Short-lived Quran Platform signed access token.",
        }
