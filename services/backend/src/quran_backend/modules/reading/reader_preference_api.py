from __future__ import annotations

from typing import cast

from django.utils.decorators import method_decorator
from django.views.decorators.debug import sensitive_post_parameters
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.reading.reader_preference_serializers import (
    QuranReaderPreferenceResponseSerializer,
    QuranReaderPreferenceWriteSerializer,
)
from quran_backend.modules.reading.reader_preferences import (
    get_quran_reader_preference,
    put_quran_reader_preference,
)


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["quran-reader-preference"])
class QuranReaderPreferenceView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="quran_reader_preference_retrieve",
        parameters=[OpenApiParameter("locale", str, OpenApiParameter.PATH)],
        responses={
            status.HTTP_200_OK: QuranReaderPreferenceResponseSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Unsupported locale."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
        },
    )
    def get(self, request: Request, locale: str) -> Response:
        return Response(get_quran_reader_preference(cast(User, request.user), locale))

    @extend_schema(
        operation_id="quran_reader_preference_replace",
        parameters=[OpenApiParameter("locale", str, OpenApiParameter.PATH)],
        request=QuranReaderPreferenceWriteSerializer,
        responses={
            status.HTTP_200_OK: QuranReaderPreferenceResponseSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Validation failed."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_409_CONFLICT: OpenApiResponse(description="Revision conflict."),
        },
    )
    def put(self, request: Request, locale: str) -> Response:
        serializer = QuranReaderPreferenceWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(
            put_quran_reader_preference(
                user=cast(User, request.user),
                device=_authenticated_device(request),
                locale=locale,
                data=dict(serializer.validated_data),
            )
        )


def _authenticated_device(request: Request) -> Device | None:
    if isinstance(request.auth, AccessAuthContext):
        return request.auth.device
    return None
