# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Course statistics and ratings API (docs/courses/README.md, «Отзывы и статистика»)."""

from __future__ import annotations

from typing import Any

from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import serializers, status
from rest_framework.exceptions import NotFound
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.course_feedback.serializers import (
    CourseEventBatchSerializer,
    CourseEventResultSerializer,
    CourseRatingSerializer,
)
from quran_backend.modules.course_feedback.services import live_courses, rate_course, record_events
from quran_backend.modules.course_feedback.throttling import (
    CourseEventRateThrottle,
    CourseRatingRateThrottle,
)
from quran_backend.modules.courses.api import NOT_FOUND


class CourseRatingResultSerializer(serializers.Serializer[Any]):
    stars = serializers.IntegerField()
    comment = serializers.CharField(allow_blank=True)
    updated_at = serializers.DateTimeField()


class CourseEventsView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (CourseEventRateThrottle,)

    @extend_schema(
        tags=["courses"],
        operation_id="courses_events",
        request=CourseEventBatchSerializer,
        responses={202: CourseEventResultSerializer, 400: None, 429: None},
        description=(
            "Обезличенные события тем: открыли, начали и досмотрели видео, отметили "
            "изученной, «Полезно» и «Не очень». Хранятся только суммы за день по курсу, "
            "теме, платформе и событию: без человека, устройства и адреса."
        ),
    )
    def post(self, request: Request) -> Response:
        batch = CourseEventBatchSerializer(data=request.data)
        batch.is_valid(raise_exception=True)
        accepted = record_events(
            platform=batch.validated_data["platform"],
            events=[
                (item["course"], item["lesson"], item["event"])
                for item in batch.validated_data["events"]
            ],
        )
        response = Response({"accepted": accepted}, status=status.HTTP_202_ACCEPTED)
        response["Cache-Control"] = "no-store"
        return response


class CourseRatingView(PrivateNoStoreResponseMixin, APIView):
    throttle_classes = (CourseRatingRateThrottle,)

    @extend_schema(
        tags=["courses"],
        operation_id="courses_rating_set",
        request=CourseRatingSerializer,
        responses={
            200: CourseRatingResultSerializer,
            400: None,
            401: None,
            404: OpenApiResponse(description=f"«{NOT_FOUND}»"),
            429: None,
        },
        description=(
            "Оценка курса от 1 до 5 и необязательный комментарий. Нужен вход, хотя бы "
            "гостевой: одна оценка на установку или аккаунт, повторная заменяет прежнюю. "
            "Хранится не аккаунт, а необратимый ключ; оценки и комментарии видит только админ."
        ),
    )
    def put(self, request: Request, slug: str) -> Response:
        body = CourseRatingSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        course = live_courses([slug]).get(slug)
        if course is None:
            raise NotFound(NOT_FOUND)
        rating = rate_course(course=course, voter_id=request.user.pk, **body.validated_data)
        return Response(
            {"stars": rating.stars, "comment": rating.comment, "updated_at": rating.updated_at}
        )
