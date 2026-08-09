from __future__ import annotations

from typing import Any, NoReturn

from django.utils import timezone
from django.utils.cache import patch_vary_headers
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.accounts.authentication import SignedAccessTokenAuthentication
from quran_backend.modules.accounts.exceptions import AccessTokenInvalid, AuthRateLimitExceeded
from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.serializers import (
    GuestBootstrapRequestSerializer,
    GuestBootstrapResponseSerializer,
    RefreshTokenRequestSerializer,
    TokenPairResponseSerializer,
)
from quran_backend.modules.accounts.services import (
    AccessAuthContext,
    GuestBootstrapResult,
    IssuedCredentials,
    access_token_ttl_seconds,
    bootstrap_guest,
    refresh_token_ttl_seconds,
    revoke_access_session,
    revoke_all_user_sessions,
    rotate_refresh_token,
)
from quran_backend.modules.accounts.throttling import (
    GuestBootstrapThrottle,
    RefreshTokenThrottle,
)


class PrivateNoStoreResponseMixin:
    def finalize_response(
        self,
        request: Request,
        response: Response,
        *args: Any,
        **kwargs: Any,
    ) -> Response:
        response = super().finalize_response(request, response, *args, **kwargs)  # type: ignore[misc]
        response["Cache-Control"] = "private, no-store"
        response["Pragma"] = "no-cache"
        response["Expires"] = "0"
        patch_vary_headers(response, ("Authorization",))
        return response


@extend_schema(tags=["authentication"])
class GuestBootstrapView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (GuestBootstrapThrottle,)

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise AuthRateLimitExceeded(wait)

    @extend_schema(
        request=GuestBootstrapRequestSerializer,
        responses={status.HTTP_200_OK: GuestBootstrapResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        serializer = GuestBootstrapRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = bootstrap_guest(**serializer.validated_data)
        return Response(_guest_response(result), status=status.HTTP_200_OK)


@extend_schema(tags=["authentication"])
class RefreshTokenView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (RefreshTokenThrottle,)

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise AuthRateLimitExceeded(wait)

    @extend_schema(
        request=RefreshTokenRequestSerializer,
        responses={status.HTTP_200_OK: TokenPairResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        serializer = RefreshTokenRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        credentials = rotate_refresh_token(serializer.validated_data["refresh_token"])
        return Response(_credentials_response(credentials), status=status.HTTP_200_OK)


@extend_schema(tags=["authentication"])
class LogoutView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedAccessTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(request=None, responses={status.HTTP_204_NO_CONTENT: None})
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        revoke_access_session(
            user=request.user,
            context=request.auth,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(tags=["authentication"])
class LogoutAllView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedAccessTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(request=None, responses={status.HTTP_204_NO_CONTENT: None})
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        revoke_all_user_sessions(user=request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)


def _guest_response(result: GuestBootstrapResult) -> dict[str, object]:
    response = _credentials_response(result.credentials)
    response["user"] = {
        "id": result.user.id,
        "status": result.user.status,
        "preferred_locale": result.user.preferred_locale,
    }
    response["device"] = {
        "id": result.device.id,
        "platform": result.device.platform,
        "locale": result.device.locale,
        "app_version": result.device.app_version,
        "bootstrap_generation": result.device.bootstrap_generation,
    }
    return response


def _credentials_response(credentials: IssuedCredentials) -> dict[str, object]:
    now = timezone.now()
    return {
        "token_type": "Bearer",
        "access_token": credentials.access_token,
        "expires_in": access_token_ttl_seconds(),
        "access_expires_at": credentials.access_expires_at,
        "refresh_token": credentials.refresh_token,
        "refresh_expires_in": min(
            refresh_token_ttl_seconds(),
            max(0, int((credentials.refresh_expires_at - now).total_seconds())),
        ),
        "refresh_expires_at": credentials.refresh_expires_at,
    }
