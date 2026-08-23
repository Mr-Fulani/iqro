from __future__ import annotations

from django.urls import path

from quran_backend.modules.accounts.views import CurrentSessionView

app_name = "account_user"

urlpatterns = [
    path("me", CurrentSessionView.as_view(), name="me"),
]
