from __future__ import annotations

import uuid
from typing import Any, NoReturn, cast

from django.utils.decorators import method_decorator
from django.views.decorators.debug import sensitive_post_parameters
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.reading.habit_serializers import (
    AutomaticReadingSessionCreateSerializer,
    ManualReadingSessionCreateSerializer,
    ManualReadingSessionUpdateSerializer,
    PrayerReadingCheckInCreateSerializer,
    PrayerReadingCheckInDeleteSerializer,
    PrayerReadingCheckInOutputSerializer,
    PrayerReadingCheckInUpdateSerializer,
    PrayerReadingDayOutputSerializer,
    PrayerReadingPlanOutputSerializer,
    PrayerReadingPlanQuerySerializer,
    PrayerReadingPlanWriteSerializer,
    ReadingGoalDeleteSerializer,
    ReadingGoalEnvelopeSerializer,
    ReadingGoalOutputSerializer,
    ReadingGoalWriteSerializer,
    ReadingSessionDeleteSerializer,
    ReadingSessionListOutputSerializer,
    ReadingSessionListQuerySerializer,
    ReadingSessionOutputSerializer,
    TodayOutputSerializer,
    TodayQuerySerializer,
)
from quran_backend.modules.reading.habit_services import (
    ReadingGoalNotFoundError,
    archive_reading_goal,
    delete_prayer_reading_check_in,
    discard_manual_session,
    get_active_goal,
    get_prayer_reading_day,
    get_today_summary,
    goal_snapshot,
    list_reading_sessions,
    prayer_reading_check_in_snapshot,
    prayer_reading_plan_snapshot,
    record_automatic_session,
    record_manual_session,
    record_prayer_reading_check_in,
    session_snapshot,
    set_prayer_reading_plan,
    set_reading_goal,
    update_manual_session,
    update_prayer_reading_check_in,
)
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)


def _authenticated_user(request: Request) -> User:
    return cast(User, request.user)


def _bind_authenticated_device(request: Request, data: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(request.auth, AccessAuthContext):
        return data
    supplied_device_id = data.get("device_id")
    if supplied_device_id is not None and supplied_device_id != request.auth.device.id:
        raise ValidationError(
            {"device_id": "The device must match the authenticated access token."}
        )
    data["device_id"] = request.auth.device.id
    return data


class HabitMutationRateLimitMixin:
    def get_throttles(self) -> list[BaseThrottle]:
        method = getattr(getattr(self, "request", None), "method", None)
        if method in {
            "POST",
            "PUT",
            "PATCH",
            "DELETE",
        }:
            return [ReadingMutationRateThrottle()]
        return []

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)


