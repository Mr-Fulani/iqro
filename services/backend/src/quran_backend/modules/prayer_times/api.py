from __future__ import annotations

from typing import NoReturn

from django.utils.decorators import method_decorator
from django.views.decorators.debug import sensitive_post_parameters, sensitive_variables
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.prayer_times.cities import search_prayer_cities
from quran_backend.modules.prayer_times.exceptions import (
    PrayerCalculationRateLimitedError,
    PrayerCitySearchRateLimitedError,
)
from quran_backend.modules.prayer_times.serializers import (
    PrayerCalculationRequestSerializer,
    PrayerCalculationResponseSerializer,
    PrayerCitySearchQuerySerializer,
    PrayerCitySearchResponseSerializer,
    PrayerMethodsResponseSerializer,
)
from quran_backend.modules.prayer_times.services import (
    calculate_prayer_times,
    prayer_methods_manifest,
)
from quran_backend.modules.prayer_times.throttling import (
    PrayerCalculationThrottle,
    PrayerCitySearchThrottle,
)


@extend_schema(tags=["prayer"])
class PrayerMethodsView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="prayer_methods",
        responses={
            status.HTTP_200_OK: PrayerMethodsResponseSerializer,
            status.HTTP_503_SERVICE_UNAVAILABLE: OpenApiResponse(
                description="No published default prayer configuration is available."
            ),
        },
    )
    def get(self, request: Request) -> Response:  # noqa: ARG002
        return Response(prayer_methods_manifest())


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["prayer"])
class PrayerCalculateView(PrivateNoStoreResponseMixin, APIView):
    """Stateless one-day fallback; the request coordinates are never persisted."""

    authentication_classes: tuple[type[BaseAuthentication], ...] = ()
    permission_classes = (AllowAny,)
    throttle_classes = (PrayerCalculationThrottle,)

    @extend_schema(
        operation_id="prayer_calculate",
        request=PrayerCalculationRequestSerializer,
        responses={
            status.HTTP_200_OK: PrayerCalculationResponseSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Request validation failed."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(
                description="Prayer method configuration was not found."
            ),
            status.HTTP_409_CONFLICT: OpenApiResponse(
                description="The expected method checksum does not match."
            ),
            status.HTTP_410_GONE: OpenApiResponse(
                description="The requested method configuration was withdrawn."
            ),
            status.HTTP_422_UNPROCESSABLE_ENTITY: OpenApiResponse(
                description="The calculation cannot be resolved with the selected settings."
            ),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Prayer calculation rate limit exceeded."
            ),
        },
    )
    @sensitive_variables()
    def post(self, request: Request) -> Response:
        serializer = PrayerCalculationRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(calculate_prayer_times(dict(serializer.validated_data)))

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise PrayerCalculationRateLimitedError(wait=wait)

    def get_throttles(self) -> list[BaseThrottle]:
        return [throttle() for throttle in self.throttle_classes]


@extend_schema(tags=["prayer"])
class PrayerCitySearchView(PublicReadOnlyViewMixin, APIView):
    """Places by the start of their name, from our own copy of GeoNames.

    The query never leaves the service, and neither it nor the caller's address is stored.
    """

    throttle_classes = (PrayerCitySearchThrottle,)

    @extend_schema(
        operation_id="prayer_cities",
        parameters=[PrayerCitySearchQuerySerializer],
        responses={
            status.HTTP_200_OK: PrayerCitySearchResponseSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Request validation failed."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="City search rate limit exceeded."
            ),
        },
    )
    def get(self, request: Request) -> Response:
        query = PrayerCitySearchQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        cities = search_prayer_cities(query.validated_data["q"], query.validated_data["locale"])
        return Response(PrayerCitySearchResponseSerializer({"results": cities}).data)

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise PrayerCitySearchRateLimitedError(wait=wait)

    def get_throttles(self) -> list[BaseThrottle]:
        return [throttle() for throttle in self.throttle_classes]
