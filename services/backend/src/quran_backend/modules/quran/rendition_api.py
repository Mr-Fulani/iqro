from __future__ import annotations

from typing import Any

from django.conf import settings
from django.db.models import F, Q, QuerySet, Subquery
from django.db.models.fields.json import KeyTextTransform
from django.shortcuts import get_object_or_404
from django.urls import reverse
from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.offline_packages import offline_package_checksum
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.quran.models import (
    MushafRenditionPage,
    MushafRenditionRelease,
    PublicationStatus,
    QuranFoundationMushaf,
)
from quran_backend.modules.quran.serializers import (
    MushafPageSerializer,
    OfflineMushafManifestSerializer,
)


def visible_releases() -> QuerySet[MushafRenditionRelease]:
    releases = MushafRenditionRelease.objects.filter(
        id=F("rendition__active_release_id"),
        canonical_version_id=F("canonical_version__edition__active_version_id"),
        canonical_version__status=PublicationStatus.PUBLISHED,
        published_at__isnull=False,
    ).select_related("rendition", "canonical_version__edition")
    # QF content corrections invalidate old derived pages, never silently mix
    # new words with old pixels/hit regions. Legacy JMApps releases remain valid.
    current_qf_sources = QuranFoundationMushaf.objects.filter(
        environment=settings.QURAN_QF_ENV, is_available=True
    )
    source_filter = Q(source_metadata={})
    for source_id in (5, 19):
        source_filter |= Q(
            source_metadata__kind="quran-foundation",
            source_metadata__source_id=source_id,
            current_source_checksum__in=Subquery(
                current_qf_sources.filter(source_id=source_id).values("source_checksum_sha256")
            ),
        )
    releases = releases.alias(
        current_source_checksum=KeyTextTransform("source_checksum_sha256", "source_metadata")
    ).filter(source_filter)
    if not getattr(settings, "MUSHAF_STAGING_PREVIEWS", False):
        releases = releases.filter(staging_only=False)
    return releases


def page_payload(page: MushafRenditionPage, release: MushafRenditionRelease) -> dict[str, Any]:
    base = settings.PUBLIC_MEDIA_BASE_URL.rstrip("/")
    assets = [{**asset, "url": f"{base}/{asset['path']}"} for asset in page.assets]
    for asset in assets:
        asset.pop("path")
    return {
        "id": str(page.id),
        "edition_code": release.rendition.code,
        "canonical_edition_code": release.canonical_version.edition.code,
        "content_version": release.version,
        "number": page.number,
        "image_width": page.image_width,
        "image_height": page.image_height,
        "checksum_sha256": page.checksum_sha256,
        "assets": assets,
        "regions": page.regions,
    }


class MushafRenditionSerializer(serializers.Serializer[Any]):
    code = serializers.CharField()
    names = serializers.DictField(child=serializers.CharField())
    canonical_edition = serializers.CharField()
    version = serializers.CharField()
    checksum_sha256 = serializers.CharField()
    pages_count = serializers.IntegerField()
    widths = serializers.ListField(child=serializers.IntegerField())
    format = serializers.CharField()
    available = serializers.BooleanField()
    staging_only = serializers.BooleanField()
    source_url = serializers.URLField()


@extend_schema(tags=["quran"], responses=MushafRenditionSerializer(many=True))
class MushafRenditionListView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request) -> Response:  # noqa: ARG002
        return Response(
            [
                {
                    "code": release.rendition.code,
                    "names": release.rendition.names,
                    "canonical_edition": release.canonical_version.edition.code,
                    "version": release.version,
                    "checksum_sha256": release.checksum_sha256,
                    "pages_count": release.page_count,
                    "widths": release.widths,
                    "format": "raster-regions-v1",
                    "available": True,
                    "staging_only": release.staging_only,
                    "source_url": release.source_url,
                }
                for release in visible_releases().order_by("rendition__code")
            ]
        )


@extend_schema(tags=["quran"], responses=MushafPageSerializer)
class MushafRenditionPageView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request, code: str, page: int) -> Response:  # noqa: ARG002
        release = get_object_or_404(visible_releases(), rendition__code=code)
        item = get_object_or_404(MushafRenditionPage, release=release, number=page)
        return Response(page_payload(item, release))


@extend_schema(tags=["offline"], responses=OfflineMushafManifestSerializer)
class MushafRenditionOfflineView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request, code: str) -> Response:
        release = get_object_or_404(visible_releases(), rendition__code=code)
        try:
            width = int(request.query_params.get("width", max(release.widths)))
        except (TypeError, ValueError) as exc:
            raise ValidationError("Invalid width") from exc
        if width not in release.widths:
            raise NotFound("Requested width is not available")
        pages = list(release.pages.all())
        if [p.number for p in pages] != list(range(1, release.page_count + 1)):
            raise NotFound("Complete rendition unavailable")
        package_id = f"mushaf-rendition-{code}-{release.version}-w{width}"
        source_name = release.rendition.names.get("en", code)
        provider = "Quran.Foundation" if release.source_metadata else "JMApps"
        entries = []
        checksum_pages = []
        total = 0
        for page in pages:
            metadata = page_payload(page, release)
            candidates = [a for a in metadata["assets"] if a["width"] == width]
            if len(candidates) != 1:
                raise NotFound("Incomplete rendition assets")
            asset = {
                **candidates[0],
                "file_name": f"page-{page.number:03d}-{width}.webp",
                "content_type": "image/webp",
            }
            metadata["assets"] = [asset]
            entries.append(
                {
                    "number": page.number,
                    "asset": asset,
                    "metadata": metadata,
                    "metadata_url": request.build_absolute_uri(
                        reverse(
                            "quran:rendition-page",
                            kwargs={"code": code, "page": page.number},
                        )
                    ),
                }
            )
            checksum_pages.append(
                {
                    "number": page.number,
                    "metadata": {
                        **metadata,
                        "assets": [{k: v for k, v in asset.items() if k != "url"}],
                    },
                }
            )
            total += asset["bytes"]
        checksum = offline_package_checksum(
            {
                "schema_version": 1,
                "package_type": "mushaf_pages",
                "package_id": package_id,
                "version": release.version,
                "source_checksum_sha256": release.checksum_sha256,
                "pages": checksum_pages,
            }
        )
        return Response(
            {
                "schema_version": 1,
                "package_type": "mushaf_pages",
                "package_id": package_id,
                "version": release.version,
                "package_checksum_sha256": checksum,
                "publication_checksum_sha256": release.checksum_sha256,
                "published_at": release.published_at,
                "source": {
                    "name": f"{source_name} / {provider} · IQRO layout",
                    "url": release.source_url,
                    "checksum_sha256": release.checksum_sha256,
                },
                "rights": {
                    "offline_download": True,
                    "attribution_required": True,
                    "attribution": (
                        f"{source_name} / {provider} · IQRO layout"
                        + (" · Staging preview" if release.staging_only else "")
                    ),
                    "license_name": "",
                    "license_url": "",
                },
                "mushaf": {
                    "source_id": release.source_metadata.get("source_id"),
                    "edition_code": code,
                    "canonical_edition_code": release.canonical_version.edition.code,
                    "name": source_name,
                    "qirat_name": "Hafs",
                    "lines_per_page": 15,
                },
                "width": width,
                "page_count": len(entries),
                "total_bytes": total,
                "pages": entries,
            }
        )
