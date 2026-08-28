from __future__ import annotations

from django.urls import path

from quran_backend.modules.memorization.api import (
    MemorizationDashboardView,
    MemorizationSessionCreateView,
)

app_name = "memorization"

urlpatterns = [
    path("me/memorization", MemorizationDashboardView.as_view(), name="dashboard"),
    path(
        "me/memorization-sessions",
        MemorizationSessionCreateView.as_view(),
        name="session-create",
    ),
]
