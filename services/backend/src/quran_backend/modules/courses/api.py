# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Public read-only API of thematic courses (docs/courses/README.md, «API»).

A course is visible on a language only while it is not hidden and its live
release has a document on that language. ETag/304 and public caching come from
PublicReadOnlyViewMixin.
"""

from __future__ import annotations

from typing import Any

from django.db.models import F, QuerySet
from drf_spectacular.utils import OpenApiParameter, OpenApiResponse, extend_schema
from rest_framework import serializers
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.courses.document import cover_payload
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    BuiltInCourse,
    BuiltInCourseCover,
    CourseDocument,
    CourseReleaseStatus,
)

LANGUAGE_PARAMETER = OpenApiParameter(
    "language",
    str,
    enum=list(COURSE_LANGUAGES),
    default="ru",
    description="Язык ответа.",
)
NOT_FOUND = "Такого курса нет."
BAD_LANGUAGE = OpenApiResponse(description="Неизвестный язык: field_errors.language.")


class CourseCoverSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    thumb_url = serializers.URLField()
    width = serializers.IntegerField()
    height = serializers.IntegerField()


class CourseCardSerializer(serializers.Serializer[Any]):
    slug = serializers.SlugField()
    version = serializers.CharField()
    title = serializers.CharField()
    summary = serializers.CharField()
    source = serializers.CharField(allow_blank=True)  # type: ignore[assignment]
    cover = CourseCoverSerializer(allow_null=True)
    lesson_count = serializers.IntegerField()
    minutes = serializers.IntegerField()
    video_minutes = serializers.IntegerField()
    published_at = serializers.DateTimeField()


class BuiltInCourseCardSerializer(serializers.Serializer[Any]):
    cover = CourseCoverSerializer(allow_null=True)


class BuiltInCoursesSerializer(serializers.Serializer[Any]):
    """The prayer and tajweed cards of the catalog; their texts are the clients' own."""

    salah = BuiltInCourseCardSerializer()
    tajweed = BuiltInCourseCardSerializer()


class CourseListSerializer(serializers.Serializer[Any]):
    language = serializers.ChoiceField(choices=COURSE_LANGUAGES)
    courses = CourseCardSerializer(many=True)
    built_in = BuiltInCoursesSerializer()


class CourseSegmentSerializer(serializers.Serializer[Any]):
    text = serializers.CharField()
    bold = serializers.BooleanField(required=False)
    lang = serializers.ChoiceField(choices=["ar"], required=False)


class CourseNoteBlockSerializer(serializers.Serializer[Any]):
    """One block of a lesson's notes; which keys it has depends on `type`."""

    type = serializers.ChoiceField(choices=["heading", "paragraph", "list", "quote", "note"])
    dir = serializers.ChoiceField(choices=["ltr", "rtl"])
    text = CourseSegmentSerializer(many=True, required=False, help_text="heading")
    lines = serializers.ListField(
        child=CourseSegmentSerializer(many=True),
        required=False,
        help_text="paragraph, quote, note",
    )
    ordered = serializers.BooleanField(required=False, help_text="list")
    items = serializers.ListField(
        child=CourseSegmentSerializer(many=True), required=False, help_text="list"
    )
    source = serializers.CharField(required=False, allow_null=True, help_text="quote")  # type: ignore[assignment]


class CourseVideoPosterSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    small_url = serializers.URLField()
    width = serializers.IntegerField()
    height = serializers.IntegerField()


class CourseVideoSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    bytes = serializers.IntegerField()
    duration_ms = serializers.IntegerField()
    width = serializers.IntegerField()
    height = serializers.IntegerField()
    spoken_language = serializers.CharField(allow_blank=True)
    poster = CourseVideoPosterSerializer()


class CourseMediaImageSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    small_url = serializers.URLField()
    width = serializers.IntegerField()
    height = serializers.IntegerField()


class CourseSlideSerializer(serializers.Serializer[Any]):
    image = CourseMediaImageSerializer()
    caption = serializers.CharField(allow_blank=True)
    alt = serializers.CharField(allow_blank=True)
    dir = serializers.ChoiceField(choices=["ltr", "rtl"])


class CourseMediaBlockSerializer(serializers.Serializer[Any]):
    """One media block above the notes; which keys it has depends on `type`."""

    type = serializers.ChoiceField(choices=["video", "slides", "banner"])
    video = CourseVideoSerializer(required=False, help_text="video")
    slides = CourseSlideSerializer(many=True, required=False, help_text="slides")
    image = CourseMediaImageSerializer(required=False, help_text="banner")
    caption = serializers.CharField(required=False, allow_blank=True, help_text="banner")
    alt = serializers.CharField(required=False, allow_blank=True, help_text="banner")
    dir = serializers.ChoiceField(choices=["ltr", "rtl"], required=False, help_text="banner")


