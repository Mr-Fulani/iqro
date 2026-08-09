from __future__ import annotations

from typing import NoReturn, cast

from django.utils.decorators import method_decorator
from django.views.decorators.debug import sensitive_post_parameters
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.prayer_times.exceptions import PrayerProfileRateLimitedError
from quran_backend.modules.prayer_times.profile_serializers import (
    PrayerProfileResponseSerializer,
    PrayerProfileWriteSerializer,
)
from quran_backend.modules.prayer_times.profile_services import (
    get_prayer_profile,
    prayer_profile_snapshot,
    put_prayer_profile,
)
from quran_backend.modules.prayer_times.throttling import PrayerProfileMutationThrottle


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["prayer-profile"])
class PrayerProfileView(PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "PUT":
            return [PrayerProfileMutationThrottle()]
        return []

    @extend_schema(
        operation_id="prayer_profile_retrieve",
        responses={
            status.HTTP_200_OK: PrayerProfileResponseSerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Prayer profile not found."),
        },
    )
    def get(self, request: Request) -> Response:
        profile = get_prayer_profile(cast(User, request.user))
        return Response(prayer_profile_snapshot(profile))

    @extend_schema(
        operation_id="prayer_profile_replace",
        request=PrayerProfileWriteSerializer,
        responses={
            status.HTTP_200_OK: PrayerProfileResponseSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(
                description="Prayer profile validation failed."
            ),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(
                description="Prayer method configuration not found."
            ),
            status.HTTP_409_CONFLICT: OpenApiResponse(
                description="Revision or exact method checksum conflict."
            ),
            status.HTTP_410_GONE: OpenApiResponse(
                description="Prayer method configuration withdrawn or inactive."
            ),
            status.HTTP_422_UNPROCESSABLE_ENTITY: OpenApiResponse(
                description=(
                    "The calculation engine/version is unsupported or the selected method "
                    "does not support a requested rule."
                )
            ),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Prayer-profile mutation rate limit exceeded."
            ),
        },
    )
    def put(self, request: Request) -> Response:
        serializer = PrayerProfileWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(
            put_prayer_profile(
                user=cast(User, request.user),
                device=_authenticated_device(request),
                data=dict(serializer.validated_data),
            )
        )

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise PrayerProfileRateLimitedError(wait=wait)


def _authenticated_device(request: Request) -> Device | None:
    if isinstance(request.auth, AccessAuthContext):
        return request.auth.device
    return None
