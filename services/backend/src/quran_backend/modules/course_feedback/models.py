# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Anonymous course statistics and ratings (docs/courses/README.md, «Отзывы и статистика»).

Only daily sums are counted, as for announcements: no person, device, address
or cookie. A rating keeps a keyed digest of the voter and the course instead of
the voter, so one installation or account rates a course once and nobody can
tell from the table who rated what.
"""

from __future__ import annotations

from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from quran_backend.modules.announcements.models import PLATFORMS
from quran_backend.modules.core.models import BaseModel
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    BuiltInCourse,
    Course,
    LearnerProgressKind,
)

MAX_COMMENT_CHARS = 1000
# The Names of Allah stay a section of their own for readers, yet count like the
# prayer and the tajweed course: a name is a lesson (docs/names-of-allah/README.md).
NAMES = LearnerProgressKind.NAMES.value
BUILTIN_STATS = {**dict(BuiltInCourse.choices), NAMES: str(LearnerProgressKind.NAMES.label)}


class CourseStatEvent(models.TextChoices):
    LESSON_OPENED = "lesson_opened", "Открыли тему"
    VIDEO_STARTED = "video_started", "Начали видео"
    VIDEO_FINISHED = "video_finished", "Досмотрели видео"
    LESSON_COMPLETED = "lesson_completed", "Отметили изученной"
    LESSON_HELPFUL = "lesson_helpful", "Полезно"
    LESSON_NOT_HELPFUL = "lesson_not_helpful", "Не очень"
    # Of the Names of Allah only: the section itself, without a lesson.
    SECTION_OPENED = "section_opened", "Открыли раздел"


class CourseDailyStat(models.Model):
    """Daily sums only: no person, device, address or cookie is ever stored."""

    date = models.DateField()
    # A course of the catalog, or one of the built-in courses: exactly one of the two.
    course = models.ForeignKey(
        Course, on_delete=models.CASCADE, related_name="daily_stats", null=True, blank=True
    )
    builtin = models.CharField(
        max_length=16, choices=list(BUILTIN_STATS.items()), blank=True, default=""
    )
    # The slug, not a key: a lesson removed from the course keeps its history.
    # Empty for «Открыли раздел».
    lesson = models.SlugField(max_length=64, blank=True)
    platform = models.CharField(max_length=8, choices=[(code, code) for code in PLATFORMS])
    event = models.CharField(max_length=20, choices=CourseStatEvent)
    count = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "course_daily_stat"
        constraints = [
            models.UniqueConstraint(
                fields=("date", "course", "lesson", "platform", "event"),
                name="course_daily_stat_unique",
            ),
            models.UniqueConstraint(
                fields=("date", "builtin", "lesson", "platform", "event"),
                condition=models.Q(course__isnull=True),
                name="course_daily_stat_builtin_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(course__isnull=False, builtin="")
                | (models.Q(course__isnull=True) & ~models.Q(builtin="")),
                name="course_daily_stat_one_course",
            ),
        ]
        indexes = [models.Index(fields=("course", "date"), name="course_daily_stat_course_idx")]

    def __str__(self) -> str:
        return f"{self.date} {self.lesson} {self.platform} {self.event}: {self.count}"


class CourseRating(BaseModel):
    """One rating per installation or account and course; a new one replaces it."""

    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name="ratings")
    # HMAC of the voter and the course: not reversible, different for every course.
    voter_digest = models.CharField(max_length=64)
    stars = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True, max_length=MAX_COMMENT_CHARS)
    language = models.CharField(max_length=2, choices=[(code, code) for code in COURSE_LANGUAGES])
    platform = models.CharField(max_length=8, choices=[(code, code) for code in PLATFORMS])
    release_number = models.PositiveIntegerField()

    class Meta:
        db_table = "course_rating"
        ordering = ("-updated_at",)
        constraints = [
            models.UniqueConstraint(
                fields=("course", "voter_digest"), name="course_rating_one_per_voter"
            ),
            models.CheckConstraint(
                condition=models.Q(stars__gte=1, stars__lte=5), name="course_rating_stars_range"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.course} · {self.stars}★"


class CourseAnalytics(Course):
    """The admin pages «Курсы: сводка» and «Аналитика» of one course."""

    class Meta:
        proxy = True
        verbose_name = "аналитика курса"
        verbose_name_plural = "Курсы: сводка"
