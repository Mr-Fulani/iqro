from __future__ import annotations

import uuid

from django.conf import settings
from django.db.models import QuerySet
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics
from rest_framework.exceptions import NotFound
from rest_framework.pagination import CursorPagination
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.audio.models import (
    AudioTrack,
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
)
from quran_backend.modules.audio.serializers import (
    AudioTrackSerializer,
    AyahAudioSegmentSerializer,
    AyahPlaybackSerializer,
    PublicCatalogPageQuerySerializer,
    QuranFoundationAyahChapterSerializer,
    QuranFoundationAyahRecitationSerializer,
    RecitationEditionSerializer,
    RecitationListQuerySerializer,
    ReciterDetailSerializer,
    SurahPlaybackSerializer,
    TrackListQuerySerializer,
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
