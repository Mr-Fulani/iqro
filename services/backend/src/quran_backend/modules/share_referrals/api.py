from __future__ import annotations

from typing import cast

from django.http import HttpResponse, HttpResponseRedirect
from django.urls import reverse
from drf_spectacular.utils import OpenApiExample, OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.share_referrals.permissions import IsVerifiedAccount
from quran_backend.modules.share_referrals.selectors import select_available_campaign
from quran_backend.modules.share_referrals.serializers import (
    ReferralLinkOutputSerializer,
    ReferralLinkRequestSerializer,
    ReferralRedirectQuerySerializer,
    ReferralSummarySerializer,
    ShareConfigQuerySerializer,
    ShareConfigResponseSerializer,
    ShareEventCreateSerializer,
    ShareEventOutputSerializer,
)
from quran_backend.modules.share_referrals.services import (
    get_or_create_referral_link,
    ingest_share_event,
    localized_campaign,
    record_click,
    referral_link_url,
    referral_summary,
)
from quran_backend.modules.share_referrals.throttling import (
    ReferralLinkRateThrottle,
    ReferralRedirectRateThrottle,
    ShareEventRateThrottle,
)


def _user(request: Request) -> User:
    return cast(User, request.user)


@extend_schema(tags=["share & referrals"])
class ShareConfigView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="share_config_retrieve",
        parameters=[
            OpenApiParameter("locale", str, OpenApiParameter.QUERY, default="en"),
            OpenApiParameter("campaign", str, OpenApiParameter.QUERY, required=False),
        ],
        responses={status.HTTP_200_OK: ShareConfigResponseSerializer},
        examples=[
            OpenApiExample(
                "Active Russian campaign",
                value={
                    "available": True,
                    "fallback_reason": None,
                    "requested_locale": "ru",
                    "used_fallback": False,
                    "campaign": {
                        "key": "app-invite",
                        "config_version": 7,
                        "updated_at": "2026-08-30T12:00:00Z",
                        "locale": "ru",
                        "title": "Поделиться IQRO",
                        "message": "Попробуйте IQRO.",
                        "cta_label": "Поделиться",
                        "canonical_download_url": "https://iqro.example/download",
                        "ios_url": "",
                        "android_url": "",
                        "referral_enabled": True,
                    },
                },
                response_only=True,
            )
        ],
        description=(
            "Returns active remote share copy and trusted download URLs. "
            "`available=false` tells the client to use its bundled fallback."
        ),
    )
    def get(self, request: Request) -> Response:
        query = ShareConfigQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        locale = str(query.validated_data["locale"])
        campaign_key = query.validated_data.get("campaign")
        localized = localized_campaign(
            str(campaign_key) if campaign_key else None,
            locale,
        )
        if localized is None:
            return Response(
                {
                    "available": False,
                    "fallback_reason": "no_active_localized_campaign",
                    "requested_locale": locale,
                    "used_fallback": True,
                    "campaign": None,
                }
            )
        campaign = localized.campaign
        copy = localized.copy
        return Response(
            {
                "available": True,
                "fallback_reason": None,
                "requested_locale": locale,
                "used_fallback": localized.used_fallback,
                "campaign": {
                    "key": campaign.key,
                    "config_version": campaign.config_version,
                    "updated_at": campaign.updated_at,
                    "locale": copy.locale,
                    "title": copy.title,
                    "message": copy.message,
                    "cta_label": copy.cta_label,
                    "canonical_download_url": campaign.canonical_download_url,
                    "ios_url": campaign.ios_url,
                    "android_url": campaign.android_url,
                    "referral_enabled": campaign.referral_enabled,
                },
            }
        )


