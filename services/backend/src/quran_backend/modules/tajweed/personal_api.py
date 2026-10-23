# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The learner's own tajweed data: lesson progress and practice results of a course."""

from __future__ import annotations

from typing import Any, NoReturn

from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.exceptions import APIException, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)
from quran_backend.modules.tajweed.practice import (
    PracticeSessionConflictError,
    PracticeSessionError,
    record_practice_session,
    user_practice_state,
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


class TajweedStreakSerializer(serializers.Serializer[Any]):
    current = serializers.IntegerField()
    best = serializers.IntegerField()
    last_date = serializers.DateField(allow_null=True)


class TajweedReviewItemSerializer(serializers.Serializer[Any]):
    key = serializers.CharField()
    target = serializers.CharField()
    type = serializers.CharField()
    box = serializers.IntegerField()
    due_at = serializers.DateTimeField()


class TajweedPracticeStateSerializer(serializers.Serializer[Any]):
    course = serializers.SlugField()
    sessions = serializers.IntegerField()
    answers = serializers.IntegerField()
    correct = serializers.IntegerField()
    score = serializers.IntegerField()
    streak = TajweedStreakSerializer()
    review = TajweedReviewItemSerializer(many=True)


class TajweedPracticeAnswerSerializer(serializers.Serializer[Any]):
    key = serializers.CharField()
    target = serializers.CharField()
    type = serializers.CharField()
    correct = serializers.BooleanField()
    at = serializers.DateTimeField()


class TajweedPracticeSessionSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    course = serializers.SlugField()
    local_date = serializers.DateField()
    finished_at = serializers.DateTimeField()
    answers = TajweedPracticeAnswerSerializer(many=True)


class PracticeSessionConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "Эта сессия уже сохранена с другими ответами."
    default_code = "practice_session_conflict"


@extend_schema(tags=["tajweed"])
class TajweedPracticeStateView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="tajweed_practice_retrieve", responses=TajweedPracticeStateSerializer
    )
    def get(self, request: Request, course: str) -> Response:
        return Response(user_practice_state(request.user, course))


@extend_schema(tags=["tajweed"])
class TajweedPracticeSessionView(
    TajweedMutationRateLimitMixin, PrivateNoStoreResponseMixin, APIView
):
    @extend_schema(
        operation_id="tajweed_practice_session_create",
        request=TajweedPracticeSessionSerializer,
        responses={
            200: TajweedPracticeStateSerializer,
            201: TajweedPracticeStateSerializer,
            409: OpenApiTypes.OBJECT,
        },
        description="Сохраняет сессию практики один раз по её id и возвращает состояние: "
        "счёт, серию и задания на повторение.",
    )
    def post(self, request: Request) -> Response:
        try:
            state, created = record_practice_session(request.user, request.data)
        except PracticeSessionError as error:
            raise ValidationError({"session": str(error)}) from error
        except PracticeSessionConflictError as error:
            raise PracticeSessionConflict from error
        return Response(state, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
