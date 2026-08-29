from __future__ import annotations

from django.db.models import Q, QuerySet
from django.utils import timezone

from quran_backend.modules.share_referrals.models import ShareCampaign


def available_campaigns() -> QuerySet[ShareCampaign]:
    now = timezone.now()
    return (
        ShareCampaign.objects.filter(is_active=True)
        .filter(Q(starts_at__isnull=True) | Q(starts_at__lte=now))
        .filter(Q(ends_at__isnull=True) | Q(ends_at__gt=now))
        .prefetch_related("localized_copies")
        .order_by("-priority", "key")
    )


def select_available_campaign(key: str | None = None) -> ShareCampaign | None:
    queryset = available_campaigns()
    if key:
        queryset = queryset.filter(key=key.strip().lower())
    return queryset.first()
