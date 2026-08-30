from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.audio.models import (
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.memorization.models import (
    MemorizationPlan,
    MemorizationSession,
)
from quran_backend.modules.quran.models import Ayah


class MemorizationPlanRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The memorization plan changed on another client."
    default_code = "memorization_plan_revision_conflict"


class MemorizationPlanNotFoundError(NotFound):
    default_detail = "A memorization plan was not found."
    default_code = "memorization_plan_not_found"


class MemorizationSessionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The memorization session identifier is already in use."
    default_code = "memorization_session_conflict"


def get_memorization_dashboard(
    user: User,
    *,
    fallback_timezone_name: str | None = None,
    recent_days: int = 14,
) -> dict[str, Any]:
    plan = (
        MemorizationPlan.objects.filter(user=user)
        .select_related(
            "start_ayah__surah__edition_version__edition",
            "end_ayah__surah__edition_version__edition",
            "recitation__reciter",
            "device",
        )
        .first()
    )
    timezone_name = (
        plan.timezone_name if plan is not None else fallback_timezone_name or user.timezone or "UTC"
    )
    local_date = timezone.now().astimezone(ZoneInfo(timezone_name)).date()
    today_sessions = list(
        MemorizationSession.objects.filter(user=user, local_date=local_date)
        .select_related("start_ayah__surah", "end_ayah__surah", "device")
        .order_by("created_at")
    )
    completed = sum(item.completed_repetitions for item in today_sessions)
    target = plan.daily_repetitions if plan is not None else 0
    recent_start = local_date - timedelta(days=recent_days - 1)
    recent_rows = list(
        MemorizationSession.objects.filter(
            user=user,
            local_date__gte=recent_start,
            local_date__lte=local_date,
        )
        .values("local_date")
        .annotate(
            completed_repetitions=Sum("completed_repetitions"),
            session_count=Count("id"),
        )
        .order_by("-local_date")
    )
    latest_by_date = {
        item.local_date: item.assessment
        for item in MemorizationSession.objects.filter(
            user=user,
            local_date__gte=recent_start,
            local_date__lte=local_date,
        ).order_by("local_date", "created_at")
    }
    return {
        "timezone_name": timezone_name,
        "plan": plan_snapshot(plan) if plan is not None else None,
        "today": {
            "local_date": local_date.isoformat(),
            "completed_repetitions": completed,
            "target_repetitions": target,
            "remaining_repetitions": max(target - completed, 0),
            "is_completed": target > 0 and completed >= target,
            "last_assessment": today_sessions[-1].assessment if today_sessions else None,
            "sessions": [session_snapshot(item) for item in today_sessions],
        },
        "recent_days": [
            {
                "local_date": row["local_date"].isoformat(),
                "completed_repetitions": row["completed_repetitions"] or 0,
                "session_count": row["session_count"],
                "last_assessment": latest_by_date[row["local_date"]],
            }
            for row in recent_rows
        ],
    }


@transaction.atomic
def reset_today_memorization_progress(
    user: User,
    *,
    fallback_timezone_name: str | None = None,
) -> int:
    User.objects.select_for_update().only("id").get(id=user.id)
    plan_timezone = (
        MemorizationPlan.objects.filter(user=user).values_list("timezone_name", flat=True).first()
    )
    timezone_name = plan_timezone or fallback_timezone_name or user.timezone or "UTC"
    local_date = timezone.now().astimezone(ZoneInfo(timezone_name)).date()
    deleted, _details = MemorizationSession.objects.filter(
        user=user,
        local_date=local_date,
    ).delete()
    return deleted


@transaction.atomic
def set_memorization_plan(  # noqa: PLR0913
    *,
    user: User,
    start_ayah_id: uuid.UUID,
    end_ayah_id: uuid.UUID,
    recitation_id: uuid.UUID | None,
    daily_repetitions: int,
    pause_seconds: int,
    timezone_name: str,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[MemorizationPlan, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    ayahs = {
        item.id: item
        for item in Ayah.objects.filter(id__in=(start_ayah_id, end_ayah_id)).select_related(
            "surah__edition_version__edition"
        )
    }
    if len(ayahs) != len({start_ayah_id, end_ayah_id}):
        raise ValidationError({"ayah_range": "One or more ayahs were not found."})
    start_ayah = ayahs[start_ayah_id]
    end_ayah = ayahs[end_ayah_id]
    recitation = _published_recitation(recitation_id)
    device = _device_for_user(user, device_id)
    current = (
        MemorizationPlan.objects.select_for_update(of=("self",))
        .select_related(
            "start_ayah__surah__edition_version__edition",
            "end_ayah__surah__edition_version__edition",
            "recitation__reciter",
            "device",
        )
        .filter(user=user)
        .first()
    )
    if current is None:
        if base_revision != 0:
            raise MemorizationPlanRevisionConflictError
        plan = MemorizationPlan(
            user=user,
            start_ayah=start_ayah,
            end_ayah=end_ayah,
            recitation=recitation,
            daily_repetitions=daily_repetitions,
            pause_seconds=pause_seconds,
            timezone_name=timezone_name,
            client_updated_at=client_updated_at,
            device=device,
        )
        _full_clean(plan)
        plan.save(force_insert=True)
        return plan, True
    if current.revision != base_revision:
        raise MemorizationPlanRevisionConflictError
    next_values = (
        start_ayah.id,
        end_ayah.id,
        recitation.id if recitation else None,
        daily_repetitions,
        pause_seconds,
        timezone_name,
        device.id if device else None,
    )
    current_values = (
        current.start_ayah_id,
        current.end_ayah_id,
        current.recitation_id,
        current.daily_repetitions,
        current.pause_seconds,
        current.timezone_name,
        current.device_id,
    )
    if next_values == current_values:
        return current, False
    current.start_ayah = start_ayah
    current.end_ayah = end_ayah
    current.recitation = recitation
    current.daily_repetitions = daily_repetitions
    current.pause_seconds = pause_seconds
    current.timezone_name = timezone_name
    current.client_updated_at = client_updated_at
    current.device = device
    current.revision += 1
    _full_clean(current)
    current.save()
    return current, False


@transaction.atomic
def record_memorization_session(  # noqa: PLR0913
    *,
    user: User,
    session_id: uuid.UUID,
    plan_id: uuid.UUID,
    completed_repetitions: int,
    assessment: str,
    duration_seconds: int,
    timezone_name: str,
    local_date: date,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> tuple[MemorizationSession, bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    existing = (
        MemorizationSession.objects.select_for_update(of=("self",))
        .select_related("start_ayah__surah", "end_ayah__surah", "device")
        .filter(id=session_id)
        .first()
    )
    if existing is not None:
        expected = (
            user.id,
            plan_id,
            completed_repetitions,
            assessment,
            duration_seconds,
            timezone_name,
            local_date,
        )
        actual = (
            existing.user_id,
            existing.plan_id,
            existing.completed_repetitions,
            existing.assessment,
            existing.duration_seconds,
            existing.timezone_name,
            existing.local_date,
        )
        if actual != expected:
            raise MemorizationSessionConflictError
        return existing, False
    try:
        plan = (
            MemorizationPlan.objects.select_for_update(of=("self",))
            .select_related("start_ayah__surah", "end_ayah__surah")
            .get(id=plan_id, user=user)
        )
    except MemorizationPlan.DoesNotExist as exc:
        raise MemorizationPlanNotFoundError from exc
    user_local_date = timezone.now().astimezone(ZoneInfo(timezone_name)).date()
    if local_date > user_local_date:
        raise ValidationError({"local_date": "Future sessions cannot be recorded."})
    if local_date < user_local_date - timedelta(days=7):
        raise ValidationError({"local_date": "Sessions can be restored for the last 7 days."})
    device = _device_for_user(user, device_id)
    session = MemorizationSession(
        id=session_id,
        user=user,
        plan=plan,
        start_ayah=plan.start_ayah,
        end_ayah=plan.end_ayah,
        daily_target_repetitions=plan.daily_repetitions,
        completed_repetitions=completed_repetitions,
        assessment=assessment,
        duration_seconds=duration_seconds,
        timezone_name=timezone_name,
        local_date=local_date,
        client_updated_at=client_updated_at,
        device=device,
    )
    _full_clean(session)
    session.save(force_insert=True)
    return session, True


def plan_snapshot(plan: MemorizationPlan) -> dict[str, Any]:
    version = plan.start_ayah.surah.edition_version
    recitation = plan.recitation if plan.recitation_id else None
    reciter = recitation.reciter if recitation is not None else None
    return {
        "id": str(plan.id),
        "edition_code": version.edition.code,
        "content_version": version.version,
        "start_ayah": _ayah_snapshot(plan.start_ayah),
        "end_ayah": _ayah_snapshot(plan.end_ayah),
        "recitation_id": str(plan.recitation_id) if plan.recitation_id else None,
        "reciter": (
            {
                "id": str(reciter.id),
                "name_ar": reciter.name_ar,
                "name_en": reciter.name_en,
                "name_ru": reciter.name_ru,
                "name_tr": reciter.name_tr,
            }
            if reciter is not None
            else None
        ),
        "daily_repetitions": plan.daily_repetitions,
        "pause_seconds": plan.pause_seconds,
        "timezone_name": plan.timezone_name,
        "revision": plan.revision,
        "client_updated_at": plan.client_updated_at,
        "device_id": str(plan.device_id) if plan.device_id else None,
        "created_at": plan.created_at,
        "updated_at": plan.updated_at,
    }


def session_snapshot(session: MemorizationSession) -> dict[str, Any]:
    return {
        "id": str(session.id),
        "plan_id": str(session.plan_id),
        "start_ayah": _ayah_snapshot(session.start_ayah),
        "end_ayah": _ayah_snapshot(session.end_ayah),
        "daily_target_repetitions": session.daily_target_repetitions,
        "completed_repetitions": session.completed_repetitions,
        "assessment": session.assessment,
        "duration_seconds": session.duration_seconds,
        "timezone_name": session.timezone_name,
        "local_date": session.local_date.isoformat(),
        "client_updated_at": session.client_updated_at,
        "device_id": str(session.device_id) if session.device_id else None,
        "created_at": session.created_at,
    }


def _ayah_snapshot(ayah: Ayah) -> dict[str, Any]:
    return {
        "id": str(ayah.id),
        "surah_number": ayah.surah.number,
        "ayah_number": ayah.number,
        "text_uthmani": ayah.text_uthmani,
    }


def _published_recitation(recitation_id: uuid.UUID | None) -> RecitationEdition | None:
    if recitation_id is None:
        return None
    try:
        return RecitationEdition.objects.select_related("reciter").get(
            id=recitation_id,
            status=RecitationPublicationStatus.PUBLISHED,
            stream_allowed=True,
        )
    except RecitationEdition.DoesNotExist as exc:
        raise ValidationError({"recitation_id": "A streamable recitation was not found."}) from exc


def _device_for_user(user: User, device_id: uuid.UUID | None) -> Device | None:
    if device_id is None:
        return None
    try:
        return Device.objects.get(id=device_id, user=user)
    except Device.DoesNotExist as exc:
        raise ValidationError({"device_id": "The device must belong to this user."}) from exc


def _full_clean(instance: MemorizationPlan | MemorizationSession) -> None:
    try:
        instance.full_clean()
    except DjangoValidationError as exc:
        details = exc.message_dict if hasattr(exc, "message_dict") else exc.messages
        raise ValidationError(details) from exc
