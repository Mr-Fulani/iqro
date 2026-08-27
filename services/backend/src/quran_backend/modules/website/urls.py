from __future__ import annotations

from django.urls import path

from quran_backend.modules.website.api import SocialProfileListView

app_name = "website"

urlpatterns = [
    path("social-profiles", SocialProfileListView.as_view(), name="social-profile-list"),
]
