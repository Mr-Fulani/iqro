"""Public read-only API of the prayer-learning course, shared by the app and the site.

The course document is compiled at publication and stored per language, so a
request is one indexed row read; ETag/304 come from PublicReadOnlyViewMixin.
"""

from __future__ import annotations

from typing import Any

from django.db.models import F, QuerySet
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import serializers
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.offline_packages import (
    OFFLINE_PACKAGE_SCHEMA_VERSION,
    offline_package_checksum,
)
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCompiledDocument,
    SalahCourse,
    SalahPublicationStatus,
)

LANGUAGE_PARAMETER = OpenApiParameter(
    "language", str, enum=list(SALAH_LANGUAGES), default="ru", description="Язык документа."
)


class SalahCourseSummarySerializer(serializers.Serializer[Any]):
    slug = serializers.SlugField()
    version = serializers.CharField()
    methodology = serializers.CharField()
    languages = serializers.ListField(child=serializers.CharField())
    published_at = serializers.DateTimeField()


def _language(request: Request) -> str:
    language = request.query_params.get("language", "ru")
    if language not in SALAH_LANGUAGES:
        raise ValidationError({"language": f"Поддерживаются: {', '.join(SALAH_LANGUAGES)}."})
    return language


def _published_documents() -> QuerySet[SalahCompiledDocument]:
    return SalahCompiledDocument.objects.filter(
        version__status=SalahPublicationStatus.PUBLISHED,
        version__course__active_version=F("version"),
    )


def _document(slug: str, language: str) -> SalahCompiledDocument:
    document = _published_documents().filter(version__course__slug=slug, language=language).first()
    if document is None:
        raise NotFound("Такого курса нет.")
    return document


class SalahCourseListView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(responses=SalahCourseSummarySerializer(many=True))
    def get(self, _request: Request) -> Response:
        courses = (
            SalahCourse.objects.filter(active_version__status=SalahPublicationStatus.PUBLISHED)
            .select_related("active_version")
            .order_by("slug")
        )
        return Response(
            [
                {
                    "slug": course.slug,
                    "version": course.active_version.version,
                    "methodology": course.active_version.methodology,
                    "languages": list(SALAH_LANGUAGES),
                    "published_at": course.active_version.published_at,
                }
                for course in courses
                if course.active_version is not None
            ]
        )


class SalahCourseDocumentView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        parameters=[LANGUAGE_PARAMETER],
        responses=OpenApiTypes.OBJECT,
        description="Скомпилированный документ курса (docs/salah/learning-spec.md §6).",
    )
    def get(self, request: Request, slug: str) -> Response:
        return Response(_document(slug, _language(request)).payload)


class SalahOfflineManifestView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(parameters=[LANGUAGE_PARAMETER], responses=OpenApiTypes.OBJECT)
    def get(self, request: Request, slug: str) -> Response:
        language = _language(request)
        document = _document(slug, language)
        course = document.payload["course"]
        images = [
            (key, media)
            for key, media in sorted(document.payload.get("media", {}).items())
            if str(media.get("url", "")).endswith(".webp")
        ]
        checksum_payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "salah_course",
            "package_id": f"{slug}:{language}",
            "version": course["version"],
            "source_checksum_sha256": document.checksum_sha256,
            "items": [
                {"key": key, "sha256": media["sha256"], "bytes": media["bytes"]}
                for key, media in images
            ],
        }
        return Response(
            {
                **checksum_payload,
                "package_checksum_sha256": offline_package_checksum(checksum_payload),
                "published_at": course["published_at"],
                "total_bytes": sum(media["bytes"] for _, media in images),
                "items": [
                    {
                        "key": key,
                        "asset": {
                            "url": media["url"],
                            "file_name": media["url"].rsplit("/", 1)[-1],
                            "content_type": "image/webp",
                            "bytes": media["bytes"],
                            "sha256": media["sha256"],
                        },
                    }
                    for key, media in images
                ],
            }
        )
