from __future__ import annotations

from django.urls import path

from quran_backend.modules.prayer_times.profile_api import PrayerProfileView

app_name = "prayer_profile"

urlpatterns = [
    path("me/prayer-profile", PrayerProfileView.as_view(), name="detail"),
]
