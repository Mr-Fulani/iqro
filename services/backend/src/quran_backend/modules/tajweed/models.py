from __future__ import annotations

from typing import Any

from django.conf import settings
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


# The tajweed course (docs/tajweed/course.md): versioned like the prayer course.
# A version is imported from a snapshot in git or copied into a draft in the
# admin, edited there, signed off by the owner and published; published
# versions never change.
TAJWEED_COURSE_LANGUAGES = tuple(code for code, _name in settings.LANGUAGES)


class TajweedCourseStatus(models.TextChoices):
    DRAFT = "draft", "Черновик"
    PUBLISHED = "published", "Опубликована"
    WITHDRAWN = "withdrawn", "Отозвана"


class TajweedCourse(BaseModel):
    slug = models.SlugField(max_length=64, unique=True)
    active_version = models.ForeignKey(
        "TajweedCourseVersion",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )

    class Meta:
        db_table = "tajweed_course"
        ordering = ["slug"]

    def __str__(self) -> str:
        return self.slug

    def clean(self) -> None:
        super().clean()
        version = self.active_version if self.active_version_id else None
        if version and version.course_id != self.id:
            raise ValidationError({"active_version": "Версия принадлежит другому курсу."})
        if version and version.status != TajweedCourseStatus.PUBLISHED:
            raise ValidationError(
                {"active_version": "Активной может быть только опубликованная версия."}
            )


class TajweedCourseVersion(BaseModel):
    course = models.ForeignKey(TajweedCourse, on_delete=models.PROTECT, related_name="versions")
    version = models.CharField(max_length=64)
    schema_version = models.PositiveSmallIntegerField()
    snapshot = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64)
    status = models.CharField(
        max_length=16,
        choices=TajweedCourseStatus,
        default=TajweedCourseStatus.DRAFT,
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
    # SHA-256 of the new lesson videos and dubs the owner marked as watched before signing.
    watched_videos = models.JSONField(default=list, blank=True)

    class Meta:
        db_table = "tajweed_course_version"
        ordering = ["course", "-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["course", "version"], name="tajweed_course_version_unique"
            ),
            models.CheckConstraint(
                condition=~models.Q(status=TajweedCourseStatus.PUBLISHED)
                | (models.Q(published_at__isnull=False) & models.Q(reviewed_by__isnull=False)),
                name="tajweed_course_published_is_signed",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.course.slug}@{self.version}"

    @property
    def is_signed(self) -> bool:
        return self.reviewed_by_id is not None and self.reviewed_at is not None

    def sign(self, user: Any, note: str = "") -> None:
        """Records the owner's sign-off; only drafts can be signed."""
        if self.status != TajweedCourseStatus.DRAFT:
            raise ValidationError("Подписать можно только черновик.")
        self.reviewed_by = user
        self.reviewed_at = timezone.now()
        self.review_note = note
        self.save(update_fields=["reviewed_by", "reviewed_at", "review_note", "updated_at"])


class TajweedCourseDocument(BaseModel):
    """The ready-to-serve course document for one language."""

    version = models.ForeignKey(
        TajweedCourseVersion, on_delete=models.CASCADE, related_name="documents"
    )
    language = models.CharField(max_length=8)
    payload = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64)
    bytes = models.PositiveIntegerField()

    class Meta:
        db_table = "tajweed_course_document"
        ordering = ["version", "language"]
        constraints = [
            models.UniqueConstraint(
                fields=["version", "language"], name="tajweed_course_document_unique"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.version}:{self.language}"


class TajweedCourseProgress(BaseModel):
    """A learner's lessons of one course, in the clients' local format.

    Writes are merged lesson by lesson (`progress.merge_progress`), so a phone
    and a browser never overwrite each other's passed lessons.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tajweed_progress"
    )
    course = models.SlugField(max_length=64)
    lessons = models.JSONField(default=dict)

    class Meta:
        db_table = "tajweed_course_progress"
        ordering = ["user", "course"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "course"], name="tajweed_course_progress_unique"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.user_id}:{self.course}"


class TajweedPracticeSession(BaseModel):
    """One finished practice session: the answers, as the client sent them.

    The id comes from the client, so a session sent twice is stored once. The
    score, streak and review list are computed from all sessions
    (`practice.practice_state`), never stored.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tajweed_practice"
    )
    course = models.SlugField(max_length=64)
    local_date = models.DateField()
    finished_at = models.DateTimeField()
    answers = models.JSONField(default=list)

    class Meta:
        db_table = "tajweed_practice_session"
        ordering = ["user", "finished_at"]
        indexes = [
            models.Index(fields=["user", "course"], name="tajweed_practice_user_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.user_id}:{self.course}:{self.local_date}"
