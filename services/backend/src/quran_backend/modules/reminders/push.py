from __future__ import annotations

import base64
import binascii
import json
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from urllib.parse import urlparse

from cryptography.hazmat.primitives.asymmetric import ec
from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from pywebpush import WebPushException, webpush
from rest_framework.exceptions import APIException, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.prayer_times.models import PrayerProfile
from quran_backend.modules.prayer_times.services import calculate_prayer_times
from quran_backend.modules.prayer_times.timezones import get_prayer_timezone
from quran_backend.modules.reminders.models import (
    ReminderRule,
    ReminderTimezoneMode,
    ReminderType,
    WebPushSchedule,
    WebPushSubscription,
)

SUPPORTED_WEB_PUSH_TYPES = (
    ReminderType.PRAYER,
    ReminderType.QURAN_READING,
    ReminderType.QURAN_REVIEW,
)


@dataclass(frozen=True)
class ClaimedWebPushSchedule:
    schedule_id: uuid.UUID
    claim_token: uuid.UUID


def web_push_status(*, device: Device | None) -> dict[str, object]:
    subscription = _active_device_subscription(device)
    return {
        "available": bool(settings.WEB_PUSH_ENABLED),
        "enabled": subscription is not None,
        "vapid_public_key": settings.WEB_PUSH_VAPID_PUBLIC_KEY if settings.WEB_PUSH_ENABLED else "",
        "timezone_name": subscription.timezone_name if subscription is not None else None,
        "locale": subscription.locale if subscription is not None else None,
        "prayer_location_configured": bool(
            subscription is not None
            and subscription.prayer_latitude is not None
            and subscription.prayer_longitude is not None
        ),
        "prayer_profile_configured": bool(
            device is not None and PrayerProfile.objects.filter(user_id=device.user_id).exists()
        ),
        "supported_reminder_types": list(SUPPORTED_WEB_PUSH_TYPES),
    }


@transaction.atomic
def upsert_web_push_subscription(
    *,
    user: User,
    device: Device | None,
    data: dict[str, Any],
) -> dict[str, object]:
    if not settings.WEB_PUSH_ENABLED:
        raise ValidationError({"detail": "Web Push is not configured."})
    if device is None or device.user_id != user.id:
        raise ValidationError({"detail": "An authenticated device is required."})

    endpoint = str(data["endpoint"])
    _validate_push_endpoint(endpoint)
    _validate_subscription_key(str(data["p256dh"]), expected_bytes=65, field="p256dh")
    _validate_subscription_key(str(data["auth"]), expected_bytes=16, field="auth")

    Device.objects.select_for_update().only("id", "user_id").get(pk=device.pk)
    endpoint_owner = (
        WebPushSubscription.objects.select_for_update().filter(endpoint=endpoint).first()
    )
    current = WebPushSubscription.objects.select_for_update().filter(device=device).first()
    if endpoint_owner is not None and endpoint_owner.device_id != device.id:
        endpoint_owner.delete()
    if current is None:
        current = WebPushSubscription(device=device)

    current.endpoint = endpoint
    current.p256dh = str(data["p256dh"])
    current.auth = str(data["auth"])
    current.timezone_name = str(data["timezone_name"])
    current.locale = str(data["locale"])
    current.expires_at = data.get("expires_at")
    prayer_location = data.get("prayer_location")
    if prayer_location is not None:
        current.prayer_latitude = prayer_location["latitude"]
        current.prayer_longitude = prayer_location["longitude"]
    current.revoked_at = None
    current.consecutive_failures = 0
    current.last_failure_at = None
    try:
        current.save()
    except DjangoValidationError as exc:
        raise ValidationError(exc.message_dict) from exc

    subscription_id = current.id
    transaction.on_commit(lambda: refresh_subscription_schedules(subscription_id))
    return web_push_status(device=device)