@extend_schema(tags=["reading-habit"])
class TodayView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="reading_today",
        responses=TodayOutputSerializer,
        parameters=[TodayQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        query = TodayQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(
            get_today_summary(
                _authenticated_user(request),
                fallback_timezone_name=query.validated_data.get("timezone_name"),
            )
        )


@extend_schema(tags=["reading-habit"])
class ReadingGoalView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="reading_goal_retrieve",
        responses=ReadingGoalEnvelopeSerializer,
    )
    def get(self, request: Request) -> Response:
        goal = get_active_goal(_authenticated_user(request))
        return Response({"goal": goal_snapshot(goal) if goal is not None else None})

    @extend_schema(
        operation_id="reading_goal_set",
        request=ReadingGoalWriteSerializer,
        responses={
            status.HTTP_200_OK: ReadingGoalOutputSerializer,
            status.HTTP_201_CREATED: ReadingGoalOutputSerializer,
        },
    )
    def put(self, request: Request) -> Response:
        serializer = ReadingGoalWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        goal, created = set_reading_goal(
            user=_authenticated_user(request),
            **data,
        )
        return Response(
            goal_snapshot(goal),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @extend_schema(
        operation_id="reading_goal_archive",
        request=None,
        responses=ReadingGoalOutputSerializer,
        parameters=[ReadingGoalDeleteSerializer],
    )
    def delete(self, request: Request) -> Response:
        serializer = ReadingGoalDeleteSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        goal = archive_reading_goal(
            user=_authenticated_user(request),
            **dict(serializer.validated_data),
        )
        return Response(goal_snapshot(goal))


@extend_schema(tags=["reading-habit"])
class ReadingSessionListView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="reading_session_list",
        responses=ReadingSessionListOutputSerializer,
        parameters=[ReadingSessionListQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        query = ReadingSessionListQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        sessions = list_reading_sessions(
            _authenticated_user(request),
            limit=query.validated_data["limit"],
        )
        return Response({"results": [session_snapshot(session) for session in sessions]})


@extend_schema(tags=["reading-habit"])
class PrayerReadingPlanView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="prayer_reading_plan_retrieve",
        responses=PrayerReadingDayOutputSerializer,
        parameters=[PrayerReadingPlanQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        query = PrayerReadingPlanQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(
            get_prayer_reading_day(
                _authenticated_user(request),
                fallback_timezone_name=query.validated_data.get("timezone_name"),
            )
        )

    @extend_schema(
        operation_id="prayer_reading_plan_set",
        request=PrayerReadingPlanWriteSerializer,
        responses={
            status.HTTP_200_OK: PrayerReadingPlanOutputSerializer,
            status.HTTP_201_CREATED: PrayerReadingPlanOutputSerializer,
        },
    )
    def put(self, request: Request) -> Response:
        serializer = PrayerReadingPlanWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        plan, created = set_prayer_reading_plan(
            user=_authenticated_user(request),
            **data,
        )
        return Response(
            prayer_reading_plan_snapshot(plan),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reading-habit"])
class PrayerReadingCheckInCreateView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="prayer_reading_check_in_create",
        request=PrayerReadingCheckInCreateSerializer,
        responses={
            status.HTTP_200_OK: PrayerReadingCheckInOutputSerializer,
            status.HTTP_201_CREATED: PrayerReadingCheckInOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = PrayerReadingCheckInCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        check_in, created = record_prayer_reading_check_in(
            user=_authenticated_user(request),
            check_in_id=data.pop("id"),
            **data,
        )
        return Response(
            prayer_reading_check_in_snapshot(check_in),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["reading-habit"])
class PrayerReadingCheckInDetailView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="prayer_reading_check_in_update",
        request=PrayerReadingCheckInUpdateSerializer,
        responses=PrayerReadingCheckInOutputSerializer,
        parameters=[OpenApiParameter("check_in_id", uuid.UUID, OpenApiParameter.PATH)],
    )
    def patch(self, request: Request, check_in_id: uuid.UUID) -> Response:
        serializer = PrayerReadingCheckInUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        check_in = update_prayer_reading_check_in(
            user=_authenticated_user(request),
            check_in_id=check_in_id,
            **data,
        )
        return Response(prayer_reading_check_in_snapshot(check_in))

    @extend_schema(
        operation_id="prayer_reading_check_in_delete",
        request=None,
        responses={status.HTTP_204_NO_CONTENT: None},
        parameters=[PrayerReadingCheckInDeleteSerializer],
    )
    def delete(self, request: Request, check_in_id: uuid.UUID) -> Response:
        serializer = PrayerReadingCheckInDeleteSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        delete_prayer_reading_check_in(
            user=_authenticated_user(request),
            check_in_id=check_in_id,
            **data,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reading-habit"])
class AutomaticReadingSessionCreateView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="reading_session_automatic_create",
        request=AutomaticReadingSessionCreateSerializer,
        responses={
            status.HTTP_200_OK: ReadingSessionOutputSerializer,
            status.HTTP_201_CREATED: ReadingSessionOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = AutomaticReadingSessionCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        session, created = record_automatic_session(
            user=_authenticated_user(request),
            session_id=data.pop("id"),
            **data,
        )
        return Response(
            session_snapshot(session),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reading-habit"])
class ManualReadingSessionCreateView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="reading_session_manual_create",
        request=ManualReadingSessionCreateSerializer,
        responses={
            status.HTTP_200_OK: ReadingSessionOutputSerializer,
            status.HTTP_201_CREATED: ReadingSessionOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = ManualReadingSessionCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        session, created = record_manual_session(
            user=_authenticated_user(request),
            session_id=data.pop("id"),
            **data,
        )
        return Response(
            session_snapshot(session),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reading-habit"])
class ManualReadingSessionDetailView(
    HabitMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="reading_session_manual_update",
        request=ManualReadingSessionUpdateSerializer,
        responses=ReadingSessionOutputSerializer,
        parameters=[OpenApiParameter("session_id", uuid.UUID, OpenApiParameter.PATH)],
    )
    def patch(self, request: Request, session_id: uuid.UUID) -> Response:
        serializer = ManualReadingSessionUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        session = update_manual_session(
            user=_authenticated_user(request),
            session_id=session_id,
            **data,
        )
        return Response(session_snapshot(session))

    @extend_schema(
        operation_id="reading_session_manual_delete",
        request=None,
        responses=ReadingSessionOutputSerializer,
        parameters=[ReadingSessionDeleteSerializer],
    )
    def delete(self, request: Request, session_id: uuid.UUID) -> Response:
        serializer = ReadingSessionDeleteSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        session = discard_manual_session(
            user=_authenticated_user(request),
            session_id=session_id,
            **data,
        )
        return Response(session_snapshot(session))


__all__ = [
    "AutomaticReadingSessionCreateView",
    "ManualReadingSessionCreateView",
    "ManualReadingSessionDetailView",
    "PrayerReadingCheckInCreateView",
    "PrayerReadingCheckInDetailView",
    "PrayerReadingPlanView",
    "ReadingGoalNotFoundError",
    "ReadingGoalView",
    "ReadingSessionListView",
    "TodayView",
]
