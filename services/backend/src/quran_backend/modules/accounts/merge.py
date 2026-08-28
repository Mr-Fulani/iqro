from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.accounts.exceptions import AccountLinkUnavailable
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Consent,
    Device,
    GuestMergeAudit,
    RefreshSession,
    RefreshToken,
    User,
    UserStatus,
)
from quran_backend.modules.feedback.models import FeedbackAudit, FeedbackMessage, FeedbackTicket
from quran_backend.modules.memorization.models import MemorizationPlan, MemorizationSession
from quran_backend.modules.prayer_times.models import PrayerProfile
from quran_backend.modules.reading.change_log import append_sync_change
from quran_backend.modules.reading.habit_services import recalculate_reading_streak
from quran_backend.modules.reading.models import (
    Bookmark,
    GoalProgress,
    PrayerReadingCheckIn,
    PrayerReadingPlan,
    QuranReaderPreference,
    ReadingGoal,
    ReadingGoalStatus,
    ReadingPosition,
    ReadingSession,
    ReadingStreak,
    RetiredBookmarkId,
    SyncAction,
    SyncChange,
    SyncEntityType,
    SyncOperation,
    UserSyncCursor,
)
from quran_backend.modules.reading.services import bookmark_snapshot, reading_position_snapshot
from quran_backend.modules.reminders.models import ReminderRule, RetiredReminderId
from quran_backend.modules.reminders.services import reminder_sync_snapshot


@dataclass(frozen=True, slots=True)
class GuestMergeResult:
    target_user: User
    moved_counts: dict[str, int]
    replayed: bool


@transaction.atomic
def merge_guest_into_account(
    *,
    source_user: User,
    target_user: User,
    trigger_identity: AuthIdentity,
    idempotency_key: uuid.UUID,
) -> GuestMergeResult:
    """Move all supported guest-owned state into an existing active account."""

    locked_users = {
        user.id: user
        for user in User.objects.select_for_update()
        .filter(id__in=(source_user.id, target_user.id))
        .order_by("id")
    }
    source = locked_users.get(source_user.id)
    target = locked_users.get(target_user.id)
    if source is None or target is None or source.id == target.id:
        raise AccountLinkUnavailable

    existing_audit = (
        GuestMergeAudit.objects.select_for_update()
        .filter(source_user=source)
        .select_related("target_user")
        .first()
    )
    if existing_audit is not None:
        if (
            existing_audit.target_user_id != target.id
            or existing_audit.idempotency_key != idempotency_key
        ):
            raise AccountLinkUnavailable
        return GuestMergeResult(
            target_user=existing_audit.target_user,
            moved_counts={
                str(key): int(value) for key, value in existing_audit.moved_counts.items()
            },
            replayed=True,
        )

    if (
        source.status != UserStatus.GUEST
        or not source.is_active
        or target.status != UserStatus.ACTIVE
        or not target.is_active
        or trigger_identity.user_id != target.id
        or not trigger_identity.email_verified
    ):
        raise AccountLinkUnavailable

    counts: dict[str, int] = {}
    _move_devices_and_revoke_sessions(source=source, target=target, counts=counts)
    _merge_consents(source=source, target=target, counts=counts)
    _merge_reading_state(source=source, target=target, counts=counts)
    _merge_memorization_state(source=source, target=target, counts=counts)
    _merge_reminders(source=source, target=target, counts=counts)
    _merge_prayer_profile(source=source, target=target, counts=counts)
    _merge_feedback(source=source, target=target, counts=counts)
    _move_identities(source=source, target=target, counts=counts)
    _rebuild_target_sync_feed(source=source, target=target)

    source.status = UserStatus.DELETED
    source.is_active = False
    source.email = None
    source.deleted_at = timezone.now()
    source.save(update_fields=["status", "is_active", "email", "deleted_at", "updated_at"])
    GuestMergeAudit.objects.create(
        source_user=source,
        target_user=target,
        trigger_identity=trigger_identity,
        idempotency_key=idempotency_key,
        moved_counts=counts,
    )
    return GuestMergeResult(target_user=target, moved_counts=counts, replayed=False)


