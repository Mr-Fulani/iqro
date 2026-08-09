from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, AuthenticationFailed, Throttled


class AccessTokenInvalid(AuthenticationFailed):
    default_detail = "Authentication credentials could not be validated."
    default_code = "access_token_invalid"


class RefreshTokenInvalid(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = "Refresh credentials could not be validated."
    default_code = "refresh_token_invalid"
    auth_header = "Bearer"


class RefreshTokenReused(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = "Refresh credentials could not be validated."
    default_code = "refresh_token_reused"
    auth_header = "Bearer"


class GuestBootstrapUnavailable(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "Guest bootstrap is unavailable for this installation."
    default_code = "guest_bootstrap_unavailable"


class AuthRateLimitExceeded(Throttled):
    default_detail = "Too many authentication requests. Retry later."
    default_code = "auth_rate_limited"
