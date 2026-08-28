from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Any
from zoneinfo import ZoneInfo

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.reading.models import (
    GoalProgress,
    PrayerReadingCheckIn,
    PrayerReadingPlan,
    ReadingGoal,
    ReadingGoalMetric,
    ReadingGoalStatus,
    ReadingSession,
    ReadingSessionSource,
    ReadingSessionStatus,
    ReadingStreak,
)
from quran_backend.modules.reading.services import reading_position_snapshot

MANUAL_BACKDATE_DAYS = 7
RECALCULATION_VERSION = 2
AMOUNT_QUANTUM = Decimal("0.01")
PRAYERS_PER_DAY = 5


class ReadingGoalNotFoundError(NotFound):
    default_detail = "An active reading goal was not found."
    default_code = "reading_goal_not_found"


class ReadingGoalRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The reading goal changed on another client."
    default_code = "reading_goal_revision_conflict"


class ReadingSessionNotFoundError(NotFound):
    default_detail = "The reading session was not found."
    default_code = "reading_session_not_found"


class ReadingSessionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The reading session identifier is already in use."
    default_code = "reading_session_conflict"


class ReadingSessionRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The reading session changed on another client."
    default_code = "reading_session_revision_conflict"


class ReadingSessionImmutableError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "Only manual reading sessions can be edited or deleted."
    default_code = "reading_session_immutable"


class PrayerReadingPlanNotFoundError(NotFound):
    default_detail = "A prayer reading plan was not found."
    default_code = "prayer_reading_plan_not_found"


class PrayerReadingPlanRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The prayer reading plan changed on another client."
    default_code = "prayer_reading_plan_revision_conflict"


class PrayerReadingCheckInNotFoundError(NotFound):
    default_detail = "The prayer reading check-in was not found."
    default_code = "prayer_reading_check_in_not_found"


class PrayerReadingCheckInConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The prayer reading check-in identifier is already in use."
    default_code = "prayer_reading_check_in_conflict"


def get_active_goal(user: User) -> ReadingGoal | None:
    return (
        ReadingGoal.objects.filter(user=user, status=ReadingGoalStatus.ACTIVE)
        .select_related("device")
        .first()
    )


def get_prayer_reading_day(
    user: User,
    *,
    fallback_timezone_name: str | None = None,
) -> dict[str, Any]:
    plan = (
        PrayerReadingPlan.objects.filter(user=user)
        .select_related("device")
        .first()
    )
    timezone_name = (
        plan.timezone_name
        if plan is not None
        else fallback_timezone_name or user.timezone or "UTC"
    )
    local_date = _local_date(timezone.now(), timezone_name)
    check_ins = (
        list(
            PrayerReadingCheckIn.objects.filter(
                user=user,
                plan=plan,
                local_date=local_date,
            )
            .select_related("reading_session", "device")
            .order_by("created_at")
        )
        if plan is not None
        else []
    )
    achieved_pages = sum(check_in.pages for check_in in check_ins)
    target_pages = plan.pages_per_prayer * PRAYERS_PER_DAY if plan is not None else 0
    return {
        "local_date": local_date.isoformat(),
        "timezone_name": timezone_name,
        "plan": prayer_reading_plan_snapshot(plan) if plan is not None else None,
        "check_ins": [prayer_reading_check_in_snapshot(item) for item in check_ins],
        "achieved_pages": achieved_pages,
        "target_pages": target_pages,
        "remaining_pages": max(target_pages - achieved_pages, 0),
    }