@transaction.atomic
def delete_web_push_subscription(*, user: User, device: Device | None) -> bool:
    if device is None or device.user_id != user.id:
        raise ValidationError({"detail": "An authenticated device is required."})
    deleted, _ = WebPushSubscription.objects.filter(device=device).delete()
    return deleted > 0


def refresh_subscription_schedules(
    subscription_id: uuid.UUID,
    *,
    now: datetime | None = None,
) -> None:
    current_time = now or timezone.now()
    subscription = (
        WebPushSubscription.objects.select_related("device__user")
        .filter(id=subscription_id, revoked_at__isnull=True)
        .first()
    )
    if subscription is None:
        return
    rules = list(
        ReminderRule.objects.filter(
            user=subscription.device.user,
            deleted_at__isnull=True,
            is_enabled=True,
            reminder_type__in=SUPPORTED_WEB_PUSH_TYPES,
        )
    )
    rule_ids = {rule.id for rule in rules}
    subscription.schedules.exclude(reminder_id__in=rule_ids).delete()
    for rule in rules:
        _upsert_schedule(subscription=subscription, reminder=rule, after=current_time)


def refresh_reminder_schedules(
    reminder_id: uuid.UUID,
    *,
    now: datetime | None = None,
) -> None:
    current_time = now or timezone.now()
    reminder = ReminderRule.objects.filter(id=reminder_id).first()
    if reminder is None:
        WebPushSchedule.objects.filter(reminder_id=reminder_id).delete()
        return
    subscriptions = WebPushSubscription.objects.filter(
        device__user_id=reminder.user_id,
        revoked_at__isnull=True,
    )
    if not _web_push_eligible(reminder):
        WebPushSchedule.objects.filter(reminder=reminder).delete()
        return
    for subscription in subscriptions:
        _upsert_schedule(subscription=subscription, reminder=reminder, after=current_time)


def refresh_user_prayer_schedules(
    user_id: uuid.UUID,
    *,
    now: datetime | None = None,
) -> None:
    reminder_ids = ReminderRule.objects.filter(
        user_id=user_id,
        reminder_type=ReminderType.PRAYER,
        deleted_at__isnull=True,
        is_enabled=True,
    ).values_list("id", flat=True)
    for reminder_id in reminder_ids:
        refresh_reminder_schedules(reminder_id, now=now)


def next_local_occurrence(
    reminder: ReminderRule,
    subscription: WebPushSubscription,
    *,
    after: datetime,
) -> datetime | None:
    if not _web_push_eligible(reminder):
        return None
    if reminder.reminder_type == ReminderType.PRAYER:
        return _next_prayer_occurrence(reminder, subscription, after=after)
    if reminder.local_time is None:
        return None
    zone_name = (
        reminder.timezone_name
        if reminder.timezone_mode == ReminderTimezoneMode.FIXED
        else subscription.timezone_name
    )
    if not zone_name:
        return None
    zone = get_prayer_timezone(zone_name)
    after_utc = after.astimezone(UTC)
    start_date = after_utc.astimezone(zone).date()
    for offset in range(8):
        local_date = start_date + timedelta(days=offset)
        if not _weekday_enabled(reminder.weekdays_mask, local_date):
            continue
        candidate = _resolve_local_wall_time(local_date, reminder.local_time, zone)
        if candidate.astimezone(UTC) > after_utc:
            return candidate.astimezone(UTC)
    return None