def _merge_consents(*, source: User, target: User, counts: dict[str, int]) -> None:
    moved = 0
    for consent in Consent.objects.select_for_update().filter(user=source).order_by("id"):
        existing = (
            Consent.objects.select_for_update()
            .filter(
                user=target,
                purpose=consent.purpose,
                policy_version=consent.policy_version,
            )
            .first()
        )
        if existing is None:
            consent.user = target
            consent.save(update_fields=["user", "updated_at"])
        else:
            if consent.updated_at > existing.updated_at:
                existing.granted_at = consent.granted_at
                existing.withdrawn_at = consent.withdrawn_at
                existing.save(update_fields=["granted_at", "withdrawn_at", "updated_at"])
            consent.delete()
        moved += 1
    counts["consents"] = moved


def _merge_reading_state(*, source: User, target: User, counts: dict[str, int]) -> None:
    positions = list(
        ReadingPosition.objects.select_for_update(of=("self",))
        .filter(user=source)
        .select_related("edition", "page__edition_version", "ayah__surah__edition_version")
        .order_by("id")
    )
    for source_position in positions:
        target_position = (
            ReadingPosition.objects.select_for_update()
            .filter(user=target, edition=source_position.edition)
            .first()
        )
        if target_position is None:
            source_position.user = target
            source_position.save(update_fields=["user", "updated_at"])
            continue
        if _position_rank(source_position) > _position_rank(target_position):
            _copy_position(source=source_position, target=target_position)
        source_position.delete()
    counts["reading_positions"] = len(positions)

    counts["bookmarks"] = Bookmark.objects.filter(user=source).update(user=target)

    retired_count = 0
    for retired in RetiredBookmarkId.objects.select_for_update().filter(user=source).order_by("id"):
        existing = (
            RetiredBookmarkId.objects.select_for_update()
            .filter(user=target, bookmark_id=retired.bookmark_id)
            .first()
        )
        if existing is None:
            retired.user = target
            retired.save(update_fields=["user", "updated_at"])
        else:
            if retired.last_revision > existing.last_revision:
                existing.last_revision = retired.last_revision
                existing.retired_at = max(existing.retired_at, retired.retired_at)
                existing.save(update_fields=["last_revision", "retired_at", "updated_at"])
            retired.delete()
        retired_count += 1
    counts["retired_bookmark_ids"] = retired_count

    source_active_goal = (
        ReadingGoal.objects.select_for_update()
        .filter(user=source, status=ReadingGoalStatus.ACTIVE)
        .first()
    )
    target_active_goal = (
        ReadingGoal.objects.select_for_update()
        .filter(user=target, status=ReadingGoalStatus.ACTIVE)
        .first()
    )
    if source_active_goal is not None and target_active_goal is not None:
        if _goal_rank(source_active_goal) > _goal_rank(target_active_goal):
            _archive_goal_for_merge(target_active_goal)
        else:
            _archive_goal_for_merge(source_active_goal)

    counts["reading_goals"] = ReadingGoal.objects.filter(user=source).update(user=target)
    counts["reading_sessions"] = ReadingSession.objects.filter(user=source).update(user=target)
    _merge_prayer_reading_state(source=source, target=target, counts=counts)
    _merge_quran_reader_preferences(source=source, target=target, counts=counts)
    counts["goal_progress"] = GoalProgress.objects.filter(user=source).update(user=target)
    counts["reading_streaks"] = ReadingStreak.objects.filter(user__in=(source, target)).count()
    ReadingStreak.objects.filter(user__in=(source, target)).delete()
    recalculate_reading_streak(target, reference_date=timezone.now().date())


