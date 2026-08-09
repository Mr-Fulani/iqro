from __future__ import annotations

import uuid
from datetime import time
from typing import Any

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.quran.models import Ayah
from quran_backend.modules.quran.selectors import published_active_ayahs_by_id
from quran_backend.modules.reminders.exceptions import (
    ReminderCreateConflictError,
    ReminderDeletedError,
    ReminderIdNotReusableError,
    ReminderNotFoundError,
    ReminderQuotaExceededError,
    ReminderRevisionConflictError,
)
from quran_backend.modules.reminders.models import (
    ALL_WEEKDAYS_MASK,
    ReminderRule,
    ReminderSignal,
    ReminderTimezoneMode,
    ReminderType,
    RetiredReminderId,
)
from quran_backend.modules.reminders.policies import reminder_id_policy, reminder_quota_policy
from quran_backend.modules.reminders.selectors import list_reminders, reminder_queryset


def reminder_snapshot(reminder: ReminderRule) -> dict[str, Any]:
    if reminder.deleted_at is not None:
        schedule = None
    elif reminder.prayer_event is not None:
        schedule = {
            "kind": "prayer",
            "prayer_event": reminder.prayer_event,
            "prayer_offset_minutes": reminder.prayer_offset_minutes,
        }
    else:
        schedule = {
            "kind": "local_time",
            "local_time": _time_string(reminder.local_time),
        }

    target: dict[str, Any] | None = None
    if reminder.start_ayah_id is not None and reminder.end_ayah_id is not None:
        start_ayah = reminder.start_ayah
        end_ayah = reminder.end_ayah
        assert start_ayah is not None
        assert end_ayah is not None
        target = {
            "start": _ayah_snapshot(start_ayah),
            "end": _ayah_snapshot(end_ayah),
        }

    return {
        "id": str(reminder.id),
        "reminder_type": reminder.reminder_type,
        "schedule": schedule,
        "review_target": target,
        "weekdays_mask": reminder.weekdays_mask,
        "timezone": {
            "mode": reminder.timezone_mode,
            **(
                {"name": reminder.timezone_name}
                if reminder.timezone_mode == ReminderTimezoneMode.FIXED
                else {}
            ),
        },
        "delivery_mode": reminder.delivery_mode,
        "signal": reminder.signal,
        "is_enabled": reminder.is_enabled,
        "revision": reminder.revision,
        "client_updated_at": reminder.client_updated_at.isoformat(),
        "device_id": str(reminder.device_id) if reminder.device_id else None,
        "deleted_at": reminder.deleted_at.isoformat() if reminder.deleted_at else None,
        "created_at": reminder.created_at.isoformat(),
        "updated_at": reminder.updated_at.isoformat(),
    }


def full_reminder_snapshot(user: User) -> dict[str, Any]:
    reminders = [reminder_snapshot(reminder) for reminder in list_reminders(user)]
    return {
        "mode": "full_snapshot",
        "authoritative": True,
        "generated_at": timezone.now().isoformat(),
        "count": len(reminders),
        "reminders": reminders,
    }


def get_reminder_snapshot(user: User, reminder_id: uuid.UUID) -> dict[str, Any]:
    reminder = reminder_queryset().filter(user=user, id=reminder_id).first()
    if reminder is None:
        raise ReminderNotFoundError
    return reminder_snapshot(reminder)


@transaction.atomic
def create_reminder(
    *,
    user: User,
    device: Device | None,
    data: dict[str, Any],
) -> tuple[dict[str, Any], bool]:
    """Create a rule or replay one byte-equivalent normalized create."""

    User.objects.select_for_update().only("id").get(pk=user.pk)
    reminder_id = data["id"]
    existing = reminder_queryset(for_update=True).filter(id=reminder_id).first()

    if existing is not None:
        if existing.user_id == user.id and existing.deleted_at is not None:
            raise ReminderDeletedError
        if (
            existing.user_id == user.id
            and _stored_functional_state(existing) == _input_functional_state(data)
            and existing.client_updated_at == data["client_updated_at"]
            and existing.device_id == (device.id if device else None)
        ):
            return reminder_snapshot(existing), False
        raise ReminderCreateConflictError

    retired = RetiredReminderId.objects.filter(reminder_id=reminder_id).only("user_id").first()
    if retired is not None:
        if retired.user_id == user.id:
            raise ReminderDeletedError
        raise ReminderCreateConflictError
    if not reminder_id_policy().accepts_new_id(reminder_id, now=timezone.now()):
        raise ReminderIdNotReusableError

    desired = _create_values(data)

    quota_policy = reminder_quota_policy()
    user_rules = ReminderRule.objects.filter(user=user)
    if (
        user_rules.count() >= quota_policy.max_total_per_user
        or user_rules.filter(deleted_at__isnull=True).count() >= quota_policy.max_active_per_user
    ):
        raise ReminderQuotaExceededError

    reminder = ReminderRule(
        id=reminder_id,
        user=user,
        client_updated_at=data["client_updated_at"],
        device=device,
        revision=1,
        **desired,
    )
    _validate_reminder(reminder)
    try:
        # Keep IntegrityError inside a savepoint so a colliding cross-user UUID
        # can be mapped without leaving the outer user-lock transaction broken.
        with transaction.atomic():
            reminder.save()
    except IntegrityError as exc:
        raise ReminderCreateConflictError from exc
    return reminder_snapshot(reminder), True


