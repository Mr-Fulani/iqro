from __future__ import annotations

import uuid
from datetime import datetime

from django.db.models import Prefetch, Q, QuerySet

from quran_backend.modules.announcements.models import (
    Announcement,
    AnnouncementKind,
    AnnouncementStatus,
    AnnouncementStep,
    AnnouncementTranslation,
)
from quran_backend.modules.audio.models import Reciter

MAX_ACTIVE = 10


def _with_content(queryset: QuerySet[Announcement]) -> QuerySet[Announcement]:
    return queryset.prefetch_related(
        Prefetch("translations", queryset=AnnouncementTranslation.objects.order_by("language")),
        Prefetch("step_images", queryset=AnnouncementStep.objects.order_by("order")),
    )


def attach_reciters(announcements: list[Announcement]) -> list[Announcement]:
    """Look up the reciters of «listen» buttons in one query instead of one each."""
    ids = {item.action_reciter for item in announcements if item.action_reciter}
    reciters = Reciter.objects.in_bulk(ids) if ids else {}
    for item in announcements:
        if item.action_reciter:
            item._reciter_cache = (item.action_reciter, reciters.get(item.action_reciter))
    return announcements


def _version_tuple(value: str) -> tuple[int, int, int]:
    parts = [int(part) for part in value.split(".")]
    return (*parts, 0, 0, 0)[:3]  # type: ignore[return-value]


def visible_to(
    announcement: Announcement,
    *,
    platform: str,
    locale: str,
    app_version: str | None,
) -> bool:
    """The audience rules that do not depend on who is asking, so answers stay cacheable."""
    if platform not in announcement.audience_platforms:
        return False
    # Store rules: money is asked for on the site only (see the plan, decision 1).
    if announcement.kind == AnnouncementKind.FUNDRAISING and platform != "web":
        return False
    if locale not in announcement.audience_languages:
        return False
    if platform != "web" and app_version:
        version = _version_tuple(app_version)
        if announcement.app_version_min and version < _version_tuple(announcement.app_version_min):
            return False
        if announcement.app_version_max and version > _version_tuple(announcement.app_version_max):
            return False
    return True


def published_announcements() -> QuerySet[Announcement]:
    return _with_content(Announcement.objects.filter(status=AnnouncementStatus.PUBLISHED))


def active_announcements(
    *,
    now: datetime,
    platform: str,
    locale: str,
    app_version: str | None,
) -> list[Announcement]:
    """What may appear on the home screen right now: bubble, card or window."""
    candidates = published_announcements().filter(starts_at__lte=now, ends_at__gt=now)
    candidates = candidates.filter(
        Q(channel_bubble=True) | Q(channel_home_card=True) | Q(channel_modal=True)
    ).order_by("-pinned", "-starts_at", "-id")
    chosen = [
        item
        for item in candidates
        if visible_to(item, platform=platform, locale=locale, app_version=app_version)
    ]
    return attach_reciters(chosen[:MAX_ACTIVE])


def feed_announcements(*, now: datetime, kind: str | None) -> QuerySet[Announcement]:
    queryset = published_announcements().filter(starts_at__lte=now)
    if kind:
        queryset = queryset.filter(kind=kind)
    return queryset


def published_announcement(announcement_id: uuid.UUID, *, now: datetime) -> Announcement | None:
    return published_announcements().filter(pk=announcement_id, starts_at__lte=now).first()


def published_ids(candidates: set[uuid.UUID]) -> set[uuid.UUID]:
    return set(
        Announcement.objects.filter(
            pk__in=candidates,
            status=AnnouncementStatus.PUBLISHED,
        ).values_list("pk", flat=True)
    )
