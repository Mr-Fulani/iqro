from __future__ import annotations

from datetime import timedelta

from celery import shared_task
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from quran_backend.modules.announcements.models import (
    Announcement,
    AnnouncementSettings,
    AnnouncementStatus,
)
from quran_backend.modules.core.content_revalidation import enqueue_announcements_change

# The beat runs every five minutes; a first run looks back a little further.
FIRST_LOOKBACK = timedelta(minutes=10)


@shared_task(name="announcements.revalidate_window_changes")  # type: ignore[untyped-decorator]
def revalidate_window_changes() -> bool:
    """Refresh the site when a published announcement starts or leaves the home screen."""
    with transaction.atomic():
        settings_row, _ = AnnouncementSettings.objects.select_for_update().get_or_create(
            singleton=True
        )
        now = timezone.now()
        since = settings_row.window_checked_at or now - FIRST_LOOKBACK
        changed = Announcement.objects.filter(
            Q(starts_at__gt=since, starts_at__lte=now) | Q(ends_at__gt=since, ends_at__lte=now),
            status=AnnouncementStatus.PUBLISHED,
        ).exists()
        settings_row.window_checked_at = now
        settings_row.save(update_fields=["window_checked_at", "updated_at"])
        if changed:
            enqueue_announcements_change(action="scheduled")
    return changed
