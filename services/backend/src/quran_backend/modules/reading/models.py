from __future__ import annotations

from decimal import Decimal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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


class ReadingGoalMetric(models.TextChoices):
    MINUTES = "minutes", "Minutes"
    PAGES = "pages", "Pages"
    AYAHS = "ayahs", "Ayahs"


class ReadingGoalStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    ARCHIVED = "archived", "Archived"


class ReadingSessionSource(models.TextChoices):
    AUTOMATIC = "automatic", "Automatic"
    MANUAL = "manual", "Manual"


class ReadingSessionStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    COMPLETED = "completed", "Completed"
    DISCARDED = "discarded", "Discarded"


class PrayerReadingPrayer(models.TextChoices):
    FAJR = "fajr", "Fajr"
    DHUHR = "dhuhr", "Dhuhr"
    ASR = "asr", "Asr"
    MAGHRIB = "maghrib", "Maghrib"
    ISHA = "isha", "Isha"


READING_GOAL_LIMITS: dict[str, Decimal] = {
    ReadingGoalMetric.MINUTES: Decimal("1440"),
    ReadingGoalMetric.PAGES: Decimal("604"),
    ReadingGoalMetric.AYAHS: Decimal("6236"),
}


class ReadingGoal(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reading_goals",
    )
    metric = models.CharField(max_length=16, choices=ReadingGoalMetric)
    target_amount = models.DecimalField(max_digits=8, decimal_places=2)
    timezone_name = models.CharField(max_length=64)
    started_on = models.DateField()
    ended_on = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=16,
        choices=ReadingGoalStatus,
        default=ReadingGoalStatus.ACTIVE,
    )
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="reading_goals",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "reading_goal"
        constraints = [
            models.UniqueConstraint(
                fields=["user"],
                condition=models.Q(status=ReadingGoalStatus.ACTIVE),
                name="reading_goal_one_active_per_user",
            ),
            models.CheckConstraint(
                condition=models.Q(target_amount__gt=0),
                name="reading_goal_target_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reading_goal_revision_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(ended_on__isnull=True)
                | models.Q(ended_on__gte=models.F("started_on")),
                name="reading_goal_date_order",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(status=ReadingGoalStatus.ACTIVE, ended_on__isnull=True)
                    | models.Q(status=ReadingGoalStatus.ARCHIVED, ended_on__isnull=False)
                ),
                name="reading_goal_status_shape",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "status"], name="reading_goal_user_status_idx"),
            models.Index(
                fields=["user", "started_on", "ended_on"],
                name="reading_goal_user_dates_idx",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        if self.metric in {ReadingGoalMetric.PAGES, ReadingGoalMetric.AYAHS}:
            _validate_whole_amount(self.target_amount, field="target_amount")
        limit = READING_GOAL_LIMITS.get(self.metric)
        if limit is not None and self.target_amount > limit:
            raise ValidationError({"target_amount": f"Target must not exceed {int(limit)}."})
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class PrayerReadingPlan(BaseModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="prayer_reading_plan",
    )
    pages_per_prayer = models.PositiveSmallIntegerField(default=2)
    notifications_enabled = models.BooleanField(default=True)
    timezone_name = models.CharField(max_length=64)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="prayer_reading_plans",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "prayer_reading_plan"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(pages_per_prayer__gte=1, pages_per_prayer__lte=20),
                name="prayer_reading_plan_pages_range",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="prayer_reading_plan_revision_positive",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class ReadingSession(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reading_sessions",
    )
    goal = models.ForeignKey(
        ReadingGoal,
        on_delete=models.SET_NULL,
        related_name="sessions",
        null=True,
        blank=True,
    )
    source = models.CharField(max_length=16, choices=ReadingSessionSource)
    status = models.CharField(
        max_length=16,
        choices=ReadingSessionStatus,
        default=ReadingSessionStatus.COMPLETED,
    )
    timezone_name = models.CharField(max_length=64)
    local_date = models.DateField()
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    active_seconds = models.PositiveIntegerField(default=0)
    credited_pages = models.PositiveSmallIntegerField(default=0)
    credited_ayahs = models.PositiveSmallIntegerField(default=0)
    manual_metric = models.CharField(
        max_length=16,
        choices=ReadingGoalMetric,
        blank=True,
        default="",
    )
    manual_amount = models.DecimalField(
        max_digits=8,
        decimal_places=2,
        null=True,
        blank=True,
    )
    edition = models.ForeignKey(
        "quran.QuranEdition",
        on_delete=models.PROTECT,
        related_name="reading_sessions",
        null=True,
        blank=True,
    )
    start_page = models.ForeignKey(
        "quran.MushafPage",
        on_delete=models.PROTECT,
        related_name="reading_sessions_started",
        null=True,
        blank=True,
    )
    end_page = models.ForeignKey(
        "quran.MushafPage",
        on_delete=models.PROTECT,
        related_name="reading_sessions_ended",
        null=True,
        blank=True,
    )
    start_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="reading_sessions_started",
        null=True,
        blank=True,
    )
    end_ayah = models.ForeignKey(
        "quran.Ayah",
        on_delete=models.PROTECT,
        related_name="reading_sessions_ended",
        null=True,
        blank=True,
    )
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="reading_sessions",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "reading_session"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="reading_session_revision_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(ended_at__isnull=True)
                | models.Q(started_at__isnull=True)
                | models.Q(ended_at__gte=models.F("started_at")),
                name="reading_session_time_order",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        source=ReadingSessionSource.MANUAL,
                        manual_metric__in=ReadingGoalMetric.values,
                        manual_amount__gt=0,
                    )
                    | models.Q(
                        source=ReadingSessionSource.AUTOMATIC,
                        manual_metric="",
                        manual_amount__isnull=True,
                    )
                ),
                name="reading_session_source_shape",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=ReadingSessionStatus.ACTIVE,
                        ended_at__isnull=True,
                        deleted_at__isnull=True,
                    )
                    | models.Q(
                        status=ReadingSessionStatus.COMPLETED,
                        ended_at__isnull=False,
                        deleted_at__isnull=True,
                    )
                    | models.Q(
                        status=ReadingSessionStatus.DISCARDED,
                        ended_at__isnull=False,
                        deleted_at__isnull=False,
                    )
                ),
                name="reading_session_status_shape",
            ),
            models.CheckConstraint(
                condition=(
                    ~models.Q(status=ReadingSessionStatus.COMPLETED)
                    | models.Q(source=ReadingSessionSource.MANUAL)
                    | models.Q(active_seconds__gt=0)
                    | models.Q(credited_pages__gt=0)
                    | models.Q(credited_ayahs__gt=0)
                ),
                name="reading_session_completed_has_activity",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "local_date", "deleted_at"],
                name="reading_session_user_date_idx",
            ),
            models.Index(
                fields=["goal", "local_date", "deleted_at"],
                name="reading_session_goal_date_idx",
            ),
            models.Index(
                fields=["user", "created_at"],
                name="reading_session_user_time_idx",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        if (
            self.manual_metric in {ReadingGoalMetric.PAGES, ReadingGoalMetric.AYAHS}
            and self.manual_amount is not None
        ):
            _validate_whole_amount(self.manual_amount, field="manual_amount")
        if self.manual_metric and self.manual_amount is not None:
            limit = READING_GOAL_LIMITS.get(self.manual_metric)
            if limit is not None and self.manual_amount > limit:
                raise ValidationError({"manual_amount": f"Amount must not exceed {int(limit)}."})
        if self.active_seconds > 24 * 60 * 60:
            raise ValidationError({"active_seconds": "Active time must not exceed 24 hours."})
        if self.credited_pages > int(READING_GOAL_LIMITS[ReadingGoalMetric.PAGES]):
            raise ValidationError({"credited_pages": "Page count must not exceed 604."})
        if self.credited_ayahs > int(READING_GOAL_LIMITS[ReadingGoalMetric.AYAHS]):
            raise ValidationError({"credited_ayahs": "Ayah count must not exceed 6236."})
        goal = self.goal if self.goal_id is not None else None
        if goal is not None and goal.user_id != self.user_id:
            raise ValidationError({"goal": "Goal must belong to the same user."})
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})
        self._validate_quran_references()

    def _validate_quran_references(self) -> None:
        edition_id = self.edition_id
        start_page = self.start_page if self.start_page_id is not None else None
        end_page = self.end_page if self.end_page_id is not None else None
        start_ayah = self.start_ayah if self.start_ayah_id is not None else None
        end_ayah = self.end_ayah if self.end_ayah_id is not None else None
        references = {
            "start_page": (
                start_page.edition_version.edition_id if start_page is not None else None
            ),
            "end_page": (end_page.edition_version.edition_id if end_page is not None else None),
            "start_ayah": (
                start_ayah.surah.edition_version.edition_id if start_ayah is not None else None
            ),
            "end_ayah": (
                end_ayah.surah.edition_version.edition_id if end_ayah is not None else None
            ),
        }
        if edition_id is None and any(value is not None for value in references.values()):
            raise ValidationError({"edition": "Edition is required when Quran references are set."})
        errors = {
            field: "Reference must belong to the selected Quran edition."
            for field, reference_edition_id in references.items()
            if reference_edition_id is not None and reference_edition_id != edition_id
        }
        if errors:
            raise ValidationError(errors)