@transaction.atomic
def patch_reminder(
    *,
    user: User,
    device: Device | None,
    reminder_id: uuid.UUID,
    data: dict[str, Any],
) -> dict[str, Any]:
    current = reminder_queryset(for_update=True).filter(user=user, id=reminder_id).first()
    if current is None:
        raise ReminderNotFoundError
    if current.deleted_at is not None:
        raise ReminderDeletedError

    desired = _patched_values(current, data)
    if _stored_functional_state(current) == _values_functional_state(desired):
        # A no-op or retry of an already-applied patch is idempotent even if
        # its base revision is now stale.
        return reminder_snapshot(current)
    if data["base_revision"] != current.revision:
        raise ReminderRevisionConflictError

    _assign_functional_values(current, desired)
    current.client_updated_at = data["client_updated_at"]
    current.device = device
    current.revision += 1
    _validate_reminder(current)
    current.save()
    return reminder_snapshot(current)


@transaction.atomic
def delete_reminder(
    *,
    user: User,
    device: Device | None,
    reminder_id: uuid.UUID,
    data: dict[str, Any],
) -> dict[str, Any]:
    del device  # Tombstones intentionally discard device provenance.
    current = reminder_queryset(for_update=True).filter(user=user, id=reminder_id).first()
    if current is None:
        raise ReminderNotFoundError
    if current.deleted_at is not None:
        return reminder_snapshot(current)
    if data["base_revision"] != current.revision:
        raise ReminderRevisionConflictError

    current.device = None
    current.prayer_event = None
    current.local_time = None
    current.prayer_offset_minutes = None
    current.start_ayah = None
    current.end_ayah = None
    current.weekdays_mask = ALL_WEEKDAYS_MASK
    current.timezone_mode = ReminderTimezoneMode.DEVICE_LOCAL
    current.timezone_name = None
    current.signal = ReminderSignal.SILENT
    current.is_enabled = False
    current.deleted_at = timezone.now()
    current.client_updated_at = data["client_updated_at"]
    current.revision += 1
    _validate_reminder(current)
    current.save()
    return reminder_snapshot(current)


def _create_values(data: dict[str, Any]) -> dict[str, Any]:
    values: dict[str, Any] = {
        "reminder_type": str(data["reminder_type"]),
        "weekdays_mask": data["weekdays_mask"],
        "signal": str(data["signal"]),
        "is_enabled": data["is_enabled"],
        **_schedule_values(dict(data["schedule"])),
        **_timezone_values(dict(data["timezone"])),
    }
    target = data.get("review_target")
    values.update(_target_values(dict(target) if target is not None else None))
    return values


def _patched_values(current: ReminderRule, data: dict[str, Any]) -> dict[str, Any]:
    values = _stored_values(current)
    reminder_type = str(data.get("reminder_type", current.reminder_type))
    if reminder_type != current.reminder_type and "schedule" not in data:
        raise ValidationError({"schedule": "A schedule is required when changing reminder_type."})
    values["reminder_type"] = reminder_type

    if "schedule" in data:
        values.update(_schedule_values(dict(data["schedule"])))
    if "timezone" in data:
        values.update(_timezone_values(dict(data["timezone"])))
    for field in ("weekdays_mask", "signal", "is_enabled"):
        if field in data:
            values[field] = data[field]

    _apply_review_target_patch(current, values, data, reminder_type)

    _validate_type_schedule(values)
    return values


def _apply_review_target_patch(
    current: ReminderRule,
    values: dict[str, Any],
    data: dict[str, Any],
    reminder_type: str,
) -> None:
    if reminder_type != ReminderType.QURAN_REVIEW:
        if data.get("review_target") is not None:
            raise ValidationError(
                {"review_target": "Only Quran review reminders can have an ayah range."}
            )
        values.update(_target_values(None))
        return
    if "review_target" not in data:
        if current.reminder_type != ReminderType.QURAN_REVIEW:
            raise ValidationError(
                {"review_target": "An ayah range is required when changing to Quran review."}
            )
        return

    target = data["review_target"]
    if target is None:
        raise ValidationError({"review_target": "A Quran review reminder requires an ayah range."})
    normalized_target = dict(target)
    if (
        current.reminder_type == ReminderType.QURAN_REVIEW
        and current.start_ayah_id == normalized_target["start_ayah_id"]
        and current.end_ayah_id == normalized_target["end_ayah_id"]
    ):
        values.update(
            {
                "start_ayah": current.start_ayah,
                "end_ayah": current.end_ayah,
            }
        )
        return
    values.update(_target_values(normalized_target))


