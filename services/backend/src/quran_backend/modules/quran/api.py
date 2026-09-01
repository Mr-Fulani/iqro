from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from django.conf import settings
from django.db.models import QuerySet
from django.shortcuts import get_object_or_404
from django.urls import reverse
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics
from rest_framework.exceptions import NotFound
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.offline_packages import (
    OFFLINE_PACKAGE_SCHEMA_VERSION,
    offline_package_checksum,
)
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.quran.models import (
    Ayah,
    Hizb,
    Juz,
    MushafPage,
    QuranEdition,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationNativePageAsset,
    RubElHizb,
    Surah,
)
from quran_backend.modules.quran.quran_foundation_native import active_native_publication
from quran_backend.modules.quran.selectors import (
    public_quran_foundation_mushaf_pages,
    public_quran_foundation_mushafs,
    published_ayahs,
    published_editions,
    published_hizb,
    published_juz,
    published_pages,
    published_rub_el_hizb,
    published_surahs,
)
from quran_backend.modules.quran.serializers import (
    AyahSerializer,
    HizbSerializer,
    JuzSerializer,
    MushafPageSerializer,
    OfflineMushafManifestQuerySerializer,
    OfflineMushafManifestSerializer,
    QuranEditionSerializer,
    QuranFoundationMushafPageSerializer,
    QuranFoundationMushafSerializer,
    RubElHizbSerializer,
    SurahSerializer,
)


class PublicQuranViewMixin(PublicReadOnlyViewMixin):
    """Backward-compatible Quran-specific alias for the shared public API behavior."""


@extend_schema(tags=["quran"])
class QuranEditionListView(PublicQuranViewMixin, generics.ListAPIView[QuranEdition]):
    serializer_class = QuranEditionSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[QuranEdition]:
        return published_editions()


@extend_schema(tags=["quran"])
class QuranEditionDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[QuranEdition]):
    serializer_class = QuranEditionSerializer
    lookup_field = "code"
    lookup_url_kwarg = "edition"

    def get_queryset(self) -> QuerySet[QuranEdition]:
        return published_editions()


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class SurahListView(PublicQuranViewMixin, generics.ListAPIView[Surah]):
    serializer_class = SurahSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Surah]:
        return published_surahs(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class SurahDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[Surah]):
    serializer_class = SurahSerializer
    lookup_field = "number"
    lookup_url_kwarg = "surah"

    def get_queryset(self) -> QuerySet[Surah]:
        return published_surahs(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class AyahListView(PublicQuranViewMixin, generics.ListAPIView[Ayah]):
    serializer_class = AyahSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Ayah]:
        return published_ayahs(self.kwargs["edition"], self.kwargs["surah"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
        OpenApiParameter("ayah", int, OpenApiParameter.PATH),
    ],
)
class AyahDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[Ayah]):
    serializer_class = AyahSerializer
    lookup_field = "number"
    lookup_url_kwarg = "ayah"

    def get_queryset(self) -> QuerySet[Ayah]:
        return published_ayahs(self.kwargs["edition"], self.kwargs["surah"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("page", int, OpenApiParameter.PATH),
    ],
)
class MushafPageDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[MushafPage]):
    serializer_class = MushafPageSerializer
    lookup_field = "number"
    lookup_url_kwarg = "page"

    def get_queryset(self) -> QuerySet[MushafPage]:
        return published_pages(self.kwargs["edition"])


def _canonical_offline_asset(
    variants: object,
    *,
    width: int,
) -> dict[str, Any] | None:
    if not isinstance(variants, list):
        return None
    for raw_variant in variants:
        if not isinstance(raw_variant, Mapping) or raw_variant.get("width") != width:
            continue
        relative_path = str(raw_variant.get("path", "")).strip("/")
        checksum = str(raw_variant.get("sha256", ""))
        height = raw_variant.get("height")
        size_bytes = raw_variant.get("bytes")
        if (
            raw_variant.get("format") != "webp"
            or not relative_path
            or "\\" in relative_path
            or ".." in relative_path.split("/")
            or not isinstance(height, int)
            or height <= 0
            or not isinstance(size_bytes, int)
            or size_bytes <= 0
            or len(checksum) != 64
            or checksum != checksum.lower()
            or any(character not in "0123456789abcdef" for character in checksum)
        ):
            return None
        return {
            "relative_path": relative_path,
            "height": height,
            "bytes": size_bytes,
            "sha256": checksum,
        }
    return None


