from __future__ import annotations

import base64
import binascii
import json
import uuid
from datetime import datetime
from typing import Any, NoReturn, cast

from django.http import HttpResponse, HttpResponseRedirect
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.announcements.models import (
    ActionType,
    Announcement,
    AnnouncementReceipt,
)
from quran_backend.modules.announcements.routes import external_url_allowed
from quran_backend.modules.announcements.selectors import (
    active_announcements,
    attach_reciters,
    feed_announcements,
    published_announcement,
    published_waves,
    visible_to,
)
from quran_backend.modules.announcements.serializers import (
    ActiveAnnouncementsSerializer,
    AnnouncementEventBatchSerializer,
    AnnouncementEventResultSerializer,
    AnnouncementFeedQuerySerializer,
    AnnouncementFeedSerializer,
    AnnouncementQuerySerializer,
    AnnouncementReceiptListSerializer,
    AnnouncementReceiptSerializer,
    AnnouncementReceiptWriteSerializer,
    AnnouncementSerializer,
    announcement_payload,
)
from quran_backend.modules.announcements.services import (
    announcements_enabled,
    receipt_snapshot,
    record_events,
    set_receipt,
)
from quran_backend.modules.announcements.throttling import AnnouncementEventRateThrottle
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)

FEED_PAGE_SIZE = 20
FEED_SCAN_CHUNK = 100


def _query(serializer_class: type[AnnouncementQuerySerializer], request: Request) -> dict[str, Any]:
    query = serializer_class(data=request.query_params)
    query.is_valid(raise_exception=True)
    return cast(dict[str, Any], query.validated_data)


def _encode_cursor(announcement: Announcement) -> str:
    raw = json.dumps([announcement.starts_at.isoformat(), str(announcement.id)])
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def _decode_cursor(value: str) -> tuple[datetime, uuid.UUID]:
    try:
        padded = value + "=" * (-len(value) % 4)
        starts_at, announcement_id = json.loads(base64.urlsafe_b64decode(padded))
        return datetime.fromisoformat(starts_at), uuid.UUID(announcement_id)
    except (binascii.Error, ValueError, TypeError) as exc:
        raise ValidationError({"cursor": "Unknown cursor."}) from exc


@extend_schema(tags=["announcements"])
class ActiveAnnouncementsView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="announcements_active",
        parameters=[AnnouncementQuerySerializer],
        responses=ActiveAnnouncementsSerializer,
        description=(
            "Announcements for the home screen now: the bubble on phones, the card and the "
            "step window on desktop. The same for every visitor; read and dismissed marks, "
            "bubble frequency and the guest/signed-in audience are applied by the client. "
            "Compare windows with the server time from the Date header, not the device clock."
        ),
    )
    def get(self, request: Request) -> Response:
        args = _query(AnnouncementQuerySerializer, request)
        now = timezone.now()
        enabled = announcements_enabled()
        results = (
            [
                announcement_payload(item, args["locale"])
                for item in active_announcements(
                    now=now,
                    platform=args["platform"],
                    locale=args["locale"],
                    app_version=args.get("app_version"),
                )
            ]
            if enabled
            else []
        )
        return Response({"enabled": enabled, "results": results})


@extend_schema(tags=["announcements"])
class AnnouncementFeedView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="announcements_feed",
        parameters=[AnnouncementFeedQuerySerializer],
        responses=AnnouncementFeedSerializer,
        description="The «What's new» feed, newest first; pinned items open the first page.",
    )
    def get(self, request: Request) -> Response:
        args = _query(AnnouncementFeedQuerySerializer, request)
        now = timezone.now()
        if not announcements_enabled():
            return Response({"next_cursor": None, "results": []})
        locale = args["locale"]

        def visible(item: Announcement) -> bool:
            return visible_to(
                item,
                platform=args["platform"],
                locale=locale,
                app_version=args.get("app_version"),
            )

        base = feed_announcements(now=now, kind=args.get("kind"))
        page: list[Announcement] = []
        cursor = args.get("cursor")
        if cursor is None:
            page.extend(
                item
                for item in base.filter(pinned=True).order_by("-starts_at", "-id")
                if visible(item)
            )
            remaining = base.filter(pinned=False)
        else:
            starts_at, announcement_id = _decode_cursor(cursor)
            remaining = (
                base.filter(pinned=False)
                .exclude(starts_at__gt=starts_at)
                .exclude(starts_at=starts_at, id__gte=announcement_id)
            )
        remaining = remaining.order_by("-starts_at", "-id")

        # Audience rules are checked in Python, so scan until one item past the page.
        offset = 0
        regular: list[Announcement] = []
        while len(regular) <= FEED_PAGE_SIZE:
            chunk = list(remaining[offset : offset + FEED_SCAN_CHUNK])
            if not chunk:
                break
            offset += len(chunk)
            regular.extend(item for item in chunk if visible(item))
        next_cursor = None
        if len(regular) > FEED_PAGE_SIZE:
            regular = regular[:FEED_PAGE_SIZE]
            next_cursor = _encode_cursor(regular[-1])
        page.extend(regular)
        attach_reciters(page)
        return Response(
            {
                "next_cursor": next_cursor,
                "results": [announcement_payload(item, locale) for item in page],
            }
        )


