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

from quran_backend.modules.accounts.authentication import (
    SignedAccessTokenAuthentication,
    SignedLifecycleTokenAuthentication,
)
from quran_backend.modules.accounts.email_auth import (
    EmailVerificationResult,
    start_email_challenge,
    verify_email_challenge,
)
from quran_backend.modules.accounts.exceptions import AccessTokenInvalid, AuthRateLimitExceeded
from quran_backend.modules.accounts.lifecycle import (
    cancel_account_deletion,
    list_user_devices,
    request_account_deletion,
    revoke_user_device,
)
from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.accounts.serializers import (
    AccountDeletionRequestSerializer,
    CurrentSessionResponseSerializer,
    DeviceInventorySerializer,
    EmailChallengeStartRequestSerializer,
    EmailChallengeStartResponseSerializer,
    EmailChallengeVerifyRequestSerializer,
    EmailChallengeVerifyResponseSerializer,
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
    EmailStartThrottle,
    EmailVerifyThrottle,
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
class EmailChallengeStartView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedLifecycleTokenAuthentication,)
    permission_classes = (IsAuthenticated,)
    throttle_classes = (EmailStartThrottle,)

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise AuthRateLimitExceeded(wait)

    @extend_schema(
        request=EmailChallengeStartRequestSerializer,
        responses={status.HTTP_202_ACCEPTED: EmailChallengeStartResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        serializer = EmailChallengeStartRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = start_email_challenge(
            user=request.user,
            device=request.auth.device,
            email=serializer.validated_data["email"],
        )
        return Response(
            {
                "challenge_id": result.challenge.id,
                "expires_in": result.expires_in,
                "expires_at": result.challenge.expires_at,
            },
            status=status.HTTP_202_ACCEPTED,
        )


@extend_schema(tags=["authentication"])
class EmailChallengeVerifyView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (EmailVerifyThrottle,)

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise AuthRateLimitExceeded(wait)

    @extend_schema(
        request=EmailChallengeVerifyRequestSerializer,
        responses={status.HTTP_200_OK: EmailChallengeVerifyResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        serializer = EmailChallengeVerifyRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = verify_email_challenge(**serializer.validated_data)
        return Response(_email_verification_response(result), status=status.HTTP_200_OK)


@extend_schema(tags=["authentication"])
class LogoutView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedLifecycleTokenAuthentication,)
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
    authentication_classes = (SignedLifecycleTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(request=None, responses={status.HTTP_204_NO_CONTENT: None})
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        revoke_all_user_sessions(user=request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(tags=["user"])
class CurrentSessionView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedLifecycleTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(responses={status.HTTP_200_OK: CurrentSessionResponseSerializer})
    def get(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        return Response(
            {
                "user": _user_summary(request.user),
                "device": _device_summary(request.auth.device),
            },
            status=status.HTTP_200_OK,
        )


@extend_schema(tags=["user"])
class DeviceListView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedAccessTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(responses={status.HTTP_200_OK: DeviceInventorySerializer(many=True)})
    def get(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        return Response(
            list_user_devices(user=request.user, context=request.auth),
            status=status.HTTP_200_OK,
        )


@extend_schema(tags=["user"])
class DeviceDetailView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedAccessTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(request=None, responses={status.HTTP_204_NO_CONTENT: None})
    def delete(self, request: Request, device_id: Any) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        revoke_user_device(user=request.user, context=request.auth, device_id=device_id)
        return Response(status=status.HTTP_204_NO_CONTENT)


@extend_schema(tags=["user"])
class AccountDeletionRequestView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedAccessTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(
        request=AccountDeletionRequestSerializer,
        responses={status.HTTP_202_ACCEPTED: CurrentSessionResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        serializer = AccountDeletionRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request_account_deletion(
            user=request.user,
            context=request.auth,
            reauth_challenge_id=serializer.validated_data["reauth_challenge_id"],
        )
        return Response(
            {"user": _user_summary(user), "device": _device_summary(request.auth.device)},
            status=status.HTTP_202_ACCEPTED,
        )


@extend_schema(tags=["user"])
class AccountDeletionCancelView(PrivateNoStoreResponseMixin, APIView):
    authentication_classes = (SignedLifecycleTokenAuthentication,)
    permission_classes = (IsAuthenticated,)

    @extend_schema(
        request=AccountDeletionRequestSerializer,
        responses={status.HTTP_200_OK: CurrentSessionResponseSerializer},
    )
    def post(self, request: Request) -> Response:
        if not isinstance(request.auth, AccessAuthContext) or not isinstance(request.user, User):
            raise AccessTokenInvalid
        serializer = AccountDeletionRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = cancel_account_deletion(
            user=request.user,
            context=request.auth,
            reauth_challenge_id=serializer.validated_data["reauth_challenge_id"],
        )
        return Response(
            {"user": _user_summary(user), "device": _device_summary(request.auth.device)},
            status=status.HTTP_200_OK,
        )


def _guest_response(result: GuestBootstrapResult) -> dict[str, object]:
    response = _credentials_response(result.credentials)
    response["user"] = _user_summary(result.user)
    response["device"] = _device_summary(result.device)
    return response


def _email_verification_response(result: EmailVerificationResult) -> dict[str, object]:
    response = _credentials_response(result.credentials)
    response["user"] = _user_summary(result.user)
    response["device"] = _device_summary(result.device)
    response["merged_guest"] = result.merged_guest
    response["replayed"] = result.replayed
    return response


def _user_summary(user: User) -> dict[str, object]:
    return {
        "id": user.id,
        "status": user.status,
        "preferred_locale": user.preferred_locale,
        "email": user.email,
        "deletion_requested_at": user.deletion_requested_at,
        "deletion_scheduled_for": user.deletion_scheduled_for,
    }


def _device_summary(device: Device) -> dict[str, object]:
    return {
        "id": device.id,
        "platform": device.platform,
        "locale": device.locale,
        "app_version": device.app_version,
        "bootstrap_generation": device.bootstrap_generation,
    }


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
