# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The learner's own tajweed data: lesson progress of a course."""

from __future__ import annotations

from typing import Any, NoReturn

from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)
from quran_backend.modules.tajweed.progress import (
    TajweedProgressError,
    merge_user_progress,
    user_progress,
)


class TajweedLessonProgressSerializer(serializers.Serializer[Any]):
    status = serializers.ChoiceField(choices=["in_progress", "completed"])
    step_slug = serializers.CharField()
    content_version = serializers.CharField()
    updated_at = serializers.DateTimeField()


class TajweedProgressSerializer(serializers.Serializer[Any]):
    course = serializers.SlugField(read_only=True)
    lessons = serializers.DictField(child=TajweedLessonProgressSerializer())


class TajweedMutationRateLimitMixin:
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(getattr(self, "request", None), "method", None) in {"POST", "PUT"}:
            return [ReadingMutationRateThrottle()]
        return []

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)


@extend_schema(tags=["tajweed"])
class TajweedProgressView(TajweedMutationRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    @extend_schema(operation_id="tajweed_progress_retrieve", responses=TajweedProgressSerializer)
    def get(self, request: Request, course: str) -> Response:
        return Response(user_progress(request.user, course))

    @extend_schema(
        operation_id="tajweed_progress_merge",
        request=TajweedProgressSerializer,
        responses=TajweedProgressSerializer,
        description="Сливает переданные уроки с сохранёнными: пройденный урок остаётся "
        "пройденным, иначе побеждает более поздняя запись. Ответ — итог слияния.",
    )
    def put(self, request: Request, course: str) -> Response:
        data = request.data if isinstance(request.data, dict) else {}
        try:
            return Response(merge_user_progress(request.user, course, data.get("lessons")))
        except TajweedProgressError as error:
            raise ValidationError({"lessons": str(error)}) from error