@extend_schema(tags=["announcements"])
class AnnouncementDetailView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="announcements_detail",
        parameters=[AnnouncementQuerySerializer],
        responses={200: AnnouncementSerializer, 404: None},
    )
    def get(self, request: Request, announcement_id: uuid.UUID) -> Response:
        args = _query(AnnouncementQuerySerializer, request)
        announcement = published_announcement(announcement_id, now=timezone.now())
        if (
            announcement is None
            or not announcements_enabled()
            or not visible_to(
                announcement,
                platform=args["platform"],
                locale=args["locale"],
                app_version=args.get("app_version"),
            )
        ):
            raise NotFound("The announcement was not found.")
        return Response(announcement_payload(announcement, args["locale"]))


@extend_schema(tags=["announcements"])
class AnnouncementRedirectView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (AnnouncementEventRateThrottle,)

    @extend_schema(
        operation_id="announcements_go",
        parameters=[
            OpenApiParameter("platform", str, enum=["web", "android", "ios"], required=False),
            OpenApiParameter(
                "surface",
                str,
                enum=["bubble", "card", "feed", "modal", "push"],
                required=False,
            ),
        ],
        responses={
            302: OpenApiResponse(description="Redirect to the allowed external page."),
            404: OpenApiResponse(description="No published external link."),
        },
    )
    def get(self, request: Request, announcement_id: uuid.UUID) -> HttpResponse:
        announcement = published_announcement(announcement_id, now=timezone.now())
        if (
            announcement is None
            or announcement.action_type != ActionType.EXTERNAL
            or not external_url_allowed(announcement.action_url)
        ):
            raise NotFound("The link was not found.")
        platform = request.query_params.get("platform", "web")
        surface = request.query_params.get("surface", "card")
        if platform in {"web", "android", "ios"} and surface in {
            "bubble",
            "card",
            "feed",
            "modal",
            "push",
        }:
            record_events(
                platform=platform,
                events=[(announcement.id, surface, "click", None)],
                published_waves={announcement.id: announcement.wave},
            )
        response = HttpResponseRedirect(announcement.action_url)
        response["Cache-Control"] = "no-store"
        response["Referrer-Policy"] = "no-referrer"
        return response


@extend_schema(tags=["announcements"])
class AnnouncementEventsView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (AnnouncementEventRateThrottle,)

    @extend_schema(
        operation_id="announcements_events",
        request=AnnouncementEventBatchSerializer,
        responses={202: AnnouncementEventResultSerializer, 400: None, 429: None},
        description=(
            "Anonymous impressions, opens, clicks and dismissals. Only daily sums per "
            "announcement, platform, surface and event are kept: no person, device or address."
        ),
    )
    def post(self, request: Request) -> Response:
        batch = AnnouncementEventBatchSerializer(data=request.data)
        batch.is_valid(raise_exception=True)
        events = [
            (item["id"], item["surface"], item["event"], item.get("wave"))
            for item in batch.validated_data["events"]
        ]
        accepted = record_events(
            platform=batch.validated_data["platform"],
            events=events,
            published_waves=published_waves({item[0] for item in events}),
        )
        response = Response({"accepted": accepted}, status=status.HTTP_202_ACCEPTED)
        response["Cache-Control"] = "no-store"
        return response


@extend_schema(tags=["announcements"])
class AnnouncementReceiptListView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="announcement_receipts_list",
        responses={200: AnnouncementReceiptListSerializer, 401: None},
    )
    def get(self, request: Request) -> Response:
        receipts = AnnouncementReceipt.objects.filter(user=cast(User, request.user))
        return Response({"results": [receipt_snapshot(receipt) for receipt in receipts]})


@extend_schema(tags=["announcements"])
class AnnouncementReceiptDetailView(PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        return [ReadingMutationRateThrottle()]

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)

    @extend_schema(
        operation_id="announcement_receipt_set",
        request=AnnouncementReceiptWriteSerializer,
        responses={200: AnnouncementReceiptSerializer, 400: None, 401: None, 404: None, 429: None},
        description=(
            "Marks only move forward: read or dismissed can not be undone. `wave` is the "
            "wave the announcement was shown in: the mark hides it until the next wave."
        ),
    )
    def put(self, request: Request, announcement_id: uuid.UUID) -> Response:
        body = AnnouncementReceiptWriteSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        announcement = published_announcement(announcement_id, now=timezone.now())
        if announcement is None:
            raise NotFound("The announcement was not found.")
        receipt = set_receipt(
            user=cast(User, request.user),
            announcement=announcement,
            read=body.validated_data["read"],
            dismissed=body.validated_data["dismissed"],
            wave=body.validated_data.get("wave"),
        )
        return Response(receipt_snapshot(receipt))
