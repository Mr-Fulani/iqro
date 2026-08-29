from __future__ import annotations

from django.urls import path

from quran_backend.modules.share_referrals.api import (
    MyReferralLinkView,
    MyReferralSummaryView,
    ReferralRedirectView,
    ShareConfigView,
    ShareEventCreateView,
)

app_name = "share-referrals"

urlpatterns = [
    path("api/v1/share/config", ShareConfigView.as_view(), name="share-config"),
    path("api/v1/share/events", ShareEventCreateView.as_view(), name="share-event-create"),
    path("api/v1/me/referrals/links", MyReferralLinkView.as_view(), name="my-referral-link"),
    path(
        "api/v1/me/referrals/summary",
        MyReferralSummaryView.as_view(),
        name="my-referral-summary",
    ),
    path("r/<str:code>", ReferralRedirectView.as_view(), name="referral-redirect"),
]