def _next_prayer_occurrence(
    reminder: ReminderRule,
    subscription: WebPushSubscription,
    *,
    after: datetime,
) -> datetime | None:
    if (
        reminder.prayer_event is None
        or subscription.prayer_latitude is None
        or subscription.prayer_longitude is None
    ):
        return None
    profile = (
        PrayerProfile.objects.select_related("method_config")
        .filter(user_id=reminder.user_id)
        .first()
    )
    if profile is None:
        return None
    zone_name = (
        reminder.timezone_name
        if reminder.timezone_mode == ReminderTimezoneMode.FIXED
        else subscription.timezone_name
    )
    if not zone_name:
        return None
    zone = get_prayer_timezone(zone_name)
    after_utc = after.astimezone(UTC)
    start_date = after_utc.astimezone(zone).date()
    for offset in range(8):
        local_date = start_date + timedelta(days=offset)
        if not _weekday_enabled(reminder.weekdays_mask, local_date):
            continue
        try:
            calculation = calculate_prayer_times(
                {
                    "date": local_date,
                    "timezone": zone_name,
                    "location": {
                        "latitude": subscription.prayer_latitude,
                        "longitude": subscription.prayer_longitude,
                    },
                    "method_config_id": profile.method_config_id,
                    "method_checksum_sha256": profile.method_config.checksum_sha256,
                    "asr_method": profile.asr_method,
                    "high_latitude_rule": profile.high_latitude_rule,
                    "polar_resolution": profile.polar_resolution,
                    "adjustments": {
                        field.removesuffix("_adjustment_minutes"): getattr(profile, field)
                        for field in PrayerProfile.adjustment_fields
                    },
                }
            )
        except APIException:
            return None
        event = calculation["times"][reminder.prayer_event]
        candidate = datetime.fromisoformat(str(event["utc"]).replace("Z", "+00:00"))
        if candidate > after_utc:
            return candidate
    return None


@transaction.atomic
def claim_due_web_push_schedules(
    *,
    now: datetime | None = None,
    batch_size: int | None = None,
) -> list[ClaimedWebPushSchedule]:
    current_time = now or timezone.now()
    limit = batch_size or settings.WEB_PUSH_DISPATCH_BATCH_SIZE
    claim_until = current_time + timedelta(seconds=settings.WEB_PUSH_CLAIM_TTL_SECONDS)
    due = list(
        WebPushSchedule.objects.select_for_update(skip_locked=True)
        .filter(
            next_attempt_at__lte=current_time,
            subscription__revoked_at__isnull=True,
            reminder__deleted_at__isnull=True,
            reminder__is_enabled=True,
        )
        .filter(Q(claimed_until__isnull=True) | Q(claimed_until__lt=current_time))
        .order_by("next_attempt_at", "id")[:limit]
    )
    claimed: list[ClaimedWebPushSchedule] = []
    for schedule in due:
        token = uuid.uuid4()
        schedule.claim_token = token
        schedule.claimed_until = claim_until
        claimed.append(ClaimedWebPushSchedule(schedule_id=schedule.id, claim_token=token))
    WebPushSchedule.objects.bulk_update(due, ["claim_token", "claimed_until"])
    return claimed


def deliver_claimed_web_push_schedule(  # noqa: PLR0911 - explicit delivery outcomes
    *, schedule_id: uuid.UUID, claim_token: uuid.UUID
) -> str:
    schedule = (
        WebPushSchedule.objects.select_related(
            "subscription__device__user",
            "reminder__start_ayah__surah",
            "reminder__end_ayah__surah",
        )
        .filter(id=schedule_id, claim_token=claim_token)
        .first()
    )
    if schedule is None:
        return "not_claimed"
    if not settings.WEB_PUSH_ENABLED:
        _release_claim(schedule, error_code="disabled")
        return "disabled"
    if timezone.now() >= schedule.occurrence_at + timedelta(
        seconds=settings.WEB_PUSH_RETRY_WINDOW_SECONDS
    ):
        _record_expired_occurrence(schedule)
        return "expired"

    payload = _notification_payload(schedule)
    try:
        webpush(
            subscription_info={
                "endpoint": schedule.subscription.endpoint,
                "keys": {
                    "p256dh": schedule.subscription.p256dh,
                    "auth": schedule.subscription.auth,
                },
            },
            data=json.dumps(payload, separators=(",", ":"), ensure_ascii=False),
            vapid_private_key=settings.WEB_PUSH_VAPID_PRIVATE_KEY,
            vapid_claims={"sub": settings.WEB_PUSH_VAPID_SUBJECT},
            timeout=settings.WEB_PUSH_REQUEST_TIMEOUT_SECONDS,
            ttl=settings.WEB_PUSH_MESSAGE_TTL_SECONDS,
        )
    except WebPushException as exc:
        status_code = getattr(exc.response, "status_code", None)
        if status_code in {404, 410}:
            _revoke_expired_subscription(schedule.subscription_id)
            return "subscription_expired"
        _record_delivery_failure(schedule, status_code=status_code)
        return "retry"
    except OSError:
        _record_delivery_failure(schedule, status_code=None)
        return "retry"

    _record_delivery_success(schedule)
    return "delivered"


