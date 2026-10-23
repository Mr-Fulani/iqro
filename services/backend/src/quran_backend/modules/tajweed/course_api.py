"""Public read-only API of the tajweed course, shared by the app and the site.

The course document is compiled at publication and stored per language;
examples are picked from the published tajweed markup on request. ETag/304 and
public caching come from PublicReadOnlyViewMixin.
"""

from __future__ import annotations

from typing import Any

from django.conf import settings
from django.db.models import F, QuerySet
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import serializers
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.tajweed.course_examples import (
    DEFAULT_LIMIT,
    MAX_LIMIT,
    MAX_OFFSET,
    lesson_examples,
)
from quran_backend.modules.tajweed.models import (
    TAJWEED_COURSE_LANGUAGES,
    AyahTajweed,
    TajweedCourse,
    TajweedCourseDocument,
    TajweedCourseStatus,
    TajweedCourseVersion,
)
from quran_backend.modules.tajweed.practice import (
    DEFAULT_TASKS,
    MAX_REVIEW,
    MAX_TASKS,
    practice_tasks,
)
from quran_backend.modules.tajweed.selectors import (
    published_tajweed_ayahs,
    published_tajweed_edition,
)

LANGUAGE_PARAMETER = OpenApiParameter(
    "language",
    str,
    enum=list(TAJWEED_COURSE_LANGUAGES),
    default="ru",
    description="Язык документа.",
)


class TajweedCourseSummarySerializer(serializers.Serializer[Any]):
    slug = serializers.SlugField()
    version = serializers.CharField()
    languages = serializers.ListField(child=serializers.CharField())
    published_at = serializers.DateTimeField()


class TajweedExamplesQuerySerializer(serializers.Serializer[Any]):
    offset = serializers.IntegerField(min_value=0, max_value=MAX_OFFSET, default=0)
    limit = serializers.IntegerField(min_value=1, max_value=MAX_LIMIT, default=DEFAULT_LIMIT)


class TajweedExamplePartSerializer(serializers.Serializer[Any]):
    position = serializers.IntegerField(min_value=1)
    start = serializers.IntegerField(min_value=0)
    end = serializers.IntegerField(min_value=1)


class TajweedExampleOccurrenceSerializer(serializers.Serializer[Any]):
    parts = TajweedExamplePartSerializer(many=True)
    variant = serializers.CharField(required=False)


class TajweedExampleWordSerializer(serializers.Serializer[Any]):
    position = serializers.IntegerField(min_value=1)
    text = serializers.CharField()


class TajweedExampleSerializer(serializers.Serializer[Any]):
    verse_key = serializers.CharField()
    surah_number = serializers.IntegerField()
    ayah_number = serializers.IntegerField()
    page_number = serializers.IntegerField()
    words = TajweedExampleWordSerializer(many=True)
    occurrences = TajweedExampleOccurrenceSerializer(many=True)


class TajweedExamplesResponseSerializer(serializers.Serializer[Any]):
    lesson = serializers.SlugField()
    target = serializers.CharField()
    offset = serializers.IntegerField()
    next_offset = serializers.IntegerField(allow_null=True)
    examples = TajweedExampleSerializer(many=True)


def course_language(request: Request) -> str:
    language = request.query_params.get("language", "ru")
    if language not in TAJWEED_COURSE_LANGUAGES:
        raise ValidationError(
            {"language": f"Поддерживаются: {', '.join(TAJWEED_COURSE_LANGUAGES)}."}
        )
    return language


def _published_documents() -> QuerySet[TajweedCourseDocument]:
    return TajweedCourseDocument.objects.filter(
        version__status=TajweedCourseStatus.PUBLISHED,
        version__course__active_version=F("version"),
    )


def published_course_version(slug: str) -> TajweedCourseVersion:
    course = (
        TajweedCourse.objects.filter(
            slug=slug, active_version__status=TajweedCourseStatus.PUBLISHED
        )
        .select_related("active_version")
        .first()
    )
    if course is None or course.active_version is None:
        raise NotFound("Такого курса нет.")
    return course.active_version


def published_course_ayahs() -> QuerySet[AyahTajweed]:
    edition = published_tajweed_edition(settings.QURAN_QF_ENV)
    if edition is None:
        raise NotFound("Разметка таджвида ещё не опубликована.")
    return published_tajweed_ayahs(edition)


