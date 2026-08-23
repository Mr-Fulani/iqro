from __future__ import annotations

from django.urls import path

from quran_backend.modules.accounts.views import (
    AccountDeletionCancelView,
    AccountDeletionRequestView,
    CurrentSessionView,
    DeviceDetailView,
    DeviceListView,
)

app_name = "account_user"

urlpatterns = [
    path("me", CurrentSessionView.as_view(), name="me"),
    path("me/devices", DeviceListView.as_view(), name="devices"),
    path("me/devices/<uuid:device_id>", DeviceDetailView.as_view(), name="device-detail"),
    path(
        "me/deletion-request",
        AccountDeletionRequestView.as_view(),
        name="deletion-request",
    ),
    path(
        "me/deletion-cancel",
        AccountDeletionCancelView.as_view(),
        name="deletion-cancel",
    ),
]
