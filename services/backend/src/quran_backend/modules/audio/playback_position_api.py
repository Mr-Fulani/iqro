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
from quran_backend.modules.audio.playback_position_serializers import (
    AudioPlaybackPositionEnvelopeSerializer,
    AudioPlaybackPositionSerializer,
    AudioPlaybackPositionWriteSerializer,
)
from quran_backend.modules.audio.playback_positions import (
    get_audio_playback_position,
    put_audio_playback_position,
)
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["audio-playback-position"])
class AudioPlaybackPositionView(PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "PUT":
            return [ReadingMutationRateThrottle()]
        return []

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait=wait)

    @extend_schema(
        operation_id="audio_playback_position_retrieve",
        responses={
            status.HTTP_200_OK: AudioPlaybackPositionEnvelopeSerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
        },
    )
    def get(self, request: Request) -> Response:
        position = get_audio_playback_position(cast(User, request.user))
        return Response(
            {
                "position": (
                    AudioPlaybackPositionSerializer(position).data if position is not None else None
                )
            }
        )

    @extend_schema(
        operation_id="audio_playback_position_replace",
        request=AudioPlaybackPositionWriteSerializer,
        responses={
            status.HTTP_200_OK: AudioPlaybackPositionEnvelopeSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Validation failed."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_409_CONFLICT: OpenApiResponse(description="Revision conflict."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Reading mutation rate limit exceeded."
            ),
        },
    )
    def put(self, request: Request) -> Response:
        serializer = AudioPlaybackPositionWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        position = put_audio_playback_position(
            user=cast(User, request.user),
            device=_authenticated_device(request),
            data=dict(serializer.validated_data),
        )
        return Response({"position": AudioPlaybackPositionSerializer(position).data})


def _authenticated_device(request: Request) -> Device | None:
    if isinstance(request.auth, AccessAuthContext):
        return request.auth.device
    return None
