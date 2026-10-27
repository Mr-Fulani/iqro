from __future__ import annotations

from django.urls import path

from quran_backend.modules.memorization.api import (
    MemorizationDashboardView,
    MemorizationItemDetailView,
    MemorizationItemListView,
    MemorizationSelectionPreviewView,
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
    path("me/memorization-items", MemorizationItemListView.as_view(), name="item-list"),
    path(
        "me/memorization-items/preview",
        MemorizationSelectionPreviewView.as_view(),
        name="item-preview",
    ),
    path(
        "me/memorization-items/<uuid:item_id>",
        MemorizationItemDetailView.as_view(),
        name="item-detail",
    ),
]
