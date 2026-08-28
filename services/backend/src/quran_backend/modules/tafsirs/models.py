from __future__ import annotations

from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel


class TafsirPublicationStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class TafsirEdition(BaseModel):
    environment = models.CharField(max_length=16)
    provider = models.CharField(max_length=32, default="quran_foundation")
    source_id = models.PositiveIntegerField()
    slug = models.SlugField(max_length=128)
    language_code = models.CharField(max_length=8, db_index=True)
    language_name = models.CharField(max_length=64)
    name = models.CharField(max_length=255)
    author_name = models.CharField(max_length=255)
    source_name = models.CharField(max_length=255)
    source_url = models.URLField()
    license_name = models.CharField(max_length=255)
    license_url = models.URLField()
    attribution = models.CharField(max_length=500)
    is_available = models.BooleanField(default=True, db_index=True)
    active_version = models.ForeignKey(
        "TafsirEditionVersion",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="active_for_editions",
    )

    class Meta:
        db_table = "tafsir_edition"
        ordering = ["language_code", "name", "source_id"]
        constraints = [
            models.UniqueConstraint(
                fields=["environment", "provider", "source_id"],
                name="tafsir_edition_provider_source_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.language_code}:{self.slug}"

    def clean(self) -> None:
        super().clean()
        active_version = self.active_version if self.active_version_id else None
        if active_version and active_version.edition_id != self.id:
            raise ValidationError("The active version must belong to this Tafsir edition.")
        if active_version and active_version.status != TafsirPublicationStatus.PUBLISHED:
            raise ValidationError("Only a published Tafsir version can be active.")


class TafsirEditionVersion(BaseModel):
    edition = models.ForeignKey(
        TafsirEdition,
        on_delete=models.PROTECT,
        related_name="versions",
    )
    sync_sequence = models.PositiveBigIntegerField()
    schema_version = models.CharField(max_length=32)
    checksum_sha256 = models.CharField(max_length=64)
    status = models.CharField(
        max_length=16,
        choices=TafsirPublicationStatus,
        default=TafsirPublicationStatus.DRAFT,
    )
    record_count = models.PositiveSmallIntegerField()
    covered_ayah_count = models.PositiveSmallIntegerField()
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "tafsir_edition_version"
        ordering = ["-sync_sequence"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition", "sync_sequence"],
                name="tafsir_version_sequence_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(record_count__gt=0),
                name="tafsir_version_positive_record_count",
            ),
            models.CheckConstraint(
                condition=models.Q(covered_ayah_count__gt=0),
                name="tafsir_version_positive_coverage",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=TafsirPublicationStatus.PUBLISHED,
                        published_at__isnull=False,
                    )
                    | ~models.Q(status=TafsirPublicationStatus.PUBLISHED)
                ),
                name="tafsir_published_version_timestamp",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.edition.slug}@{self.sync_sequence}"

    def publish(self) -> None:
        self.status = TafsirPublicationStatus.PUBLISHED
        self.published_at = timezone.now()


class AyahTafsir(BaseModel):
    edition_version = models.ForeignKey(
        TafsirEditionVersion,
        on_delete=models.CASCADE,
        related_name="ayah_tafsirs",
    )
    source_id = models.PositiveBigIntegerField()
    provider_group_id = models.PositiveBigIntegerField(null=True, blank=True)
    verse_key = models.CharField(max_length=16)
    surah_number = models.PositiveSmallIntegerField()
    ayah_number = models.PositiveSmallIntegerField()
    start_verse_id = models.PositiveSmallIntegerField()
    end_verse_id = models.PositiveSmallIntegerField()
    start_verse_key = models.CharField(max_length=16)
    end_verse_key = models.CharField(max_length=16)
    start_surah_number = models.PositiveSmallIntegerField()
    start_ayah_number = models.PositiveSmallIntegerField()
    end_surah_number = models.PositiveSmallIntegerField()
    end_ayah_number = models.PositiveSmallIntegerField()
    group_verses_count = models.PositiveSmallIntegerField()
    text = models.TextField()
    source_text = models.TextField()

    class Meta:
        db_table = "tafsir_ayah"
        ordering = ["surah_number", "ayah_number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "source_id"],
                name="tafsir_ayah_version_source_unique",
            ),
            models.UniqueConstraint(
                fields=["edition_version", "verse_key"],
                name="tafsir_ayah_version_key_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(surah_number__gte=1, surah_number__lte=114),
                name="tafsir_ayah_surah_range",
            ),
            models.CheckConstraint(
                condition=models.Q(ayah_number__gte=1),
                name="tafsir_ayah_number_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(end_verse_id__gte=models.F("start_verse_id")),
                name="tafsir_ayah_valid_range",
            ),
        ]
        indexes = [
            models.Index(
                fields=["edition_version", "surah_number", "ayah_number"],
                name="tafsir_ayah_lookup_idx",
            ),
            models.Index(
                fields=["edition_version", "start_verse_id", "end_verse_id"],
                name="tafsir_ayah_range_idx",
            ),
        ]


class QuranFoundationTafsirSyncState(BaseModel):
    environment = models.CharField(max_length=16)
    resources_filter = models.CharField(max_length=255)
    sync_token = models.TextField(blank=True)
    last_sync_sequence = models.PositiveBigIntegerField(default=0)
    last_attempt_at = models.DateTimeField(null=True, blank=True)
    last_success_at = models.DateTimeField(null=True, blank=True)
    consecutive_failures = models.PositiveIntegerField(default=0)
    last_error_code = models.CharField(max_length=64, blank=True)

    class Meta:
        db_table = "tafsir_qf_sync_state"
        constraints = [
            models.UniqueConstraint(
                fields=["environment", "resources_filter"],
                name="tafsir_qf_sync_state_unique",
            ),
        ]