class CourseLessonSerializer(serializers.Serializer[Any]):
    slug = serializers.SlugField()
    number = serializers.IntegerField(min_value=1)
    title = serializers.CharField()
    summary = serializers.CharField(allow_blank=True)
    minutes = serializers.IntegerField()
    video = CourseVideoSerializer(allow_null=True, help_text="Видео из media, для старых клиентов.")
    media = CourseMediaBlockSerializer(
        many=True, required=False, help_text="Нет в выпусках, подготовленных до медиа."
    )
    notes = CourseNoteBlockSerializer(many=True)
    sources = serializers.ListField(child=serializers.CharField())


class CourseHeaderSerializer(serializers.Serializer[Any]):
    slug = serializers.SlugField()
    version = serializers.CharField()
    language = serializers.ChoiceField(choices=COURSE_LANGUAGES)
    languages = serializers.ListField(child=serializers.ChoiceField(choices=COURSE_LANGUAGES))
    title = serializers.CharField()
    summary = serializers.CharField()
    source = serializers.CharField(allow_blank=True)  # type: ignore[assignment]
    cover = CourseCoverSerializer(allow_null=True)
    published_at = serializers.DateTimeField()
    checksum_sha256 = serializers.CharField()


class CourseDocumentSerializer(serializers.Serializer[Any]):
    schema_version = serializers.IntegerField()
    course = CourseHeaderSerializer()
    lessons = CourseLessonSerializer(many=True)


def course_language(request: Request) -> str:
    language = request.query_params.get("language", "ru")
    if language not in COURSE_LANGUAGES:
        raise ValidationError({"language": [f"Поддерживаются: {', '.join(COURSE_LANGUAGES)}."]})
    return language


def visible_documents(language: str) -> QuerySet[CourseDocument]:
    return CourseDocument.objects.filter(
        language=language,
        release__status=CourseReleaseStatus.PUBLISHED,
        release__course__live_release=F("release"),
        release__course__hidden_at__isnull=True,
    ).select_related("release", "release__course")


def built_in_courses() -> dict[str, dict[str, Any]]:
    covers = {row.course: row for row in BuiltInCourseCover.objects.all()}
    cards: dict[str, dict[str, Any]] = {}
    for course in BuiltInCourse.values:
        row = covers.get(course)
        cover = None
        if row is not None and row.cover_object_key:
            cover = {
                "object_key": row.cover_object_key,
                "thumb_object_key": row.cover_thumb_object_key,
                "width": row.cover_width,
                "height": row.cover_height,
            }
        cards[course] = {"cover": cover_payload(cover)}
    return cards


def _published_at(document: CourseDocument) -> str:
    published_at = document.release.published_at
    assert published_at is not None  # a published release always has the date
    return published_at.isoformat()


class CourseListView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["courses"],
        operation_id="courses_list",
        parameters=[LANGUAGE_PARAMETER],
        responses={200: CourseListSerializer, 400: BAD_LANGUAGE},
        description=(
            "Видимые курсы с выпуском на этом языке, по порядку каталога, "
            "и обложки карточек «Обучение намазу» и «Таджвид»."
        ),
    )
    def get(self, request: Request) -> Response:
        language = course_language(request)
        documents = sorted(
            visible_documents(language).defer("payload"),
            key=lambda document: (document.release.course.position, document.card["title"]),
        )
        return Response(
            {
                "language": language,
                "courses": [
                    {**document.card, "published_at": _published_at(document)}
                    for document in documents
                ],
                "built_in": built_in_courses(),
            }
        )


class CourseDocumentView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["courses"],
        operation_id="courses_document",
        parameters=[LANGUAGE_PARAMETER],
        responses={
            200: CourseDocumentSerializer,
            400: BAD_LANGUAGE,
            404: OpenApiResponse(
                description=f"«{NOT_FOUND}» Курса нет, он скрыт или нет выпуска на этом языке."
            ),
        },
        description="Документ опубликованного выпуска курса на этом языке.",
    )
    def get(self, request: Request, slug: str) -> Response:
        language = course_language(request)
        document = visible_documents(language).filter(release__course__slug=slug).first()
        if document is None:
            raise NotFound(NOT_FOUND)
        payload = document.payload
        return Response(
            {
                **payload,
                "course": {
                    **payload["course"],
                    "published_at": _published_at(document),
                    "checksum_sha256": document.checksum_sha256,
                },
            }
        )
