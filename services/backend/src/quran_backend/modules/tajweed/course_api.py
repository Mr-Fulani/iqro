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