@extend_schema(tags=["offline"])
class QuranEditionMushafOfflineManifestView(PublicQuranViewMixin, APIView):
    @extend_schema(
        parameters=[
            OpenApiParameter("edition", str, OpenApiParameter.PATH),
            OfflineMushafManifestQuerySerializer,
        ],
        responses=OfflineMushafManifestSerializer,
    )
    def get(self, request: Request, edition: str) -> Response:
        query = OfflineMushafManifestQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        source = get_object_or_404(published_editions(), code=edition)
        version = source.active_version
        if version is None:
            raise NotFound("A published offline Mushaf package is not available.")
        pages = list(published_pages(edition))
        if len(pages) != version.page_count or {page.number for page in pages} != set(
            range(1, version.page_count + 1)
        ):
            raise NotFound("A complete offline Mushaf package is not available.")

        widths_by_page = [
            {
                int(variant["width"])
                for variant in page.asset_variants
                if isinstance(variant, Mapping)
                and isinstance(variant.get("width"), int)
                and _canonical_offline_asset(page.asset_variants, width=int(variant["width"]))
                is not None
            }
            for page in pages
        ]
        available_widths = sorted(set.intersection(*widths_by_page))
        requested_width = query.validated_data.get("width")
        width = (
            requested_width
            if requested_width is not None
            else (max(available_widths) if available_widths else 0)
        )
        if width not in available_widths:
            raise NotFound("The requested offline Mushaf width is not published.")

        selected_assets = [
            _canonical_offline_asset(page.asset_variants, width=width) for page in pages
        ]
        if any(asset is None for asset in selected_assets):
            raise NotFound("The offline Mushaf package failed its integrity check.")
        verified_assets = [asset for asset in selected_assets if asset is not None]
        package_id = f"quran-edition-{source.code}-{version.version}-w{width}"
        page_payloads = [
            {
                "number": page.number,
                "metadata_url": request.build_absolute_uri(
                    reverse(
                        "quran:page-detail",
                        kwargs={"edition": source.code, "page": page.number},
                    )
                ),
                "asset": {
                    "url": (
                        f"{settings.PUBLIC_MEDIA_BASE_URL.rstrip('/')}/{asset['relative_path']}"
                    ),
                    "file_name": f"page-{page.number:03d}-{width}.webp",
                    "content_type": "image/webp",
                    "width": width,
                    "height": asset["height"],
                    "bytes": asset["bytes"],
                    "sha256": asset["sha256"],
                },
            }
            for page, asset in zip(pages, verified_assets, strict=True)
        ]
        checksum_payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "mushaf_pages",
            "package_id": package_id,
            "version": version.version,
            "source_checksum_sha256": version.checksum_sha256,
            "pages": [
                {
                    "number": page.number,
                    "file_name": f"page-{page.number:03d}-{width}.webp",
                    "content_type": "image/webp",
                    "width": width,
                    "height": asset["height"],
                    "bytes": asset["bytes"],
                    "sha256": asset["sha256"],
                }
                for page, asset in zip(pages, verified_assets, strict=True)
            ],
        }
        payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "mushaf_pages",
            "package_id": package_id,
            "version": version.version,
            "package_checksum_sha256": offline_package_checksum(checksum_payload),
            "publication_checksum_sha256": version.checksum_sha256,
            "published_at": version.published_at,
            "source": {
                "name": source.source_name,
                "url": source.source_url,
                "checksum_sha256": version.checksum_sha256,
            },
            "rights": {
                "offline_download": True,
                "attribution_required": True,
                "attribution": f"{source.source_name}. {source.license_name}.",
                "license_name": source.license_name,
                "license_url": source.license_url,
            },
            "mushaf": {
                "source_id": None,
                "edition_code": source.code,
                "name": source.name_en,
                "qirat_name": source.riwayah,
                "lines_per_page": None,
            },
            "width": width,
            "page_count": len(page_payloads),
            "total_bytes": sum(int(asset["bytes"]) for asset in verified_assets),
            "pages": page_payloads,
        }
        return Response(OfflineMushafManifestSerializer(payload).data)


@extend_schema(tags=["quran"])
class QuranFoundationMushafListView(
    PublicQuranViewMixin,
    generics.ListAPIView[QuranFoundationMushaf],
):
    serializer_class = QuranFoundationMushafSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[QuranFoundationMushaf]:
        return public_quran_foundation_mushafs(settings.QURAN_QF_ENV)


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("mushaf", int, OpenApiParameter.PATH),
        OpenApiParameter("page", int, OpenApiParameter.PATH),
    ],
)
class QuranFoundationMushafPageDetailView(
    PublicQuranViewMixin,
    generics.RetrieveAPIView[QuranFoundationMushafPage],
):
    serializer_class = QuranFoundationMushafPageSerializer
    lookup_field = "page_number"
    lookup_url_kwarg = "page"

    def get_queryset(self) -> QuerySet[QuranFoundationMushafPage]:
        return public_quran_foundation_mushaf_pages(
            settings.QURAN_QF_ENV,
            self.kwargs["mushaf"],
        )


