from __future__ import annotations

from django.urls import path

from quran_backend.modules.core.api import LiveHealthView, ReadyHealthView

app_name = "core"

urlpatterns = [
    path("health/live", LiveHealthView.as_view(), name="health-live"),
    path("health/ready", ReadyHealthView.as_view(), name="health-ready"),
]
