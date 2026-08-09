from __future__ import annotations

import uuid
from typing import Any, NoReturn, cast

from django.utils.cache import patch_vary_headers
from drf_spectacular.utils import OpenApiParameter, PolymorphicProxySerializer, extend_schema
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.reading.serializers import (
    BookmarkCreateSerializer,
    BookmarkDeleteSerializer,
    BookmarkListQuerySerializer,
    BookmarkOutputSerializer,
    BookmarkPageOutputSerializer,
    BookmarkUpdateSerializer,
    FullResyncResponseSerializer,
    ReadingPositionOutputSerializer,
    ReadingPositionWriteSerializer,
    SyncCursorExpiredResponseSerializer,
    SyncPullQuerySerializer,
    SyncPullResponseSerializer,
    SyncPushResponseSerializer,
    SyncPushSerializer,
)
from quran_backend.modules.reading.services import (
    SyncCursorExpiredError,
    apply_sync_batch,
    bookmark_snapshot,
    create_bookmark_direct,
    delete_bookmark_direct,
    full_resync_page,
    get_bookmark,
    get_reading_position,
    list_bookmarks,
    pull_changes,
    reading_position_snapshot,
    update_bookmark_direct,
    upsert_reading_position_direct,
)
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
    SyncPushThrottle,
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


class PrivateNoStoreResponseMixin:
    def finalize_response(
        self,
        request: Request,
        response: Response,
        *args: Any,
        **kwargs: Any,
    ) -> Response:
        response = super().finalize_response(request, response, *args, **kwargs)  # type: ignore[misc]
        response["Cache-Control"] = "private, no-store"
        response["Pragma"] = "no-cache"
        response["Expires"] = "0"
        patch_vary_headers(response, ("Authorization",))
        return response


class ReadingRateLimitMixin:
    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)


