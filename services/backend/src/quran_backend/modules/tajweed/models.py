from __future__ import annotations

from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel


class TajweedPublicationStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class TajweedEdition(BaseModel):
    environment = models.CharField(max_length=16)
    provider = models.CharField(max_length=32, default="quran_foundation")
    code = models.SlugField(max_length=64)
    name = models.CharField(max_length=255)
    source_name = models.CharField(max_length=255)
    source_url = models.URLField()
    license_name = models.CharField(max_length=255)
    license_url = models.URLField()
    attribution = models.CharField(max_length=500)
    active_version = models.ForeignKey(
        "TajweedEditionVersion",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="active_for_editions",
    )

    class Meta:
        db_table = "tajweed_edition"
        ordering = ["environment", "code"]
        constraints = [
            models.UniqueConstraint(
                fields=["environment", "provider", "code"],
                name="tajweed_edition_provider_code_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.environment}:{self.code}"

    def clean(self) -> None:
        super().clean()
        active_version = self.active_version if self.active_version_id else None
        if active_version and active_version.edition_id != self.id:
            raise ValidationError("The active version must belong to this tajweed edition.")
        if active_version and active_version.status != TajweedPublicationStatus.PUBLISHED:
            raise ValidationError("Only a published tajweed version can be active.")


class TajweedEditionVersion(BaseModel):
    edition = models.ForeignKey(
        TajweedEdition,
        on_delete=models.PROTECT,
        related_name="versions",
    )
    checksum_sha256 = models.CharField(max_length=64)
    schema_version = models.CharField(max_length=32)
    status = models.CharField(
        max_length=16,
        choices=TajweedPublicationStatus,
        default=TajweedPublicationStatus.DRAFT,
    )
    ayah_count = models.PositiveSmallIntegerField()
    word_count = models.PositiveIntegerField()
    fragment_count = models.PositiveIntegerField()
    # QF Mushaf 19 (QCF V4) and Mushaf 4 snapshots that fixed the word positions.
    mushaf_source_checksum_sha256 = models.CharField(max_length=64)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "tajweed_edition_version"
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition", "checksum_sha256"],
                name="tajweed_version_checksum_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(ayah_count__gt=0),
                name="tajweed_version_positive_ayah_count",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=TajweedPublicationStatus.PUBLISHED,
                        published_at__isnull=False,
                    )
                    | ~models.Q(status=TajweedPublicationStatus.PUBLISHED)
                ),
                name="tajweed_published_version_timestamp",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.edition.code}@{self.checksum_sha256[:12]}"

    def publish(self) -> None:
        self.status = TajweedPublicationStatus.PUBLISHED
        self.published_at = timezone.now()


class AyahTajweed(BaseModel):
    edition_version = models.ForeignKey(
        TajweedEditionVersion,
        on_delete=models.CASCADE,
        related_name="ayahs",
    )
    verse_key = models.CharField(max_length=16)
    surah_number = models.PositiveSmallIntegerField()
    ayah_number = models.PositiveSmallIntegerField()
    page_number = models.PositiveSmallIntegerField()
    source_text = models.TextField()
    # Words that carry rules: [{position, text, rules: [{code, start, end, ...}]}].
    words = models.JSONField(default=list)
    rules = models.JSONField(default=list)

    class Meta:
        db_table = "tajweed_ayah"
        ordering = ["surah_number", "ayah_number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "verse_key"],
                name="tajweed_ayah_version_key_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(surah_number__gte=1, surah_number__lte=114),
                name="tajweed_ayah_surah_range",
            ),
            models.CheckConstraint(
                condition=models.Q(ayah_number__gte=1),
                name="tajweed_ayah_number_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(page_number__gte=1),
                name="tajweed_ayah_page_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["edition_version", "surah_number", "ayah_number"],
                name="tajweed_ayah_lookup_idx",
            ),
            models.Index(
                fields=["edition_version", "page_number"],
                name="tajweed_ayah_page_idx",
            ),
        ]

    def __str__(self) -> str:
        return self.verse_key
