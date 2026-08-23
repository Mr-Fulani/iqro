from __future__ import annotations

from django.urls import path

from quran_backend.modules.accounts.views import (
    EmailChallengeStartView,
    EmailChallengeVerifyView,
    GuestBootstrapView,
    LogoutAllView,
    LogoutView,
    RefreshTokenView,
)

app_name = "accounts"

urlpatterns = [
    path("guest", GuestBootstrapView.as_view(), name="guest-bootstrap"),
    path("email/start", EmailChallengeStartView.as_view(), name="email-start"),
    path("email/verify", EmailChallengeVerifyView.as_view(), name="email-verify"),
    path("token/refresh", RefreshTokenView.as_view(), name="token-refresh"),
    path("logout", LogoutView.as_view(), name="logout"),
    path("logout-all", LogoutAllView.as_view(), name="logout-all"),
]
