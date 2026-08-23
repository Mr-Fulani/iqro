from __future__ import annotations

from django.urls import path

from quran_backend.modules.core.api import (
    LiveHealthView,
    MetricsView,
    OperationalHealthView,
    ReadyHealthView,
)

app_name = "core"

urlpatterns = [
    path("health/live", LiveHealthView.as_view(), name="health-live"),
    path("health/ready", ReadyHealthView.as_view(), name="health-ready"),
    path("health/operations", OperationalHealthView.as_view(), name="health-operations"),
    path("metrics", MetricsView.as_view(), name="metrics"),
]
