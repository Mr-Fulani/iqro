from __future__ import annotations

from typing import Any, cast

from django.utils.cache import patch_vary_headers
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.feedback.models import FeedbackStatus
from quran_backend.modules.feedback.serializers import (
    FeedbackMessageCreateSerializer,
    FeedbackTicketCreateSerializer,
    FeedbackTicketDetailSerializer,
    FeedbackTicketPageSerializer,
    FeedbackTransitionSerializer,
)
from quran_backend.modules.feedback.services import (
    add_reporter_message,
    close_ticket,
    create_ticket,
    get_ticket,
    list_tickets,
    reopen_ticket,
    ticket_detail_snapshot,
    ticket_summary_snapshot,
)
from quran_backend.modules.feedback.throttling import FeedbackWriteRateThrottle


def _authenticated_user(request: Request) -> User:
    return cast(User, request.user)


def _channel(request: Request) -> str:
    if isinstance(request.auth, AccessAuthContext):
        return str(request.auth.device.platform)
    return "web"


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


class FeedbackTicketCursorPagination(CursorPagination):
    page_size = 25
    page_size_query_param = "page_size"
    max_page_size = 100
    ordering = ("-created_at", "-id")


@extend_schema(tags=["feedback"])
class FeedbackTicketListCreateView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="feedback_ticket_list",
        responses=FeedbackTicketPageSerializer,
        parameters=[
            OpenApiParameter("cursor", str, OpenApiParameter.QUERY),
            OpenApiParameter("page_size", int, OpenApiParameter.QUERY),
            OpenApiParameter(
                "status",
                str,
                OpenApiParameter.QUERY,
                enum=list(FeedbackStatus.values),
            ),
        ],
    )
    def get(self, request: Request) -> Response:
        tickets = list_tickets(_authenticated_user(request))
        status_filter = request.query_params.get("status")
        if status_filter:
            if status_filter not in FeedbackStatus.values:
                raise ValidationError({"status": "Unknown feedback ticket status."})
            tickets = tickets.filter(status=status_filter)
        paginator = FeedbackTicketCursorPagination()
        page = paginator.paginate_queryset(tickets, request, view=self)
        if page is None:  # pragma: no cover - page size is configured above.
            msg = "Feedback pagination is not configured."
            raise RuntimeError(msg)
        return paginator.get_paginated_response(
            [ticket_summary_snapshot(ticket) for ticket in page]
        )

    @extend_schema(
        operation_id="feedback_ticket_create",
        request=FeedbackTicketCreateSerializer,
        responses={
            status.HTTP_200_OK: FeedbackTicketDetailSerializer,
            status.HTTP_201_CREATED: FeedbackTicketDetailSerializer,
        },
    )
    def post(self, request: Request) -> Response:
        serializer = FeedbackTicketCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ticket, created = create_ticket(
            _authenticated_user(request),
            dict(serializer.validated_data),
            channel=_channel(request),
        )
        response_status = status.HTTP_201_CREATED if created else status.HTTP_200_OK
        return Response(ticket_detail_snapshot(ticket), status=response_status)

    def get_throttles(self) -> list[BaseThrottle]:
        if getattr(self, "request", None) is not None and self.request.method == "POST":
            return [FeedbackWriteRateThrottle()]
        return []


@extend_schema(tags=["feedback"])
class FeedbackTicketDetailView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="feedback_ticket_retrieve",
        responses=FeedbackTicketDetailSerializer,
        parameters=[OpenApiParameter("public_id", str, OpenApiParameter.PATH)],
    )
    def get(self, request: Request, public_id: str) -> Response:
        ticket = get_ticket(_authenticated_user(request), public_id)
        return Response(ticket_detail_snapshot(ticket))


@extend_schema(tags=["feedback"])
class FeedbackMessageCreateView(PrivateNoStoreResponseMixin, APIView):
    throttle_classes = [FeedbackWriteRateThrottle]

    @extend_schema(
        operation_id="feedback_message_create",
        request=FeedbackMessageCreateSerializer,
        responses={
            status.HTTP_200_OK: FeedbackTicketDetailSerializer,
            status.HTTP_201_CREATED: FeedbackTicketDetailSerializer,
        },
        parameters=[OpenApiParameter("public_id", str, OpenApiParameter.PATH)],
    )
    def post(self, request: Request, public_id: str) -> Response:
        serializer = FeedbackMessageCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ticket, _message, created = add_reporter_message(
            _authenticated_user(request),
            public_id,
            dict(serializer.validated_data),
        )
        response_status = status.HTTP_201_CREATED if created else status.HTTP_200_OK
        return Response(ticket_detail_snapshot(ticket), status=response_status)


@extend_schema(tags=["feedback"])
class FeedbackTicketCloseView(PrivateNoStoreResponseMixin, APIView):
    throttle_classes = [FeedbackWriteRateThrottle]

    @extend_schema(
        operation_id="feedback_ticket_close",
        request=FeedbackTransitionSerializer,
        responses=FeedbackTicketDetailSerializer,
        parameters=[OpenApiParameter("public_id", str, OpenApiParameter.PATH)],
    )
    def post(self, request: Request, public_id: str) -> Response:
        serializer = FeedbackTransitionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ticket = close_ticket(
            _authenticated_user(request),
            public_id,
            reason=str(serializer.validated_data.get("reason", "")),
        )
        return Response(ticket_detail_snapshot(ticket))


@extend_schema(tags=["feedback"])
class FeedbackTicketReopenView(PrivateNoStoreResponseMixin, APIView):
    throttle_classes = [FeedbackWriteRateThrottle]

    @extend_schema(
        operation_id="feedback_ticket_reopen",
        request=FeedbackTransitionSerializer,
        responses=FeedbackTicketDetailSerializer,
        parameters=[OpenApiParameter("public_id", str, OpenApiParameter.PATH)],
    )
    def post(self, request: Request, public_id: str) -> Response:
        serializer = FeedbackTransitionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        ticket = reopen_ticket(
            _authenticated_user(request),
            public_id,
            reason=str(serializer.validated_data.get("reason", "")),
        )
        return Response(ticket_detail_snapshot(ticket))