class TajweedCourseListView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(tags=["tajweed"], responses=TajweedCourseSummarySerializer(many=True))
    def get(self, _request: Request) -> Response:
        courses = (
            TajweedCourse.objects.filter(active_version__status=TajweedCourseStatus.PUBLISHED)
            .select_related("active_version")
            .order_by("slug")
        )
        return Response(
            [
                {
                    "slug": course.slug,
                    "version": course.active_version.version,
                    "languages": list(TAJWEED_COURSE_LANGUAGES),
                    "published_at": course.active_version.published_at,
                }
                for course in courses
                if course.active_version is not None
            ]
        )


class TajweedCourseDocumentView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["tajweed"],
        parameters=[LANGUAGE_PARAMETER],
        responses=OpenApiTypes.OBJECT,
        description="Скомпилированный документ курса (docs/tajweed/course.md).",
    )
    def get(self, request: Request, slug: str) -> Response:
        document = (
            _published_documents()
            .filter(version__course__slug=slug, language=course_language(request))
            .first()
        )
        if document is None:
            raise NotFound("Такого курса нет.")
        return Response(document.payload)


class TajweedLessonExamplesView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["tajweed"],
        parameters=[TajweedExamplesQuerySerializer],
        responses=TajweedExamplesResponseSerializer,
        description="Примеры урока из разметки всего Корана, в постоянном порядке.",
    )
    def get(self, request: Request, slug: str, lesson: str) -> Response:
        query = TajweedExamplesQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        version = published_course_version(slug)
        source = next(
            (item for item in version.snapshot["lessons"] if item["slug"] == lesson), None
        )
        if source is None:
            raise NotFound("Такого урока нет.")
        page = lesson_examples(
            published_course_ayahs(),
            target=source["target"],
            preferred=source.get("examples", []),
            offset=query.validated_data["offset"],
            limit=query.validated_data["limit"],
        )
        return Response({"lesson": lesson, **page})


class TajweedPracticeQuerySerializer(serializers.Serializer[Any]):
    lessons = serializers.CharField(max_length=2000, help_text="Пройденные уроки через запятую.")
    count = serializers.IntegerField(min_value=1, max_value=MAX_TASKS, default=DEFAULT_TASKS)
    seed = serializers.IntegerField(min_value=0, max_value=2**31 - 1, default=0)
    review = serializers.CharField(
        max_length=2000,
        required=False,
        default="",
        allow_blank=True,
        help_text="Ключи заданий на повторение через запятую: type~verse_key~target.",
    )


class TajweedPracticeTaskSerializer(serializers.Serializer[Any]):
    key = serializers.CharField()
    type = serializers.ChoiceField(choices=["find", "identify", "listen"])
    target = serializers.CharField()
    review = serializers.BooleanField()
    example = TajweedExampleSerializer()
    focus = serializers.IntegerField(min_value=0)
    options = serializers.ListField(child=serializers.CharField(), required=False)


class TajweedPracticeResponseSerializer(serializers.Serializer[Any]):
    seed = serializers.IntegerField()
    tasks = TajweedPracticeTaskSerializer(many=True)


MAX_PRACTICE_LESSONS = 30


class TajweedPracticeView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["tajweed"],
        parameters=[TajweedPracticeQuerySerializer],
        responses=TajweedPracticeResponseSerializer,
        description="Задания практики по целям пройденных уроков (docs/tajweed/practice.md).",
    )
    def get(self, request: Request, slug: str) -> Response:
        query = TajweedPracticeQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        passed = set(query.validated_data["lessons"].split(",")[:MAX_PRACTICE_LESSONS])
        version = published_course_version(slug)
        targets = [
            lesson["target"]
            for section in version.snapshot["sections"]
            for lesson_slug in section["lessons"]
            for lesson in version.snapshot["lessons"]
            if lesson["slug"] == lesson_slug and lesson_slug in passed
        ]
        if not targets:
            raise ValidationError({"lessons": "Нет ни одного урока этого курса."})
        review = [key for key in query.validated_data["review"].split(",") if key][:MAX_REVIEW]
        seed = query.validated_data["seed"]
        tasks = practice_tasks(
            published_course_ayahs(),
            targets=targets,
            count=query.validated_data["count"],
            seed=seed,
            review=review,
        )
        return Response({"seed": seed, "tasks": tasks})
