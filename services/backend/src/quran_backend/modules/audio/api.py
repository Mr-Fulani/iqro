from __future__ import annotations

import uuid
from typing import Any

from django.conf import settings
from django.db.models import Prefetch, QuerySet
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics
from rest_framework.exceptions import NotFound, PermissionDenied
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    RecitationEdition,
    Reciter,
)
from quran_backend.modules.audio.selectors import (
    public_ayah_segments,
    public_quran_foundation_ayah_chapters,
    public_quran_foundation_ayah_recitations,
    public_recitation_base,
    public_recitations,
    public_reciters,
    public_surah_tracks,
    public_tracks,
    verified_audio_segments,
)
from quran_backend.modules.audio.serializers import (
    AudioTrackSerializer,
    AyahAudioSegmentSerializer,
    AyahPlaybackSerializer,
    OfflineAudioManifestQuerySerializer,
    OfflineAudioManifestSerializer,
    PublicCatalogPageQuerySerializer,
    QuranFoundationAyahChapterSerializer,
    QuranFoundationAyahRecitationSerializer,
    RecitationEditionSerializer,
    RecitationListQuerySerializer,
    ReciterDetailSerializer,
    SurahPlaybackSerializer,
    TrackListQuerySerializer,
    public_audio_url,
)
from quran_backend.modules.core.offline_packages import (
    OFFLINE_PACKAGE_SCHEMA_VERSION,
    offline_package_checksum,
)
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin


