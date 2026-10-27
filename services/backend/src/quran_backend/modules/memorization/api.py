from __future__ import annotations

import uuid
from typing import Any, NoReturn, cast

from django.utils.decorators import method_decorator
from django.views.decorators.debug import sensitive_post_parameters
from drf_spectacular.utils import extend_schema
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.memorization.items import (
    add_memorization_selection,
    delete_memorization_item,
    preview_memorization_selection,
    update_memorization_item,
)
from quran_backend.modules.memorization.serializers import (
    MemorizationDashboardOutputSerializer,
    MemorizationItemAddSerializer,
    MemorizationItemDeleteQuerySerializer,
    MemorizationItemMutationOutputSerializer,
    MemorizationItemUpdateSerializer,
    MemorizationPlanOutputSerializer,
    MemorizationPlanWriteSerializer,
    MemorizationQuerySerializer,
    MemorizationResetQuerySerializer,
    MemorizationSelectionPreviewOutputSerializer,
    MemorizationSelectionSerializer,
    MemorizationSessionCreateSerializer,
    MemorizationSessionOutputSerializer,
)
from quran_backend.modules.memorization.services import (
    get_memorization_dashboard,
    plan_snapshot,
    record_memorization_session,
    reset_today_memorization_progress,
    session_snapshot,
    set_memorization_plan,
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


class MemorizationMutationRateLimitMixin:
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(getattr(self, "request", None), "method", None) in {
            "DELETE",
            "PATCH",
            "POST",
            "PUT",
        }:
            return [ReadingMutationRateThrottle()]
        return []

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)


@extend_schema(tags=["memorization"])
class MemorizationDashboardView(
    MemorizationMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="memorization_dashboard_retrieve",
        responses=MemorizationDashboardOutputSerializer,
        parameters=[MemorizationQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        query = MemorizationQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(
            get_memorization_dashboard(
                _authenticated_user(request),
                fallback_timezone_name=query.validated_data.get("timezone_name"),
                recent_days=query.validated_data["recent_days"],
            )
        )

    @extend_schema(
        operation_id="memorization_plan_set",
        request=MemorizationPlanWriteSerializer,
        responses={
            status.HTTP_200_OK: MemorizationPlanOutputSerializer,
            status.HTTP_201_CREATED: MemorizationPlanOutputSerializer,
        },
    )
    def put(self, request: Request) -> Response:
        serializer = MemorizationPlanWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        plan, created = set_memorization_plan(
            user=_authenticated_user(request),
            **data,
        )
        return Response(
            plan_snapshot(plan),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@method_decorator(sensitive_post_parameters(), name="dispatch")
@extend_schema(tags=["memorization"])
class MemorizationSessionCreateView(
    MemorizationMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="memorization_session_create",
        request=MemorizationSessionCreateSerializer,
        responses={
            status.HTTP_200_OK: MemorizationSessionOutputSerializer,
            status.HTTP_201_CREATED: MemorizationSessionOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = MemorizationSessionCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        session_id = data.pop("id")
        session, created = record_memorization_session(
            user=_authenticated_user(request),
            session_id=session_id,
            **data,
        )
        return Response(
            session_snapshot(session),
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @extend_schema(
        operation_id="memorization_today_progress_reset",
        parameters=[MemorizationResetQuerySerializer],
        responses={status.HTTP_204_NO_CONTENT: None},
    )
    def delete(self, request: Request) -> Response:
        query = MemorizationResetQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        reset_today_memorization_progress(
            _authenticated_user(request),
            fallback_timezone_name=query.validated_data.get("timezone_name"),
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


def _selection_bounds(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "edition_code": data.pop("edition_code"),
        "start": (data.pop("start_surah"), data.pop("start_ayah")),
        "end": (data.pop("end_surah"), data.pop("end_ayah")),
    }


@extend_schema(tags=["memorization"])
class MemorizationItemListView(
    MemorizationMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="memorization_item_add",
        request=MemorizationItemAddSerializer,
        responses={
            status.HTTP_200_OK: MemorizationItemMutationOutputSerializer,
            status.HTTP_201_CREATED: MemorizationItemMutationOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = MemorizationItemAddSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        result = add_memorization_selection(
            user=_authenticated_user(request),
            **_selection_bounds(data),
            **data,
        )
        return Response(
            result,
            status=status.HTTP_200_OK
            if result["result"] == "duplicate"
            else status.HTTP_201_CREATED,
        )


@extend_schema(tags=["memorization"])
class MemorizationSelectionPreviewView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="memorization_selection_preview",
        parameters=[MemorizationSelectionSerializer],
        responses=MemorizationSelectionPreviewOutputSerializer,
    )
    def get(self, request: Request) -> Response:
        query = MemorizationSelectionSerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(
            preview_memorization_selection(
                _authenticated_user(request),
                **_selection_bounds(dict(query.validated_data)),
            )
        )


@extend_schema(tags=["memorization"])
class MemorizationItemDetailView(
    MemorizationMutationRateLimitMixin,
    PrivateNoStoreResponseMixin,
    APIView,
):
    @extend_schema(
        operation_id="memorization_item_update",
        request=MemorizationItemUpdateSerializer,
        responses=MemorizationItemMutationOutputSerializer,
    )
    def patch(self, request: Request, item_id: uuid.UUID) -> Response:
        serializer = MemorizationItemUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = _bind_authenticated_device(request, dict(serializer.validated_data))
        return Response(
            update_memorization_item(
                user=_authenticated_user(request),
                item_id=item_id,
                **data,
            )
        )

    @extend_schema(
        operation_id="memorization_item_delete",
        parameters=[MemorizationItemDeleteQuerySerializer],
        responses=MemorizationItemMutationOutputSerializer,
    )
    def delete(self, request: Request, item_id: uuid.UUID) -> Response:
        query = MemorizationItemDeleteQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(
            delete_memorization_item(
                user=_authenticated_user(request),
                item_id=item_id,
                base_revision=query.validated_data["base_revision"],
            )
        )