def _merge_memorization_state(*, source: User, target: User, counts: dict[str, int]) -> None:
    source_plan = MemorizationPlan.objects.select_for_update().filter(user=source).first()
    if source_plan is None:
        counts["memorization_plans"] = 0
        counts["memorization_sessions"] = 0
        return
    source_sessions = list(
        MemorizationSession.objects.select_for_update().filter(user=source).order_by("id")
    )
    target_plan = MemorizationPlan.objects.select_for_update().filter(user=target).first()
    if target_plan is None:
        source_plan.user = target
        source_plan.save(update_fields=["user", "updated_at"])
        MemorizationSession.objects.filter(user=source).update(user=target)
        counts["memorization_plans"] = 1
        counts["memorization_sessions"] = len(source_sessions)
        return

    if _memorization_plan_rank(source_plan) > _memorization_plan_rank(target_plan):
        for field in (
            "start_ayah",
            "end_ayah",
            "recitation",
            "daily_repetitions",
            "pause_seconds",
            "timezone_name",
            "client_updated_at",
            "device",
        ):
            setattr(target_plan, field, getattr(source_plan, field))
        target_plan.revision = max(target_plan.revision, source_plan.revision) + 1
        target_plan.save()
    MemorizationSession.objects.filter(user=source).update(user=target, plan=target_plan)
    source_plan.delete()
    counts["memorization_plans"] = 1
    counts["memorization_sessions"] = len(source_sessions)


def _memorization_plan_rank(plan: MemorizationPlan) -> tuple[Any, ...]:
    return (plan.client_updated_at, plan.updated_at, plan.id)


def _position_rank(position: ReadingPosition) -> tuple[Any, ...]:
    return (position.client_updated_at, position.last_read_at, position.updated_at, position.id)


def _goal_rank(goal: ReadingGoal) -> tuple[Any, ...]:
    return (goal.client_updated_at, goal.updated_at, goal.id)


def _merge_prayer_reading_state(
    *,
    source: User,
    target: User,
    counts: dict[str, int],
) -> None:
    source_plan = PrayerReadingPlan.objects.select_for_update().filter(user=source).first()
    if source_plan is None:
        counts["prayer_reading_plans"] = 0
        counts["prayer_reading_check_ins"] = 0
        return
    source_check_ins = list(
        PrayerReadingCheckIn.objects.select_for_update().filter(user=source).order_by("id")
    )
    target_plan = PrayerReadingPlan.objects.select_for_update().filter(user=target).first()
    if target_plan is None:
        source_plan.user = target
        source_plan.save(update_fields=["user", "updated_at"])
        PrayerReadingCheckIn.objects.filter(user=source).update(user=target)
        counts["prayer_reading_plans"] = 1
        counts["prayer_reading_check_ins"] = len(source_check_ins)
        return

    if _prayer_reading_plan_rank(source_plan) > _prayer_reading_plan_rank(target_plan):
        target_plan.pages_per_prayer = source_plan.pages_per_prayer
        target_plan.timezone_name = source_plan.timezone_name
        target_plan.client_updated_at = source_plan.client_updated_at
        target_plan.device = source_plan.device
        target_plan.revision = max(target_plan.revision, source_plan.revision) + 1
        target_plan.save()

    for source_check_in in source_check_ins:
        target_check_in = (
            PrayerReadingCheckIn.objects.select_for_update()
            .filter(
                user=target,
                local_date=source_check_in.local_date,
                prayer=source_check_in.prayer,
            )
            .first()
        )
        if target_check_in is None:
            source_check_in.user = target
            source_check_in.plan = target_plan
            source_check_in.save(update_fields=["user", "plan", "updated_at"])
            continue
        if _prayer_reading_check_in_rank(source_check_in) > _prayer_reading_check_in_rank(
            target_check_in
        ):
            target_check_in.pages = source_check_in.pages
            target_check_in.timezone_name = source_check_in.timezone_name
            target_check_in.reading_session = source_check_in.reading_session
            target_check_in.client_updated_at = source_check_in.client_updated_at
            target_check_in.device = source_check_in.device
            target_check_in.revision = (
                max(
                    target_check_in.revision,
                    source_check_in.revision,
                )
                + 1
            )
            target_check_in.save()
        source_check_in.delete()
    source_plan.delete()
    counts["prayer_reading_plans"] = 1
    counts["prayer_reading_check_ins"] = len(source_check_ins)


