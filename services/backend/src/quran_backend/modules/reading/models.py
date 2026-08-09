from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel


class SyncEntityType(models.TextChoices):
    READING_POSITION = "reading_position", "Reading position"
    BOOKMARK = "bookmark", "Bookmark"
    REMINDER = "reminder", "Reminder"


class SyncAction(models.TextChoices):
    UPSERT = "upsert", "Upsert"
    DELETE = "delete", "Delete"


class SyncOutcome(models.TextChoices):
    ACCEPTED = "accepted", "Accepted"
    CONFLICT = "conflict", "Conflict"


class ReadingPosition(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reading_positions",
    )
    edition = models.ForeignKey(
        "quran.QuranEdition",
        on_delete=models.PROTECT,
        related_name="reading_positions",
    )
    page = models.ForeignKey(
        "quran.MushafPage",
        on_delete=models.PROTECT,
        related_name="reading_positions",
    )
    ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="reading_positions",
        null=True,
        blank=True,
    )
    intra_page_anchor = models.JSONField(default=dict, blank=True)
    progress_percent = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    last_read_at = models.DateTimeField(default=timezone.now, db_index=True)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="reading_positions",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "reading_position"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "edition"],
                name="reading_position_user_edition_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reading_position_revision_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(progress_percent__gte=0, progress_percent__lte=100),
                name="reading_position_progress_range",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "last_read_at"], name="reading_position_user_time_idx"),
        ]

    def clean(self) -> None:
        super().clean()
        if self.page.edition_version.edition_id != self.edition_id:
            raise ValidationError({"page": "Page must belong to the selected Quran edition."})
        ayah = self.ayah
        if ayah is not None and ayah.surah.edition_version.edition_id != self.edition_id:
            raise ValidationError({"ayah": "Ayah must belong to the selected Quran edition."})
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class Bookmark(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="bookmarks",
    )
    edition = models.ForeignKey(
        "quran.QuranEdition",
        on_delete=models.PROTECT,
        related_name="bookmarks",
    )
    page = models.ForeignKey(
        "quran.MushafPage",
        on_delete=models.PROTECT,
        related_name="bookmarks",
        null=True,
        blank=True,
    )
    ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="bookmarks",
        null=True,
        blank=True,
    )
    label = models.CharField(max_length=120, blank=True)
    color_key = models.CharField(max_length=32, default="default")
    note = models.TextField(blank=True, max_length=2000)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="bookmarks",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "reading_bookmark"
        ordering = ["-updated_at", "-id"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(page__isnull=False) | models.Q(ayah__isnull=False),
                name="reading_bookmark_has_target",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reading_bookmark_revision_positive",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "deleted_at"], name="reading_bookmark_user_del_idx"),
            models.Index(fields=["user", "edition"], name="reading_bookmark_user_ed_idx"),
        ]

    def clean(self) -> None:
        super().clean()
        page = self.page
        if page is not None and page.edition_version.edition_id != self.edition_id:
            raise ValidationError({"page": "Page must belong to the selected Quran edition."})
        ayah = self.ayah
        if ayah is not None and ayah.surah.edition_version.edition_id != self.edition_id:
            raise ValidationError({"ayah": "Ayah must belong to the selected Quran edition."})
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class RetiredBookmarkId(BaseModel):
    """Compact permanent identity ledger for physically pruned bookmark tombstones."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="retired_bookmark_ids",
    )
    bookmark_id = models.UUIDField()
    last_revision = models.PositiveBigIntegerField()
    retired_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "reading_retired_bookmark_id"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "bookmark_id"],
                name="reading_retired_bookmark_user_id_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(last_revision__gte=1),
                name="reading_retired_bookmark_revision_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "retired_at"],
                name="reading_retired_bm_time_idx",
            )
        ]


class UserSyncCursor(BaseModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sync_cursor",
    )
    value = models.PositiveBigIntegerField(default=0)
    minimum_valid_cursor = models.PositiveBigIntegerField(default=0)

    class Meta:
        db_table = "reading_user_sync_cursor"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(minimum_valid_cursor__lte=models.F("value")),
                name="reading_sync_cursor_floor_lte_value",
            )
        ]


class SyncChange(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sync_changes",
    )
    sequence = models.PositiveBigIntegerField()
    entity_type = models.CharField(max_length=32, choices=SyncEntityType)
    entity_id = models.UUIDField()
    action = models.CharField(max_length=16, choices=SyncAction)
    revision = models.PositiveBigIntegerField()
    snapshot = models.JSONField()

    class Meta:
        db_table = "reading_sync_change"
        ordering = ["sequence"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "sequence"],
                name="reading_sync_change_user_sequence_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(sequence__gte=1),
                name="reading_sync_change_sequence_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reading_sync_change_revision_positive",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "sequence"], name="reading_sync_change_cursor_idx"),
            models.Index(
                fields=["user", "entity_type", "entity_id"],
                name="reading_sync_change_entity_idx",
            ),
        ]


class SyncOperation(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sync_operations",
    )
    operation_id = models.UUIDField()
    entity_type = models.CharField(max_length=32, choices=SyncEntityType)
    entity_id = models.UUIDField()
    action = models.CharField(max_length=16, choices=SyncAction)
    request_hash = models.CharField(max_length=64)
    outcome = models.CharField(max_length=16, choices=SyncOutcome)
    response = models.JSONField()
    processed_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "reading_sync_operation"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "operation_id"],
                name="reading_sync_operation_user_id_unique",
            )
        ]
        indexes = [
            models.Index(fields=["user", "processed_at"], name="reading_sync_op_user_time_idx"),
            models.Index(fields=["processed_at"], name="reading_sync_op_prune_idx"),
            models.Index(
                fields=["user", "entity_type", "entity_id"],
                name="reading_sync_op_entity_idx",
            ),
        ]
