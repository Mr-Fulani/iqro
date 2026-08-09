from __future__ import annotations

from django.urls import path

from quran_backend.modules.prayer_times.api import PrayerCalculateView, PrayerMethodsView

app_name = "prayer_times"

urlpatterns = [
    path("methods", PrayerMethodsView.as_view(), name="methods"),
    path("calculate", PrayerCalculateView.as_view(), name="calculate"),
]