def _active_device_subscription(device: Device | None) -> WebPushSubscription | None:
    if device is None:
        return None
    return WebPushSubscription.objects.filter(device=device, revoked_at__isnull=True).first()


def _upsert_schedule(
    *,
    subscription: WebPushSubscription,
    reminder: ReminderRule,
    after: datetime,
) -> None:
    occurrence = next_local_occurrence(reminder, subscription, after=after)
    if occurrence is None:
        WebPushSchedule.objects.filter(subscription=subscription, reminder=reminder).delete()
        return
    WebPushSchedule.objects.update_or_create(
        subscription=subscription,
        reminder=reminder,
        defaults={
            "occurrence_at": occurrence,
            "next_attempt_at": occurrence,
            "attempt_count": 0,
            "claim_token": None,
            "claimed_until": None,
            "last_error_code": "",
        },
    )


def _web_push_eligible(reminder: ReminderRule) -> bool:
    if (
        reminder.deleted_at is not None
        or not reminder.is_enabled
        or reminder.reminder_type not in SUPPORTED_WEB_PUSH_TYPES
    ):
        return False
    if reminder.reminder_type == ReminderType.PRAYER:
        return reminder.prayer_event is not None
    return reminder.local_time is not None


def _weekday_enabled(mask: int, value: date) -> bool:
    return bool(mask & (1 << value.weekday()))


def _resolve_local_wall_time(local_date: date, local_time: time, zone: Any) -> datetime:
    naive = datetime.combine(local_date, local_time.replace(tzinfo=None))
    first = naive.replace(tzinfo=zone, fold=0)
    if _round_trips(first, naive, zone):
        return first
    # A DST gap is resolved to the first existing wall-clock minute after
    # the requested value. Folds deliberately use the first occurrence.
    for minute in range(1, 181):
        shifted = naive + timedelta(minutes=minute)
        candidate = shifted.replace(tzinfo=zone, fold=0)
        if _round_trips(candidate, shifted, zone):
            return candidate
    raise RuntimeError(f"Unable to resolve local wall time in {zone}")


def _round_trips(candidate: datetime, naive: datetime, zone: Any) -> bool:
    return candidate.astimezone(UTC).astimezone(zone).replace(tzinfo=None) == naive


def _notification_payload(schedule: WebPushSchedule) -> dict[str, object]:
    reminder = schedule.reminder
    locale = schedule.subscription.locale
    title, body = _localized_message(reminder, locale)
    return {
        "title": title,
        "body": body,
        "url": _notification_url(reminder, locale),
        "tag": f"reminder-{reminder.id}",
        "signal": reminder.signal,
    }


