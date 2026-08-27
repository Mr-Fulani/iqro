from __future__ import annotations

from rest_framework import serializers

from quran_backend.modules.website.models import SocialProfile


class SocialProfileSerializer(serializers.ModelSerializer[SocialProfile]):
    platform_name = serializers.CharField(source="get_platform_display", read_only=True)
    url = serializers.URLField(source="profile_url", read_only=True)

    class Meta:
        model = SocialProfile
        fields = (
            "platform",
            "platform_name",
            "display_name",
            "url",
            "sort_order",
            "include_in_seo",
        )
