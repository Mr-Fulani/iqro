from __future__ import annotations

from django.urls import path

from quran_backend.modules.reminders.api import (
    ReminderDetailView,
    ReminderListCreateView,
    WebPushSubscriptionView,
)

app_name = "reminders"

urlpatterns = [
    path("me/reminders", ReminderListCreateView.as_view(), name="reminder-list"),
    path(
        "me/reminders/<uuid:reminder_id>",
        ReminderDetailView.as_view(),
        name="reminder-detail",
    ),
    path("me/web-push", WebPushSubscriptionView.as_view(), name="web-push"),
]