@transaction.atomic
def set_prayer_reading_plan(  # noqa: PLR0913
    *,
    user: User,
    pages_per_prayer: int,
    timezone_name: str,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[PrayerReadingPlan, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    device = _device_for_user(user, device_id)
    current = (
        PrayerReadingPlan.objects.select_for_update(of=("self",))
        .select_related("device")
        .filter(user=user)
        .first()
    )
    if current is None:
        if base_revision != 0:
            raise PrayerReadingPlanRevisionConflictError
        plan = PrayerReadingPlan(
            user=user,
            pages_per_prayer=pages_per_prayer,
            timezone_name=timezone_name,
            client_updated_at=client_updated_at,
            device=device,
        )
        plan.full_clean()
        plan.save(force_insert=True)
        return plan, True
    if current.revision != base_revision:
        raise PrayerReadingPlanRevisionConflictError
    if (
        current.pages_per_prayer == pages_per_prayer
        and current.timezone_name == timezone_name
        and current.device_id == (device.id if device is not None else None)
    ):
        return current, False
    current.pages_per_prayer = pages_per_prayer
    current.timezone_name = timezone_name
    current.client_updated_at = client_updated_at
    current.device = device
    current.revision += 1
    current.full_clean()
    current.save(
        update_fields=[
            "pages_per_prayer",
            "timezone_name",
            "client_updated_at",
            "device",
            "revision",
            "updated_at",
        ]
    )
    return current, False


@transaction.atomic
def record_prayer_reading_check_in(  # noqa: PLR0913
    *,
    user: User,
    check_in_id: uuid.UUID,
    session_id: uuid.UUID,
    prayer: str,
    local_date: date,
    timezone_name: str,
    client_updated_at: datetime,
    pages: int | None = None,
    device_id: uuid.UUID | None = None,
) -> tuple[PrayerReadingCheckIn, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    try:
        plan = (
            PrayerReadingPlan.objects.select_for_update(of=("self",))
            .select_related("device")
            .get(user=user)
        )
    except PrayerReadingPlan.DoesNotExist as exc:
        raise PrayerReadingPlanNotFoundError from exc
    if timezone_name != plan.timezone_name:
        raise ValidationError(
            {"timezone_name": "Timezone must match the active prayer reading plan."}
        )
    _validate_manual_date(local_date, timezone_name)
    device = _device_for_user(user, device_id)
    actual_pages = pages if pages is not None else plan.pages_per_prayer

    existing_by_id = (
        PrayerReadingCheckIn.objects.select_for_update(of=("self",))
        .select_related("reading_session", "device")
        .filter(id=check_in_id)
        .first()
    )
    if existing_by_id is not None:
        if not _prayer_check_in_matches(
            existing_by_id,
            user=user,
            plan=plan,
            prayer=prayer,
            local_date=local_date,
            timezone_name=timezone_name,
            session_id=session_id,
            pages=pages,
        ):
            raise PrayerReadingCheckInConflictError
        return existing_by_id, False

    existing_slot = (
        PrayerReadingCheckIn.objects.select_for_update(of=("self",))
        .select_related("reading_session", "device")
        .filter(user=user, local_date=local_date, prayer=prayer)
        .first()
    )
    if existing_slot is not None:
        return existing_slot, False

    now = timezone.now()
    session, _session_created = _create_completed_session(
        user=user,
        session_id=session_id,
        device_id=device_id,
        values={
            "source": ReadingSessionSource.MANUAL,
            "timezone_name": timezone_name,
            "local_date": local_date,
            "started_at": now,
            "ended_at": now,
            "active_seconds": 0,
            "credited_pages": 0,
            "credited_ayahs": 0,
            "manual_metric": ReadingGoalMetric.PAGES,
            "manual_amount": Decimal(actual_pages),
            "client_updated_at": client_updated_at,
        },
    )
    check_in = PrayerReadingCheckIn(
        id=check_in_id,
        user=user,
        plan=plan,
        prayer=prayer,
        local_date=local_date,
        timezone_name=timezone_name,
        pages=actual_pages,
        reading_session=session,
        client_updated_at=client_updated_at,
        device=device,
    )
    check_in.full_clean()
    check_in.save(force_insert=True)
    return check_in, True


@transaction.atomic
def update_prayer_reading_check_in(  # noqa: PLR0913
    *,
    user: User,
    check_in_id: uuid.UUID,
    pages: int,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> PrayerReadingCheckIn:
    User.objects.select_for_update().only("id").get(id=user.id)
    try:
        check_in = (
            PrayerReadingCheckIn.objects.select_for_update(of=("self",))
            .select_related("reading_session", "plan", "device")
            .get(user=user, id=check_in_id)
        )
    except PrayerReadingCheckIn.DoesNotExist as exc:
        raise PrayerReadingCheckInNotFoundError from exc
    if check_in.revision != base_revision:
        raise PrayerReadingCheckInConflictError

    device = _device_for_user(user, device_id)
    if check_in.pages == pages and check_in.device_id == (
        device.id if device is not None else None
    ):
        return check_in

    session = check_in.reading_session
    if session is None:
        raise PrayerReadingCheckInConflictError
    update_manual_session(
        user=user,
        session_id=session.id,
        base_revision=session.revision,
        timezone_name=check_in.timezone_name,
        local_date=check_in.local_date,
        metric=ReadingGoalMetric.PAGES,
        amount=Decimal(pages),
        client_updated_at=client_updated_at,
        device_id=device_id,
    )
    check_in.pages = pages
    check_in.client_updated_at = client_updated_at
    check_in.device = device
    check_in.revision += 1
    check_in.full_clean()
    check_in.save(
        update_fields=[
            "pages",
            "client_updated_at",
            "device",
            "revision",
            "updated_at",
        ]
    )
    return check_in


@transaction.atomic
def delete_prayer_reading_check_in(
    *,
    user: User,
    check_in_id: uuid.UUID,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> None:
    User.objects.select_for_update().only("id").get(id=user.id)
    try:
        check_in = (
            PrayerReadingCheckIn.objects.select_for_update(of=("self",))
            .select_related("reading_session", "plan", "device")
            .get(user=user, id=check_in_id)
        )
    except PrayerReadingCheckIn.DoesNotExist as exc:
        raise PrayerReadingCheckInNotFoundError from exc
    if check_in.revision != base_revision:
        raise PrayerReadingCheckInConflictError
    session = check_in.reading_session
    if session is not None and session.status != ReadingSessionStatus.DISCARDED:
        discard_manual_session(
            user=user,
            session_id=session.id,
            base_revision=session.revision,
            client_updated_at=client_updated_at,
            device_id=device_id,
        )
    check_in.delete()


def prayer_reading_plan_snapshot(plan: PrayerReadingPlan) -> dict[str, Any]:
    return {
        "id": str(plan.id),
        "pages_per_prayer": plan.pages_per_prayer,
        "timezone_name": plan.timezone_name,
        "revision": plan.revision,
        "client_updated_at": plan.client_updated_at.isoformat(),
        "device_id": str(plan.device_id) if plan.device_id else None,
        "created_at": plan.created_at.isoformat(),
        "updated_at": plan.updated_at.isoformat(),
    }


def prayer_reading_check_in_snapshot(check_in: PrayerReadingCheckIn) -> dict[str, Any]:
    return {
        "id": str(check_in.id),
        "prayer": check_in.prayer,
        "local_date": check_in.local_date.isoformat(),
        "timezone_name": check_in.timezone_name,
        "pages": check_in.pages,
        "reading_session_id": (
            str(check_in.reading_session_id) if check_in.reading_session_id else None
        ),
        "revision": check_in.revision,
        "client_updated_at": check_in.client_updated_at.isoformat(),
        "device_id": str(check_in.device_id) if check_in.device_id else None,
        "created_at": check_in.created_at.isoformat(),
        "updated_at": check_in.updated_at.isoformat(),
    }


@transaction.atomic
def set_reading_goal(  # noqa: PLR0913
    *,
    user: User,
    metric: str,
    target_amount: Decimal,
    timezone_name: str,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[ReadingGoal, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    device = _device_for_user(user, device_id)
    current = (
        ReadingGoal.objects.select_for_update()
        .filter(user=user, status=ReadingGoalStatus.ACTIVE)
        .first()
    )
    local_today = _local_date(timezone.now(), timezone_name)

    if current is None:
        if base_revision != 0:
            raise ReadingGoalRevisionConflictError
    else:
        if current.revision != base_revision:
            raise ReadingGoalRevisionConflictError
        if (
            current.metric == metric
            and current.target_amount == target_amount
            and current.timezone_name == timezone_name
        ):
            return current, False
        current.status = ReadingGoalStatus.ARCHIVED
        current.ended_on = max(current.started_on, local_today)
        current.client_updated_at = client_updated_at
        current.revision += 1
        current.full_clean()
        current.save(
            update_fields=[
                "status",
                "ended_on",
                "client_updated_at",
                "revision",
                "updated_at",
            ]
        )

    goal = ReadingGoal(
        user=user,
        metric=metric,
        target_amount=target_amount,
        timezone_name=timezone_name,
        started_on=local_today,
        client_updated_at=client_updated_at,
        device=device,
    )
    goal.full_clean()
    goal.save(force_insert=True)
    _assign_unclaimed_sessions(goal, local_date=local_today)
    recalculate_goal_progress(goal, local_today)
    recalculate_reading_streak(user, reference_date=local_today)
    return goal, True


@transaction.atomic
def archive_reading_goal(
    *,
    user: User,
    base_revision: int,
    client_updated_at: datetime,
) -> ReadingGoal:
    User.objects.select_for_update().only("id").get(id=user.id)
    try:
        goal = ReadingGoal.objects.select_for_update().get(
            user=user,
            status=ReadingGoalStatus.ACTIVE,
        )
    except ReadingGoal.DoesNotExist as exc:
        raise ReadingGoalNotFoundError from exc
    if goal.revision != base_revision:
        raise ReadingGoalRevisionConflictError
    local_today = _local_date(timezone.now(), goal.timezone_name)
    goal.status = ReadingGoalStatus.ARCHIVED
    goal.ended_on = max(goal.started_on, local_today)
    goal.client_updated_at = client_updated_at
    goal.revision += 1
    goal.full_clean()
    goal.save(
        update_fields=[
            "status",
            "ended_on",
            "client_updated_at",
            "revision",
            "updated_at",
        ]
    )
    return goal


@transaction.atomic
def record_automatic_session(  # noqa: PLR0913
    *,
    user: User,
    session_id: uuid.UUID,
    timezone_name: str,
    started_at: datetime,
    ended_at: datetime,
    active_seconds: int,
    credited_pages: int,
    credited_ayahs: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[ReadingSession, bool]:
    local_date = _local_date(ended_at, timezone_name)
    values = {
        "source": ReadingSessionSource.AUTOMATIC,
        "timezone_name": timezone_name,
        "local_date": local_date,
        "started_at": started_at,
        "ended_at": ended_at,
        "active_seconds": active_seconds,
        "credited_pages": credited_pages,
        "credited_ayahs": credited_ayahs,
        "manual_metric": "",
        "manual_amount": None,
        "client_updated_at": client_updated_at,
    }
    return _create_completed_session(
        user=user,
        session_id=session_id,
        device_id=device_id,
        values=values,
    )


@transaction.atomic
def record_manual_session(  # noqa: PLR0913
    *,
    user: User,
    session_id: uuid.UUID,
    timezone_name: str,
    local_date: date,
    metric: str,
    amount: Decimal,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[ReadingSession, bool]:
    _validate_manual_date(local_date, timezone_name)
    now = timezone.now()
    values = {
        "source": ReadingSessionSource.MANUAL,
        "timezone_name": timezone_name,
        "local_date": local_date,
        "started_at": now,
        "ended_at": now,
        "active_seconds": 0,
        "credited_pages": 0,
        "credited_ayahs": 0,
        "manual_metric": metric,
        "manual_amount": amount,
        "client_updated_at": client_updated_at,
    }
    return _create_completed_session(
        user=user,
        session_id=session_id,
        device_id=device_id,
        values=values,
    )


def _create_completed_session(
    *,
    user: User,
    session_id: uuid.UUID,
    device_id: uuid.UUID | None,
    values: dict[str, Any],
) -> tuple[ReadingSession, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    device = _device_for_user(user, device_id)
    existing = (
        ReadingSession.objects.select_for_update(of=("self",))
        .select_related("goal", "device")
        .filter(id=session_id)
        .first()
    )
    if existing is not None:
        if existing.user_id != user.id or not _session_matches_create(existing, values, device):
            raise ReadingSessionConflictError
        return existing, False

    goal = _goal_for_date(user, values["local_date"])
    session = ReadingSession(
        id=session_id,
        user=user,
        goal=goal,
        status=ReadingSessionStatus.COMPLETED,
        device=device,
        **values,
    )
    session.full_clean()
    session.save(force_insert=True)
    if goal is not None:
        recalculate_goal_progress(goal, session.local_date)
    recalculate_reading_streak(
        user,
        reference_date=_reference_date_for_user(user),
    )
    return session, True


@transaction.atomic
def update_manual_session(  # noqa: PLR0913
    *,
    user: User,
    session_id: uuid.UUID,
    base_revision: int,
    timezone_name: str,
    local_date: date,
    metric: str,
    amount: Decimal,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> ReadingSession:
    User.objects.select_for_update().only("id").get(id=user.id)
    session = _manual_session_for_update(user, session_id)
    if session.revision != base_revision:
        raise ReadingSessionRevisionConflictError
    _validate_manual_date(local_date, timezone_name)
    old_goal = session.goal
    old_date = session.local_date
    session.goal = _goal_for_date(user, local_date)
    session.timezone_name = timezone_name
    session.local_date = local_date
    session.manual_metric = metric
    session.manual_amount = amount
    session.client_updated_at = client_updated_at
    session.device = _device_for_user(user, device_id)
    session.revision += 1
    session.full_clean()
    session.save(
        update_fields=[
            "goal",
            "timezone_name",
            "local_date",
            "manual_metric",
            "manual_amount",
            "client_updated_at",
            "device",
            "revision",
            "updated_at",
        ]
    )
    _recalculate_affected_progress(old_goal, old_date, session.goal, session.local_date)
    recalculate_reading_streak(user, reference_date=_reference_date_for_user(user))
    return session


@transaction.atomic
def discard_manual_session(
    *,
    user: User,
    session_id: uuid.UUID,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> ReadingSession:
    User.objects.select_for_update().only("id").get(id=user.id)
    session = _manual_session_for_update(user, session_id)
    if session.revision != base_revision:
        raise ReadingSessionRevisionConflictError
    old_goal = session.goal
    old_date = session.local_date
    now = timezone.now()
    session.status = ReadingSessionStatus.DISCARDED
    session.deleted_at = now
    session.ended_at = session.ended_at or now
    session.client_updated_at = client_updated_at
    session.device = _device_for_user(user, device_id)
    session.revision += 1
    session.full_clean()
    session.save(
        update_fields=[
            "status",
            "deleted_at",
            "ended_at",
            "client_updated_at",
            "device",
            "revision",
            "updated_at",
        ]
    )
    if old_goal is not None:
        recalculate_goal_progress(old_goal, old_date)
    recalculate_reading_streak(user, reference_date=_reference_date_for_user(user))
    return session


def list_reading_sessions(user: User, *, limit: int) -> list[ReadingSession]:
    return list(
        ReadingSession.objects.filter(user=user, deleted_at__isnull=True)
        .select_related("goal", "device")
        .order_by("-local_date", "-created_at")[:limit]
    )


def get_today_summary(
    user: User,
    *,
    fallback_timezone_name: str | None = None,
) -> dict[str, Any]:
    goal = get_active_goal(user)
    timezone_name = (
        goal.timezone_name if goal is not None else fallback_timezone_name or user.timezone or "UTC"
    )
    local_today = _local_date(timezone.now(), timezone_name)
    progress = (
        GoalProgress.objects.filter(goal=goal, local_date=local_today).first()
        if goal is not None
        else None
    )
    streak = ReadingStreak.objects.filter(user=user).first()
    position = (
        user.reading_positions.select_related(
            "edition",
            "page__edition_version",
            "ayah__surah__edition_version",
            "device",
        )
        .order_by("-last_read_at", "-updated_at")
        .first()
    )
    return {
        "local_date": local_today.isoformat(),
        "timezone_name": timezone_name,
        "continue_reading": reading_position_snapshot(position) if position is not None else None,
        "goal": goal_snapshot(goal) if goal is not None else None,
        "progress": progress_snapshot(goal, progress) if goal is not None else None,
        "streak": streak_snapshot(streak, reference_date=local_today),
    }


def goal_snapshot(goal: ReadingGoal) -> dict[str, Any]:
    return {
        "id": str(goal.id),
        "metric": goal.metric,
        "target_amount": _amount_string(goal.target_amount),
        "timezone_name": goal.timezone_name,
        "started_on": goal.started_on.isoformat(),
        "ended_on": goal.ended_on.isoformat() if goal.ended_on else None,
        "status": goal.status,
        "revision": goal.revision,
        "client_updated_at": goal.client_updated_at.isoformat(),
        "device_id": str(goal.device_id) if goal.device_id else None,
        "created_at": goal.created_at.isoformat(),
        "updated_at": goal.updated_at.isoformat(),
    }


def session_snapshot(session: ReadingSession) -> dict[str, Any]:
    return {
        "id": str(session.id),
        "goal_id": str(session.goal_id) if session.goal_id else None,
        "source": session.source,
        "status": session.status,
        "timezone_name": session.timezone_name,
        "local_date": session.local_date.isoformat(),
        "started_at": session.started_at.isoformat() if session.started_at else None,
        "ended_at": session.ended_at.isoformat() if session.ended_at else None,
        "active_seconds": session.active_seconds,
        "credited_pages": session.credited_pages,
        "credited_ayahs": session.credited_ayahs,
        "manual_metric": session.manual_metric or None,
        "manual_amount": (
            _amount_string(session.manual_amount) if session.manual_amount is not None else None
        ),
        "revision": session.revision,
        "client_updated_at": session.client_updated_at.isoformat(),
        "device_id": str(session.device_id) if session.device_id else None,
        "deleted_at": session.deleted_at.isoformat() if session.deleted_at else None,
        "created_at": session.created_at.isoformat(),
        "updated_at": session.updated_at.isoformat(),
    }


def progress_snapshot(
    goal: ReadingGoal,
    progress: GoalProgress | None,
) -> dict[str, Any]:
    achieved = progress.achieved_amount if progress is not None else Decimal("0")
    remaining = max(goal.target_amount - achieved, Decimal("0"))
    return {
        "goal_id": str(goal.id),
        "local_date": (
            progress.local_date.isoformat()
            if progress is not None
            else _local_date(timezone.now(), goal.timezone_name).isoformat()
        ),
        "metric": goal.metric,
        "target_amount": _amount_string(goal.target_amount),
        "achieved_amount": _amount_string(achieved),
        "remaining_amount": _amount_string(remaining),
        "is_completed": progress is not None and progress.completed_at is not None,
        "completed_at": (
            progress.completed_at.isoformat()
            if progress is not None and progress.completed_at is not None
            else None
        ),
    }


def streak_snapshot(
    streak: ReadingStreak | None,
    *,
    reference_date: date,
) -> dict[str, Any]:
    if streak is None:
        return {
            "current_count": 0,
            "longest_count": 0,
            "last_qualifying_date": None,
        }
    current = streak.current_count
    if (
        streak.last_qualifying_date is None
        or streak.last_qualifying_date < reference_date - timedelta(days=1)
    ):
        current = 0
    return {
        "current_count": current,
        "longest_count": streak.longest_count,
        "last_qualifying_date": (
            streak.last_qualifying_date.isoformat()
            if streak.last_qualifying_date is not None
            else None
        ),
    }


def recalculate_goal_progress(goal: ReadingGoal, local_date: date) -> GoalProgress | None:
    amount = Decimal("0")
    sessions = ReadingSession.objects.filter(
        goal=goal,
        local_date=local_date,
        status=ReadingSessionStatus.COMPLETED,
        deleted_at__isnull=True,
    ).only(
        "source",
        "active_seconds",
        "credited_pages",
        "credited_ayahs",
        "manual_metric",
        "manual_amount",
    )
    for session in sessions:
        amount += _session_contribution(session, goal.metric)
    amount = amount.quantize(AMOUNT_QUANTUM, rounding=ROUND_HALF_UP)

    progress = (
        GoalProgress.objects.select_for_update().filter(goal=goal, local_date=local_date).first()
    )
    if amount == 0:
        if progress is not None:
            progress.delete()
        return None

    completed_at = progress.completed_at if progress is not None else None
    completed_at = completed_at or timezone.now() if amount >= goal.target_amount else None
    if progress is None:
        progress = GoalProgress(
            user=goal.user,
            goal=goal,
            local_date=local_date,
        )
    progress.achieved_amount = amount
    progress.completed_at = completed_at
    progress.recalculation_version = RECALCULATION_VERSION
    progress.full_clean()
    progress.save()
    return progress


def recalculate_reading_streak(
    user: User,
    *,
    reference_date: date,
) -> ReadingStreak:
    qualifying_dates = list(
        ReadingSession.objects.filter(
            user=user,
            status=ReadingSessionStatus.COMPLETED,
            deleted_at__isnull=True,
            local_date__lte=reference_date,
        )
        .order_by("local_date")
        .values_list("local_date", flat=True)
        .distinct()
    )
    longest = 0
    run = 0
    previous: date | None = None
    for qualifying_date in qualifying_dates:
        run = run + 1 if previous == qualifying_date - timedelta(days=1) else 1
        longest = max(longest, run)
        previous = qualifying_date

    current = 0
    last_date = qualifying_dates[-1] if qualifying_dates else None
    if last_date is not None and last_date >= reference_date - timedelta(days=1):
        current = 1
        cursor = last_date
        known_dates = set(qualifying_dates)
        while cursor - timedelta(days=1) in known_dates:
            current += 1
            cursor -= timedelta(days=1)

    streak, _created = ReadingStreak.objects.select_for_update().get_or_create(user=user)
    streak.current_count = current
    streak.longest_count = longest
    streak.last_qualifying_date = last_date
    streak.recalculation_version = RECALCULATION_VERSION
    streak.full_clean()
    streak.save()
    return streak


def _manual_session_for_update(user: User, session_id: uuid.UUID) -> ReadingSession:
    try:
        session = (
            ReadingSession.objects.select_for_update(of=("self",))
            .select_related("goal", "device")
            .get(user=user, id=session_id)
        )
    except ReadingSession.DoesNotExist as exc:
        raise ReadingSessionNotFoundError from exc
    if session.source != ReadingSessionSource.MANUAL:
        raise ReadingSessionImmutableError
    if session.status == ReadingSessionStatus.DISCARDED:
        raise ReadingSessionNotFoundError
    return session


def _goal_for_date(user: User, local_date: date) -> ReadingGoal | None:
    return (
        ReadingGoal.objects.filter(
            user=user,
            started_on__lte=local_date,
        )
        .filter(Q(ended_on__isnull=True) | Q(ended_on__gte=local_date))
        .order_by("-started_on", "-created_at")
        .first()
    )


def _assign_unclaimed_sessions(goal: ReadingGoal, *, local_date: date) -> None:
    sessions = ReadingSession.objects.select_for_update().filter(
        user=goal.user,
        goal__isnull=True,
        local_date=local_date,
        status=ReadingSessionStatus.COMPLETED,
        deleted_at__isnull=True,
    )
    for session in sessions:
        if _session_contribution(session, goal.metric) > 0:
            session.goal = goal
            session.save(update_fields=["goal", "updated_at"])


def _recalculate_affected_progress(
    old_goal: ReadingGoal | None,
    old_date: date,
    new_goal: ReadingGoal | None,
    new_date: date,
) -> None:
    affected = {
        (goal.id, local_date): goal
        for goal, local_date in ((old_goal, old_date), (new_goal, new_date))
        if goal is not None
    }
    for (_goal_id, local_date), goal in affected.items():
        recalculate_goal_progress(goal, local_date)


def _session_contribution(session: ReadingSession, metric: str) -> Decimal:
    if session.source == ReadingSessionSource.MANUAL:
        if session.manual_metric != metric or session.manual_amount is None:
            return Decimal("0")
        return session.manual_amount
    if metric == ReadingGoalMetric.MINUTES:
        return Decimal(session.active_seconds) / Decimal(60)
    if metric == ReadingGoalMetric.PAGES:
        return Decimal(session.credited_pages)
    if metric == ReadingGoalMetric.AYAHS:
        return Decimal(session.credited_ayahs)
    return Decimal("0")


def _session_matches_create(
    session: ReadingSession,
    values: dict[str, Any],
    device: Device | None,
) -> bool:
    return (
        session.status == ReadingSessionStatus.COMPLETED
        and session.deleted_at is None
        and session.source == values["source"]
        and session.timezone_name == values["timezone_name"]
        and session.local_date == values["local_date"]
        and session.started_at == values["started_at"]
        and session.ended_at == values["ended_at"]
        and session.active_seconds == values["active_seconds"]
        and session.credited_pages == values["credited_pages"]
        and session.credited_ayahs == values["credited_ayahs"]
        and session.manual_metric == values["manual_metric"]
        and session.manual_amount == values["manual_amount"]
        and session.client_updated_at == values["client_updated_at"]
        and session.device_id == (device.id if device is not None else None)
    )


def _prayer_check_in_matches(  # noqa: PLR0913
    check_in: PrayerReadingCheckIn,
    *,
    user: User,
    plan: PrayerReadingPlan,
    prayer: str,
    local_date: date,
    timezone_name: str,
    session_id: uuid.UUID,
    pages: int | None,
) -> bool:
    return (
        check_in.user_id == user.id
        and check_in.plan_id == plan.id
        and check_in.prayer == prayer
        and check_in.local_date == local_date
        and check_in.timezone_name == timezone_name
        and check_in.reading_session_id == session_id
        and (pages is None or check_in.pages == pages)
    )


def _validate_manual_date(local_date: date, timezone_name: str) -> None:
    local_today = _local_date(timezone.now(), timezone_name)
    if local_date > local_today:
        raise ValidationError({"local_date": "Future reading cannot be recorded."})
    if local_date < local_today - timedelta(days=MANUAL_BACKDATE_DAYS):
        raise ValidationError(
            {
                "local_date": (
                    f"Manual reading can be backdated by at most {MANUAL_BACKDATE_DAYS} days."
                )
            }
        )


def _local_date(value: datetime, timezone_name: str) -> date:
    return timezone.localtime(value, ZoneInfo(timezone_name)).date()


def _reference_date_for_user(user: User) -> date:
    goal = get_active_goal(user)
    timezone_name = goal.timezone_name if goal is not None else user.timezone or "UTC"
    return _local_date(timezone.now(), timezone_name)


def _device_for_user(user: User, device_id: uuid.UUID | None) -> Device | None:
    if device_id is None:
        return None
    try:
        return Device.objects.get(id=device_id, user=user)
    except Device.DoesNotExist as exc:
        raise ValidationError({"device_id": "Device must belong to the same user."}) from exc


def _amount_string(value: Decimal) -> str:
    return format(value.quantize(AMOUNT_QUANTUM), "f")