def _prayer_reading_plan_rank(plan: PrayerReadingPlan) -> tuple[Any, ...]:
    return (plan.client_updated_at, plan.updated_at, plan.id)


def _prayer_reading_check_in_rank(check_in: PrayerReadingCheckIn) -> tuple[Any, ...]:
    return (check_in.client_updated_at, check_in.updated_at, check_in.id)


def _merge_quran_reader_preferences(
    *,
    source: User,
    target: User,
    counts: dict[str, int],
) -> None:
    preferences = list(
        QuranReaderPreference.objects.select_for_update()
        .filter(user=source)
        .order_by("locale", "id")
    )
    for source_preference in preferences:
        target_preference = (
            QuranReaderPreference.objects.select_for_update()
            .filter(user=target, locale=source_preference.locale)
            .first()
        )
        if target_preference is None:
            source_preference.user = target
            source_preference.save(update_fields=["user", "updated_at"])
            continue
        if _quran_reader_preference_rank(source_preference) > _quran_reader_preference_rank(
            target_preference
        ):
            for field in (
                "translation_enabled",
                "translation_source_id",
                "tafsir_enabled",
                "tafsir_source_id",
                "client_updated_at",
                "device",
            ):
                setattr(target_preference, field, getattr(source_preference, field))
            target_preference.revision = (
                max(
                    target_preference.revision,
                    source_preference.revision,
                )
                + 1
            )
            target_preference.save()
        source_preference.delete()
    counts["quran_reader_preferences"] = len(preferences)


def _quran_reader_preference_rank(preference: QuranReaderPreference) -> tuple[Any, ...]:
    return (preference.client_updated_at, preference.updated_at, preference.id)


def _archive_goal_for_merge(goal: ReadingGoal) -> None:
    goal.status = ReadingGoalStatus.ARCHIVED
    goal.ended_on = max(goal.started_on, timezone.now().date())
    goal.revision += 1
    goal.save(update_fields=["status", "ended_on", "revision", "updated_at"])


def _copy_position(*, source: ReadingPosition, target: ReadingPosition) -> None:
    target.page = source.page
    target.ayah = source.ayah
    target.intra_page_anchor = source.intra_page_anchor
    target.progress_percent = source.progress_percent
    target.last_read_at = source.last_read_at
    target.client_updated_at = source.client_updated_at
    target.device = source.device
    target.revision = max(target.revision, source.revision) + 1
    target.save()


def _merge_reminders(*, source: User, target: User, counts: dict[str, int]) -> None:
    counts["reminders"] = ReminderRule.objects.filter(user=source).update(user=target)
    counts["retired_reminder_ids"] = RetiredReminderId.objects.filter(user=source).update(
        user=target
    )


def _merge_prayer_profile(*, source: User, target: User, counts: dict[str, int]) -> None:
    source_profile = PrayerProfile.objects.select_for_update().filter(user=source).first()
    if source_profile is None:
        counts["prayer_profiles"] = 0
        return
    target_profile = PrayerProfile.objects.select_for_update().filter(user=target).first()
    if target_profile is None:
        source_profile.user = target
        source_profile.save(update_fields=["user", "updated_at"])
    else:
        if (source_profile.client_updated_at, source_profile.updated_at) > (
            target_profile.client_updated_at,
            target_profile.updated_at,
        ):
            _copy_prayer_profile(source=source_profile, target=target_profile)
        source_profile.delete()
    counts["prayer_profiles"] = 1