@extend_schema(tags=["share & referrals"])
class MyReferralLinkView(PrivateNoStoreResponseMixin, APIView):
    permission_classes = (IsVerifiedAccount,)
    throttle_classes = (ReferralLinkRateThrottle,)

    @extend_schema(
        operation_id="my_referral_link_get_or_create",
        request=ReferralLinkRequestSerializer,
        responses={
            status.HTTP_200_OK: ReferralLinkOutputSerializer,
            status.HTTP_201_CREATED: ReferralLinkOutputSerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_403_FORBIDDEN: OpenApiResponse(description="Verified account required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Campaign unavailable."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(description="Rate limit exceeded."),
        },
        examples=[
            OpenApiExample(
                "Get or create link",
                value={"campaign_key": "app-invite"},
                request_only=True,
            )
        ],
    )
    def post(self, request: Request) -> Response:
        serializer = ReferralLinkRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        campaign_key = serializer.validated_data.get("campaign_key")
        campaign = select_available_campaign(str(campaign_key) if campaign_key else None)
        # The service produces the canonical domain error for a missing campaign.
        key = str(campaign_key or "") if campaign is None else campaign.key
        link, created = get_or_create_referral_link(_user(request), key)
        fallback_base = request.build_absolute_uri(
            reverse("share-referrals:referral-redirect", kwargs={"code": "CODE"})
        ).removesuffix("CODE")
        body = {
            "campaign_key": link.campaign.key,
            "code": link.code,
            "short_url": referral_link_url(link, fallback_base=fallback_base),
            "is_enabled": link.is_enabled,
            "created_at": link.created_at,
        }
        return Response(body, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


@extend_schema(tags=["share & referrals"])
class MyReferralSummaryView(PrivateNoStoreResponseMixin, APIView):
    permission_classes = (IsVerifiedAccount,)

    @extend_schema(
        operation_id="my_referral_summary_retrieve",
        parameters=[
            OpenApiParameter("campaign", str, OpenApiParameter.QUERY, required=False),
        ],
        responses={
            status.HTTP_200_OK: ReferralSummarySerializer,
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_403_FORBIDDEN: OpenApiResponse(description="Verified account required."),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(description="Campaign unavailable."),
        },
    )
    def get(self, request: Request) -> Response:
        campaign_key = request.query_params.get("campaign")
        return Response(referral_summary(_user(request), campaign_key))


@extend_schema(tags=["share & referrals"])
class ShareEventCreateView(PrivateNoStoreResponseMixin, APIView):
    throttle_classes = (ShareEventRateThrottle,)

    @extend_schema(
        operation_id="share_event_ingest",
        request=ShareEventCreateSerializer,
        responses={
            status.HTTP_200_OK: ShareEventOutputSerializer,
            status.HTTP_201_CREATED: ShareEventOutputSerializer,
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Invalid event payload."),
            status.HTTP_401_UNAUTHORIZED: OpenApiResponse(description="Authentication required."),
            status.HTTP_409_CONFLICT: OpenApiResponse(
                description="Event idempotency conflict or invalid event time."
            ),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(description="Rate limit exceeded."),
        },
        examples=[
            OpenApiExample(
                "Existing ShareGateway envelope",
                value={
                    "eventId": "019c4a44-b3d0-7a00-8000-000000000001",
                    "campaignId": "app-invite",
                    "action": "open-system-share",
                    "result": "shared",
                    "occurredAt": "2026-08-30T12:00:00Z",
                    "accountMode": "verified",
                },
                request_only=True,
            )
        ],
    )
    def post(self, request: Request) -> Response:
        serializer = ShareEventCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        event, created = ingest_share_event(_user(request), dict(serializer.validated_data))
        return Response(
            {
                "client_event_id": event.client_event_id,
                "accepted": True,
                "replayed": not created,
                "received_at": event.received_at,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


@extend_schema(tags=["share & referrals"])
class ReferralRedirectView(APIView):
    authentication_classes = ()
    permission_classes = (AllowAny,)
    throttle_classes = (ReferralRedirectRateThrottle,)

    @extend_schema(
        operation_id="referral_short_link_redirect",
        parameters=[
            OpenApiParameter("code", str, OpenApiParameter.PATH),
            OpenApiParameter(
                "channel",
                str,
                OpenApiParameter.QUERY,
                required=False,
                enum=["system", "copy", "whatsapp", "telegram", "email", "sms", "other"],
            ),
        ],
        responses={
            status.HTTP_302_FOUND: OpenApiResponse(
                description="Redirect to the server-owned canonical download URL."
            ),
            status.HTTP_404_NOT_FOUND: OpenApiResponse(
                description="Unknown, disabled, revoked or expired referral code."
            ),
            status.HTTP_400_BAD_REQUEST: OpenApiResponse(description="Unsupported channel."),
            status.HTTP_429_TOO_MANY_REQUESTS: OpenApiResponse(description="Rate limit exceeded."),
        },
    )
    def get(self, request: Request, code: str) -> HttpResponse:
        query = ReferralRedirectQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        _click, target = record_click(code, channel=str(query.validated_data["channel"]))
        response = HttpResponseRedirect(target)
        response["Cache-Control"] = "private, no-store, max-age=0"
        response["Referrer-Policy"] = "no-referrer"
        return response
