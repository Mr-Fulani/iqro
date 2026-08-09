from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta
from typing import TypedDict
from uuid import UUID

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.db import transaction
from django.db.models import Count, Exists, OuterRef, QuerySet
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.reading.models import SyncChange, SyncOperation
from quran_backend.modules.reminders.models import ReminderRule, RetiredReminderId
from quran_backend.modules.reminders.policies import reminder_id_policy


class ReminderPruneResult(TypedDict):
    dry_run: bool
    tombstones: int
    retired_ids_evicted: int
    has_more: bool
    retention_days: int


def prune_reminder_tombstones(
    *,
    now: datetime | None = None,
    dry_run: bool = False,
) -> ReminderPruneResult:
    """Replace one bounded batch of expired tombstones with compact ID ledgers."""

    effective_now = now or timezone.now()
    policy = reminder_id_policy()
    if not policy.is_safe:
        raise ImproperlyConfigured(
            "QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS must exceed the unseen reminder "
            "UUIDv7 age window plus QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS."
        )
    batch_size = _positive_setting("QURAN_REMINDER_PRUNE_BATCH_SIZE", 5_000)
    retired_limit = _positive_setting("QURAN_RETIRED_REMINDER_ID_MAX_PER_USER", 50_000)
    cutoff = effective_now - timedelta(days=policy.tombstone_retention_days)

    if dry_run:
        candidates = list(_eligible_tombstones(cutoff)[:batch_size])
        selected = _limit_per_user(candidates, retired_limit)
        return {
            "dry_run": True,
            "tombstones": len(selected),
            "retired_ids_evicted": _required_evictions(selected, retired_limit),
            "has_more": _eligible_tombstones(cutoff).count() > len(selected),
            "retention_days": policy.tombstone_retention_days,
        }

    tombstones, evicted = _prune_batch(
        cutoff=cutoff,
        batch_size=batch_size,
        retired_limit=retired_limit,
        retired_at=effective_now,
    )
    return {
        "dry_run": False,
        "tombstones": tombstones,
        "retired_ids_evicted": evicted,
        "has_more": _eligible_tombstones(cutoff).exists(),
        "retention_days": policy.tombstone_retention_days,
    }


def _eligible_tombstones(cutoff: datetime) -> QuerySet[ReminderRule]:
    retained_changes = SyncChange.objects.filter(
        user_id=OuterRef("user_id"),
        entity_type="reminder",
        entity_id=OuterRef("id"),
    )
    retained_operations = SyncOperation.objects.filter(
        user_id=OuterRef("user_id"),
        entity_type="reminder",
        entity_id=OuterRef("id"),
    )
    return (
        ReminderRule.objects.filter(deleted_at__lt=cutoff)
        .annotate(has_retained_change=Exists(retained_changes))
        .annotate(has_retained_operation=Exists(retained_operations))
        .filter(has_retained_change=False, has_retained_operation=False)
        .order_by("deleted_at", "id")
    )


@transaction.atomic
def _prune_batch(
    *,
    cutoff: datetime,
    batch_size: int,
    retired_limit: int,
    retired_at: datetime,
) -> tuple[int, int]:
    candidate_rows = list(_eligible_tombstones(cutoff).values_list("id", "user_id")[:batch_size])
    candidate_ids = _limit_candidate_ids_per_user(candidate_rows, retired_limit)
    if not candidate_ids:
        return 0, 0

    candidate_id_set = set(candidate_ids)
    user_ids = sorted(
        {user_id for reminder_id, user_id in candidate_rows if reminder_id in candidate_id_set}
    )
    # Match the create path's lock order: User first, then ReminderRule. This
    # serializes ledger/quota decisions without a create-vs-prune deadlock.
    list(User.objects.select_for_update().filter(id__in=user_ids).order_by("id").only("id"))
    tombstones = list(
        _eligible_tombstones(cutoff)
        .select_for_update(of=("self",), skip_locked=True)
        .filter(id__in=candidate_ids)
    )
    if not tombstones:
        return 0, 0

    selected = _limit_per_user(tombstones, retired_limit)
    evicted = _evict_for_capacity(selected, retired_limit)
    RetiredReminderId.objects.bulk_create(
        [
            RetiredReminderId(
                reminder_id=tombstone.id,
                user_id=tombstone.user_id,
                last_revision=tombstone.revision,
                retired_at=retired_at,
            )
            for tombstone in selected
        ]
    )
    selected_ids = [tombstone.id for tombstone in selected]
    ReminderRule.objects.filter(id__in=selected_ids).delete()
    return len(selected_ids), evicted


def _limit_candidate_ids_per_user(
    rows: list[tuple[UUID, UUID]],
    retired_limit: int,
) -> list[UUID]:
    counts: Counter[UUID] = Counter()
    selected: list[UUID] = []
    for reminder_id, user_id in rows:
        if counts[user_id] >= retired_limit:
            continue
        counts[user_id] += 1
        selected.append(reminder_id)
    return selected


def _limit_per_user(
    tombstones: list[ReminderRule],
    retired_limit: int,
) -> list[ReminderRule]:
    counts: Counter[UUID] = Counter()
    selected: list[ReminderRule] = []
    for tombstone in tombstones:
        if counts[tombstone.user_id] >= retired_limit:
            continue
        counts[tombstone.user_id] += 1
        selected.append(tombstone)
    return selected


def _required_evictions(tombstones: list[ReminderRule], retired_limit: int) -> int:
    additions: Counter[UUID] = Counter(tombstone.user_id for tombstone in tombstones)
    existing = dict(
        RetiredReminderId.objects.filter(user_id__in=additions)
        .values_list("user_id")
        .annotate(total_count=Count("reminder_id"))
    )
    return sum(
        max(0, existing.get(user_id, 0) + addition_count - retired_limit)
        for user_id, addition_count in additions.items()
    )


def _evict_for_capacity(tombstones: list[ReminderRule], retired_limit: int) -> int:
    by_user: dict[UUID, list[ReminderRule]] = defaultdict(list)
    for tombstone in tombstones:
        by_user[tombstone.user_id].append(tombstone)

    evicted = 0
    for user_id, additions in by_user.items():
        current_count = RetiredReminderId.objects.filter(user_id=user_id).count()
        excess = max(0, current_count + len(additions) - retired_limit)
        if not excess:
            continue
        # Every ledger row was created only after the tombstone outlived the
        # accepted UUIDv7 window. Evicted IDs therefore remain non-reusable by
        # the create-path freshness policy.
        retired_ids = list(
            RetiredReminderId.objects.filter(user_id=user_id)
            .order_by("retired_at", "reminder_id")
            .values_list("reminder_id", flat=True)[:excess]
        )
        deleted, _ = RetiredReminderId.objects.filter(reminder_id__in=retired_ids).delete()
        evicted += deleted
    return evicted


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
