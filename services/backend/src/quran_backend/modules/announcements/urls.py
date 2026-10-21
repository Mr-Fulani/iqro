from __future__ import annotations

from django.urls import path

from quran_backend.modules.announcements.api import (
    ActiveAnnouncementsView,
    AnnouncementDetailView,
    AnnouncementEventsView,
    AnnouncementFeedView,
    AnnouncementReceiptDetailView,
    AnnouncementReceiptListView,
    AnnouncementRedirectView,
)

app_name = "announcements"

urlpatterns = [
    path("announcements", AnnouncementFeedView.as_view(), name="feed"),
    path("announcements/active", ActiveAnnouncementsView.as_view(), name="active"),
    path("announcements/events", AnnouncementEventsView.as_view(), name="events"),
    path("announcements/<uuid:announcement_id>", AnnouncementDetailView.as_view(), name="detail"),
    path(
        "announcements/<uuid:announcement_id>/go",
        AnnouncementRedirectView.as_view(),
        name="go",
    ),
    path("me/announcement-receipts", AnnouncementReceiptListView.as_view(), name="receipt-list"),
    path(
        "me/announcement-receipts/<uuid:announcement_id>",
        AnnouncementReceiptDetailView.as_view(),
        name="receipt-detail",
    ),
]
