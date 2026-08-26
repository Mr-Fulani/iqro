from __future__ import annotations

from enum import IntFlag
from typing import Any, Final

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel
from quran_backend.modules.prayer_times.timezones import (
    InvalidPrayerTimezoneError,
    get_prayer_timezone,
)

MIN_PRAYER_OFFSET_MINUTES: Final = -120
MAX_PRAYER_OFFSET_MINUTES: Final = 120


class ReminderWeekday(IntFlag):
    MONDAY = 1 << 0
    TUESDAY = 1 << 1
    WEDNESDAY = 1 << 2
    THURSDAY = 1 << 3
    FRIDAY = 1 << 4
    SATURDAY = 1 << 5
    SUNDAY = 1 << 6


ALL_WEEKDAYS_MASK: Final = int(
    ReminderWeekday.MONDAY
    | ReminderWeekday.TUESDAY
    | ReminderWeekday.WEDNESDAY
    | ReminderWeekday.THURSDAY
    | ReminderWeekday.FRIDAY
    | ReminderWeekday.SATURDAY
    | ReminderWeekday.SUNDAY
)


class ReminderType(models.TextChoices):
    PRAYER = "prayer", "Prayer"
    QURAN_READING = "quran_reading", "Quran reading"
    QURAN_REVIEW = "quran_review", "Quran review"


class ReminderPrayerEvent(models.TextChoices):
    FAJR = "fajr", "Fajr"
    DHUHR = "dhuhr", "Dhuhr"
    ASR = "asr", "Asr"
    MAGHRIB = "maghrib", "Maghrib"
    ISHA = "isha", "Isha"


class ReminderTimezoneMode(models.TextChoices):
    DEVICE_LOCAL = "device_local", "Device local timezone"
    FIXED = "fixed", "Fixed timezone"


class ReminderDeliveryMode(models.TextChoices):
    LOCAL = "local", "Local client notification"


class ReminderSignal(models.TextChoices):
    SILENT = "silent", "Silent"
    VIBRATION = "vibration", "Vibration"
    SOUND = "sound", "Short system sound"