def _schedule_values(schedule: dict[str, Any]) -> dict[str, Any]:
    if schedule["kind"] == "prayer":
        return {
            "prayer_event": str(schedule["prayer_event"]),
            "prayer_offset_minutes": schedule["prayer_offset_minutes"],
            "local_time": None,
        }
    return {
        "prayer_event": None,
        "prayer_offset_minutes": None,
        "local_time": schedule["local_time"],
    }


def _timezone_values(timezone_data: dict[str, Any]) -> dict[str, Any]:
    mode = str(timezone_data["mode"])
    return {
        "timezone_mode": mode,
        "timezone_name": timezone_data.get("name") if mode == ReminderTimezoneMode.FIXED else None,
    }


def _target_values(target: dict[str, Any] | None) -> dict[str, Any]:
    if target is None:
        return {"start_ayah": None, "end_ayah": None}
    ids = [target["start_ayah_id"], target["end_ayah_id"]]
    ayahs = {ayah.id: ayah for ayah in published_active_ayahs_by_id(ids)}
    errors: dict[str, str] = {}
    if ids[0] not in ayahs:
        errors["start_ayah_id"] = "Ayah was not found."
    if ids[1] not in ayahs:
        errors["end_ayah_id"] = "Ayah was not found."
    if errors:
        raise ValidationError({"review_target": errors})
    return {"start_ayah": ayahs[ids[0]], "end_ayah": ayahs[ids[1]]}


def _stored_values(reminder: ReminderRule) -> dict[str, Any]:
    return {
        "reminder_type": reminder.reminder_type,
        "prayer_event": reminder.prayer_event,
        "local_time": reminder.local_time,
        "prayer_offset_minutes": reminder.prayer_offset_minutes,
        "start_ayah": reminder.start_ayah,
        "end_ayah": reminder.end_ayah,
        "weekdays_mask": reminder.weekdays_mask,
        "timezone_mode": reminder.timezone_mode,
        "timezone_name": reminder.timezone_name,
        "signal": reminder.signal,
        "is_enabled": reminder.is_enabled,
    }


def _assign_functional_values(reminder: ReminderRule, values: dict[str, Any]) -> None:
    for field, value in values.items():
        setattr(reminder, field, value)


def _stored_functional_state(reminder: ReminderRule) -> tuple[Any, ...]:
    return (
        reminder.reminder_type,
        reminder.prayer_event,
        reminder.local_time,
        reminder.prayer_offset_minutes,
        reminder.start_ayah_id,
        reminder.end_ayah_id,
        reminder.weekdays_mask,
        reminder.timezone_mode,
        reminder.timezone_name,
        reminder.signal,
        reminder.is_enabled,
    )


def _input_functional_state(data: dict[str, Any]) -> tuple[Any, ...]:
    schedule = dict(data["schedule"])
    target = data.get("review_target")
    target_data = dict(target) if target is not None else {}
    timezone_data = dict(data["timezone"])
    is_prayer = schedule["kind"] == "prayer"
    return (
        str(data["reminder_type"]),
        str(schedule["prayer_event"]) if is_prayer else None,
        None if is_prayer else schedule["local_time"],
        schedule["prayer_offset_minutes"] if is_prayer else None,
        target_data.get("start_ayah_id"),
        target_data.get("end_ayah_id"),
        data["weekdays_mask"],
        str(timezone_data["mode"]),
        timezone_data.get("name"),
        str(data["signal"]),
        data["is_enabled"],
    )


def _values_functional_state(values: dict[str, Any]) -> tuple[Any, ...]:
    start = values["start_ayah"]
    end = values["end_ayah"]
    return (
        str(values["reminder_type"]),
        values["prayer_event"],
        values["local_time"],
        values["prayer_offset_minutes"],
        start.id if start is not None else None,
        end.id if end is not None else None,
        values["weekdays_mask"],
        str(values["timezone_mode"]),
        values["timezone_name"],
        str(values["signal"]),
        values["is_enabled"],
    )


def _validate_type_schedule(values: dict[str, Any]) -> None:
    reminder_type = values["reminder_type"]
    is_prayer_schedule = values["prayer_event"] is not None
    if reminder_type == ReminderType.PRAYER and not is_prayer_schedule:
        raise ValidationError({"schedule": "A prayer reminder requires a prayer schedule."})
    if reminder_type != ReminderType.PRAYER and is_prayer_schedule:
        raise ValidationError({"schedule": "A Quran reminder requires a local-time schedule."})


def _validate_reminder(reminder: ReminderRule) -> None:
    try:
        reminder.full_clean()
    except DjangoValidationError as exc:
        if hasattr(exc, "message_dict"):
            raise ValidationError(exc.message_dict) from exc
        raise ValidationError(exc.messages) from exc


def _ayah_snapshot(ayah: Ayah) -> dict[str, Any]:
    return {
        "id": str(ayah.id),
        "surah_number": ayah.surah.number,
        "ayah_number": ayah.number,
    }


def _time_string(value: time | None) -> str:
    if value is None:  # pragma: no cover - protected by the model constraint.
        raise RuntimeError("Local-time reminder has no local time.")
    return value.isoformat()