class ReciterCursorPagination(CursorPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 100
    ordering = ("name_en", "code", "id")


class RecitationCursorPagination(CursorPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 100
    ordering = ("code", "version", "id")


class AudioTrackCursorPagination(CursorPagination):
    page_size = 50
    page_size_query_param = "page_size"
    max_page_size = 114
    ordering = ("scope", "surah_number", "juz_number", "id")


def _is_verified_offline_rendition(rendition: AudioRendition) -> bool:
    checksum = rendition.checksum_sha256
    return bool(
        rendition.object_key
        and len(checksum) == 64
        and checksum == checksum.lower()
        and all(character in "0123456789abcdef" for character in checksum)
        and rendition.size_bytes > 0
        and rendition.etag
        and rendition.cdn_contract_verified_at
    )


@extend_schema(tags=["audio"])
class ReciterListView(PublicReadOnlyViewMixin, generics.ListAPIView[Reciter]):
    serializer_class = ReciterDetailSerializer
    pagination_class = ReciterCursorPagination

    @extend_schema(parameters=[PublicCatalogPageQuerySerializer])
    def get(self, request: Request, *args: object, **kwargs: object) -> Response:
        return super().get(request, *args, **kwargs)

    def get_queryset(self) -> QuerySet[Reciter]:
        query = PublicCatalogPageQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        return public_reciters()


@extend_schema(tags=["audio"])
class ReciterDetailView(PublicReadOnlyViewMixin, generics.RetrieveAPIView[Reciter]):
    serializer_class = ReciterDetailSerializer
    lookup_url_kwarg = "reciter_id"

    def get_queryset(self) -> QuerySet[Reciter]:
        return public_reciters()


@extend_schema(tags=["audio"])
class RecitationListView(PublicReadOnlyViewMixin, generics.ListAPIView[RecitationEdition]):
    serializer_class = RecitationEditionSerializer
    pagination_class = RecitationCursorPagination

    @extend_schema(parameters=[RecitationListQuerySerializer])
    def get(self, request: Request, *args: object, **kwargs: object) -> Response:
        return super().get(request, *args, **kwargs)

    def get_queryset(self) -> QuerySet[RecitationEdition]:
        query = RecitationListQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        recitations = public_recitations()
        reciter_id = query.validated_data.get("reciter_id")
        if reciter_id is not None:
            recitations = recitations.filter(reciter_id=reciter_id)
        edition_code = query.validated_data.get("quran_edition")
        if edition_code is not None:
            recitations = recitations.filter(quran_edition_version__edition__code=edition_code)
        style = query.validated_data.get("style")
        if style is not None:
            recitations = recitations.filter(style=style)
        return recitations


@extend_schema(tags=["audio"])
class RecitationDetailView(PublicReadOnlyViewMixin, generics.RetrieveAPIView[RecitationEdition]):
    serializer_class = RecitationEditionSerializer
    lookup_url_kwarg = "recitation_id"

    def get_queryset(self) -> QuerySet[RecitationEdition]:
        return public_recitations()


@extend_schema(tags=["audio"])
class QuranFoundationAyahRecitationListView(
    PublicReadOnlyViewMixin,
    generics.ListAPIView[QuranFoundationAyahRecitation],
):
    serializer_class = QuranFoundationAyahRecitationSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[QuranFoundationAyahRecitation]:
        return public_quran_foundation_ayah_recitations(settings.QURAN_QF_ENV)


@extend_schema(
    tags=["audio"],
    parameters=[
        OpenApiParameter("recitation", int, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class QuranFoundationAyahRecitationChapterView(
    PublicReadOnlyViewMixin,
    generics.RetrieveAPIView[QuranFoundationAyahRecitationChapter],
):
    serializer_class = QuranFoundationAyahChapterSerializer
    lookup_field = "chapter_number"
    lookup_url_kwarg = "surah"

    def get_queryset(self) -> QuerySet[QuranFoundationAyahRecitationChapter]:
        return public_quran_foundation_ayah_chapters(
            settings.QURAN_QF_ENV,
            self.kwargs["recitation"],
        )


@extend_schema(tags=["audio"])
class AudioTrackListView(PublicReadOnlyViewMixin, generics.ListAPIView[AudioTrack]):
    serializer_class = AudioTrackSerializer
    pagination_class = AudioTrackCursorPagination

    @extend_schema(parameters=[TrackListQuerySerializer])
    def get(self, request: Request, *args: object, **kwargs: object) -> Response:
        return super().get(request, *args, **kwargs)

    def get_queryset(self) -> QuerySet[AudioTrack]:
        query = TrackListQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        recitation_id = self.kwargs["recitation_id"]
        get_object_or_404(public_recitation_base(), pk=recitation_id)
        tracks = public_tracks(recitation_id)
        scope = query.validated_data.get("scope")
        if scope is not None:
            tracks = tracks.filter(scope=scope)
        return tracks


@extend_schema(tags=["offline"])
class AudioOfflineManifestView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        parameters=[
            OpenApiParameter("recitation_id", uuid.UUID, OpenApiParameter.PATH),
            OfflineAudioManifestQuerySerializer,
        ],
        responses=OfflineAudioManifestSerializer,
    )
    def get(self, request: Request, recitation_id: uuid.UUID) -> Response:
        query = OfflineAudioManifestQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        recitation = get_object_or_404(public_recitation_base(), pk=recitation_id)
        if not recitation.offline_download_allowed:
            raise PermissionDenied("This recitation is not licensed for offline download.")

        track_queryset = (
            public_tracks(recitation_id)
            .filter(scope=AudioTrackScope.SURAH)
            .prefetch_related(
                Prefetch(
                    "segments",
                    queryset=verified_audio_segments().select_related("ayah"),
                    to_attr="verified_segments",
                )
            )
        )
        tracks = list(track_queryset)
        if len(tracks) != 114 or {track.surah_number for track in tracks} != set(range(1, 115)):
            raise NotFound("A complete 114-surah offline audio package is not available.")

        managed_quality_sets = [
            {
                rendition.quality
                for rendition in getattr(track, "public_renditions", [])
                if _is_verified_offline_rendition(rendition)
            }
            for track in tracks
        ]
        available_qualities = sorted(set.intersection(*managed_quality_sets))
        requested_quality = query.validated_data.get("quality")
        if requested_quality is not None and requested_quality not in available_qualities:
            raise NotFound("The requested quality is not complete for this recitation.")

        package_quality = str(requested_quality or "default")
        package_id = f"recitation-{recitation.id}-{recitation.version}-{package_quality}"
        track_payloads: list[dict[str, Any]] = []
        checksum_tracks: list[dict[str, Any]] = []
        for track in tracks:
            renditions: list[AudioRendition] = list(getattr(track, "public_renditions", []))
            if requested_quality is None:
                rendition = next((item for item in renditions if item.is_default), None)
            else:
                rendition = next(
                    (item for item in renditions if item.quality == requested_quality),
                    None,
                )
            if rendition is None or not _is_verified_offline_rendition(rendition):
                raise NotFound("The offline audio package failed its integrity check.")
            assert rendition.object_key is not None

            segments = [
                {
                    "ayah_id": segment.ayah_id,
                    "ayah_number": segment.ayah.number,
                    "start_ms": segment.start_ms,
                    "end_ms": segment.end_ms,
                }
                for segment in getattr(track, "verified_segments", [])
            ]
            timing = (
                {
                    "version": track.timing_version.version,
                    "source_checksum_sha256": track.timing_version.source_checksum_sha256,
                }
                if track.timing_version is not None
                else None
            )
            file_name = f"surah-{track.surah_number:03d}.{rendition.codec}"
            asset = {
                "url": public_audio_url(rendition.object_key),
                "file_name": file_name,
                "content_type": rendition.content_type,
                "codec": rendition.codec,
                "bitrate_kbps": rendition.bitrate_kbps,
                "bytes": rendition.size_bytes,
                "sha256": rendition.checksum_sha256,
                "etag": rendition.etag,
                "range_supported": True,
                "immutable": True,
            }
            track_payloads.append(
                {
                    "id": track.id,
                    "surah_number": track.surah_number,
                    "duration_ms": track.duration_ms,
                    "rendition_quality": rendition.quality,
                    "timing": timing,
                    "segments": segments,
                    "asset": asset,
                }
            )
            checksum_tracks.append(
                {
                    "id": str(track.id),
                    "surah_number": track.surah_number,
                    "duration_ms": track.duration_ms,
                    "rendition_quality": rendition.quality,
                    "timing": timing,
                    "segments": [
                        {
                            "ayah_id": str(segment["ayah_id"]),
                            "ayah_number": segment["ayah_number"],
                            "start_ms": segment["start_ms"],
                            "end_ms": segment["end_ms"],
                        }
                        for segment in segments
                    ],
                    "asset": {
                        "file_name": file_name,
                        "content_type": rendition.content_type,
                        "codec": rendition.codec,
                        "bitrate_kbps": rendition.bitrate_kbps,
                        "bytes": rendition.size_bytes,
                        "sha256": rendition.checksum_sha256,
                        "etag": rendition.etag,
                    },
                }
            )

        checksum_payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "surah_audio",
            "package_id": package_id,
            "version": recitation.version,
            "quality": package_quality,
            "source_checksum_sha256": recitation.source_checksum_sha256,
            "tracks": checksum_tracks,
        }
        edition = recitation.quran_edition_version
        payload = {
            "schema_version": OFFLINE_PACKAGE_SCHEMA_VERSION,
            "package_type": "surah_audio",
            "package_id": package_id,
            "version": recitation.version,
            "quality": package_quality,
            "available_qualities": available_qualities,
            "package_checksum_sha256": offline_package_checksum(checksum_payload),
            "published_at": recitation.published_at,
            "source": {
                "name": recitation.source_name,
                "url": recitation.source_url,
                "version": recitation.source_version,
                "checksum_sha256": recitation.source_checksum_sha256,
            },
            "license": {
                "rights_holder": recitation.rights_holder,
                "name": recitation.license_name,
                "url": recitation.license_url,
                "spdx_id": recitation.license_spdx_id,
                "attribution": recitation.license_attribution,
            },
            "rights": {"stream": True, "offline_download": True},
            "reciter": recitation.reciter,
            "quran_edition": {
                "code": edition.edition.code,
                "version": edition.version,
                "checksum_sha256": edition.checksum_sha256,
            },
            "track_count": len(track_payloads),
            "total_bytes": sum(item["asset"]["bytes"] for item in track_payloads),
            "tracks": track_payloads,
        }
        return Response(OfflineAudioManifestSerializer(payload).data)


@extend_schema(tags=["audio"])
class SurahPlaybackView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        responses=SurahPlaybackSerializer,
        parameters=[
            OpenApiParameter("recitation_id", uuid.UUID, OpenApiParameter.PATH),
            OpenApiParameter("surah", int, OpenApiParameter.PATH),
        ],
    )
    def get(self, request: Request, recitation_id: uuid.UUID, surah: int) -> Response:  # noqa: ARG002
        get_object_or_404(public_recitation_base(), pk=recitation_id)
        track = public_surah_tracks(recitation_id, surah).first()
        if track is None:
            raise NotFound("A published audio track is not available for this surah.")
        return Response(
            {
                "track": AudioTrackSerializer(track).data,
                "segments": AyahAudioSegmentSerializer(
                    getattr(track, "verified_segments", []),
                    many=True,
                ).data,
            }
        )


@extend_schema(tags=["audio"])
class AyahPlaybackView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        responses=AyahPlaybackSerializer,
        parameters=[
            OpenApiParameter("recitation_id", uuid.UUID, OpenApiParameter.PATH),
            OpenApiParameter("surah", int, OpenApiParameter.PATH),
            OpenApiParameter("ayah", int, OpenApiParameter.PATH),
        ],
    )
    def get(
        self,
        request: Request,  # noqa: ARG002
        recitation_id: uuid.UUID,
        surah: int,
        ayah: int,
    ) -> Response:
        get_object_or_404(public_recitation_base(), pk=recitation_id)
        segment: AyahAudioSegment | None = public_ayah_segments(
            recitation_id,
            surah,
            ayah,
        ).first()
        if segment is None:
            raise NotFound("Verified audio timing is not available for this ayah.")
        return Response(
            {
                "track": AudioTrackSerializer(segment.track).data,
                "segment": AyahAudioSegmentSerializer(segment).data,
            }
        )
