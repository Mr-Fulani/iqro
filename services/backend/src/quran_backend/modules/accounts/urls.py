from __future__ import annotations

from django.urls import path

from quran_backend.modules.accounts.views import (
    GuestBootstrapView,
    LogoutAllView,
    LogoutView,
    RefreshTokenView,
)

app_name = "accounts"

urlpatterns = [
    path("guest", GuestBootstrapView.as_view(), name="guest-bootstrap"),
    path("token/refresh", RefreshTokenView.as_view(), name="token-refresh"),
    path("logout", LogoutView.as_view(), name="logout"),
    path("logout-all", LogoutAllView.as_view(), name="logout-all"),
]