@extend_schema(tags=["offline"])
class QuranFoundationMushafOfflineManifestView(PublicQuranViewMixin, APIView):
    @extend_schema(
        parameters=[
            OpenApiParameter("mushaf", int, OpenApiParameter.PATH),
            OfflineMushafManifestQuerySerializer,
        ],
        responses=OfflineMushafManifestSerializer,
    )
    def get(self, request: Request, mushaf: int) -> Response:
        query = OfflineMushafManifestQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        source = get_object_or_404(
            public_quran_foundation_mushafs(settings.QURAN_QF_ENV),
            source_id=mushaf,
        )
        publication = active_native_publication(source)
        if publication is None:
            raise NotFound("A complete published offline Mushaf package is not available.")

        requested_width = query.validated_data.get("width")
        width = requested_width if requested_width is not None else max(publication.required_widths)
        if width not in publication.required_widths:
            raise NotFound("The requested offline Mushaf width is not published.")

        assets = list(
            QuranFoundationNativePageAsset.objects.filter(
                publication=publication,
                width=width,
            ).order_by("page_number")
        )
        if len(assets) != publication.expected_pages or any(
            not asset.checksum_sha256 or asset.size_bytes <= 0 for asset in assets
        ):
            raise NotFound("The offline Mushaf package failed its integrity check.")

        package_id = f"qf-mushaf-{source.source_id}-native-{publication.render_version}-w{width}"
        pages = [
            {
                "number": asset.page_number,
                "metadata_url": request.build_absolute_uri(
                    reverse(
                        "quran:quran-foundation-mushaf-page-detail",
                        kwargs={"mushaf": source.source_id, "page": asset.page_number},
                    )
                ),
                "asset": {
                    "url": f"{settings.PUBLIC_MEDIA_BASE_URL.rstrip('/')}/{asset.storage_key}",
                    "file_name": f"page-{asset.page_number:03d}-{width}.webp",
                    "content_type": asset.content_type,
                    "width": asset.width,
                    "height": asset.height,
                    "bytes": asset.size_bytes,
                    "sha256": asset.checksum_sha256,
                },
            }
            for asset in assets
        ]
        checksum_pages = [
            {
                "number": asset.page_number,
                "file_name": f"page-{asset.page_number:03d}-{width}.webp",
                "content_type": asset.content_type,
                "width": asset.width,
                "height": asset.height,
                "bytes": asset.size_bytes,
                "sha256": asset.checksum_sha256,
            }
            for asset in assets
        ]
        checksum_payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "mushaf_pages",
            "package_id": package_id,
            "version": publication.render_version,
            "source_checksum_sha256": publication.source_checksum_sha256,
            "pages": checksum_pages,
        }
        payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "mushaf_pages",
            "package_id": package_id,
            "version": publication.render_version,
            "package_checksum_sha256": offline_package_checksum(checksum_payload),
            "publication_checksum_sha256": publication.manifest_checksum_sha256,
            "published_at": publication.published_at,
            "source": {
                "name": "Quran.Foundation Content API",
                "url": "https://api-docs.quran.foundation/docs/category/content-apis/",
                "checksum_sha256": publication.source_checksum_sha256,
            },
            "rights": {
                "offline_download": True,
                "attribution_required": True,
                "attribution": "Quran text and layout data provided by Quran.Foundation.",
                "license_name": "",
                "license_url": "",
            },
            "mushaf": {
                "source_id": source.source_id,
                "edition_code": None,
                "name": source.name,
                "qirat_name": source.qirat_name,
                "lines_per_page": source.lines_per_page,
            },
            "width": width,
            "page_count": len(pages),
            "total_bytes": sum(asset.size_bytes for asset in assets),
            "pages": pages,
        }
        return Response(OfflineMushafManifestSerializer(payload).data)


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class JuzListView(PublicQuranViewMixin, generics.ListAPIView[Juz]):
    serializer_class = JuzSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Juz]:
        return published_juz(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class HizbListView(PublicQuranViewMixin, generics.ListAPIView[Hizb]):
    serializer_class = HizbSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Hizb]:
        return published_hizb(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class RubElHizbListView(PublicQuranViewMixin, generics.ListAPIView[RubElHizb]):
    serializer_class = RubElHizbSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[RubElHizb]:
        return published_rub_el_hizb(self.kwargs["edition"])
