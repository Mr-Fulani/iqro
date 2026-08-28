from __future__ import annotations

from django.conf import settings
from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.tafsirs.models import AyahTafsir, TafsirEdition
from quran_backend.modules.tafsirs.selectors import (
    published_surah_tafsir,
    published_tafsir_editions,
)
from quran_backend.modules.tafsirs.serializers import (
    AyahTafsirSerializer,
    TafsirEditionSerializer,
)


@extend_schema(
    tags=["quran-tafsirs"],
    parameters=[
        OpenApiParameter(
            "language",
            str,
            OpenApiParameter.QUERY,
            required=False,
            description="Optional ISO 639-1 Tafsir language filter.",
        )
    ],
)
class TafsirEditionListView(PublicReadOnlyViewMixin, generics.ListAPIView[TafsirEdition]):
    serializer_class = TafsirEditionSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[TafsirEdition]:
        return published_tafsir_editions(
            settings.QURAN_QF_ENV,
            language_code=self.request.query_params.get("language"),
        )


@extend_schema(
    tags=["quran-tafsirs"],
    parameters=[
        OpenApiParameter("tafsir", int, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class SurahTafsirListView(PublicReadOnlyViewMixin, generics.ListAPIView[AyahTafsir]):
    serializer_class = AyahTafsirSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[AyahTafsir]:
        return published_surah_tafsir(
            settings.QURAN_QF_ENV,
            source_id=self.kwargs["tafsir"],
            surah_number=self.kwargs["surah"],
        )
