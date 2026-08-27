from __future__ import annotations

from drf_spectacular.utils import extend_schema
from rest_framework import generics

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.website.models import SocialProfile
from quran_backend.modules.website.selectors import public_social_profiles
from quran_backend.modules.website.serializers import SocialProfileSerializer


@extend_schema(tags=["website"])
class SocialProfileListView(PublicReadOnlyViewMixin, generics.ListAPIView[SocialProfile]):
    serializer_class = SocialProfileSerializer
    pagination_class = None

    def get_queryset(self):  # type: ignore[no-untyped-def]
        return public_social_profiles()
