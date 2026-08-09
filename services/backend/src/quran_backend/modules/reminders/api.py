from __future__ import annotations

import uuid
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
from quran_backend.modules.reminders.exceptions import ReminderRateLimitExceeded
from quran_backend.modules.reminders.serializers import (
    ReminderCreateSerializer,
    ReminderDeleteSerializer,
    ReminderFullSnapshotSerializer,
    ReminderOutputSerializer,
    ReminderPatchSerializer,
)
from quran_backend.modules.reminders.services import (
    create_reminder,
    delete_reminder,
    full_reminder_snapshot,
    get_reminder_snapshot,
    patch_reminder,
)
from quran_backend.modules.reminders.throttling import ReminderMutationThrottle


def _authenticated_user(request: Request) -> User:
    return cast(User, request.user)


def _authenticated_device(request: Request) -> Device | None:
    if isinstance(request.auth, AccessAuthContext):
        return request.auth.device
    return None


class ReminderRateLimitMixin:
    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReminderRateLimitExceeded(wait=wait)


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reminders"])
class ReminderListCreateView(
    ReminderRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "POST":
            return [ReminderMutationThrottle()]
        return []

    @extend_schema(
        operation_id="reminder_full_snapshot",
        responses={
            status.HTTP_200_OK: ReminderFullSnapshotSerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
        },
    )
    def get(self, request: Request) -> Response:
        return Response(full_reminder_snapshot(_authenticated_user(request)))

    @extend_schema(
        operation_id="reminder_create",
        request=ReminderCreateSerializer,
        responses={
            status.HTTP_200_OK: ReminderOutputSerializer,
            status.HTTP_201_CREATED: ReminderOutputSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Request validation failed."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_409_CONFLICT: OpenApiResponse(
                description="The id is reused or a user quota has been reached."
            ),
            status.HTTP_410_GONE: OpenApiResponse(
                description="The UUID belongs to a deleted reminder and cannot be resurrected."
            ),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Reminder mutation rate limit exceeded."
            ),
        },
    )
    def post(self, request: Request) -> Response:
        serializer = ReminderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        entity, created = create_reminder(
            user=_authenticated_user(request),
            device=_authenticated_device(request),
            data=dict(serializer.validated_data),
        )
        return Response(entity, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["reminders"])
class ReminderDetailView(
    ReminderRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method in {
            "PATCH",
            "DELETE",
        }:
            return [ReminderMutationThrottle()]
        return []

    @extend_schema(
        operation_id="reminder_retrieve",
        responses={
            status.HTTP_200_OK: ReminderOutputSerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Reminder was not found."),
        },
    )
    def get(self, request: Request, reminder_id: uuid.UUID) -> Response:
        return Response(get_reminder_snapshot(_authenticated_user(request), reminder_id))

    @extend_schema(
        operation_id="reminder_patch",
        request=ReminderPatchSerializer,
        responses={
            status.HTTP_200_OK: ReminderOutputSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Request validation failed."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Reminder was not found."),
            status.HTTP_409_CONFLICT: OpenApiResponse(description="Revision conflict."),
            status.HTTP_410_GONE: OpenApiResponse(description="Reminder is a tombstone."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Reminder mutation rate limit exceeded."
            ),
        },
    )
    def patch(self, request: Request, reminder_id: uuid.UUID) -> Response:
        serializer = ReminderPatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(
            patch_reminder(
                user=_authenticated_user(request),
                device=_authenticated_device(request),
                reminder_id=reminder_id,
                data=dict(serializer.validated_data),
            )
        )

    @extend_schema(
        operation_id="reminder_delete",
        request=ReminderDeleteSerializer,
        responses={
            status.HTTP_200_OK: ReminderOutputSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Request validation failed."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Reminder was not found."),
            status.HTTP_409_CONFLICT: OpenApiResponse(description="Revision conflict."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(
                description="Reminder mutation rate limit exceeded."
            ),
        },
    )
    def delete(self, request: Request, reminder_id: uuid.UUID) -> Response:
        serializer = ReminderDeleteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(
            delete_reminder(
                user=_authenticated_user(request),
                device=_authenticated_device(request),
                reminder_id=reminder_id,
                data=dict(serializer.validated_data),
            )
        )
