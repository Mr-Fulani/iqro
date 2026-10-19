"""The prayer-learning course: versioned like the du'a catalogue.

A version is imported from a source snapshot, compiled into one linear
document per language, signed off by the owner and published. Published
versions never change; a correction is a new version.
"""

from __future__ import annotations

from typing import Any

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.audio.validators import validate_relative_object_key, validate_sha256
from quran_backend.modules.core.models import BaseModel

SALAH_LANGUAGES = ("ru", "en", "ar", "tr")


class SalahPublicationStatus(models.TextChoices):
    DRAFT = "draft", "Черновик"
    PUBLISHED = "published", "Опубликована"
    WITHDRAWN = "withdrawn", "Отозвана"


class SalahCourse(BaseModel):
    slug = models.SlugField(max_length=64, unique=True)
    active_version = models.ForeignKey(
        "SalahCourseVersion",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )

    class Meta:
        ordering = ["slug"]

    def __str__(self) -> str:
        return self.slug

    def clean(self) -> None:
        super().clean()
        version = self.active_version if self.active_version_id else None
        if version and version.course_id != self.id:
            raise ValidationError({"active_version": "Версия принадлежит другому курсу."})
        if version and version.status != SalahPublicationStatus.PUBLISHED:
            raise ValidationError(
                {"active_version": "Активной может быть только опубликованная версия."}
            )


class SalahCourseVersion(BaseModel):
    course = models.ForeignKey(SalahCourse, on_delete=models.PROTECT, related_name="versions")
    version = models.CharField(max_length=64)
    schema_version = models.PositiveSmallIntegerField()
    methodology = models.CharField(max_length=32)
    source_title = models.JSONField(default=dict)
    snapshot = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    status = models.CharField(
        max_length=16,
        choices=SalahPublicationStatus,
        default=SalahPublicationStatus.DRAFT,
        db_index=True,
    )
    published_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.TextField(blank=True)

    class Meta:
        ordering = ["course", "-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["course", "version"], name="salah_version_unique"),
            models.CheckConstraint(
                condition=~models.Q(status=SalahPublicationStatus.PUBLISHED)
                | (models.Q(published_at__isnull=False) & models.Q(reviewed_by__isnull=False)),
                name="salah_published_is_signed",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.course.slug}@{self.version}"

    @property
    def is_signed(self) -> bool:
        return self.reviewed_by_id is not None and self.reviewed_at is not None

    def sign(self, user: Any, note: str = "") -> None:
        """Records the owner's religious sign-off; only drafts can be signed."""
        if self.status != SalahPublicationStatus.DRAFT:
            raise ValidationError("Подписать можно только черновик.")
        self.reviewed_by = user
        self.reviewed_at = timezone.now()
        self.review_note = note
        self.save(update_fields=["reviewed_by", "reviewed_at", "review_note", "updated_at"])


class SalahCompiledDocument(BaseModel):
    """The ready-to-serve course document for one language."""

    version = models.ForeignKey(
        SalahCourseVersion, on_delete=models.CASCADE, related_name="documents"
    )
    language = models.CharField(max_length=8)
    payload = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    bytes = models.PositiveIntegerField()

    class Meta:
        ordering = ["version", "language"]
        constraints = [
            models.UniqueConstraint(fields=["version", "language"], name="salah_document_unique"),
        ]

    def __str__(self) -> str:
        return f"{self.version}:{self.language}"


class SalahMediaAsset(BaseModel):
    """An illustration or short recording, stored under an immutable key."""

    version = models.ForeignKey(SalahCourseVersion, on_delete=models.CASCADE, related_name="media")
    key = models.SlugField(max_length=96)
    object_key = models.CharField(max_length=512, validators=[validate_relative_object_key])
    content_type = models.CharField(max_length=64)
    width = models.PositiveSmallIntegerField(null=True, blank=True)
    height = models.PositiveSmallIntegerField(null=True, blank=True)
    bytes = models.PositiveIntegerField()
    sha256 = models.CharField(max_length=64, validators=[validate_sha256])

    class Meta:
        ordering = ["version", "key"]
        constraints = [
            models.UniqueConstraint(fields=["version", "key"], name="salah_media_unique"),
        ]

    def __str__(self) -> str:
        return f"{self.version}:{self.key}"
