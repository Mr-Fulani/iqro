from __future__ import annotations

import secrets
import uuid
from typing import Any

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from quran_backend.modules.core.models import BaseModel


def generate_feedback_public_id() -> str:
    """Return an opaque, support-friendly identifier with 144 bits of entropy."""
    return f"FB-{secrets.token_urlsafe(18)}"


class FeedbackCategory(models.TextChoices):
    GENERAL = "general", "General suggestion"
    TECHNICAL = "technical", "Technical problem"
    RELIGIOUS_CONTENT = "religious_content", "Religious content concern"
    PAGE_LAYOUT = "page_layout", "Mushaf page or region problem"
    AUDIO = "audio", "Audio, timing or reciter problem"
    ADVERTISEMENT = "advertisement", "Advertisement complaint"
    ACCOUNT_SYNC = "account_sync", "Account or synchronization"
    DONATION_LINK = "donation_link", "Donation or external link"
    ACCESSIBILITY_LOCALIZATION = (
        "accessibility_localization",
        "Accessibility or localization",
    )
    OTHER = "other", "Other"


class FeedbackStatus(models.TextChoices):
    NEW = "new", "New"
    TRIAGED = "triaged", "Triaged"
    IN_PROGRESS = "in_progress", "In progress"
    WAITING_FOR_USER = "waiting_for_user", "Waiting for user"
    RESOLVED = "resolved", "Resolved"
    REJECTED = "rejected", "Rejected"
    DUPLICATE = "duplicate", "Duplicate"
    CLOSED = "closed", "Closed"


class FeedbackPriority(models.TextChoices):
    NORMAL = "normal", "Normal"
    HIGH = "high", "High"
    CRITICAL = "critical", "Critical"


class FeedbackChannel(models.TextChoices):
    IOS = "ios", "iOS"
    ANDROID = "android", "Android"
    WEB = "web", "Web"
    TELEGRAM = "telegram", "Telegram Mini App"


class FeedbackAuthorType(models.TextChoices):
    REPORTER = "reporter", "Reporter"
    OPERATOR = "operator", "Operator"
    SYSTEM = "system", "System"


class FeedbackVisibility(models.TextChoices):
    PUBLIC = "public", "Public"
    INTERNAL = "internal", "Internal"


class FeedbackAuditAction(models.TextChoices):
    CREATED = "created", "Created"
    STATUS_CHANGED = "status_changed", "Status changed"
    ROUTING_CHANGED = "routing_changed", "Routing changed"
    MESSAGE_ADDED = "message_added", "Message added"
    REOPENED = "reopened", "Reopened"