class BookmarkCursorPagination(CursorPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 200
    ordering = ("-updated_at", "-id")


@extend_schema(tags=["reading"])
class ReadingPositionView(ReadingRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "PUT":
            return [ReadingMutationRateThrottle()]
        return []

    @extend_schema(
        responses=ReadingPositionOutputSerializer,
        parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
    )
    def get(self, request: Request, edition: str) -> Response:
        position = get_reading_position(_authenticated_user(request), edition)
        return Response(reading_position_snapshot(position))

    @extend_schema(
        request=ReadingPositionWriteSerializer,
        responses=ReadingPositionOutputSerializer,
        parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
    )
    def put(self, request: Request, edition: str) -> Response:
        body = dict(request.data)
        body["edition_code"] = edition
        serializer = ReadingPositionWriteSerializer(data=body)
        serializer.is_valid(raise_exception=True)
        entity = upsert_reading_position_direct(
            _authenticated_user(request),
            _bind_authenticated_device(request, dict(serializer.validated_data)),
        )
        return Response(entity)


@extend_schema(tags=["reading"])
class BookmarkListCreateView(ReadingRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "POST":
            return [ReadingMutationRateThrottle()]
        return []

    @extend_schema(
        operation_id="bookmark_list",
        responses=BookmarkPageOutputSerializer,
        parameters=[BookmarkListQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        query = BookmarkListQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        include_deleted = query.validated_data["include_deleted"]
        bookmarks = list_bookmarks(
            _authenticated_user(request),
            include_deleted=include_deleted,
        )
        paginator = BookmarkCursorPagination()
        page = paginator.paginate_queryset(bookmarks, request, view=self)
        if page is None:  # pragma: no cover - page_size is always configured.
            msg = "Bookmark cursor pagination is not configured."
            raise RuntimeError(msg)
        return paginator.get_paginated_response([bookmark_snapshot(bookmark) for bookmark in page])

    @extend_schema(
        operation_id="bookmark_create",
        request=BookmarkCreateSerializer,
        responses={
            status.HTTP_200_OK: BookmarkOutputSerializer,
            status.HTTP_201_CREATED: BookmarkOutputSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = BookmarkCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        entity, created = create_bookmark_direct(
            _authenticated_user(request),
            _bind_authenticated_device(request, dict(serializer.validated_data)),
        )
        response_status = status.HTTP_201_CREATED if created else status.HTTP_200_OK
        return Response(entity, status=response_status)


@extend_schema(tags=["reading"])
class BookmarkDetailView(ReadingRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method in {
            "PATCH",
            "DELETE",
        }:
            return [ReadingMutationRateThrottle()]
        return []

    @extend_schema(operation_id="bookmark_retrieve", responses=BookmarkOutputSerializer)
    def get(self, request: Request, bookmark_id: uuid.UUID) -> Response:
        bookmark = get_bookmark(_authenticated_user(request), bookmark_id)
        return Response(bookmark_snapshot(bookmark))

    @extend_schema(
        operation_id="bookmark_update",
        request=BookmarkUpdateSerializer,
        responses=BookmarkOutputSerializer,
    )
    def patch(self, request: Request, bookmark_id: uuid.UUID) -> Response:
        serializer = BookmarkUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        entity = update_bookmark_direct(
            _authenticated_user(request),
            bookmark_id,
            _bind_authenticated_device(request, dict(serializer.validated_data)),
        )
        return Response(entity)

    @extend_schema(
        operation_id="bookmark_delete",
        request=None,
        responses={status.HTTP_200_OK: BookmarkOutputSerializer},
        parameters=[BookmarkDeleteSerializer],
    )
    def delete(self, request: Request, bookmark_id: uuid.UUID) -> Response:
        serializer = BookmarkDeleteSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        entity = delete_bookmark_direct(
            _authenticated_user(request),
            bookmark_id,
            _bind_authenticated_device(request, dict(serializer.validated_data)),
        )
        return Response(entity)


@extend_schema(tags=["sync"])
class SyncPushView(ReadingRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    throttle_classes = (SyncPushThrottle,)

    @extend_schema(request=SyncPushSerializer, responses=SyncPushResponseSerializer)
    def post(self, request: Request) -> Response:
        serializer = SyncPushSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        operations = cast(list[dict[str, Any]], serializer.validated_data["operations"])
        operations = [
            _bind_authenticated_device(request, dict(operation)) for operation in operations
        ]
        result = apply_sync_batch(_authenticated_user(request), operations)
        return Response(result)


@extend_schema(tags=["sync"])
class SyncPullView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        responses={
            status.HTTP_200_OK: PolymorphicProxySerializer(
                component_name="SyncPullOrFullResyncResponse",
                serializers={
                    "incremental": SyncPullResponseSerializer,
                    "full_resync": FullResyncResponseSerializer,
                },
                resource_type_field_name="mode",
            ),
            (
                status.HTTP_410_GONE,
                "application/problem+json",
            ): SyncCursorExpiredResponseSerializer,
        },
        parameters=[SyncPullQuerySerializer],
    )
    def get(self, request: Request) -> Response:
        serializer = SyncPullQuerySerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        try:
            if serializer.validated_data["full_resync"]:
                result = full_resync_page(
                    _authenticated_user(request),
                    limit=serializer.validated_data["limit"],
                    page_token=serializer.validated_data.get("page_token"),
                )
            else:
                result = pull_changes(
                    _authenticated_user(request),
                    cursor=serializer.validated_data.get("cursor", 0),
                    limit=serializer.validated_data["limit"],
                )
        except SyncCursorExpiredError as exc:
            return _sync_cursor_expired_response(request, exc)
        return Response(result)


def _sync_cursor_expired_response(
    request: Request,
    exc: SyncCursorExpiredError,
) -> Response:
    return Response(
        {
            "type": "https://api.quran.example/problems/sync_cursor_expired",
            "title": "Gone",
            "status": status.HTTP_410_GONE,
            "code": "sync_cursor_expired",
            "detail": str(exc.detail),
            "instance": request.path,
            "request_id": str(getattr(request, "request_id", "-")),
            "full_resync_required": True,
            "minimum_valid_cursor": exc.minimum_valid_cursor,
            "current_cursor": exc.current_cursor,
        },
        status=status.HTTP_410_GONE,
        content_type="application/problem+json",
    )