def _copy_prayer_profile(*, source: PrayerProfile, target: PrayerProfile) -> None:
    copied_fields = [
        "method_config",
        "asr_method",
        "high_latitude_rule",
        "polar_resolution",
        *PrayerProfile.adjustment_fields,
        "timezone_mode",
        "fixed_timezone",
        "client_updated_at",
        "device",
    ]
    for field in copied_fields:
        setattr(target, field, getattr(source, field))
    target.revision = max(target.revision, source.revision) + 1
    target.save()


def _merge_feedback(*, source: User, target: User, counts: dict[str, int]) -> None:
    moved_tickets = 0
    for ticket in FeedbackTicket.objects.select_for_update().filter(reporter=source).order_by("id"):
        if FeedbackTicket.objects.filter(
            reporter=target,
            client_request_id=ticket.client_request_id,
        ).exists():
            ticket.client_request_id = uuid.uuid7()
        ticket.reporter = target
        ticket.save(update_fields=["reporter", "client_request_id", "updated_at"])
        moved_tickets += 1
    counts["feedback_tickets"] = moved_tickets
    counts["feedback_messages"] = FeedbackMessage.objects.filter(author=source).update(
        author=target
    )
    counts["feedback_audits"] = FeedbackAudit.objects.filter(actor=source).update(actor=target)


def _move_identities(*, source: User, target: User, counts: dict[str, int]) -> None:
    counts["auth_identities"] = AuthIdentity.objects.filter(user=source).update(user=target)


def _move_devices_and_revoke_sessions(
    *,
    source: User,
    target: User,
    counts: dict[str, int],
) -> None:
    now = timezone.now()
    session_ids = list(
        RefreshSession.objects.select_for_update()
        .filter(user=source)
        .order_by("id")
        .values_list("id", flat=True)
    )
    if session_ids:
        RefreshToken.objects.filter(session_id__in=session_ids, revoked_at__isnull=True).update(
            revoked_at=now
        )
        RefreshSession.objects.filter(id__in=session_ids).update(user=target, revoked_at=now)
    counts["refresh_sessions"] = len(session_ids)
    counts["devices"] = Device.objects.filter(user=source).update(user=target)


def _rebuild_target_sync_feed(*, source: User, target: User) -> None:
    SyncOperation.objects.filter(user=source).delete()
    SyncChange.objects.filter(user=source).delete()
    UserSyncCursor.objects.filter(user=source).delete()

    positions = (
        ReadingPosition.objects.filter(user=target)
        .select_related(
            "edition",
            "page__edition_version",
            "ayah__surah__edition_version",
            "device",
        )
        .order_by("id")
    )
    for position in positions:
        append_sync_change(
            user=target,
            entity_type=SyncEntityType.READING_POSITION,
            entity_id=position.id,
            action=SyncAction.UPSERT,
            revision=position.revision,
            snapshot=reading_position_snapshot(position),
        )

    bookmarks = (
        Bookmark.objects.filter(user=target)
        .select_related(
            "edition",
            "page__edition_version",
            "ayah__surah__edition_version",
            "device",
        )
        .order_by("id")
    )
    for bookmark in bookmarks:
        append_sync_change(
            user=target,
            entity_type=SyncEntityType.BOOKMARK,
            entity_id=bookmark.id,
            action=SyncAction.DELETE if bookmark.deleted_at else SyncAction.UPSERT,
            revision=bookmark.revision,
            snapshot=bookmark_snapshot(bookmark),
        )

    reminders = (
        ReminderRule.objects.filter(user=target)
        .select_related("device", "start_ayah__surah", "end_ayah__surah")
        .order_by("id")
    )
    for reminder in reminders:
        append_sync_change(
            user=target,
            entity_type=SyncEntityType.REMINDER,
            entity_id=reminder.id,
            action=SyncAction.DELETE if reminder.deleted_at else SyncAction.UPSERT,
            revision=reminder.revision,
            snapshot=reminder_sync_snapshot(reminder),
        )