class PrayerReadingCheckIn(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="prayer_reading_check_ins",
    )
    plan = models.ForeignKey(
        PrayerReadingPlan,
        on_delete=models.CASCADE,
        related_name="check_ins",
    )
    prayer = models.CharField(max_length=16, choices=PrayerReadingPrayer)
    local_date = models.DateField()
    timezone_name = models.CharField(max_length=64)
    pages = models.PositiveSmallIntegerField()
    reading_session = models.OneToOneField(
        ReadingSession,
        on_delete=models.SET_NULL,
        related_name="prayer_reading_check_in",
        null=True,
        blank=True,
    )
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="prayer_reading_check_ins",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "prayer_reading_check_in"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "local_date", "prayer"],
                name="prayer_reading_check_in_daily_prayer_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(pages__gte=1, pages__lte=604),
                name="prayer_reading_check_in_pages_range",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="prayer_reading_check_in_revision_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "local_date"],
                name="prayer_reading_user_date_idx",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        _validate_timezone_name(self.timezone_name)
        if self.plan.user_id != self.user_id:
            raise ValidationError({"plan": "Plan must belong to the same user."})
        session = self.reading_session
        if session is not None and session.user_id != self.user_id:
            raise ValidationError(
                {"reading_session": "Reading session must belong to the same user."}
            )
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class GoalProgress(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reading_goal_progress",
    )
    goal = models.ForeignKey(
        ReadingGoal,
        on_delete=models.CASCADE,
        related_name="progress",
    )
    local_date = models.DateField()
    achieved_amount = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=Decimal("0"),
    )
    completed_at = models.DateTimeField(null=True, blank=True)
    recalculation_version = models.PositiveIntegerField(default=1)

    class Meta:
        db_table = "reading_goal_progress"
        constraints = [
            models.UniqueConstraint(
                fields=["goal", "local_date"],
                name="reading_goal_progress_goal_date_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(achieved_amount__gte=0),
                name="reading_goal_progress_amount_nonnegative",
            ),
            models.CheckConstraint(
                condition=models.Q(recalculation_version__gte=1),
                name="reading_goal_progress_version_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["user", "local_date"],
                name="reading_progress_user_date_idx",
            ),
            models.Index(
                fields=["user", "completed_at"],
                name="reading_progress_user_done_idx",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        if self.goal.user_id != self.user_id:
            raise ValidationError({"goal": "Goal must belong to the same user."})


class QuranReaderPreference(BaseModel):
    """Account-synced Quran reader display preferences for one interface locale."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="quran_reader_preferences",
    )
    locale = models.CharField(max_length=8)
    translation_enabled = models.BooleanField(default=False)
    translation_source_id = models.PositiveIntegerField(null=True, blank=True)
    tafsir_enabled = models.BooleanField(default=False)
    tafsir_source_id = models.PositiveIntegerField(null=True, blank=True)
    client_updated_at = models.DateTimeField()
    revision = models.PositiveBigIntegerField(default=1)
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="quran_reader_preferences",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "quran_reader_preference"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "locale"],
                name="quran_reader_preference_user_locale_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru", "tr"]),
                name="quran_reader_preference_supported_locale",
            ),
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="quran_reader_preference_revision_positive",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(translation_enabled=False)
                    | models.Q(translation_source_id__isnull=False)
                ),
                name="quran_reader_preference_translation_shape",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(tafsir_enabled=False) | models.Q(tafsir_source_id__isnull=False)
                ),
                name="quran_reader_preference_tafsir_shape",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        device = self.device
        if device is not None and device.user_id != self.user_id:
            raise ValidationError({"device": "Device must belong to the same user."})


class ReadingStreak(BaseModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reading_streak",
    )
    current_count = models.PositiveIntegerField(default=0)
    longest_count = models.PositiveIntegerField(default=0)
    last_qualifying_date = models.DateField(null=True, blank=True)
    recalculation_version = models.PositiveIntegerField(default=1)

    class Meta:
        db_table = "reading_streak"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(longest_count__gte=models.F("current_count")),
                name="reading_streak_longest_gte_current",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(current_count=0)
                    | models.Q(current_count__gt=0, last_qualifying_date__isnull=False)
                ),
                name="reading_streak_current_date_shape",
            ),
            models.CheckConstraint(
                condition=models.Q(recalculation_version__gte=1),
                name="reading_streak_version_positive",
            ),
        ]


def _validate_timezone_name(value: str) -> None:
    try:
        ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError) as exc:
        raise ValidationError({"timezone_name": "Use a valid IANA timezone name."}) from exc


def _validate_whole_amount(value: Decimal, *, field: str) -> None:
    if value != value.to_integral_value():
        raise ValidationError({field: "Pages and ayahs must use whole numbers."})