def _localized_message(reminder: ReminderRule, locale: str) -> tuple[str, str]:
    if reminder.reminder_type == ReminderType.PRAYER:
        prayer_names = {
            "ru": {
                "fajr": "Фаджр",
                "dhuhr": "Зухр",  # noqa: RUF001
                "asr": "Аср",  # noqa: RUF001
                "maghrib": "Магриб",
                "isha": "Иша",
            },
            "en": {
                "fajr": "Fajr",
                "dhuhr": "Dhuhr",
                "asr": "Asr",
                "maghrib": "Maghrib",
                "isha": "Isha",
            },
            "ar": {
                "fajr": "الفجر",
                "dhuhr": "الظهر",
                "asr": "العصر",
                "maghrib": "المغرب",
                "isha": "العشاء",
            },
            "tr": {
                "fajr": "Sabah",
                "dhuhr": "Öğle",
                "asr": "İkindi",
                "maghrib": "Akşam",
                "isha": "Yatsı",  # noqa: RUF001
            },
        }
        bodies = {
            "ru": "Наступило время намаза.",
            "en": "It is time for prayer.",
            "ar": "حان وقت الصلاة.",
            "tr": "Namaz vakti geldi.",
        }
        selected_locale = locale if locale in prayer_names else "en"
        prayer_name = prayer_names[selected_locale].get(str(reminder.prayer_event), "Prayer")
        return prayer_name, bodies[selected_locale]
    messages = {
        "ru": {
            "reading": ("Время читать Коран", "Ваше запланированное чтение Корана."),
            "review": ("Время повторить аяты", "Откройте сохранённый диапазон для повторения."),
        },
        "en": {
            "reading": ("Time to read the Quran", "Your scheduled Quran reading."),
            "review": ("Time to review ayahs", "Open your saved ayah range for review."),
        },
        "ar": {
            "reading": ("حان وقت قراءة القرآن", "موعدك المقرر لقراءة القرآن."),
            "review": ("حان وقت مراجعة الآيات", "افتح نطاق الآيات المحفوظ للمراجعة."),
        },
        "tr": {
            "reading": (
                "Kur'an okuma zamanı",  # noqa: RUF001
                "Planladığınız Kur'an okuma vakti.",  # noqa: RUF001
            ),
            "review": (
                "Ayetleri tekrar etme zamanı",  # noqa: RUF001
                "Tekrar için kaydettiğiniz ayetleri açın.",  # noqa: RUF001
            ),
        },
    }
    selected = messages.get(locale, messages["en"])
    return selected["review" if reminder.reminder_type == ReminderType.QURAN_REVIEW else "reading"]


def _notification_url(reminder: ReminderRule, locale: str) -> str:
    if reminder.reminder_type == ReminderType.PRAYER:
        return f"/{locale}/prayer"
    if reminder.reminder_type == ReminderType.QURAN_REVIEW and reminder.start_ayah is not None:
        return (
            f"/{locale}/quran?surah={reminder.start_ayah.surah.number}"
            f"&ayah={reminder.start_ayah.number}"
        )
    return f"/{locale}/quran"


@transaction.atomic
def _record_delivery_success(schedule: WebPushSchedule) -> None:
    locked = (
        WebPushSchedule.objects.select_for_update()
        .select_related("subscription", "reminder")
        .filter(id=schedule.id, claim_token=schedule.claim_token)
        .first()
    )
    if locked is None:
        return
    current_time = timezone.now()
    subscription = locked.subscription
    subscription.last_success_at = current_time
    subscription.last_failure_at = None
    subscription.consecutive_failures = 0
    subscription.save(
        update_fields=[
            "last_success_at",
            "last_failure_at",
            "consecutive_failures",
            "updated_at",
        ]
    )
    following = next_local_occurrence(
        locked.reminder,
        subscription,
        after=max(locked.occurrence_at, current_time),
    )
    if following is None:
        locked.delete()
        return
    locked.occurrence_at = following
    locked.next_attempt_at = following
    locked.attempt_count = 0
    locked.claim_token = None
    locked.claimed_until = None
    locked.last_error_code = ""
    locked.save()


