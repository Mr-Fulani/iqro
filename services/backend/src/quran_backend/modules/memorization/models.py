from __future__ import annotations

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from quran_backend.modules.core.models import BaseModel


class MemorizationAssessment(models.TextChoices):
    DIFFICULT = "difficult", "Difficult"
    REPEAT = "repeat", "Repeat"
    MEMORIZED = "memorized", "Memorized"


class MemorizationPlan(BaseModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="memorization_plan",
    )
    start_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="memorization_plans_started",
    )
    end_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="memorization_plans_ended",
    )
    recitation = models.ForeignKey(
        "audio.RecitationEdition",
        on_delete=models.SET_NULL,
        related_name="memorization_plans",
        null=True,
        blank=True,
    )
    daily_repetitions = models.PositiveSmallIntegerField(default=5)
    pause_seconds = models.PositiveSmallIntegerField(default=2)
    timezone_name = models.CharField(max_length=64)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="memorization_plans",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "memorization_plan"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(daily_repetitions__gte=1, daily_repetitions__lte=100),
                name="memorization_plan_repetitions_range",
            ),
            models.CheckConstraint(
                condition=models.Q(pause_seconds__gte=0, pause_seconds__lte=30),
                name="memorization_plan_pause_range",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="memorization_plan_revision_positive",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        if self.start_ayah_id and self.end_ayah_id:
            if self.start_ayah.surah_id != self.end_ayah.surah_id:
                raise ValidationError({"end_ayah": "The range must stay within one surah."})
            if self.start_ayah.number > self.end_ayah.number:
                raise ValidationError({"end_ayah": "The range end must follow its start."})
        recitation = self.recitation if self.recitation_id else None
        if recitation is not None and self.start_ayah_id:
            ayah_version_id = self.start_ayah.surah.edition_version_id
            if recitation.quran_edition_version_id != ayah_version_id:
                raise ValidationError(
                    {"recitation": "The recitation and Quran range must use the same edition."}
                )
        device = self.device if self.device_id else None
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class MemorizationSession(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="memorization_sessions",
    )
    plan = models.ForeignKey(
        MemorizationPlan,
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    start_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="memorization_sessions_started",
    )
    end_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="memorization_sessions_ended",
    )
    daily_target_repetitions = models.PositiveSmallIntegerField()
    completed_repetitions = models.PositiveSmallIntegerField()
    assessment = models.CharField(max_length=16, choices=MemorizationAssessment)
    duration_seconds = models.PositiveIntegerField(default=0)
    timezone_name = models.CharField(max_length=64)
    local_date = models.DateField()
    client_updated_at = models.DateTimeField()
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="memorization_sessions",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "memorization_session"
        ordering = ["-local_date", "-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(
                    daily_target_repetitions__gte=1,
                    daily_target_repetitions__lte=100,
                ),
                name="memorization_session_target_range",
            ),
            models.CheckConstraint(
                condition=models.Q(
                    completed_repetitions__gte=1,
                    completed_repetitions__lte=1000,
                ),
                name="memorization_session_completed_range",
            ),
            models.CheckConstraint(
                condition=models.Q(duration_seconds__lte=86_400),
                name="memorization_session_duration_range",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "local_date"],
                name="memorization_user_date_idx",
            )
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        if self.plan_id and self.plan.user_id != self.user_id:
            raise ValidationError({"plan": "The plan must belong to the same user."})
        if self.start_ayah_id and self.end_ayah_id:
            if self.start_ayah.surah_id != self.end_ayah.surah_id:
                raise ValidationError({"end_ayah": "The range must stay within one surah."})
            if self.start_ayah.number > self.end_ayah.number:
                raise ValidationError({"end_ayah": "The range end must follow its start."})
        device = self.device if self.device_id else None
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


def _validate_timezone_name(value: str) -> None:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValidationError({"timezone_name": "Use a valid IANA timezone."}) from exc
