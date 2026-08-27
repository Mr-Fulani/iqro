from __future__ import annotations

from django.db.models import QuerySet

from quran_backend.modules.website.models import SocialProfile


def public_social_profiles() -> QuerySet[SocialProfile]:
    """Return only profiles that are explicitly publishable."""

    return (
        SocialProfile.objects.filter(is_active=True)
        .exclude(profile_url="")
        .order_by(
            "sort_order",
            "platform",
        )
    )