@transaction.atomic
def _record_delivery_failure(
    schedule: WebPushSchedule,
    *,
    status_code: int | None,
) -> None:
    locked = (
        WebPushSchedule.objects.select_for_update()
        .select_related("subscription", "reminder")
        .filter(id=schedule.id, claim_token=schedule.claim_token)
        .first()
    )
    if locked is None:
        return
    current_time = timezone.now()
    subscription = locked.subscription
    subscription.last_failure_at = current_time
    subscription.consecutive_failures = min(subscription.consecutive_failures + 1, 100)
    subscription.save(update_fields=["last_failure_at", "consecutive_failures", "updated_at"])
    retry_deadline = locked.occurrence_at + timedelta(
        seconds=settings.WEB_PUSH_RETRY_WINDOW_SECONDS
    )
    locked.claim_token = None
    locked.claimed_until = None
    locked.last_error_code = f"http_{status_code}" if status_code else "transport"
    if current_time < retry_deadline:
        locked.attempt_count = min(locked.attempt_count + 1, 100)
        delay = min(30 * (2 ** min(locked.attempt_count, 6)), 900)
        locked.next_attempt_at = current_time + timedelta(seconds=delay)
        locked.save()
        return
    following = next_local_occurrence(locked.reminder, subscription, after=current_time)
    if following is None:
        locked.delete()
        return
    locked.occurrence_at = following
    locked.next_attempt_at = following
    locked.attempt_count = 0
    locked.save()


@transaction.atomic
def _record_expired_occurrence(schedule: WebPushSchedule) -> None:
    locked = (
        WebPushSchedule.objects.select_for_update()
        .select_related("subscription", "reminder")
        .filter(id=schedule.id, claim_token=schedule.claim_token)
        .first()
    )
    if locked is None:
        return
    following = next_local_occurrence(
        locked.reminder,
        locked.subscription,
        after=timezone.now(),
    )
    if following is None:
        locked.delete()
        return
    locked.occurrence_at = following
    locked.next_attempt_at = following
    locked.attempt_count = 0
    locked.claim_token = None
    locked.claimed_until = None
    locked.last_error_code = "expired"
    locked.save()


def _release_claim(schedule: WebPushSchedule, *, error_code: str) -> None:
    WebPushSchedule.objects.filter(id=schedule.id, claim_token=schedule.claim_token).update(
        claim_token=None,
        claimed_until=None,
        last_error_code=error_code,
        next_attempt_at=timezone.now() + timedelta(minutes=5),
    )


def _revoke_expired_subscription(subscription_id: uuid.UUID) -> None:
    WebPushSubscription.objects.filter(id=subscription_id).delete()


def _validate_push_endpoint(endpoint: str) -> None:
    parsed = urlparse(endpoint)
    host = (parsed.hostname or "").lower().rstrip(".")
    allowed = tuple(settings.WEB_PUSH_ALLOWED_ENDPOINT_HOST_SUFFIXES)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValidationError({"endpoint": "Use a valid HTTPS browser push endpoint."}) from exc
    if (
        parsed.scheme != "https"
        or not host
        or parsed.username is not None
        or parsed.password is not None
        or port not in {None, 443}
        or not any(host == suffix or host.endswith(f".{suffix}") for suffix in allowed)
    ):
        raise ValidationError({"endpoint": "Use a supported HTTPS browser push endpoint."})


def _validate_subscription_key(value: str, *, expected_bytes: int, field: str) -> None:
    if not value or len(value) > 128:
        raise ValidationError({field: "Invalid Web Push subscription key."})
    try:
        padded = value + "=" * (-len(value) % 4)
        decoded = base64.urlsafe_b64decode(padded.encode("ascii"))
    except (UnicodeEncodeError, binascii.Error, ValueError) as exc:
        raise ValidationError({field: "Invalid Web Push subscription key."}) from exc
    if len(decoded) != expected_bytes or (field == "p256dh" and decoded[0] != 4):
        raise ValidationError({field: "Invalid Web Push subscription key."})
    if field == "p256dh":
        try:
            ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), decoded)
        except ValueError as exc:
            raise ValidationError({field: "Invalid Web Push subscription key."}) from exc
