from __future__ import annotations

from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.quran.models import Ayah, Juz, MushafPage, QuranEdition, Surah
from quran_backend.modules.quran.selectors import (
    published_ayahs,
    published_editions,
    published_juz,
    published_pages,
    published_surahs,
)
from quran_backend.modules.quran.serializers import (
    AyahSerializer,
    JuzSerializer,
    MushafPageSerializer,
    QuranEditionSerializer,
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


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class JuzListView(PublicQuranViewMixin, generics.ListAPIView[Juz]):
    serializer_class = JuzSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Juz]:
        return published_juz(self.kwargs["edition"])
