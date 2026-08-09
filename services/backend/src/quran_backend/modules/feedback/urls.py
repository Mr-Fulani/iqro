from __future__ import annotations

from django.urls import path

from quran_backend.modules.feedback.api import (
    FeedbackMessageCreateView,
    FeedbackTicketCloseView,
    FeedbackTicketDetailView,
    FeedbackTicketListCreateView,
    FeedbackTicketReopenView,
)

app_name = "feedback"

urlpatterns = [
    path("tickets", FeedbackTicketListCreateView.as_view(), name="ticket-list"),
    path("tickets/<str:public_id>", FeedbackTicketDetailView.as_view(), name="ticket-detail"),
    path(
        "tickets/<str:public_id>/messages",
        FeedbackMessageCreateView.as_view(),
        name="message-create",
    ),
    path(
        "tickets/<str:public_id>/close",
        FeedbackTicketCloseView.as_view(),
        name="ticket-close",
    ),
    path(
        "tickets/<str:public_id>/reopen",
        FeedbackTicketReopenView.as_view(),
        name="ticket-reopen",
    ),
]
