# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Thematic courses: lessons with notes (and, from stage 2, videos) written in the admin.

The owner edits a course freely; students see its published release, an
immutable snapshot with a compiled document per language, until a newer
release is signed and published (docs/courses/plan.md, 6.2 and 6.4).
"""

from __future__ import annotations

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxLengthValidator
from django.db import models

from quran_backend.modules.audio.validators import validate_relative_object_key, validate_sha256
from quran_backend.modules.core.models import BaseModel

# The order of the 400 message: «Поддерживаются: ar, en, ru, tr.»
COURSE_LANGUAGES = ("ar", "en", "ru", "tr")
RESERVED_SLUGS = frozenset({"salah", "tajweed", "quiz", "courses", "new", "preview", "events"})
MAX_NOTES_CHARS = 20_000
MAX_SOURCES_CHARS = 2_000


def validate_course_slug(value: str) -> None:
    if value in RESERVED_SLUGS:
        raise ValidationError(
            f"Адрес «{value}» занят разделом сайта. Выберите другой, например «{value}-kurs»."
        )


class Course(BaseModel):
    slug = models.SlugField(max_length=64, unique=True, validators=[validate_course_slug])
    position = models.PositiveSmallIntegerField(
        default=100, help_text="Меньшее число выводится в каталоге раньше."
    )
    title_ru = models.CharField(max_length=120, blank=True)
    title_en = models.CharField(max_length=120, blank=True)
    title_ar = models.CharField(max_length=120, blank=True)
    title_tr = models.CharField(max_length=120, blank=True)
    summary_ru = models.CharField(max_length=400, blank=True)
    summary_en = models.CharField(max_length=400, blank=True)
    summary_ar = models.CharField(max_length=400, blank=True)
    summary_tr = models.CharField(max_length=400, blank=True)
    source_ru = models.CharField(max_length=300, blank=True)
    source_en = models.CharField(max_length=300, blank=True)
    source_ar = models.CharField(max_length=300, blank=True)
    source_tr = models.CharField(max_length=300, blank=True)
    cover_object_key = models.CharField(
        max_length=512, blank=True, editable=False, validators=[validate_relative_object_key]
    )
    cover_thumb_object_key = models.CharField(
        max_length=512, blank=True, editable=False, validators=[validate_relative_object_key]
    )
    cover_width = models.PositiveSmallIntegerField(null=True, blank=True, editable=False)
    cover_height = models.PositiveSmallIntegerField(null=True, blank=True, editable=False)
    live_release = models.ForeignKey(
        "CourseRelease",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
        editable=False,
    )
    hidden_at = models.DateTimeField(null=True, blank=True, editable=False)
    hidden_reason = models.CharField(max_length=300, blank=True, editable=False)
    # Raised by every save: a form opened before another save is refused.
    revision = models.PositiveIntegerField(default=1)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
        editable=False,
    )

    class Meta:
        db_table = "course"
        ordering = ("position", "title_ru")
        permissions = [
            ("sign_course", "Может подписывать религиозную проверку курсов"),
            ("publish_course", "Может публиковать, скрывать и откатывать курсы"),
        ]

    def __str__(self) -> str:
        return self.title_ru or self.slug

    def text(self, field: str, language: str) -> str:
        return str(getattr(self, f"{field}_{language}"))


class CourseLesson(BaseModel):
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="lessons")
    slug = models.SlugField(max_length=64)
    # Not unique: two lessons with one number keep the order they were added in.
    position = models.PositiveSmallIntegerField(
        default=0, blank=True, help_text="Пусто — в конец курса."
    )
    minutes = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        help_text="Пусто — посчитается само: видео плюс конспект из расчёта 180 слов в минуту.",
    )
    # Set by the video block of the lesson page, never by the form. RESTRICT, not PROTECT:
    # deleting the course deletes its lessons and videos together.
    video = models.ForeignKey(
        "CourseVideo",
        null=True,
        blank=True,
        on_delete=models.RESTRICT,
        related_name="+",
        editable=False,
    )
    # Video, slides and banners in the author's order (courses/lesson_media.py), set by the
    # media block of the lesson page. A list without the video's place shows it first.
    media = models.JSONField(default=list, blank=True, editable=False)
    title_ru = models.CharField(max_length=120, blank=True)
    title_en = models.CharField(max_length=120, blank=True)
    title_ar = models.CharField(max_length=120, blank=True)
    title_tr = models.CharField(max_length=120, blank=True)
    summary_ru = models.CharField(max_length=300, blank=True)
    summary_en = models.CharField(max_length=300, blank=True)
    summary_ar = models.CharField(max_length=300, blank=True)
    summary_tr = models.CharField(max_length=300, blank=True)
    notes_ru = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_NOTES_CHARS)])
    notes_en = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_NOTES_CHARS)])
    notes_ar = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_NOTES_CHARS)])
    notes_tr = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_NOTES_CHARS)])
    sources_ru = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_SOURCES_CHARS)])
    sources_en = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_SOURCES_CHARS)])
    sources_ar = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_SOURCES_CHARS)])
    sources_tr = models.TextField(blank=True, validators=[MaxLengthValidator(MAX_SOURCES_CHARS)])
    revision = models.PositiveIntegerField(default=1)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
        editable=False,
    )

    class Meta:
        db_table = "course_lesson"
        ordering = ("position", "created_at")
        constraints = [
            models.UniqueConstraint(fields=("course", "slug"), name="course_lesson_unique_slug"),
        ]

    def __str__(self) -> str:
        return self.title_ru or self.slug

    def save(self, *args: object, **kwargs: object) -> None:
        if not self.position:
            last = CourseLesson.objects.filter(course_id=self.course_id).aggregate(
                last=models.Max("position")
            )["last"]
            self.position = (last or 0) + 1
        super().save(*args, **kwargs)  # type: ignore[arg-type]

    def text(self, field: str, language: str) -> str:
        return str(getattr(self, f"{field}_{language}"))


SPOKEN_LANGUAGES = [
    ("ru", "русский"),
    ("en", "английский"),
    ("ar", "арабский"),
    ("tr", "турецкий"),
    ("", "без речи"),
]


class CourseVideo(BaseModel):
    """A lesson video as stored in R2: the file never changes after the upload.

    A row is deleted only while no release of the course mentions it; objects in
    R2 are never deleted automatically (ADR 0001).
    """

    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="videos")
    object_key = models.CharField(max_length=512, validators=[validate_relative_object_key])
    sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    bytes = models.PositiveBigIntegerField()
    duration_ms = models.PositiveIntegerField()
    width = models.PositiveSmallIntegerField()
    height = models.PositiveSmallIntegerField()
    fps = models.FloatField()
    bitrate_kbps = models.PositiveIntegerField()
    video_codec = models.CharField(max_length=16)
    audio_codec = models.CharField(max_length=16, blank=True)
    has_audio = models.BooleanField()
    spoken_language = models.CharField(
        max_length=2, blank=True, default="ru", choices=SPOKEN_LANGUAGES
    )
    poster_object_key = models.CharField(max_length=512, validators=[validate_relative_object_key])
    poster_small_object_key = models.CharField(
        max_length=512, validators=[validate_relative_object_key]
    )
    poster_width = models.PositiveSmallIntegerField()
    poster_height = models.PositiveSmallIntegerField()
    original_name = models.CharField(max_length=255, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        db_table = "course_video"
        ordering = ("course", "-created_at")
        constraints = [
            # The same file uploaded again reuses its row.
            models.UniqueConstraint(fields=("course", "sha256"), name="course_video_unique_file"),
        ]

    def __str__(self) -> str:
        return self.original_name or self.object_key


class CourseVideoDub(BaseModel):
    """The whole sound of the video on another language, joined with its picture.

    One current dub per language; a replaced or deleted dub that went into a
    release stays as a row with `retired_at`, like a video of an old release.
    """

    video = models.ForeignKey(CourseVideo, on_delete=models.CASCADE, related_name="dubs")
    language = models.CharField(max_length=2, choices=SPOKEN_LANGUAGES[:4])
    # The audio file the author uploaded.
    audio_original_name = models.CharField(max_length=255, blank=True)
    audio_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    audio_bytes = models.PositiveBigIntegerField()
    audio_codec = models.CharField(max_length=16)
    audio_duration_ms = models.PositiveIntegerField()
    # The MP4 students get: the video's picture with this sound.
    object_key = models.CharField(max_length=512, validators=[validate_relative_object_key])
    sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    bytes = models.PositiveBigIntegerField()
    duration_ms = models.PositiveIntegerField()
    retired_at = models.DateTimeField(null=True, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        db_table = "course_video_dub"
        ordering = ("video", "language", "-created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("video", "language"),
                condition=models.Q(retired_at__isnull=True),
                name="course_video_dub_one_per_language",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.video} · {self.language}"


class CourseReleaseStatus(models.TextChoices):
    IN_REVIEW = "in_review", "На проверке"
    RETURNED = "returned", "Возвращён"
    SIGNED = "signed", "Подписан"
    PUBLISHED = "published", "На сайте"
    SUPERSEDED = "superseded", "Заменён"
    WITHDRAWN = "withdrawn", "Отозван как ошибочный"


class CourseRelease(BaseModel):
    """An immutable release; the admin only shows it and runs its review actions."""

    course = models.ForeignKey(Course, on_delete=models.PROTECT, related_name="releases")
    number = models.PositiveIntegerField()
    status = models.CharField(
        max_length=16, choices=CourseReleaseStatus.choices, default=CourseReleaseStatus.IN_REVIEW
    )
    # The release on the site when this one was prepared: what the reviewer compares with.
    based_on = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    # A JSON list, not ArrayField: tests run on SQLite.
    languages = models.JSONField(default=list)
    snapshot = models.JSONField(default=dict)
    checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    change_note = models.CharField(max_length=500)
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+"
    )
    submitted_at = models.DateTimeField()
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.TextField(blank=True, validators=[MaxLengthValidator(2000)])
    # SHA-256 of the videos the reviewer marked as watched (stage 2).
    watched_videos = models.JSONField(default=list, blank=True)
    published_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
    )
    published_at = models.DateTimeField(null=True, blank=True)
    ended_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )
    ended_at = models.DateTimeField(null=True, blank=True)
    end_reason = models.CharField(max_length=300, blank=True)

    class Meta:
        db_table = "course_release"
        ordering = ("course", "-number")
        constraints = [
            models.UniqueConstraint(
                fields=("course", "number"), name="course_release_unique_number"
            ),
            models.UniqueConstraint(
                fields=("course",),
                condition=models.Q(status=CourseReleaseStatus.IN_REVIEW),
                name="course_release_one_in_review",
            ),
            models.CheckConstraint(
                condition=~models.Q(
                    status__in=(
                        CourseReleaseStatus.SIGNED,
                        CourseReleaseStatus.PUBLISHED,
                        CourseReleaseStatus.SUPERSEDED,
                    )
                )
                | models.Q(reviewed_by__isnull=False, reviewed_at__isnull=False),
                name="course_release_signed_has_reviewer",
            ),
            models.CheckConstraint(
                condition=~models.Q(
                    status__in=(CourseReleaseStatus.PUBLISHED, CourseReleaseStatus.SUPERSEDED)
                )
                | models.Q(published_at__isnull=False),
                name="course_release_published_has_date",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.course} · выпуск {self.number}"

    @property
    def version(self) -> str:
        return str(self.number)


class CourseDocument(BaseModel):
    """What clients get on one language, built when the release is prepared.

    `published_at` and `checksum_sha256` of the course are added on the way out:
    the release is published after its documents are built.
    """

    release = models.ForeignKey(CourseRelease, on_delete=models.CASCADE, related_name="documents")
    language = models.CharField(max_length=2, choices=[(code, code) for code in COURSE_LANGUAGES])
    payload = models.JSONField()
    # The catalog entry of the course on this language, so the list skips the lessons.
    card = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    bytes = models.PositiveIntegerField()

    class Meta:
        db_table = "course_document"
        ordering = ("release", "language")
        constraints = [
            models.UniqueConstraint(
                fields=("release", "language"), name="course_document_unique_language"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.release} · {self.language}"