class FeedbackTicket(BaseModel):
    public_id = models.CharField(
        max_length=32,
        unique=True,
        default=generate_feedback_public_id,
        editable=False,
    )
    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="feedback_tickets",
    )
    client_request_id = models.UUIDField()
    request_fingerprint = models.CharField(max_length=64, editable=False)
    category = models.CharField(max_length=40, choices=FeedbackCategory)
    subject = models.CharField(max_length=160)
    status = models.CharField(max_length=24, choices=FeedbackStatus, default=FeedbackStatus.NEW)
    priority = models.CharField(
        max_length=16,
        choices=FeedbackPriority,
        default=FeedbackPriority.NORMAL,
    )
    locale = models.CharField(max_length=8)
    channel = models.CharField(max_length=16, choices=FeedbackChannel)
    contact_email = models.EmailField(null=True, blank=True)
    team = models.CharField(max_length=64, blank=True)
    assignee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="assigned_feedback_tickets",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
    )
    sla_response_due_at = models.DateTimeField(null=True, blank=True, db_index=True)
    first_response_at = models.DateTimeField(null=True, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    reopened_at = models.DateTimeField(null=True, blank=True)
    reopen_count = models.PositiveSmallIntegerField(default=0)
    last_public_message_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "feedback_ticket"
        ordering = ["-created_at", "-id"]
        constraints = [
            models.UniqueConstraint(
                fields=["reporter", "client_request_id"],
                name="feedback_ticket_reporter_request_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru"]),
                name="feedback_ticket_supported_locale",
            ),
        ]
        indexes = [
            models.Index(
                fields=["reporter", "created_at", "id"],
                name="fb_ticket_reporter_time_idx",
            ),
            models.Index(
                fields=["status", "priority", "sla_response_due_at"],
                name="feedback_ticket_sla_idx",
            ),
            models.Index(fields=["category", "status"], name="feedback_ticket_route_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.public_id}: {self.subject}"

    def clean(self) -> None:
        super().clean()
        assignee = self.assignee
        if assignee is not None and not assignee.is_staff:
            raise ValidationError({"assignee": "Feedback assignee must be a staff user."})


class FeedbackContext(BaseModel):
    """Immutable reported context; identifiers intentionally survive content retirement."""

    ticket = models.OneToOneField(
        FeedbackTicket,
        on_delete=models.CASCADE,
        related_name="context",
    )
    edition_code = models.CharField(max_length=64, blank=True)
    content_version = models.CharField(max_length=64, blank=True)
    surah_number = models.PositiveSmallIntegerField(null=True, blank=True)
    ayah_number = models.PositiveSmallIntegerField(null=True, blank=True)
    page_number = models.PositiveSmallIntegerField(null=True, blank=True)
    reciter_id = models.CharField(max_length=128, blank=True)
    recitation_id = models.CharField(max_length=128, blank=True)
    audio_track_id = models.CharField(max_length=128, blank=True)
    playback_ms = models.PositiveBigIntegerField(null=True, blank=True)
    ad_campaign_id = models.CharField(max_length=128, blank=True)
    ad_creative_id = models.CharField(max_length=128, blank=True)
    route = models.CharField(max_length=255, blank=True)
    app_version = models.CharField(max_length=32, blank=True)
    app_build = models.CharField(max_length=32, blank=True)
    client_platform = models.CharField(max_length=16, choices=FeedbackChannel, blank=True)
    os_version = models.CharField(max_length=64, blank=True)

    class Meta:
        db_table = "feedback_context"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(surah_number__isnull=True)
                | models.Q(surah_number__gte=1, surah_number__lte=114),
                name="feedback_context_surah_range",
            ),
            models.CheckConstraint(
                condition=models.Q(ayah_number__isnull=True) | models.Q(ayah_number__gte=1),
                name="feedback_context_ayah_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(page_number__isnull=True)
                | models.Q(page_number__gte=1, page_number__lte=604),
                name="feedback_context_page_range",
            ),
        ]

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            msg = "Feedback context is immutable."
            raise ValidationError(msg)
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        msg = "Feedback context is immutable."
        raise ValidationError(msg)


class FeedbackMessage(BaseModel):
    ticket = models.ForeignKey(
        FeedbackTicket,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    client_message_id = models.UUIDField(default=uuid.uuid7)
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="feedback_messages",
        null=True,
        blank=True,
    )
    author_type = models.CharField(max_length=16, choices=FeedbackAuthorType)
    visibility = models.CharField(max_length=16, choices=FeedbackVisibility)
    body = models.TextField(max_length=4000)

    class Meta:
        db_table = "feedback_message"
        ordering = ["created_at", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["ticket", "client_message_id"],
                name="feedback_message_ticket_client_unique",
            )
        ]
        indexes = [
            models.Index(
                fields=["ticket", "visibility", "created_at"],
                name="feedback_message_public_idx",
            )
        ]

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            msg = "Feedback messages are immutable."
            raise ValidationError(msg)
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        msg = "Feedback messages are immutable."
        raise ValidationError(msg)


class FeedbackAudit(BaseModel):
    ticket = models.ForeignKey(
        FeedbackTicket,
        on_delete=models.CASCADE,
        related_name="audit_events",
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="feedback_audit_events",
        null=True,
        blank=True,
    )
    actor_type = models.CharField(max_length=16, choices=FeedbackAuthorType)
    action = models.CharField(max_length=24, choices=FeedbackAuditAction)
    old_values = models.JSONField(default=dict, blank=True)
    new_values = models.JSONField(default=dict, blank=True)
    reason = models.CharField(max_length=500, blank=True)

    class Meta:
        db_table = "feedback_audit"
        ordering = ["created_at", "id"]
        indexes = [models.Index(fields=["ticket", "created_at"], name="feedback_audit_time_idx")]

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            msg = "Feedback audit events are immutable."
            raise ValidationError(msg)
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        msg = "Feedback audit events are immutable."
        raise ValidationError(msg)