class ReminderRule(BaseModel):
    """A synchronized rule that clients schedule locally in the MVP."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reminder_rules",
    )
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="reminder_rules",
        null=True,
        blank=True,
    )
    reminder_type = models.CharField(max_length=24, choices=ReminderType)
    prayer_event = models.CharField(
        max_length=16,
        choices=ReminderPrayerEvent,
        null=True,
        blank=True,
    )
    local_time = models.TimeField(null=True, blank=True)
    prayer_offset_minutes = models.SmallIntegerField(
        null=True,
        blank=True,
        validators=[
            MinValueValidator(MIN_PRAYER_OFFSET_MINUTES),
            MaxValueValidator(MAX_PRAYER_OFFSET_MINUTES),
        ],
    )
    start_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="review_reminders_as_start",
        null=True,
        blank=True,
    )
    end_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="review_reminders_as_end",
        null=True,
        blank=True,
    )
    weekdays_mask = models.PositiveSmallIntegerField(
        default=ALL_WEEKDAYS_MASK,
        validators=[MinValueValidator(1), MaxValueValidator(ALL_WEEKDAYS_MASK)],
    )
    timezone_mode = models.CharField(
        max_length=16,
        choices=ReminderTimezoneMode,
        default=ReminderTimezoneMode.DEVICE_LOCAL,
    )
    timezone_name = models.CharField(max_length=64, null=True, blank=True)
    delivery_mode = models.CharField(
        max_length=16,
        choices=ReminderDeliveryMode,
        default=ReminderDeliveryMode.LOCAL,
        editable=False,
    )
    signal = models.CharField(
        max_length=16,
        choices=ReminderSignal,
        default=ReminderSignal.SOUND,
    )
    is_enabled = models.BooleanField(default=True)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)

    class Meta:
        db_table = "reminder_rule"
        ordering = ["-updated_at", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(weekdays_mask__gte=1, weekdays_mask__lte=ALL_WEEKDAYS_MASK),
                name="reminder_weekdays_mask_range",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reminder_revision_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(delivery_mode=ReminderDeliveryMode.LOCAL),
                name="reminder_delivery_local_only",
            ),
            models.CheckConstraint(
                condition=models.Q(signal__in=ReminderSignal.values),
                name="reminder_signal_valid",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        timezone_mode=ReminderTimezoneMode.DEVICE_LOCAL,
                        timezone_name__isnull=True,
                    )
                    | (
                        models.Q(
                            timezone_mode=ReminderTimezoneMode.FIXED,
                            timezone_name__isnull=False,
                        )
                        & ~models.Q(timezone_name="")
                    )
                ),
                name="reminder_timezone_shape",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(deleted_at__isnull=True)
                    & (
                        models.Q(
                            reminder_type=ReminderType.PRAYER,
                            prayer_event__in=ReminderPrayerEvent.values,
                            local_time__isnull=True,
                            prayer_offset_minutes__gte=MIN_PRAYER_OFFSET_MINUTES,
                            prayer_offset_minutes__lte=MAX_PRAYER_OFFSET_MINUTES,
                            start_ayah__isnull=True,
                            end_ayah__isnull=True,
                        )
                        | models.Q(
                            reminder_type=ReminderType.QURAN_READING,
                            prayer_event__isnull=True,
                            local_time__isnull=False,
                            prayer_offset_minutes__isnull=True,
                            start_ayah__isnull=True,
                            end_ayah__isnull=True,
                        )
                        | models.Q(
                            reminder_type=ReminderType.QURAN_REVIEW,
                            prayer_event__isnull=True,
                            local_time__isnull=False,
                            prayer_offset_minutes__isnull=True,
                            start_ayah__isnull=False,
                            end_ayah__isnull=False,
                        )
                    )
                    | models.Q(
                        deleted_at__isnull=False,
                        prayer_event__isnull=True,
                        local_time__isnull=True,
                        prayer_offset_minutes__isnull=True,
                        start_ayah__isnull=True,
                        end_ayah__isnull=True,
                    )
                ),
                name="reminder_schedule_shape",
            ),
            models.CheckConstraint(
                condition=models.Q(deleted_at__isnull=True) | models.Q(is_enabled=False),
                name="reminder_tombstone_disabled",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(deleted_at__isnull=True)
                    | models.Q(
                        device__isnull=True,
                        weekdays_mask=ALL_WEEKDAYS_MASK,
                        timezone_mode=ReminderTimezoneMode.DEVICE_LOCAL,
                        timezone_name__isnull=True,
                        signal=ReminderSignal.SILENT,
                        is_enabled=False,
                    )
                ),
                name="reminder_tombstone_minimized",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "deleted_at", "updated_at"],
                name="reminder_user_sync_idx",
            ),
            models.Index(
                fields=["user", "is_enabled", "reminder_type"],
                name="reminder_user_active_idx",
            ),
            models.Index(
                fields=["deleted_at", "id"],
                name="reminder_retention_idx",
            ),
        ]

    def __str__(self) -> str:
        schedule = self.prayer_event or self.local_time
        return f"{self.user_id}:{self.reminder_type}:{schedule}"

    def clean(self) -> None:
        super().clean()
        errors: dict[str, str] = {}
        if self.deleted_at is not None:
            self._validate_tombstone_shape(errors)
        else:
            self._validate_schedule_shape(errors)
            self._validate_timezone_shape(errors)
            device = self.device
            if device is not None and device.user_id != self.user_id:
                errors["device"] = "Device must belong to the same user."
        if errors:
            raise ValidationError(errors)

    def _validate_tombstone_shape(self, errors: dict[str, str]) -> None:
        cleared_fields = {
            "device": self.device_id,
            "prayer_event": self.prayer_event,
            "local_time": self.local_time,
            "prayer_offset_minutes": self.prayer_offset_minutes,
            "start_ayah": self.start_ayah_id,
            "end_ayah": self.end_ayah_id,
            "timezone_name": self.timezone_name,
        }
        for field, value in cleared_fields.items():
            if value is not None:
                errors[field] = "A deleted reminder must not retain scheduling data."
        if self.weekdays_mask != ALL_WEEKDAYS_MASK:
            errors["weekdays_mask"] = "A deleted reminder must use the neutral weekday mask."
        if self.timezone_mode != ReminderTimezoneMode.DEVICE_LOCAL:
            errors["timezone_mode"] = "A deleted reminder must use the neutral timezone mode."
        if self.signal != ReminderSignal.SILENT:
            errors["signal"] = "A deleted reminder must use the silent signal."
        if self.is_enabled:
            errors["is_enabled"] = "A deleted reminder must be disabled."

    def _validate_schedule_shape(self, errors: dict[str, str]) -> None:
        if self.reminder_type == ReminderType.PRAYER:
            if self.prayer_event not in ReminderPrayerEvent.values:
                errors["prayer_event"] = "A prayer reminder requires one of the five prayers."
            if self.local_time is not None:
                errors["local_time"] = "A prayer reminder is anchored to its prayer event."
            if self.prayer_offset_minutes is None:
                errors["prayer_offset_minutes"] = "A prayer reminder requires an offset."
            self._validate_no_review_range(errors)
            return

        if self.reminder_type in (ReminderType.QURAN_READING, ReminderType.QURAN_REVIEW):
            if self.prayer_event is not None:
                errors["prayer_event"] = "A Quran reminder cannot use a prayer event."
            if self.local_time is None:
                errors["local_time"] = "A Quran reminder requires a local wall-clock time."
            if self.prayer_offset_minutes is not None:
                errors["prayer_offset_minutes"] = "A Quran reminder cannot use a prayer offset."
            if self.reminder_type == ReminderType.QURAN_READING:
                self._validate_no_review_range(errors)
            else:
                self._validate_review_range(errors)

    def _validate_no_review_range(self, errors: dict[str, str]) -> None:
        if self.start_ayah_id is not None:
            errors["start_ayah"] = "Only Quran review reminders can have a target range."
        if self.end_ayah_id is not None:
            errors["end_ayah"] = "Only Quran review reminders can have a target range."

    def _validate_review_range(self, errors: dict[str, str]) -> None:
        if self.start_ayah_id is None:
            errors["start_ayah"] = "A Quran review reminder requires a start ayah."
        if self.end_ayah_id is None:
            errors["end_ayah"] = "A Quran review reminder requires an end ayah."
        if self.start_ayah_id is None or self.end_ayah_id is None:
            return

        start = self.start_ayah
        end = self.end_ayah
        assert start is not None
        assert end is not None
        if start.surah.edition_version_id != end.surah.edition_version_id:
            message = "Review range boundaries must belong to the same Quran edition version."
            errors["start_ayah"] = message
            errors["end_ayah"] = message
            return
        if (start.surah.number, start.number) > (end.surah.number, end.number):
            errors["end_ayah"] = "Review range end must not precede its start."

    def _validate_timezone_shape(self, errors: dict[str, str]) -> None:
        if self.timezone_mode == ReminderTimezoneMode.DEVICE_LOCAL:
            if self.timezone_name is not None:
                errors["timezone_name"] = "Device-local reminders cannot pin a timezone."
            return

        if self.timezone_mode != ReminderTimezoneMode.FIXED:
            return
        if not self.timezone_name:
            errors["timezone_name"] = "A fixed reminder requires an IANA timezone."
            return
        try:
            get_prayer_timezone(self.timezone_name)
        except InvalidPrayerTimezoneError as exc:
            errors["timezone_name"] = str(exc)

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()
        super().save(*args, **kwargs)


class WebPushSubscription(BaseModel):
    """A browser push capability bound to one authenticated installation."""

    device = models.OneToOneField(
        "accounts.Device",
        on_delete=models.CASCADE,
        related_name="web_push_subscription",
    )
    endpoint = models.TextField(unique=True)
    p256dh = models.CharField(max_length=128)
    auth = models.CharField(max_length=64)
    timezone_name = models.CharField(max_length=64)
    locale = models.CharField(max_length=8, default="en")
    prayer_latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        validators=[MinValueValidator(-90), MaxValueValidator(90)],
    )
    prayer_longitude = models.DecimalField(
        max_digits=10,
        decimal_places=6,
        null=True,
        blank=True,
        validators=[MinValueValidator(-180), MaxValueValidator(180)],
    )
    expires_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True, db_index=True)
    last_success_at = models.DateTimeField(null=True, blank=True)
    last_failure_at = models.DateTimeField(null=True, blank=True)
    consecutive_failures = models.PositiveSmallIntegerField(default=0)

    class Meta:
        db_table = "reminder_web_push_subscription"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru", "tr"]),
                name="reminder_push_supported_locale",
            ),
            models.CheckConstraint(
                condition=models.Q(consecutive_failures__lte=100),
                name="reminder_push_failures_bounded",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(prayer_latitude__isnull=True, prayer_longitude__isnull=True)
                    | models.Q(prayer_latitude__isnull=False, prayer_longitude__isnull=False)
                ),
                name="reminder_push_prayer_location_pair",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(prayer_latitude__isnull=True)
                    | models.Q(
                        prayer_latitude__gte=-90,
                        prayer_latitude__lte=90,
                        prayer_longitude__gte=-180,
                        prayer_longitude__lte=180,
                    )
                ),
                name="reminder_push_prayer_location_range",
            ),
        ]
        indexes = [
            models.Index(
                fields=["revoked_at", "updated_at"],
                name="reminder_push_active_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.device_id}:{self.timezone_name}"

    def clean(self) -> None:
        super().clean()
        try:
            get_prayer_timezone(self.timezone_name)
        except InvalidPrayerTimezoneError as exc:
            raise ValidationError({"timezone_name": str(exc)}) from exc

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()
        super().save(*args, **kwargs)


class WebPushSchedule(BaseModel):
    """Indexed next delivery for one local-time rule and browser subscription."""

    subscription = models.ForeignKey(
        WebPushSubscription,
        on_delete=models.CASCADE,
        related_name="schedules",
    )
    reminder = models.ForeignKey(
        ReminderRule,
        on_delete=models.CASCADE,
        related_name="web_push_schedules",
    )
    occurrence_at = models.DateTimeField()
    next_attempt_at = models.DateTimeField(db_index=True)
    attempt_count = models.PositiveSmallIntegerField(default=0)
    claim_token = models.UUIDField(null=True, blank=True)
    claimed_until = models.DateTimeField(null=True, blank=True, db_index=True)
    last_error_code = models.CharField(max_length=64, blank=True)

    class Meta:
        db_table = "reminder_web_push_schedule"
        constraints = [
            models.UniqueConstraint(
                fields=["subscription", "reminder"],
                name="reminder_push_schedule_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(attempt_count__lte=100),
                name="reminder_push_attempts_bounded",
            ),
        ]
        indexes = [
            models.Index(
                fields=["next_attempt_at", "claimed_until"],
                name="reminder_push_due_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.subscription_id}:{self.reminder_id}:{self.occurrence_at.isoformat()}"


class RetiredReminderId(models.Model):
    """Compact bounded ledger for physically pruned reminder identities."""

    reminder_id = models.UUIDField(primary_key=True, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="retired_reminder_ids",
    )
    last_revision = models.PositiveBigIntegerField()
    retired_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "reminder_retired_id"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(last_revision__gte=1),
                name="reminder_retired_revision_positive",
            )
        ]
        indexes = [
            models.Index(
                fields=["user", "retired_at"],
                name="reminder_retired_user_time_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.user_id}:{self.reminder_id}"
